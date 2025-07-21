#!/usr/bin/env bash

# Usage: bash utils/start_container.sh <container_name>
# Example:
#   bash utils/start_container.sh my_container
#
# 기능:
#   1) 중지된 컨테이너를 `docker start`로 재시작 (이미 실행 중이면 에러 없이 무시)
#   2) `docker attach`로 해당 컨테이너의 메인 프로세스(보통 bash)에 다시 연결

if [ -z "$1" ]; then
  echo "Usage: $0 <container_name>"
  exit 1
fi

CONTAINER_NAME=$1

# 컨테이너가 존재하는지, 중지 상태인지 확인

echo "Starting container if it is stopped: $CONTAINER_NAME"
docker start "$CONTAINER_NAME" 2>/dev/null

# attach: 컨테이너 메인 프로세스(bash)에 연결
echo "Attaching to container: $CONTAINER_NAME"
docker attach "$CONTAINER_NAME"