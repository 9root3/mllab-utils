#!/usr/bin/env bash
set -euo pipefail

printf "%-12s %-8s %-25s %s\n" "GPU" "PID" "ContainerName" "UsedMem(MB)"

if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo "nvidia-smi not found." >&2
  exit 0
fi

{ nvidia-smi \
    --query-compute-apps=gpu_uuid,pid,used_memory \
    --format=csv,noheader,nounits 2>/dev/null || true; } \
| while IFS=',' read -r gpu_id pid mem_mb; do
  gpu_id=$(printf '%s' "$gpu_id" | tr -d '[:space:]')
  pid=$(printf '%s' "$pid" | tr -d '[:space:]')
  mem_mb=$(printf '%s' "$mem_mb" | tr -d '[:space:]')

  [ -n "$pid" ] || continue

  gpu_index=$(printf '%s' "$gpu_id" | cut -c1-8)
  cgroup_content=$(cat "/proc/$pid/cgroup" 2>/dev/null || true)
  container_id=""

  if printf '%s' "$cgroup_content" | grep -q "docker-"; then
    container_id=$(printf '%s' "$cgroup_content" | grep -o -E 'docker-[a-f0-9]{64}' | sed 's/docker-//' | cut -c1-12 || true)

    if [ -z "$container_id" ]; then
      container_id=$(printf '%s' "$cgroup_content" | grep -o -E 'docker-[a-f0-9]+' | sed 's/docker-//' | cut -c1-12 || true)
    fi
  fi

  if [ -n "$container_id" ]; then
    container_name=$(docker ps --filter "id=$container_id" --format '{{.Names}}')
    [ -n "$container_name" ] || container_name="(stopped or unknown)"
  else
    container_name="(host-native)"
  fi

  printf "%-12s %-8s %-25s %s\n" "$gpu_index" "$pid" "$container_name" "$mem_mb"
done
