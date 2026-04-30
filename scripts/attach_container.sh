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
  mllab attach [--dry-run] <container_name>
EOF
}

dry_run=false
container_name=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -d|--dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      mllab_die "Unknown option: $1"
      ;;
    *)
      container_name=$1
      shift
      ;;
  esac
done

[ -n "$container_name" ] || { usage >&2; exit 1; }

if $dry_run; then
  mllab_print_command docker start "$container_name"
  mllab_print_command docker exec -it "$container_name" bash
else
  docker start "$container_name" >/dev/null
  docker exec -it "$container_name" bash
fi
