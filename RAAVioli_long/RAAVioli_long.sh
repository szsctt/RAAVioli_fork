#!/bin/bash

INPUT_FILE=""
MAXTHREADS=""
VIRALGENOME=""
REFGENOME=""
OUTPUT_DIR=""
MIXEDGENOME=""
ANNOTATION=""
VIRALINDEX=""
REFINDEX=""
MIXEDINDEX=""
VARIABLES_MIXED=""
VARIABLES_VIRAL=""
VARIABLES_STEPR=""

# Load config from same folder as script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.txt"
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: config.txt not found in $SCRIPT_DIR. Run mamba_setup.sh before running RAAVioli_long.sh"
    exit 1
fi

set -euo pipefail

ENV_NAME="RAAVioliLong_env"
MICROMAMBA_CMD="${MICROMAMBA_CMD:-}"

if [[ -n "$MICROMAMBA_CMD" && -x "$MICROMAMBA_CMD" ]]; then
    echo "[INFO] Using micromamba from MICROMAMBA_CMD: $MICROMAMBA_CMD"
elif command -v micromamba >/dev/null 2>&1; then
    MICROMAMBA_CMD="$(command -v micromamba)"
    echo "[INFO] Using micromamba from PATH: $MICROMAMBA_CMD"
else
    echo "[ERROR] micromamba not found. Please install micromamba and run mamba_setup.sh first." >&2
    exit 1
fi

if [[ -z "${MAMBA_ROOT_PREFIX:-}" ]]; then
    export MAMBA_ROOT_PREFIX="$SCRIPT_DIR/.micromamba"
    echo "[INFO] Setting MAMBA_ROOT_PREFIX to $MAMBA_ROOT_PREFIX"
else
    echo "[INFO] Respecting existing MAMBA_ROOT_PREFIX: $MAMBA_ROOT_PREFIX"
fi

ENV_PREFIX="$MAMBA_ROOT_PREFIX/envs/$ENV_NAME"
if [[ ! -d "$ENV_PREFIX" ]]; then
    echo "[ERROR] Environment '$ENV_NAME' not found at $ENV_PREFIX. Run mamba_setup.sh before executing RAAVioli_long.sh." >&2
    exit 1
fi

eval "$("$MICROMAMBA_CMD" shell hook -s bash)"
set +u
micromamba activate "$ENV_NAME" || {
    echo "[ERROR] Failed to activate micromamba environment: $ENV_NAME" >&2
    exit 1
}
set -u

source "$CONFIG_FILE"

if command -v pigz >/dev/null 2>&1; then
    COMPRESS_CMD=(pigz -f -c)
    DECOMPRESS_CMD=(pigz -dc)
    echo "[INFO] Using pigz for compression and decompression."
else
    COMPRESS_CMD=(gzip -f -c)
    if command -v gunzip >/dev/null 2>&1; then
        DECOMPRESS_CMD=(gunzip -c)
    else
        DECOMPRESS_CMD=(zcat)
    fi
    echo "[INFO] pigz not found. Falling back to gzip/gunzip." >&2
fi

BWA_INDEX_SUFFIXES=(.amb .ann .bwt .pac .sa)

if [[ "${FASTA_TO_CSV##*.}" == "rb" ]]; then
    if ! command -v ruby >/dev/null 2>&1; then
        echo "[ERROR] ruby not found but required for FASTA_TO_CSV." >&2
        exit 1
    fi
    FASTA_TO_CSV_CMD=(ruby "$FASTA_TO_CSV")
else
    echo "[ERROR] Unsupported FASTA_TO_CSV helper: $FASTA_TO_CSV" >&2
    echo "Please specify a Ruby script via config.txt." >&2
    exit 1
fi

bwa_index_current() {
    local fasta="$1"
    if [[ -z "$fasta" || ! -f "$fasta" ]]; then
        return 1
    fi

    local suffix index_file
    for suffix in "${BWA_INDEX_SUFFIXES[@]}"; do
        index_file="${fasta}${suffix}"
        if [[ ! -f "$index_file" || "$index_file" -ot "$fasta" ]]; then
            return 1
        fi
    done

    return 0
}

