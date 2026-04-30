#!/usr/bin/env bash
set -euo pipefail

PM_PATH=$(readlink -f "${BASH_SOURCE[0]}")
MLLAB_ROOT=$(cd "$(dirname "$PM_PATH")" && pwd)
export MLLAB_ROOT

# shellcheck source=scripts/lib.sh
source "$MLLAB_ROOT/scripts/lib.sh"
mllab_load_config

usage() {
  cat <<'EOF'
Project Manager for MLLAB

Usage:
  mllab <command> [options]
  bash pm.sh <command> [options]

Commands:
  help                         Show this help.
  version                      Print the installed mllab-utils version.
  config                       Print the effective runtime configuration.

  init <project> <git_url>     Create a project from a Git repository.
  build [options] <project> [tag]
                               Build a Docker image for a project.
  create [options] <project>   Create a project container without starting it.
  start [options] <project>    Create the project container if needed and attach.
  attach <container_name>      Start an existing container and open a shell.
  stop [-n name] <project>     Stop a project container.
  rm [-n name] <project>       Remove a project container.

  gpu                          Show GPU processes and matching Docker containers.
  sizes                        Show running containers sorted by reported size.
  test                         Run local smoke tests.

Run "mllab <command> --help" for command-specific options.
EOF
}

print_config() {
  cat <<EOF
MLLAB_ROOT=$MLLAB_ROOT
MLLAB_CONFIG_FILE=${MLLAB_CONFIG_FILE:-$HOME/.config/mllab-utils/config.env}
MLLAB_PROJECTS_DIR=$MLLAB_PROJECTS_DIR
MLLAB_IMAGE_NAMESPACE=$MLLAB_IMAGE_NAMESPACE
MLLAB_BASE_IMAGE=$MLLAB_BASE_IMAGE
MLLAB_DEFAULT_TAG=$MLLAB_DEFAULT_TAG
MLLAB_DEFAULT_PORT=$MLLAB_DEFAULT_PORT
MLLAB_DEFAULT_GPUS=$MLLAB_DEFAULT_GPUS
MLLAB_DATA_DIR=$MLLAB_DATA_DIR
MLLAB_CONTAINER_WORKDIR=$MLLAB_CONTAINER_WORKDIR
MLLAB_UTILS_MOUNT=$MLLAB_UTILS_MOUNT
MLLAB_CODE_DIR=$MLLAB_CODE_DIR
MLLAB_CONTAINER_PREFIX=$MLLAB_CONTAINER_PREFIX
MLLAB_OPEN_EDITOR=$MLLAB_OPEN_EDITOR
MLLAB_EDITOR_CMD=$MLLAB_EDITOR_CMD
EOF
}

container_name_from_project_args() {
  local explicit_name=""
  local project=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      -n|--name)
        [ "$#" -ge 2 ] || mllab_die "Missing value for $1"
        explicit_name=$2
        shift 2
        ;;
      --)
        shift
        [ "$#" -gt 0 ] && project=${*: -1}
        break
        ;;
      -*)
        shift
        ;;
      *)
        project=$1
        shift
        ;;
    esac
  done

  if [ -n "$explicit_name" ]; then
    printf '%s\n' "$explicit_name"
  else
    [ -n "$project" ] || mllab_die "Missing <project>"
    mllab_default_container_name "$project"
  fi
}

run_stop_or_rm() {
  local action=$1
  shift
  local container_name
  container_name=$(container_name_from_project_args "$@")

  case "$action" in
    stop)
      echo "Stopping container '$container_name'..."
      docker stop "$container_name"
      ;;
    rm)
      echo "Removing container '$container_name'..."
      docker rm "$container_name"
      ;;
    *)
      mllab_die "Unknown action '$action'"
      ;;
  esac
}

command=${1:-help}
[ "$#" -gt 0 ] && shift || true

case "$command" in
  help|-h|--help)
    usage
    ;;
  version)
    cat "$MLLAB_ROOT/VERSION"
    ;;
  config)
    print_config
    ;;
  init)
    exec "$MLLAB_ROOT/scripts/init_project.sh" "$@"
    ;;
  build)
    exec "$MLLAB_ROOT/scripts/build_image.sh" "$@"
    ;;
  create)
    exec "$MLLAB_ROOT/scripts/create_container.sh" "$@"
    ;;
  start)
    exec "$MLLAB_ROOT/scripts/start_project.sh" "$@"
    ;;
  attach)
    exec "$MLLAB_ROOT/scripts/attach_container.sh" "$@"
    ;;
  stop)
    run_stop_or_rm stop "$@"
    ;;
  rm)
    run_stop_or_rm rm "$@"
    ;;
  gpu)
    exec "$MLLAB_ROOT/scripts/gpu_status.sh" "$@"
    ;;
  sizes)
    exec "$MLLAB_ROOT/scripts/container_sizes.sh" "$@"
    ;;
  test)
    exec "$MLLAB_ROOT/tests/smoke.sh" "$@"
    ;;
  install)
    exec "$MLLAB_ROOT/install.sh" "$@"
    ;;
  *)
    echo "Error: Unknown command '$command'" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac
