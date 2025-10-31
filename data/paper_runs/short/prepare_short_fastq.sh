#!/usr/bin/env bash
set -euo pipefail

ROOT="/data/home/sscott@cmri.com.au/Projects/RAAVioli"
RUN_TABLE="$ROOT/data/paper_runs/short/run_to_tag.tsv"
RAW_DIR="${1:-$ROOT/data/reads/short}"
OUT_DIR="${2:-$ROOT/data/reads/short/prepared}"

if [[ ! -f "$RUN_TABLE" ]]; then
  echo "[ERROR] Run mapping table not found: $RUN_TABLE" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"

compress() {
  local input="$1"
  local output="$2"
  if command -v pigz >/dev/null 2>&1; then
    pigz -c "$input" > "$output"
  else
    gzip -c "$input" > "$output"
  fi
}

# shellcheck disable=SC2002
cat "$RUN_TABLE" | tail -n +2 | while IFS=$'\t' read -r run tag; do
  [[ -z "$run" || -z "$tag" ]] && continue
  src_r1=""
  src_r2=""
  if [[ -f "$RAW_DIR/${run}_1.fastq.gz" ]]; then
    src_r1="$RAW_DIR/${run}_1.fastq.gz"
  elif [[ -f "$RAW_DIR/${run}_1.fastq" ]]; then
    src_r1="$RAW_DIR/${run}_1.fastq"
  fi

  if [[ -f "$RAW_DIR/${run}_2.fastq.gz" ]]; then
    src_r2="$RAW_DIR/${run}_2.fastq.gz"
  elif [[ -f "$RAW_DIR/${run}_2.fastq" ]]; then
    src_r2="$RAW_DIR/${run}_2.fastq"
  fi

  if [[ -z "$src_r1" || -z "$src_r2" ]]; then
    echo "[WARN] Missing FASTQ files for $run (expected ${run}_1.fastq[.gz] and ${run}_2.fastq[.gz])" >&2
    continue
  fi

  dest_r1="$OUT_DIR/${tag}.r1.fastq.gz"
  dest_r2="$OUT_DIR/${tag}.r2.fastq.gz"

  if [[ -f "$dest_r1" && -f "$dest_r2" ]]; then
    echo "[INFO] Outputs already exist for $tag; skipping"
    continue
  fi

  printf '[INFO] Preparing %s -> %s\n' "$run" "$tag"

  if [[ "$src_r1" == *.gz ]]; then
    cp "$src_r1" "$dest_r1"
  else
    compress "$src_r1" "$dest_r1"
  fi

  if [[ "$src_r2" == *.gz ]]; then
    cp "$src_r2" "$dest_r2"
  else
    compress "$src_r2" "$dest_r2"
  fi

done