ensure_bwa_index() {
    local fasta="$1"
    local label="$2"

    if bwa_index_current "$fasta"; then
        echo "[INFO] Reusing existing BWA index for ${label:-$fasta}"
    else
        echo "[INFO] Building BWA index for ${label:-$fasta}"
        "$BWA" index -a bwtsw "$fasta"
    fi
}

prepare_annotation() {
    local source_path="$1"
    local target_dir="$2"

    if [[ -z "$source_path" ]]; then
        echo "[ERROR] Annotation path not provided." >&2
        return 1
    fi

    if [[ ! -f "$source_path" ]]; then
        echo "[ERROR] Annotation file not found: $source_path" >&2
        return 1
    fi

    mkdir -p "$target_dir"

    local filename="${source_path##*/}"
    local base="${filename%.gz}"
    local stem="${base%.gtf}"
    local sorted_path="$target_dir/${stem}.sorted.gtf"
    local tmp_sorted

    if [[ -f "$sorted_path" && "$sorted_path" -nt "$source_path" ]]; then
        echo "$sorted_path"
        return 0
    fi

    tmp_sorted="$(mktemp "${sorted_path}.XXXXXX")"
    local -a sort_cmd=(sort -t $'\t' -k1,1 -k4,4n -k5,5n)
    if [[ "$filename" == *.gz ]]; then
        "${DECOMPRESS_CMD[@]}" "$source_path" | LC_ALL=C "${sort_cmd[@]}" > "$tmp_sorted"
    else
        LC_ALL=C "${sort_cmd[@]}" "$source_path" > "$tmp_sorted"
    fi

    mv "$tmp_sorted" "$sorted_path"
    echo "$sorted_path"
}

helpFunction()
{
   echo ""
   echo "Sample usage: $0 -i sample_label.tsv -t threads -v viral_genome.fa -r reference.fa -R 1 -a annotation.gtf -o output_dir -m mixed_genome.fa"
   echo -e "\n"
   echo -e "\t-i the .tsv file with the paths to fastq.gz files as last column.\n"
   echo -e "\t-t max threads to be used.\n"
   echo -e "\t-v (optional) the fasta file with viral genome (e.g. AAV).\n\t   The bwa-index will be created in the same directory. \n\t   If you have already an index please see -V.\n\t   You must specify -V if you don't specify -v.\n"
   echo -e "\t-r (optional) the fasta file with the reference genome (e.g. hg19).\n\t   The bwa-index will be created in the same directory. \n\t   If you have already a bwa-index please see -R. N.B.\n\t   You must specify -R if you don't specify -r.\n"
   echo -e "\t-V (optional) path to the viral bwa-index with basename\n\t   (e.g. if you have the index in /home/resources/genome/index\n\t   directory and it has as basename aav.fa\n\t   you have to specify home/resources/genome/index/aav.fa ).\n\t   If specified the index of the viral genome will not be made.\n\t   If you don't specify -V you must specify -v.\n"
   echo -e "\t-R (optional) path to the reference bwa-index with basename\n\t   (e.g. if you have the index in /home/resources/genome/index\n\t   directory and it has as basename hg19.fa\n\t   you have to specify home/resources/genome/index/hg19.fa ).\n\t   If specified the index of the reference genome will not be made.\n\t   If you don't specify -R you must specify -r.\n"
   echo -e "\t-m (optional) the fasta file with the mixed genome\n\t   N.B. viral genome must be appended at the end of reference genome\n\t   with the sequence name chrV.\n\t   Please note that if not specified it will be created and \n\t   you must specify -v and -r \n\t   (since index could be located in a different dir\n\t   and to create the mixed genome both genomes are needed). \n\t   In this case if you already have\n\t   the viral index and/or the reference index \n\t   in the same directory you can specify -V 1 and/or -R 1 instead \n\t   of specifying twice the same path for -v and -V (or -r and -R).\n"
   echo -e "\t-M (optional) bwa-index of the mixed_genome.\n\t   If specified you can omit -m.\n"
   echo -e "\t-a the gtf file with the custom annotation.\n"
   echo -e "\t-o path to the output directory.\n"
   echo -e "\t Please read the Read.me to have more detailed info.\n"
   exit 1
}
while getopts "i:t:v:r:m:a:o:V:R:M:c:w:y:" opt
do
   case "$opt" in
      i ) INPUT_FILE="$OPTARG" ;;
      t ) MAXTHREADS="$OPTARG" ;;
      v ) VIRALGENOME="$OPTARG" ;;
      r ) REFGENOME="$OPTARG" ;;
      o ) OUTPUT_DIR="$OPTARG" ;;
      m ) MIXEDGENOME="$OPTARG" ;;
      a ) ANNOTATION="$OPTARG" ;;
      V ) VIRALINDEX="$OPTARG" ;;
      R ) REFINDEX="$OPTARG" ;;
      M ) MIXEDINDEX="$OPTARG" ;;
      c ) VARIABLES_MIXED="$OPTARG" ;;
      w ) VARIABLES_VIRAL="$OPTARG" ;;
      y ) VARIABLES_STEPR="$OPTARG" ;;
      ? ) helpFunction ;;
   esac
