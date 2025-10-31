#!/bin/bash
set -euo pipefail

# --- SETTINGS ---
ENV_NAME="RAAVioliLong_env"
YML_FILE="raaviolilong_env.yml"
DIR="$(pwd)"
LOG_DIR="$DIR/logs"
CONFIG_FILE="$DIR/config.txt"
MICROMAMBA_CMD="${MICROMAMBA_CMD:-}"

# --- PRECHECKS ---
mkdir -p "$LOG_DIR"

if [[ -n "$MICROMAMBA_CMD" && -x "$MICROMAMBA_CMD" ]]; then
  echo "[INFO] Using micromamba from MICROMAMBA_CMD: $MICROMAMBA_CMD"
elif command -v micromamba >/dev/null 2>&1; then
  MICROMAMBA_CMD="$(command -v micromamba)"
  echo "[INFO] Using micromamba from PATH: $MICROMAMBA_CMD"
else
  echo "[ERROR] micromamba not found. Please install micromamba (https://mamba.readthedocs.io/en/latest/installation/micromamba-installation.html) and re-run this script." >&2
  exit 1
fi

if [[ -z "${MAMBA_ROOT_PREFIX:-}" ]]; then
  export MAMBA_ROOT_PREFIX="$DIR/.micromamba"
  echo "[INFO] Setting MAMBA_ROOT_PREFIX to $MAMBA_ROOT_PREFIX"
else
  echo "[INFO] Respecting existing MAMBA_ROOT_PREFIX: $MAMBA_ROOT_PREFIX"
fi

mkdir -p "$MAMBA_ROOT_PREFIX"
ENV_PREFIX="$MAMBA_ROOT_PREFIX/envs/$ENV_NAME"

# --- STEP 1: CREATE OR UPDATE MAIN ENVIRONMENT ---
if [[ -d "$ENV_PREFIX" ]]; then
  echo "[INFO] Environment '$ENV_NAME' already exists. Updating it..."
  if [[ -f "$YML_FILE" ]]; then
    "$MICROMAMBA_CMD" install -y -n "$ENV_NAME" --file "$YML_FILE" 
  else
    echo "[WARN] Environment file '$YML_FILE' not found. Skipping YAML update."
  fi
else
  echo "[INFO] Creating new environment '$ENV_NAME'..."
  if [[ -f "$YML_FILE" ]]; then
    "$MICROMAMBA_CMD" create -y -n "$ENV_NAME" --file "$YML_FILE"
  else
    "$MICROMAMBA_CMD" create -y -n "$ENV_NAME" -c conda-forge python=3.9
  fi
fi

# --- STEP 2: ACTIVATE MAIN ENVIRONMENT ---
eval "$("$MICROMAMBA_CMD" shell hook -s bash)"
set +u
micromamba activate "$ENV_NAME"
set -u

# --- FIX LOCALE (for R LC_CTYPE errors) ---
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# --- STEP 3: INSTALL R PACKAGES VIA MICROMAMBA ---
echo "[INFO] Installing R base packages from conda-forge/bioconda using micromamba..."
"$MICROMAMBA_CMD" install -y -n "$ENV_NAME" \
  -c conda-forge -c bioconda \
  r-base r-optparse r-sqldf r-matrix \
  bioconductor-delayedarray bioconductor-summarizedexperiment

# --- STEP 4: INSTALL CRAN & BIOC PACKAGES IN R ---
echo "[INFO] Installing CRAN and Bioconductor packages inside R..."
Rscript - <<'EOF'
options(repos = c(CRAN = "https://cloud.r-project.org"))

packages <- c("optparse", "tools", "sqldf")

to_install <- setdiff(packages, rownames(installed.packages()))
if (length(to_install)) install.packages(to_install)

if (!requireNamespace("GenomicAlignments", quietly = TRUE)) {
    if (!requireNamespace("BiocManager", quietly = TRUE))
        install.packages("BiocManager")
    BiocManager::install("GenomicAlignments", update = FALSE, ask = FALSE)
}
EOF

# --- STEP 5: LOG TOOL VERSIONS ---
{
  echo "[SETUP LOG - $(date)]"
  echo "BWA: $(bwa 2>&1 | head -n1 || echo 'not found')"
  echo "SAMTOOLS: $(samtools --version | head -n1 || echo 'not found')"
  echo "BAMTOOLS: $(bamtools --version 2>&1 | head -n1 || echo 'not found')"
  echo "BEDTOOLS: $(bedtools --version 2>/dev/null || echo 'not found')"
  echo "R: $(R --version | head -n1 || echo 'not found')"
  echo "Ruby: $(ruby --version 2>&1 | head -n1 || echo 'not found')"
  echo "Python: $(python --version 2>&1)"
} > "$LOG_DIR/versions.log"

# --- STEP 6: MAKE SCRIPTS EXECUTABLE ---
chmod +x "$DIR/scripts/fqextract.pureheader.v3.py" 2>/dev/null || true
chmod +x "$DIR/scripts/fasta_to_csv.rb" 2>/dev/null || true

# --- STEP 7: GENERATE CONFIG FILE ---
{
  echo "BWA=bwa"
  echo "SAMTOOLS=samtools"
  echo "BAMTOOLS=bamtools"
  echo "BEDTOOLS=bedtools"
  echo "FASTQ_TO_FASTA=$DIR/scripts/fastq_to_fasta.tiget.v3.py"
  echo "FQEXTRACT=$DIR/scripts/fqextract.pureheader.v3.py"
  echo "FASTA_TO_CSV=$DIR/scripts/fasta_to_csv.rb"
} > "$CONFIG_FILE"

# --- SUCCESS MESSAGE ---
echo ""
echo "[SUCCESS] RAAVioliLongR environment setup complete."
echo "  - Environment name: $ENV_NAME"
echo "  - micromamba root: $MAMBA_ROOT_PREFIX"
echo "  - Config file: $CONFIG_FILE"
echo "  - Log file: $LOG_DIR/versions.log"
echo ""
echo "To activate your environment, run:"
echo "    micromamba activate $ENV_NAME"
