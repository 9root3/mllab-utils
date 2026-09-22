#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
MLLAB_ROOT=${MLLAB_ROOT:-$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)}
export MLLAB_ROOT

# shellcheck source=scripts/lib.sh
source "$MLLAB_ROOT/scripts/lib.sh"
mllab_load_config

usage() {
  cat <<'EOF'
Usage:
  mllab preflight [options]

Options:
  -g, --gpus GPUS           GPU IDs to validate. Default: config value.
  --gpu-backend BACKEND     "runtime" or "gpus". Default: config value.
  -h, --help                Show this help.
EOF
}

gpus=$MLLAB_DEFAULT_GPUS
gpu_backend=$MLLAB_GPU_BACKEND

while [ "$#" -gt 0 ]; do
  case "$1" in
    -g|--gpus)
      mllab_require_value "$1" "${2:-}"
      gpus=$2
      shift 2
      ;;
    --gpu-backend)
      mllab_require_value "$1" "${2:-}"
      gpu_backend=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      mllab_die "Unknown option: $1"
      ;;
  esac
done

docker info >/dev/null 2>&1 || mllab_die "Docker daemon is unavailable or the current user cannot access it."

if [ -n "$MLLAB_DATA_DIR" ] && [ ! -d "$MLLAB_DATA_DIR" ]; then
  mllab_die "Configured MLLAB_DATA_DIR does not exist: '$MLLAB_DATA_DIR'"
fi

case "$gpu_backend" in
  runtime|gpus)
    ;;
  *)
    mllab_die "Unsupported GPU backend '$gpu_backend'. Use 'runtime' or 'gpus'."
    ;;
esac

case "$gpus" in
  none|NONE|cpu|CPU|off|OFF)
    echo "Preflight passed: Docker available; CPU-only mode selected."
    exit 0
    ;;
esac

command -v nvidia-smi >/dev/null 2>&1 || mllab_die "nvidia-smi is not available."

gpu_inventory=$(nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader,nounits 2>/dev/null) || {
  mllab_die "nvidia-smi could not query the GPU inventory."
}

[ -n "$gpu_inventory" ] || mllab_die "No NVIDIA GPUs were reported."

requested_gpu=""
IFS=',' read -r -a requested_gpus <<< "$gpus"
for requested_gpu in "${requested_gpus[@]}"; do
  requested_gpu=$(printf '%s' "$requested_gpu" | tr -d '[:space:]')
  [[ "$requested_gpu" =~ ^[0-9]+$ ]] || mllab_die "GPU selection must contain numeric IDs or 'none': '$gpus'"
  if ! printf '%s\n' "$gpu_inventory" | awk -F', *' -v id="$requested_gpu" '$1 == id {found=1} END {exit(found ? 0 : 1)}'; then
    mllab_die "Requested GPU ID '$requested_gpu' is not present on this node."
  fi
done

if [ "$gpu_backend" = runtime ]; then
  runtimes=$(docker info --format '{{json .Runtimes}}' 2>/dev/null || true)
  printf '%s' "$runtimes" | grep -q '"nvidia"' || {
    mllab_die "Docker NVIDIA runtime is unavailable."
  }
fi

driver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | sed -n '1p' | sed 's/^ *//; s/ *$//')
echo "Preflight passed: Docker available; NVIDIA driver $driver; backend=$gpu_backend; GPUs=$gpus."
