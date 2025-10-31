# RAAVioli paper reproduction configs

This folder contains configuration files and helper scripts to reproduce the Cipriani *et al.* short- and long-read analyses with the RAAVioli pipelines.

## Prerequisites

1. Download FASTQ files with `reproduce_paper.sh` (or your own SRA workflow). The downloads should populate:
   - `data/reads/short/` with paired-end Illumina libraries (`SRR*_1.fastq`, `SRR*_2.fastq`).
   - `data/reads/long/` with PacBio single-end reads (`SRR*.fastq`).
2. Ensure the mixed genome and vector references shipped with the repository are indexed with `bwa`:

```bash
bwa index Data/genome/vector.fa
bwa index Data/genome/mixed.fa
```

## Short-read pipeline

1. Prepare FASTQ files so RAAVioli can locate them (creates `.r1/.r2.fastq.gz` named by LTR tag):

```bash
chmod +x data/paper_runs/short/prepare_short_fastq.sh
bash data/paper_runs/short/prepare_short_fastq.sh
```

   - Inputs: raw SRA FASTQs in `data/reads/short/` and the mapping table `run_to_tag.tsv`.
   - Outputs: gzipped files in `data/reads/short/prepared/` matching the `TagID` column of `association_paper_short.tsv`.

2. Launch the RAAVioli short-read workflow from `RAAVioli_short/`:

```bash
cd RAAVioli_short
bash RAAVioli_short.sh ../data/paper_runs/short/mandatory_vars_paper_short.txt
```

   The mandatory file points to:
   - `association_paper_short.tsv` (Tag ↔ sample mapping).
   - Alignment and IS reconstruction parameter files tuned for the publication.
   - Output directory: `data/results/paper_short/` (adjust inside the mandatory file if desired).

## Long-read pipeline

1. Prepare FASTQ files for the PacBio runs (rename/compress to sample-level FASTQs):

```bash
chmod +x data/paper_runs/long/prepare_long_fastq.sh
bash data/paper_runs/long/prepare_long_fastq.sh
```

   This script maps each SRA run to the `InVivo` or `ExVivo` sample listed in `run_to_sample.tsv` and writes gzipped FASTQs under `data/reads/long/prepared/`.

2. Run the long-read pipeline from `RAAVioli_long/` with the provided sample labels:

```bash
cd RAAVioli_long
bash RAAVioli_long.sh \
  -i ../data/paper_runs/long/sample_labels_paper_long.tsv \
  -t 16 \
  -v ../Data/genome/vector.fa \
  -r ../Data/genome/human_g1k_v37.fasta \
  -m ../Data/genome/mixed.fa \
  -c variables_mixed \
  -w variables_viral \
  -y variables_rscript \
  -o ../data/results/paper_long \
  -a ""
```

   Adjust thread counts and output directories as needed. Leave `-a` empty (or point to an annotation GTF if available).

## Reference outputs

The publication tables are in `data/paper_results/Cipriani_etal_Table_S1.xlsx`. After each pipeline run completes, compare the generated matrices in `data/results/paper_short/` and `data/results/paper_long/` against the spreadsheet to validate the reproduction effort.
