#!/usr/bin/env bash
set -e # 오류 발생 시 즉시 스크립트 종료

# 사용 예시:
#   bash utils/build_image.sh proj1 v1
#   bash utils/build_image.sh -c proj1 v1  # 캐시 없이 빌드

# --- 1. 인자 및 옵션 파싱 ---
NO_CACHE=false
while getopts "c" opt; do
  case ${opt} in
    c) NO_CACHE=true ;;
    \?) echo "Invalid option: -$OPTARG" 1>&2; exit 1 ;;
  esac
done
shift $((OPTIND -1))

if [ -z "$1" ]; then
  echo "Usage: $0 [-c] <project_dir> [<tag>]"
  echo "  -c: Build without using cache"
  exit 1
fi

PROJECT_DIR=$1
TAG=${2:-latest} # 태그가 없으면 'latest'를 기본값으로 사용

# --- 2. 경로 및 이름 설정 (readlink로 안정성 확보) ---
BUILD_CONTEXT=$(readlink -f "$PROJECT_DIR")
IMAGE_NAME="$(whoami)/$(basename "$BUILD_CONTEXT"):${TAG}"
DOCKERFILE_PATH="${BUILD_CONTEXT}/Dockerfile"

if [ ! -f "$DOCKERFILE_PATH" ]; then
    echo "Error: Dockerfile not found at '$DOCKERFILE_PATH'"
    exit 1
fi

# --- 3. [개선] .dockerignore 확인 및 생성 ---
DOCKERIGNORE_PATH="${BUILD_CONTEXT}/.dockerignore"
if [ ! -f "$DOCKERIGNORE_PATH" ]; then
    echo "'.dockerignore' not found. Creating a default one."
    cat << EOF > "$DOCKERIGNORE_PATH"
# Git files
.git
.gitignore

# Python cache
__pycache__/
*.pyc
*.pyo
*.pyd

# IDE/Editor files
.vscode/
.idea/

# Local data and outputs
data/
outputs/
checkpoints/
*.log

# Virtual environment
venv/
.venv/
EOF
fi

# --- 4. 최종 빌드 명령어 구성 ---
BUILD_CMD="docker build"
if $NO_CACHE; then
    BUILD_CMD+=" --no-cache"
fi
BUILD_CMD+=" -t \"${IMAGE_NAME}\" -f \"${DOCKERFILE_PATH}\" \"${BUILD_CONTEXT}\""

echo "--- Building Docker Image ---"
echo "  Image Name:    ${IMAGE_NAME}"
echo "  Dockerfile:    ${DOCKERFILE_PATH}"
echo "  Build Context: ${BUILD_CONTEXT}"
echo "  No Cache:      ${NO_CACHE}"
echo "---------------------------"

# 실제 빌드 실행
eval "$BUILD_CMD"

echo "Image '${IMAGE_NAME}' built successfully."