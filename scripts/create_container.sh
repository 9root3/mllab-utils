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
  mllab create [options] <project>

Options:
  -p, --port PORT           Container port to publish. Default: config value.
  -t, --tag TAG             Image tag. Default: config value.
  -n, --name NAME           Container name. Default: <user>_<project>.
  -g, --gpus GPUS           NVIDIA_VISIBLE_DEVICES value. Default: config value.
  -i, --image IMAGE         Override full image name.
  -r, --replace             Remove an existing container with the same name first.
  -d, --dry-run             Print Docker commands without executing them.
EOF
}

tag=$MLLAB_DEFAULT_TAG
port=$MLLAB_DEFAULT_PORT
gpus=$MLLAB_DEFAULT_GPUS
image_override=""
container_name=""
replace=false
dry_run=false
positional=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -p|--port)
      mllab_require_value "$1" "${2:-}"
      port=$2
      shift 2
      ;;
    -t|--tag)
      mllab_require_value "$1" "${2:-}"
      tag=$2
      shift 2
      ;;
    -n|--name)
      mllab_require_value "$1" "${2:-}"
      container_name=$2
      shift 2
      ;;
    -g|--gpus)
      mllab_require_value "$1" "${2:-}"
      gpus=$2
      shift 2
      ;;
    -i|--image)
      mllab_require_value "$1" "${2:-}"
      image_override=$2
      shift 2
      ;;
    -r|--replace)
      replace=true
      shift
      ;;
    -d|--dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      positional+=("$@")
      break
      ;;
    -*)
      mllab_die "Unknown option: $1"
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

[ "${#positional[@]}" -ge 1 ] || { usage >&2; exit 1; }

project=${positional[0]}
project_path=$(mllab_project_path "$project")
[ -d "$project_path" ] || mllab_die "Project directory not found: '$project_path'"

if [ -z "$container_name" ]; then
  container_name=$(mllab_default_container_name "$project")
fi

if [ -z "$image_override" ]; then
  image_name=$(mllab_image_name "$project" "$tag")
else
  image_name=$image_override
fi

if ! $dry_run && mllab_container_exists "$container_name"; then
  if $replace; then
    docker rm -f "$container_name"
  else
    mllab_die "Container '$container_name' already exists. Use 'mllab start' to reuse it or 'mllab create --replace' to recreate it."
  fi
elif $dry_run && $replace; then
  echo "Would remove existing container if present:"
  mllab_print_command docker rm -f "$container_name"
fi

cmd=(docker create --ipc=host -it)
cmd+=(--name "$container_name")
cmd+=(--gpus all)
cmd+=(--mount "src=$project_path,dst=$MLLAB_CONTAINER_WORKDIR,type=bind")
cmd+=(--mount "src=$MLLAB_ROOT,dst=$MLLAB_UTILS_MOUNT,type=bind,readonly")

if [ -n "$MLLAB_DATA_DIR" ]; then
  if [ ! -d "$MLLAB_DATA_DIR" ] && ! $dry_run; then
    mllab_die "Configured MLLAB_DATA_DIR does not exist: '$MLLAB_DATA_DIR'"
  fi
  cmd+=(--mount "src=$MLLAB_DATA_DIR,dst=/data,type=bind")
fi

cmd+=(-w "$MLLAB_CONTAINER_WORKDIR")
cmd+=(-e "NVIDIA_VISIBLE_DEVICES=$gpus")

if [ -n "${GEMINI_API_KEY:-}" ]; then
  cmd+=(-e GEMINI_API_KEY)
fi

cmd+=(-p "$port:$port")
cmd+=("$image_name" bash)

echo "Creating container with:"
echo "  IMAGE          = $image_name"
echo "  CONTAINER_NAME = $container_name"
echo "  GPU            = $gpus"
echo "  PORT           = $port"
echo "  PROJECT        = $project_path -> $MLLAB_CONTAINER_WORKDIR"
echo "  UTILS          = $MLLAB_ROOT -> $MLLAB_UTILS_MOUNT"
echo "  DATA           = ${MLLAB_DATA_DIR:-<disabled>} -> /data"
echo "  DRY_RUN        = $dry_run"

if $dry_run; then
  echo "Would run:"
  mllab_print_command "${cmd[@]}"
else
  "${cmd[@]}"
fi
