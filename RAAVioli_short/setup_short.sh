#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="RAAVioliShort_env"
YML_FILE="raaviolishort_env.yml"

MICROMAMBA_BIN_DEFAULT="$HOME/.local/bin/micromamba"
MICROMAMBA_BIN="${MICROMAMBA_BIN:-$MICROMAMBA_BIN_DEFAULT}"

ensure_path_contains() {
  local dir="$1"
  case ":$PATH:" in
    *":$dir:"*) ;;
    *) export PATH="$dir:$PATH" ;;
  esac
}


# ---------------- LOCATE ENV TOOL ---------------- #
if command -v micromamba >/dev/null 2>&1; then
  ENVTOOL="micromamba"
  ENVTOOL_CMD="$(command -v micromamba)"
elif command -v mamba >/dev/null 2>&1; then
  ENVTOOL="mamba"
  ENVTOOL_CMD="$(command -v mamba)"
elif command -v conda >/dev/null 2>&1; then
  ENVTOOL="conda"
  ENVTOOL_CMD="$(command -v conda)"
else
  # Fallback: try to bootstrap micromamba
  echo "[INFO] No environment tool found; installing micromamba to ${MICROMAMBA_BIN}..."
  install_dir="$(dirname "$MICROMAMBA_BIN")"
  mkdir -p "$install_dir"
  curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest \
    | tar -xvjf - -C "$install_dir" --strip-components=1 bin/micromamba
  ENVTOOL="micromamba"
  ENVTOOL_CMD="$MICROMAMBA_BIN"
  chmod +x "$ENVTOOL_CMD"
fi

ensure_path_contains "$(dirname "$ENVTOOL_CMD")"

if [ "$ENVTOOL" = "micromamba" ]; then
  export MAMBA_ROOT_PREFIX="${MAMBA_ROOT_PREFIX:-$HOME/micromamba}"
  mkdir -p "$MAMBA_ROOT_PREFIX"
fi


# ---------------- CREATE/UPDATE ENV ---------------- #
if [ "$ENVTOOL" = "micromamba" ]; then
  if "$ENVTOOL_CMD" env list | awk 'NF && $1 !~ /^#/ {print $1}' | grep -Fxq "$ENV_NAME"; then
    echo "[INFO] Updating existing env '$ENV_NAME'..."
    "$ENVTOOL_CMD" install -y -n "$ENV_NAME" --file "$YML_FILE" --prune
  else
    echo "[INFO] Creating env '$ENV_NAME'..."
    "$ENVTOOL_CMD" create -y -n "$ENV_NAME" --file "$YML_FILE"
  fi
elif [ "$ENVTOOL" = "mamba" ]; then
  if "$ENVTOOL_CMD" env list | awk 'NF && $1 !~ /^#/ {print $1}' | grep -Fxq "$ENV_NAME"; then
    echo "[INFO] Updating existing env '$ENV_NAME'..."
    "$ENVTOOL_CMD" env update -n "$ENV_NAME" -f "$YML_FILE" --prune
  else
    echo "[INFO] Creating env '$ENV_NAME'..."
    "$ENVTOOL_CMD" create -n "$ENV_NAME" -f "$YML_FILE" -y
  fi
elif [ "$ENVTOOL" = "conda" ]; then
  if "$ENVTOOL_CMD" env list | awk '{print $1}' | grep -Fxq "$ENV_NAME"; then
    echo "[INFO] Updating existing env '$ENV_NAME'..."
    "$ENVTOOL_CMD" env update -n "$ENV_NAME" -f "$YML_FILE" --prune
  else
    echo "[INFO] Creating env '$ENV_NAME'..."
    "$ENVTOOL_CMD" env create -n "$ENV_NAME" -f "$YML_FILE"
  fi
fi


# ---------------- ACTIVATE ENV ---------------- #
if [ "$ENVTOOL" = "micromamba" ]; then
  eval "$("$ENVTOOL_CMD" shell hook -s bash)"
  micromamba activate "$ENV_NAME"
elif [ "$ENVTOOL" = "mamba" ] || [ "$ENVTOOL" = "conda" ]; then
  eval "$("$ENVTOOL_CMD" shell.bash hook)"
  "$ENVTOOL" activate "$ENV_NAME"
fi

# ---------------- DISABLE USER-SITE (current session) ---------------- #
export PYTHONNOUSERSITE=1
unset PYTHONPATH
echo "[INFO] Disabled user site for current session."

# Also persist this setting for future activations
mkdir -p "$CONDA_PREFIX/etc/conda/activate.d"
mkdir -p "$CONDA_PREFIX/etc/conda/deactivate.d"

cat > "$CONDA_PREFIX/etc/conda/activate.d/disable_usersite.sh" <<'EOF'
export PYTHONNOUSERSITE=1
unset PYTHONPATH
EOF

cat > "$CONDA_PREFIX/etc/conda/deactivate.d/disable_usersite.sh" <<'EOF'
unset PYTHONNOUSERSITE
EOF


echo "[INFO] Configured env to ignore ~/.local site-packages."

# ---------------- VERIFICATION ---------------- #
echo "[INFO] Verifying package versions..."
python -c "import sys, numpy, pandas; \
print('Python exe:', sys.executable); \
print('NumPy     :', numpy.__version__, '->', numpy.__file__); \
print('pandas    :', pandas.__version__, '->', pandas.__file__); \
assert numpy.__version__.startswith('1.22'), 'Unexpected NumPy version!'; \
assert pandas.__version__.startswith('2.0.2'), 'Unexpected pandas version!'"

echo "[INFO] Environment '$ENV_NAME' is ready."
if [ "$ENVTOOL" = "micromamba" ]; then
  echo "[INFO] Activate with: micromamba activate $ENV_NAME"
elif [ "$ENVTOOL" = "mamba" ]; then
  echo "[INFO] Activate with: mamba activate $ENV_NAME"
else
  echo "[INFO] Activate with: conda activate $ENV_NAME"
fi
