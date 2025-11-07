#!/bin/bash
set -euo pipefail

# download data using SRA toolkit (data from PRJNA1347036)

# create micromamba env with sra-tools and eutils if not already done
eval "$(micromamba shell hook -s bash)"
if ! micromamba env list | grep -q 'RAAViolidatadownload'; then
    micromamba create -n RAAViolidatadownload \
        -c conda-forge -c bioconda \
        sra-tools entrez-direct python=3.9 -y
fi

# get SRR numbers with eutils - short read
micromamba activate RAAViolidatadownload
mkdir -p ./data/reads/short
esearch -db sra -query PRJNA1347036 | efetch -format runinfo | cut -d',' -f1 > data/reads/short/srr_numbers.txt
# remove header
sed -i '1d' data/reads/short/srr_numbers.txt
# download fastq files
while read -r srr; do
    echo "Downloading $srr"
    #fasterq-dump "$srr" --split-files --threads 4 -O ./data/reads/short
done < data/reads/short/srr_numbers.txt

# download metadata
esearch -db sra -query PRJNA1347036 | efetch -format runinfo > data/reads/short/metadata.csv

# get SRR numbers with eutils - long read
mkdir -p ./data/reads/long
esearch -db sra -query PRJNA746556 | efetch -format runinfo | cut -d',' -f1 > data/reads/long/srr_numbers.txt
# remove header
sed -i '1d' data/reads/long/srr_numbers.txt
# download fastq files
while read -r srr; do
    echo "Downloading $srr"
    #fasterq-dump "$srr" --split-files --threads 4 -O ./data/reads/long
done < data/reads/long/srr_numbers.txt

# download metadata
esearch -db sra -query PRJNA746556 | efetch -format runinfo > data/reads/long/metadata.csv

#reference genomes:
HUMAN="Data/genome/human_g1k_v37.fasta"
AAV="Data/genome/vector.fa"
MIXED="Data/genome/mixed.fa"

PROJECT_ROOT="$(pwd)"
SHORT_READS_DIR="${PROJECT_ROOT}/data/reads/short"
SHORT_SRRS_FILE="${SHORT_READS_DIR}/srr_numbers.txt"
SHORT_R1_DIR="${SHORT_READS_DIR}/r1"
SHORT_R2_DIR="${SHORT_READS_DIR}/r2"
SHORT_POOL_ID="short_pool"

if command -v micromamba >/dev/null 2>&1; then
    micromamba deactivate >/dev/null 2>&1 || true
fi

if ! micromamba env list | grep -q 'RAAVioliShort_env'; then
    pushd RAAVioli_short >/dev/null
    ./setup_short.sh
    popd >/dev/null
fi

mkdir -p "$SHORT_R1_DIR" "$SHORT_R2_DIR"

shopt -s nullglob
for fq1 in "${SHORT_READS_DIR}"/*_1.fastq; do
    base=$(basename "$fq1" "_1.fastq")
    fq2="${SHORT_READS_DIR}/${base}_2.fastq"
    if [[ ! -f "$fq2" ]]; then
        echo "[WARNING] Missing mate FASTQ for ${base}" >&2
        continue
    fi
    gzip -f -- "$fq1"
    gzip -f -- "$fq2"
    mv "${SHORT_READS_DIR}/${base}_1.fastq.gz" "${SHORT_R1_DIR}/${base}.r1.fastq.gz"
    mv "${SHORT_READS_DIR}/${base}_2.fastq.gz" "${SHORT_R2_DIR}/${base}.r2.fastq.gz"
done
shopt -u nullglob

if [[ ! -s "$SHORT_SRRS_FILE" ]]; then
    echo "[ERROR] No SRR numbers found for short reads." >&2
    exit 1
fi

SHORT_ASSOC_FILE="${SHORT_READS_DIR}/association.tsv"
{
    echo -e "TagID\tAddedField1\tCompleteAmplificationID\tconcatenatePoolIDSeqRun"
    awk -F',' 'NR>1 && $1!="" {print $1"\t"$1"\t"$1"\t"pool}' pool="$SHORT_POOL_ID" "${SHORT_READS_DIR}/metadata.csv"
} > "$SHORT_ASSOC_FILE"

SHORT_ANALYSIS_DIR="${PROJECT_ROOT}/analysis/short"
SHORT_OUTPUT_DIR="${SHORT_ANALYSIS_DIR}/output"
SHORT_TMP_DIR="${SHORT_ANALYSIS_DIR}/tmp"
mkdir -p "$SHORT_ANALYSIS_DIR" "$SHORT_OUTPUT_DIR" "$SHORT_TMP_DIR"

ALIGNMENT_VARS="${SHORT_ANALYSIS_DIR}/alignment_vars.reproduce.txt"
ISR_VARS="${SHORT_ANALYSIS_DIR}/isr_vars.reproduce.txt"
MANDATORY_VARS="${SHORT_ANALYSIS_DIR}/mandatory_vars.reproduce.txt"

cat > "$ALIGNMENT_VARS" <<EOF
FUSIORERRORRATE=0
FUSION_PRIMERS="${PROJECT_ROOT}/Data/Short/files/ITR_primer.fa"
BWA_MIN_ALN_LEN=30
minmapQ=0
mapQvec=0
EOF

cat > "$ISR_VARS" <<EOF
SUBOPTH=40
MINAAVMATCHES=30
ITR_DF=""
system_sequences_df=""
MAXCLUSTERD=20
MERGECOL="CompleteAmplificationID"
ANNOTATIONGTF=""
EOF

cat > "$MANDATORY_VARS" <<EOF
DISEASE="ReproduceStudy"
PATIENT="PRJNA1347036"
POOL="${SHORT_POOL_ID}"
NGSWORKINGPATH="${SHORT_OUTPUT_DIR}"
REMOVE_TMP_DIR="remove_tmp_yes"
TMPDIR="${SHORT_TMP_DIR}"
R1_FASTQ="${SHORT_R1_DIR}"
R2_FASTQ="${SHORT_R2_DIR}"
ASSOCIATIONFILE="${SHORT_ASSOC_FILE}"
MAXTHREADS=4
OUTPUT_NAME="reproduce"
GENOME="${PROJECT_ROOT}/${MIXED}"
VECTORGENOME="${PROJECT_ROOT}/${AAV}"
alignment_vars_file="${ALIGNMENT_VARS}"
isr_vars_file="${ISR_VARS}"
EOF

pushd RAAVioli_short >/dev/null
bash RAAVioli_short.sh "$MANDATORY_VARS"
popd >/dev/null

micromamba run -n RAAVioliShort_env python analysis/short/compare_short_results.py \
  --expected expected_results/Cipriani_etal_Table_S1.xlsx \
  --expected-sheet shortIS \
  --seqcount analysis/short/output/ReproduceStudy/PRJNA1347036/matrix/short_pool/SeqCount_reproduce.CLUSTER20.tsv \
  --mapping data/paper_runs/short/run_to_tag.tsv \
  --output-dir analysis/short/output/ReproduceStudy/PRJNA1347036/comparison \
  --match-tolerance 5