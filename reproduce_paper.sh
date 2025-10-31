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
esearch -db sra -query PRJNA1347036 | efetch -format runinfo | cut -d',' -f1 > data/reads/srr_numbers.txt
# remove header
sed -i '1d' data/reads/short/srr_numbers.txt
# download fastq files
while read -r srr; do
    echo "Downloading $srr"
    fasterq-dump "$srr" --split-files --threads 4 -O ./data/reads/short
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
    fasterq-dump "$srr" --split-files --threads 4 -O ./data/reads/long
done < data/reads/long/srr_numbers.txt

# download metadata
esearch -db sra -query PRJNA746556 | efetch -format runinfo > data/reads/long/metadata.csv


#reference genomes:
HUMAN="Data/genome/human_g1k_v37.fasta"
AAV="Data/genome/vector.fa"
MIXED="Data/genome/mixed.fa"


