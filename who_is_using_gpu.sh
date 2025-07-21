#!/usr/bin/env bash

# 헤더 출력 (고정 너비로)
printf "%-12s %-8s %-25s %s\n" "GPU" "PID" "ContainerName" "UsedMem(MB)"

# nvidia-smi로 GPU 사용 프로세스 정보 추출
nvidia-smi \
  --query-compute-apps=gpu_uuid,pid,used_memory \
  --format=csv,noheader,nounits 2>/dev/null \
| while IFS=',' read -r gpu_id pid mem_mb; do
  # 공백 제거
  gpu_id=$(echo "$gpu_id" | tr -d ' ')
  pid=$(echo "$pid" | tr -d ' ')
  mem_mb=$(echo "$mem_mb" | tr -d ' ')
  
  # PID가 없거나 제대로 읽히지 않으면 건너뜀
  [ -z "$pid" ] && continue
  
  # 간결한 GPU ID 표시
  gpu_index=$(echo $gpu_id | tr -d ' ' | cut -c1-8)
  
  # system.slice/docker-[ID].scope 패턴 인식 (systemd cgroup v2)
  cgroup_content=$(cat /proc/$pid/cgroup 2>/dev/null)
  
  container_id=""
  if echo "$cgroup_content" | grep -q "docker-"; then
    # systemd cgroup v2 패턴에서 컨테이너 ID 추출 (64자리 전체 ID 처리)
    container_id=$(echo "$cgroup_content" | grep -o -E 'docker-[a-f0-9]{64}' | sed 's/docker-//' | cut -c1-12)
    
    # 추출 실패 시 일반적인 패턴으로 시도
    if [ -z "$container_id" ]; then
      container_id=$(echo "$cgroup_content" | grep -o -E 'docker-[a-f0-9]+' | sed 's/docker-//' | cut -c1-12)
    fi
  fi
  
  if [ -n "$container_id" ]; then
    container_name=$(docker ps --filter "id=$container_id" --format '{{.Names}}')
    [ -z "$container_name" ] && container_name="(stopped or unknown)"
  else
    container_name="(host-native)"
  fi

  # 고정 너비로 정렬된 출력
  printf "%-12s %-8s %-25s %s\n" "$gpu_index" "$pid" "$container_name" "$mem_mb"
done