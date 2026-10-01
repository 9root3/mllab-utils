#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'HELP'
Usage: mllab status
       mllab gpu

Shows GPU inventory and active compute PIDs. Idle means no reported compute PID,
not a reservation. Unmapped PIDs are never assumed to be host-native processes.
HELP
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  '') ;;
  *) echo "Error: Unknown status argument: $1" >&2; exit 1 ;;
esac
[ "$#" -eq 0 ] || { echo "Error: status takes no arguments" >&2; exit 1; }

command -v nvidia-smi >/dev/null 2>&1 || {
  echo "Error: nvidia-smi not found; GPU status unavailable." >&2
  exit 1
}
inventory=$(nvidia-smi --query-gpu=index,uuid,name,memory.total,memory.used --format=csv,noheader,nounits) || {
  echo "Error: GPU inventory query failed." >&2; exit 1;
}
[ -n "$inventory" ] || { echo "Error: No NVIDIA GPUs reported." >&2; exit 1; }
processes=$(nvidia-smi --query-compute-apps=gpu_uuid,pid,used_memory --format=csv,noheader,nounits) || {
  echo "Error: Compute process query failed; occupancy is unknown." >&2; exit 1;
}

# Alternate proc root is used by offline regression fixtures; default is live /proc.
proc_root=${MLLAB_PROC_ROOT:-/proc}
process_uuids=()
process_pids=()
process_memory=()
process_owners=()
while IFS=',' read -r gpu_uuid pid memory; do
  gpu_uuid=${gpu_uuid//[[:space:]]/}
  pid=${pid//[[:space:]]/}
  memory=${memory//[[:space:]]/}
  [ -n "$gpu_uuid" ] || continue
  [[ "$pid" =~ ^[0-9]+$ ]] || { echo "Error: Invalid compute PID: $pid" >&2; exit 1; }
  owner="(unmapped PID)"
  if [ -r "$proc_root/$pid/cgroup" ]; then
    container_id=$(grep -Eo '[a-f0-9]{64}' "$proc_root/$pid/cgroup" | head -n 1 || true)
    if [ -n "$container_id" ] && command -v docker >/dev/null 2>&1; then
      if container_name=$(docker inspect --format '{{.Name}}' "$container_id" 2>/dev/null); then
        container_name=${container_name#/}
        [ -z "$container_name" ] || owner=$container_name
      fi
    fi
  else
    owner="(exited/unreadable PID)"
  fi
  process_uuids+=("$gpu_uuid")
  process_pids+=("$pid")
  process_memory+=("$memory")
  process_owners+=("$owner")
done <<< "$processes"

printf 'Node: %s\n' "$(hostname)"
printf '%-4s %-48s %-10s %-10s %-8s %s\n' GPU MODEL 'VRAM(MiB)' 'USED(MiB)' COMPUTE CONTAINERS
total=0
idle=0
while IFS=',' read -r index uuid model vram used; do
  index=${index//[[:space:]]/}
  uuid=${uuid//[[:space:]]/}
  model=$(printf '%s' "$model" | sed 's/^ *//; s/ *$//')
  vram=${vram//[[:space:]]/}
  used=${used//[[:space:]]/}
  [ -n "$uuid" ] || continue
  total=$((total + 1))
  occupancy=idle
  owners=""
  for ((i=0; i<${#process_uuids[@]}; i++)); do
    if [ "${process_uuids[i]}" = "$uuid" ]; then
      occupancy=busy
      case ",$owners," in
        *",${process_owners[i]},"*) ;;
        *) owners="${owners:+$owners,}${process_owners[i]}" ;;
      esac
    fi
  done
  if [ "$occupancy" = idle ]; then idle=$((idle + 1)); fi
  printf '%-4s %-48s %-10s %-10s %-8s %s\n' "$index" "$model" "$vram" "$used" "$occupancy" "${owners:--}"
done <<< "$inventory"
printf 'Compute-idle GPUs: %s/%s (snapshot; not reserved)\n' "$idle" "$total"
if [ "${#process_pids[@]}" -gt 0 ]; then
  printf '\n%-40s %-10s %-12s %s\n' GPU_UUID PID 'USED(MiB)' CONTAINER
  for ((i=0; i<${#process_pids[@]}; i++)); do
    printf '%-40s %-10s %-12s %s\n' "${process_uuids[i]}" "${process_pids[i]}" "${process_memory[i]}" "${process_owners[i]}"
  done
fi
