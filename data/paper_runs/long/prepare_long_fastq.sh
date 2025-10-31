#!/usr/bin/env bash
set -euo pipefail

ROOT="/data/home/sscott@cmri.com.au/Projects/RAAVioli"
RUN_TABLE="$ROOT/data/paper_runs/long/run_to_sample.tsv"
RAW_DIR="${1:-$ROOT/data/reads/long}"
OUT_DIR="${2:-$ROOT/data/reads/long/prepared}"

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
cat "$RUN_TABLE" | tail -n +2 | while IFS=$'\t' read -r run sample; do
  [[ -z "$run" || -z "$sample" ]] && continue
  src="$RAW_DIR/${run}.fastq"
  if [[ ! -f "$src" && -f "$RAW_DIR/${run}.fastq.gz" ]]; then
    src="$RAW_DIR/${run}.fastq.gz"
  fi
  if [[ ! -f "$src" ]]; then
    echo "[WARN] Missing FASTQ for $run" >&2
    continue
  fi

  dest="$OUT_DIR/${sample}.fastq.gz"
  if [[ -f "$dest" ]]; then
    echo "[INFO] Output already exists for $sample; skipping"
    continue
  fi

  printf '[INFO] Preparing %s -> %s\n' "$run" "$sample"
  if [[ "$src" == *.gz ]]; then
    cp "$src" "$dest"
  else
    compress "$src" "$dest"
  fi

done
