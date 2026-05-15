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
  mllab attach [--dry-run] [--host-user|--root] <container_name>
EOF
}

dry_run=false
run_as_host_user=$MLLAB_RUN_AS_HOST_USER
container_name=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    -d|--dry-run)
      dry_run=true
      shift
      ;;
    --host-user)
      run_as_host_user=true
      shift
      ;;
    --root)
      run_as_host_user=false
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
  exec_cmd=(docker exec -it)
  if mllab_bool "$run_as_host_user"; then
    exec_cmd+=(--user "$(id -u):$(id -g)" -e "HOME=$MLLAB_CONTAINER_HOME")
  fi
  exec_cmd+=("$container_name" bash)
  mllab_print_command "${exec_cmd[@]}"
else
  docker start "$container_name" >/dev/null 2>&1 || true
  exec_cmd=(docker exec -it)
  if mllab_bool "$run_as_host_user"; then
    exec_cmd+=(--user "$(id -u):$(id -g)" -e "HOME=$MLLAB_CONTAINER_HOME")
  fi
  exec_cmd+=("$container_name" bash)
  "${exec_cmd[@]}"
fi