done


if [ -z "$INPUT_FILE" ]
then
   echo "-i Parameter missing!";
   helpFunction
fi

if [ -z "$MAXTHREADS" ]
then
   echo "-t Parameter missing!";
   helpFunction
fi

if [ -z "$OUTPUT_DIR" ]
then
   echo "-o Parameter missing!";
   helpFunction
fi

if [ -z "$ANNOTATION" ]
then
   echo "-a Parameter missing!";
   helpFunction
fi

if [ -z "$VIRALGENOME" ] && [ -z "$VIRALINDEX" ]
then
   echo "You must specify -v or -V or both!"
   helpFunction
fi

if [ -z "$REFGENOME" ] && [ -z "$REFINDEX" ]
then
   echo "You must specify -r or -R or both!"
   helpFunction
fi

# checking if we are able to create the mixed genome if not specified
if [[ (-z "$MIXEDGENOME" && -z "$MIXEDINDEX") && (-z "$VIRALGENOME" || -z "$REFGENOME") ]]
then
    echo "You must specify -v and -r if neither -m nor -M are specified."
    exit 1
fi

### New variables added
if [ -z "$VARIABLES_MIXED" ]
then
   echo "-c Parameter missing!";
   helpFunction
fi

if [ -z "$VARIABLES_VIRAL" ]
then
   echo "-w Parameter missing!";
   helpFunction
fi

if [ -z "$VARIABLES_STEPR" ]
then
   echo "-y Parameter missing!";
   helpFunction
fi





# checking if files exist
if [ ! -s "$INPUT_FILE" ]
then
   echo "${INPUT_FILE} does not exist or has size zero"
   exit 1
fi
if [ "$VIRALINDEX" = "1" ] && [ -z "$VIRALGENOME" ]
then
    echo "You specified -V 1 but not -v. Specifying -V 1 means that the index is in the same location of the genome specified in -v."
    helpFunction
fi
if [ "$REFINDEX" = "1" ] && [ -z "$REFGENOME" ]
then
    echo "You specified -R 1 but not -r. Specifying -R 1 means that the index is in the same location of the genome specified in -r."
    helpFunction
fi

if [ ! -z "$VIRALGENOME" ] && [ ! -s "$VIRALGENOME" ]
then
   echo "${VIRALGENOME} does not exist or has size zero"
   exit 1
fi

if [ ! -z "$VIRALGENOME" ]
then
    var=$(grep ">" ${VIRALGENOME})
    var=`echo $var | sed 's/ *$//g'`
    if [ "$var" != ">chrV" ]
    then
        echo "${VIRALGENOME} must be a single sequence with sequence name equal to >chrV"
        exit 1
    fi
