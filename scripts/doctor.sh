#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
MLLAB_ROOT=${MLLAB_ROOT:-$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)}
export MLLAB_ROOT
# shellcheck source=scripts/lib.sh
source "$MLLAB_ROOT/scripts/lib.sh"
mllab_load_config

usage() {
  cat <<'HELP'
Usage: mllab doctor [options]

Options:
  -i, --image IMAGE          Existing local image. Default: MLLAB_BASE_IMAGE.
  -g, --gpus IDS             Comma-separated numeric IDs or none. Default: config.
  --gpu-backend BACKEND      runtime or gpus. Default: config.
  --timeout SECONDS         Container start timeout (1-300). Default: 30.
  -d, --dry-run              Print commands without contacting Docker/NVIDIA.
  -h, --help                 Show this help.

Runs only nvidia-smi (GPU) or a shell marker (CPU), with no host mounts, ports,
network, or image pulls. Removes only its own temporary container on exit.
HELP
}

image=$MLLAB_BASE_IMAGE
gpus=$MLLAB_DEFAULT_GPUS
backend=$MLLAB_GPU_BACKEND
timeout_seconds=30
dry_run=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    -i|--image|-g|--gpus|--gpu-backend|--timeout)
      mllab_require_value "$1" "${2:-}"
      case "$1" in
        -i|--image) image=$2 ;;
        -g|--gpus) gpus=$2 ;;
        --gpu-backend) backend=$2 ;;
        --timeout) timeout_seconds=$2 ;;
      esac
      shift 2
      ;;
    -d|--dry-run) dry_run=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) mllab_die "Unknown doctor argument: $1" ;;
  esac
done
case "$backend" in runtime|gpus) ;; *) mllab_die "Unsupported GPU backend '$backend'" ;; esac
[ -n "$image" ] || mllab_die "Invalid image name"
[[ "$image" != -* ]] || mllab_die "Invalid image name"
[[ "$timeout_seconds" =~ ^[1-9][0-9]{0,2}$ ]] || mllab_die "Timeout must be 1-300 seconds"
[ "$timeout_seconds" -le 300 ] || mllab_die "Timeout must be 1-300 seconds"
cpu_only=false
case "$gpus" in
  none|NONE|cpu|CPU|off|OFF) cpu_only=true; gpus=none ;;
  *) [[ "$gpus" =~ ^[0-9]+(,[0-9]+)*$ ]] || mllab_die "GPU IDs must be numeric IDs or none" ;;
esac

name="mllab-doctor-$(id -u)-$$-$RANDOM"
token="$name-$(date +%s)-$RANDOM"
resolved_image=$image
expected_uuids=""
if ! $dry_run; then
  command -v timeout >/dev/null 2>&1 || mllab_die "GNU timeout is required"
  bash "$MLLAB_ROOT/scripts/preflight.sh" --gpu-backend "$backend" -g "$gpus"
  resolved_image=$(docker image inspect --format '{{.Id}}' "$image") || mllab_die "Local image '$image' is unavailable; no image was pulled"
  [[ "$resolved_image" =~ ^sha256:[a-f0-9]{64}$ ]] || mllab_die "Could not resolve local image ID"
  if ! $cpu_only; then
    host_inventory=$(nvidia-smi --query-gpu=index,uuid --format=csv,noheader,nounits) || mllab_die "Could not query GPU UUIDs"
    IFS=',' read -r -a requested_ids <<< "$gpus"
    for gpu in "${requested_ids[@]}"; do
      uuid=$(printf '%s\n' "$host_inventory" | awk -F', *' -v id="$gpu" '$1 == id {print $2}')
      [ -n "$uuid" ] || mllab_die "GPU $gpu disappeared before the test"
      expected_uuids+="$uuid"$'\n'
    done
    expected_uuids=$(printf '%s' "$expected_uuids" | sort -u)
  fi
fi

cmd=(docker create --pull=never --rm --name "$name" --label io.mllab-utils.doctor=true
  --label "io.mllab-utils.doctor-token=$token"
  --network none --read-only --cap-drop ALL --memory 256m --cpus 0.5)
if $cpu_only; then
  cmd+=(-e NVIDIA_VISIBLE_DEVICES=void --entrypoint /bin/sh "$resolved_image" -c 'printf "MLLAB_DOCTOR_CPU_OK\n"')
else
  if [ "$backend" = runtime ]; then
    cmd+=(--runtime=nvidia)
  elif [[ "$gpus" == *,* ]]; then
    cmd+=(--gpus "\"device=$gpus\"")
  else
    cmd+=(--gpus "device=$gpus")
  fi
  cmd+=(-e "NVIDIA_VISIBLE_DEVICES=$gpus" -e NVIDIA_DRIVER_CAPABILITIES=utility
    --entrypoint nvidia-smi "$resolved_image" --query-gpu=uuid '--format=csv,noheader,nounits')
fi

if $dry_run; then
  mllab_print_command bash "$MLLAB_ROOT/scripts/preflight.sh" --gpu-backend "$backend" -g "$gpus"
  mllab_print_command docker image inspect --format '{{.Id}}' "$image"
  mllab_print_command "${cmd[@]}"
  mllab_print_command timeout --signal=TERM --kill-after=5 "${timeout_seconds}s" docker start --attach '<created-container-id>'
  mllab_print_command docker rm -f '<created-container-id>'
  exit 0
fi

container_id=""
remove_own_container() {
  local output
  local candidate candidate_token
  # Recover an ID if create was interrupted after Docker accepted it. A name
  # collision alone never authorizes cleanup of someone else's container.
  if [ -z "$container_id" ]; then
    output=$(docker inspect --format '{{.Id}} {{index .Config.Labels "io.mllab-utils.doctor-token"}}' "$name" 2>/dev/null || true)
    read -r candidate candidate_token <<< "$output"
    if [ "$candidate_token" = "$token" ] && [[ "$candidate" =~ ^[a-f0-9]{64}$ ]]; then
      container_id=$candidate
    fi
  fi
  if [ -n "$container_id" ]; then
    if ! output=$(docker rm -f "$container_id" 2>&1); then
      if [[ "$output" != *"No such container"* ]]; then
        echo "Error: Could not clean up doctor container $container_id: $output" >&2
        return 1
      fi
    fi
    container_id=""
  fi
}
cleanup() {
  local result=$?
  trap - EXIT
  if ! remove_own_container; then result=1; fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
container_id=$("${cmd[@]}") || mllab_die "Could not create the diagnostic container"
[[ "$container_id" =~ ^[a-f0-9]{64}$ ]] || { container_id=""; mllab_die "Invalid diagnostic container ID"; }
if output=$(timeout --signal=TERM --kill-after=5 "${timeout_seconds}s" docker start --attach "$container_id"); then
  printf '%s\n' "$output"
else
  result=$?
  printf '%s\n' "$output" >&2
  mllab_die "Diagnostic container failed or timed out (exit $result)"
fi
if $cpu_only; then
  [ "$output" = MLLAB_DOCTOR_CPU_OK ] || mllab_die "CPU diagnostic marker missing"
else
  actual_uuids=$(printf '%s\n' "$output" | sed '/^[[:space:]]*$/d; s/^[[:space:]]*//; s/[[:space:]]*$//' | sort -u)
  [ "$actual_uuids" = "$expected_uuids" ] || mllab_die "Container GPU UUIDs differ from requested host GPUs"
fi
remove_own_container || mllab_die "Doctor cleanup failed"
printf 'Doctor passed: image=%s backend=%s GPUs=%s; temporary container removed.\n' "$image" "$backend" "$gpus"
