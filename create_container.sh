#!/usr/bin/env bash

# 사용 예시:
#   1) 옵션 없이 기본값으로 실행
#      bash utils/create_container.sh proj1
#
#   2) 옵션을 사용해 커스텀 실행
#      bash utils/create_container.sh -p 9000 -t v2 -n my_container -g 0,1 proj1
#
#   3) 다른 연구원이 만든 이미지 사용 (override)
#      bash utils/create_container.sh -p 8888 -n my_container -g 0,1 -i somefriend/pytorch:latest proj1
#
# 옵션:
#   -p PORT                컨테이너 노출 포트 (기본값: 8888)
#   -t TAG                 이미지 태그 (기본값: latest)
#   -n CONTAINER_NAME      컨테이너 이름 (기본값: 프로젝트 이름과 동일)
#   -g GPU_DEVICES         사용할 GPU 인덱스 (기본값: 0,1,2,3)
#   -i IMAGE_NAME          다른 사람의 이미지 사용 (override)
#   -d                     Dry-run 모드 (명령어만 출력하고 실행 안 함)

# 기본값 설정
TAG="latest"
PORT=8888
CUDA_VISIBLE_DEVICES="0,1,2,3"
OVERRIDE_IMAGE=""
CONTAINER_NAME=""
DRY_RUN=false

# 옵션 파싱
while getopts "p:t:n:g:i:d" opt; do
  case ${opt} in
    p) PORT="$OPTARG" ;;
    t) TAG="$OPTARG" ;;
    n) CONTAINER_NAME="$OPTARG" ;;
    g) CUDA_VISIBLE_DEVICES="$OPTARG" ;;
    i) OVERRIDE_IMAGE="$OPTARG" ;;
    d) DRY_RUN=true ;;
    \?)
      echo "Invalid option: -$OPTARG" 1>&2
      exit 1
      ;;
  esac
done
shift $((OPTIND -1)) # 옵션 인자 제거 후 남은 일반 인자 처리

# 필수 인자 (project_dir)
if [ -z "$1" ]; then
  echo "Usage: $0 [-p port] [-t tag] [-n container_name] [-g gpu_devices] [-i override_image] [-d] <project_dir>"
  exit 1
fi

PROJECT_DIR=$1
PROJECT_DIR="${PROJECT_DIR%/}"  # 끝에 슬래시 자동 제거

# 기본값 설정 (컨테이너 이름이 지정되지 않았으면 '$USER_프로젝트 이름' 사용)
[ -z "$CONTAINER_NAME" ] && CONTAINER_NAME="$(whoami)_$PROJECT_DIR"

# 기존 컨테이너 확인 및 제거
if [ "$(docker ps -a --filter name=^/${CONTAINER_NAME}$ --format '{{.Names}}')" = "$CONTAINER_NAME" ]; then
    if ! $DRY_RUN; then
        read -p "Container '$CONTAINER_NAME' already exists. Remove it? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Removing existing container..."
            docker rm "$CONTAINER_NAME"
        else
            echo "Aborted."
            exit 1
        fi
    fi
fi


# override 이미지가 주어지지 않은 경우 -> 기존 로직 적용
if [ -z "$OVERRIDE_IMAGE" ]; then
  IMAGE_NAME="$(whoami)/${PROJECT_DIR}:${TAG}"
else
  IMAGE_NAME="$OVERRIDE_IMAGE"
fi

HOST_DIR="/home/$(whoami)/${PROJECT_DIR}"
HOST_DIR_UTILS="$(dirname "$HOST_DIR")/utils"
CONTAINER_WORKDIR="/workspace"

# 환경변수 설정
ENV_VARS=""
# 호스트에 GEMINI_API_KEY가 설정되어 있을 경우에만 컨테이너에 전달
if [ -n "$GEMINI_API_KEY" ]; then
  ENV_VARS="-e GEMINI_API_KEY"
fi

echo "Creating container with:"
echo "  IMAGE         = $IMAGE_NAME"
echo "  CONTAINER_NAME= $CONTAINER_NAME"
echo "  GPU           = $CUDA_VISIBLE_DEVICES"
echo "  PORT          = $PORT"
echo "  HOST_DIR      = $HOST_DIR -> CONTAINER_WORKDIR=$CONTAINER_WORKDIR"
echo "  ENV_VARS      = $ENV_VARS"

docker create --ipc=host -it \
    --name "$CONTAINER_NAME" \
    --gpus all \
    --mount src="${HOST_DIR}",dst="${CONTAINER_WORKDIR}",type=bind \
    --mount src="${HOST_DIR_UTILS}",dst="/utils",type=bind,readonly \
    --mount src="/media/data2",dst="/data",type=bind \
    -w "${CONTAINER_WORKDIR}" \
    -e NVIDIA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES}" \
    ${ENV_VARS} \
    -p "${PORT}:${PORT}" \
    "$IMAGE_NAME" \
    bash