fi
if [ ! -z "$REFGENOME" ] && [ ! -s "$REFGENOME" ]
then
   echo "${REFGENOME} does not exist or has size zero"
   exit 1
fi

source $VARIABLES_VIRAL
if [ ! -d "$OUTPUT_DIR" ]
then
    mkdir "$OUTPUT_DIR"
    mkdir "$OUTPUT_DIR/resources"
elif [ ! -d "$OUTPUT_DIR/resources" ]
then
    mkdir "$OUTPUT_DIR/resources"
fi

ANNOTATION_PREPARED=$(prepare_annotation "$ANNOTATION" "$OUTPUT_DIR/resources") || exit 1
ANNOTATION="$ANNOTATION_PREPARED"

# If mixed index is specified we don't need mixed genome. If neither MIXEDINDEX nor MIXEDGENOME is specified we have to create both
if [ ! -z "$MIXEDINDEX" ]
then
    MIXEDGENOME=$MIXEDINDEX
else
    if [ ! -z "$MIXEDGENOME" ]
    then
        ensure_bwa_index "$MIXEDGENOME" "mixed genome"
    else
        echo "[AP] ============ <`date +'%Y-%m-%d %H:%M:%S'`> [TIGET] Creating mixed genome in ${OUTPUT_DIR}/resources ============"
        cp $REFGENOME $OUTPUT_DIR/resources/mixed.fa
        MIXEDGENOME="$OUTPUT_DIR/resources/mixed.fa"
        cat ${VIRALGENOME} >>  ${MIXEDGENOME}
        ensure_bwa_index "$MIXEDGENOME" "mixed genome"
        echo "[AP] ============ <`date +'%Y-%m-%d %H:%M:%S'`> [TIGET] Mixed genome ready ============"
    fi
fi

if [ -z "$VIRALINDEX" ]
then
    ensure_bwa_index "$VIRALGENOME" "viral genome"
elif [ -z "$VIRALGENOME" ]
then
    VIRALGENOME=$VIRALINDEX
elif [ "$VIRALINDEX" != "1" ]
then
    VIRALGENOME=$VIRALINDEX
fi

if [ -f "$INPUT_FILE" ]; then
    CLEAN_INPUT_FILE=$(mktemp)
    sed 's/\r$//' "$INPUT_FILE" > "$CLEAN_INPUT_FILE"
    INPUT_FILE="$CLEAN_INPUT_FILE"
    echo "[INFO] Normalized line endings in sample label file: $INPUT_FILE"
else
    echo "[ERROR] INPUT_FILE not found: $INPUT_FILE"
    exit 1
fi

PAR_FSAMTOOLS="772"



#reading all paths from .tsv file

fq_files=($(awk -F$'\t' 'NR>=2 {print $NF}' ${INPUT_FILE}))
file_par_name="${SPEC}.k${bwa_mem_k}r${bwa_mem_r}a${bwa_mem_A}t${bwa_mem_T}d${bwa_mem_d}b${bwa_mem_B}"
list_bn=()

echo "[AP] ============ <`date +'%Y-%m-%d %H:%M:%S'`> [TIGET] Align to Vector genome and Filtering ============"
for fq_file in "${fq_files[@]}"
do
    BN=`basename $fq_file | sed 's/.fastq.gz//g'`;
    bwa_mem_R="@RG\tID:${BN}\tCN:TIGET"
    list_bn+=($BN)

                $BWA mem -k ${bwa_mem_k} -r ${bwa_mem_r} -A ${bwa_mem_A} -T ${bwa_mem_T} -d ${bwa_mem_d} -B ${bwa_mem_B} -O ${bwa_mem_O} \
                 -E ${bwa_mem_E} -L ${bwa_mem_L} -R ${bwa_mem_R} -t ${MAXTHREADS} ${VIRALGENOME} <( "${DECOMPRESS_CMD[@]}" "${fq_file}" ) | \
       $SAMTOOLS view -F ${PAR_FSAMTOOLS} -q $sam_view_q -uS - | \
        $SAMTOOLS sort - -o ${OUTPUT_DIR}/${BN}.${file_par_name}.q${sam_view_q}F${PAR_FSAMTOOLS}.sorted.bam
