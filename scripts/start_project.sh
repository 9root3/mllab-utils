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
  mllab start [options] <project>

Options are the same as "mllab create". If the container already exists,
it is reused instead of recreated.
EOF
}

dry_run=false
container_name=""
project=""
replace=false
forward_args=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -n|--name)
      mllab_require_value "$1" "${2:-}"
      container_name=$2
      forward_args+=("$1" "$2")
      shift 2
      ;;
    -d|--dry-run)
      dry_run=true
      forward_args+=("$1")
      shift
      ;;
    -p|--port|-t|--tag|-g|--gpus|-i|--image)
      mllab_require_value "$1" "${2:-}"
      forward_args+=("$1" "$2")
      shift 2
      ;;
    -r|--replace)
      replace=true
      forward_args+=("$1")
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      forward_args+=("$@")
      [ "$#" -gt 0 ] && project=${*: -1}
      break
      ;;
    -*)
      mllab_die "Unknown option: $1"
      ;;
    *)
      project=$1
      forward_args+=("$1")
      shift
      ;;
  esac
done

[ -n "$project" ] || { usage >&2; exit 1; }

if [ -z "$container_name" ]; then
  container_name=$(mllab_default_container_name "$project")
fi

if $dry_run; then
  "$MLLAB_ROOT/scripts/create_container.sh" "${forward_args[@]}"
  echo "Would run:"
  mllab_print_command docker start -ai "$container_name"
  exit 0
fi

if $replace; then
  "$MLLAB_ROOT/scripts/create_container.sh" "${forward_args[@]}"
elif mllab_container_exists "$container_name"; then
  echo "Container '$container_name' already exists. Reusing it."
else
  "$MLLAB_ROOT/scripts/create_container.sh" "${forward_args[@]}"
fi

docker start -ai "$container_name"
