#!/usr/bin/env bash

mllab_die() {
  echo "Error: $*" >&2
  exit 1
}

mllab_load_config() {
  local default_config="$MLLAB_ROOT/config/default.env"
  local user_config="${MLLAB_CONFIG_FILE:-$HOME/.config/mllab-utils/config.env}"

  if [ -f "$default_config" ]; then
    # shellcheck source=config/default.env
    source "$default_config"
  fi

  if [ -f "$user_config" ]; then
    # shellcheck disable=SC1090
    source "$user_config"
  fi

  MLLAB_PROJECTS_DIR=${MLLAB_PROJECTS_DIR%/}
  export MLLAB_PROJECTS_DIR MLLAB_IMAGE_NAMESPACE MLLAB_BASE_IMAGE
  export MLLAB_DEFAULT_TAG MLLAB_DEFAULT_PORT MLLAB_DEFAULT_GPUS
  export MLLAB_GPU_BACKEND MLLAB_NVIDIA_DRIVER_CAPABILITIES
  export MLLAB_DATA_DIR MLLAB_CONTAINER_WORKDIR MLLAB_UTILS_MOUNT
  export MLLAB_CODE_DIR MLLAB_CONTAINER_PREFIX MLLAB_RUN_AS_HOST_USER
  export MLLAB_CONTAINER_HOME MLLAB_OPEN_EDITOR MLLAB_EDITOR_CMD
}

mllab_bool() {
  case "${1:-}" in
    true|TRUE|1|yes|YES|y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

mllab_project_path() {
  local project=${1%/}
  if [[ "$project" == /* ]]; then
    printf '%s\n' "$project"
  else
    printf '%s/%s\n' "$MLLAB_PROJECTS_DIR" "$project"
  fi
}

mllab_project_name() {
  basename "${1%/}"
}

mllab_default_container_name() {
  printf '%s%s\n' "$MLLAB_CONTAINER_PREFIX" "$(mllab_project_name "$1")"
}

mllab_image_name() {
  local project=$1
  local tag=$2
  printf '%s/%s:%s\n' "$MLLAB_IMAGE_NAMESPACE" "$(mllab_project_name "$project")" "$tag"
}

mllab_print_command() {
  local arg
  for arg in "$@"; do
    printf '%q ' "$arg"
  done
  printf '\n'
}

mllab_container_exists() {
  local container_name=$1
  [ "$(docker ps -a --filter "name=^/${container_name}$" --format '{{.Names}}')" = "$container_name" ]
}

mllab_require_value() {
  local option=$1
  local value=${2:-}
  [ -n "$value" ] || mllab_die "Missing value for $option"
}

mllab_resolve_gpu_backend() {
  local requested=$1
  local runtimes
  case "$requested" in
    auto)
      runtimes=$(docker info --format '{{json .Runtimes}}') || mllab_die "Cannot select a GPU backend: Docker is unavailable or inaccessible"
      [ -n "$runtimes" ] || mllab_die "Cannot select a GPU backend: Docker returned no runtime registry"
      if grep -q '"nvidia"[[:space:]]*:' <<< "$runtimes"; then
        printf 'runtime\n'
      else
        printf 'gpus\n'
      fi
      ;;
    runtime|gpus) printf '%s\n' "$requested" ;;
    *) mllab_die "Unsupported GPU backend '$requested'. Use auto, runtime, or gpus." ;;
  esac
}

# An offline auto preview shows both valid commands, rather than guessing the
# daemon's configuration or requiring a live Docker daemon for dry-run.
mllab_print_auto_gpu_commands() {
  local gpus=$1
  shift
  local arg
  local alternative=()
  for arg in "$@"; do
    if [ "$arg" = --runtime=nvidia ]; then
      case "$gpus" in
        all|ALL) alternative+=(--gpus all) ;;
        *,*) alternative+=(--gpus "\"device=$gpus\"") ;;
        *) alternative+=(--gpus "device=$gpus") ;;
      esac
    else
      alternative+=("$arg")
    fi
  done
  echo "Auto backend: use runtime when Docker registers nvidia; otherwise use gpus."
  echo "If runtime is selected:"
  mllab_print_command "$@"
  echo "If gpus is selected:"
  mllab_print_command "${alternative[@]}"
}