done


file_par_name="${file_par_name}.q${sam_view_q}F${PAR_FSAMTOOLS}"

for BN in "${list_bn[@]}"
do
    $BAMTOOLS  filter -tag "AS:>=${bam_filter_AS}" -in ${OUTPUT_DIR}/${BN}.${file_par_name}.sorted.bam -out \
    ${OUTPUT_DIR}/${BN}.${file_par_name}.as${bam_filter_AS}.sorted.bam &
done
wait
file_par_name="${file_par_name}.as${bam_filter_AS}"
for BN in "${list_bn[@]}"
do
    $SAMTOOLS index ${OUTPUT_DIR}/${BN}.${file_par_name}.sorted.bam &
done
wait

echo "[AP] ============ <`date +'%Y-%m-%d %H:%M:%S'`> [TIGET] Create BED file ============"
for BN in "${list_bn[@]}"
do
    $BEDTOOLS   bamtobed -cigar -i ${OUTPUT_DIR}/${BN}.${file_par_name}.sorted.bam > ${OUTPUT_DIR}/${BN}.${file_par_name}.sorted.bed &
done
wait


PAR_FSAMTOOLS="772"
file_par_name="${SPEC}.k${bwa_mem_k}r${bwa_mem_r}a${bwa_mem_A}t${bwa_mem_T}d${bwa_mem_d}b${bwa_mem_B}"
file_par_name="${file_par_name}.q${sam_view_q}F${PAR_FSAMTOOLS}"
file_par_name="${file_par_name}.as${bam_filter_AS}"


for fq_file in "${fq_files[@]}"
do
    BN=`basename $fq_file | sed 's/.fastq.gz//g'`;
    echo "<`date +'%Y-%m-%d %H:%M:%S'`> [TIGET] Extract reads from raw data"
    cat ${OUTPUT_DIR}/${BN}.${file_par_name}.sorted.bed | cut -f4 | sort | uniq > ${OUTPUT_DIR}/${BN}.${file_par_name}.sorted.headerlist
    "${DECOMPRESS_CMD[@]}" "${fq_file}" | python3 $FQEXTRACT ${OUTPUT_DIR}/${BN}.${file_par_name}.sorted.headerlist | \
    "${COMPRESS_CMD[@]}" > ${OUTPUT_DIR}/${BN}.${file_par_name}.sorted.slice.fastq.gz

    echo "[AP] ============ <`date +'%Y-%m-%d %H:%M:%S'`> [TIGET] Get sequence file ============"
    #"${DECOMPRESS_CMD[@]}" "${OUTPUT_DIR}/${BN}.${file_par_name}.sorted.slice.fastq.gz" | $FASTQ_TO_FASTA -Q33 | "${FASTA_TO_CSV_CMD[@]}" | tr " " "\t" | \
    #awk '{ print $0"\t"length($2) }' > ${OUTPUT_DIR}/${BN}.${file_par_name}.sorted.slice.seq.csv
    "${DECOMPRESS_CMD[@]}" "${OUTPUT_DIR}/${BN}.${file_par_name}.sorted.slice.fastq.gz" | $FASTQ_TO_FASTA | "${FASTA_TO_CSV_CMD[@]}" | tr " " "\t" | \
    awk '{ print $0"\t"length($2) }' > ${OUTPUT_DIR}/${BN}.${file_par_name}.sorted.slice.seq.csv
done


bash step2.sh ${INPUT_FILE} ${file_par_name} ${MAXTHREADS} ${PAR_FSAMTOOLS} ${MIXEDGENOME} ${VARIABLES_MIXED} ${OUTPUT_DIR} ${ANNOTATION}


bash summarize.sh $VARIABLES_VIRAL $VARIABLES_MIXED $OUTPUT_DIR $VARIABLES_STEPR $INPUT_FILE
