#!/usr/bin/env bash

# Usage: bash utils/make_project.sh <project_name> <github_url> [--skip-dockerfile]
# Example:
#   bash utils/make_project.sh proj1 https://github.com/username/myrepo.git
#   bash utils/make_project.sh proj1 https://github.com/username/docker_repo.git --skip-dockerfile
#
# This script will create:
#   /home/$(whoami)/proj1/
#       ├── Dockerfile
#       ├── requirements.txt
#       └── code/ (cloned from github_url)

# 1) 인자 체크
if [ $# -lt 2 ]; then
    echo "Usage: $0 <project_name> <github_url> [--skip-dockerfile]"
    exit 1
fi
# 프로젝트 이름은 항상 소문자여야 합니다.
if [[ "$1" =~ [A-Z] ]]; then
    echo "Error: <project_name> must be lowercase only."
    exit 1
fi

PROJECT_NAME=$1
GITHUB_URL=$2
SKIP_DOCKERFILE=false

# 2) 세 번째 인자나 그 이상을 확인 (옵션)
if [ "$3" == "--skip-dockerfile" ]; then
    SKIP_DOCKERFILE=true
fi

PROJECT_PATH="/home/$(whoami)/$PROJECT_NAME"

# 3) 이미 동일한 프로젝트 폴더가 있는지 확인
if [ -d "$PROJECT_PATH" ]; then
    echo "Error: Project directory '$PROJECT_PATH' already exists!"
    exit 1
fi

# 4) 프로젝트 디렉토리 생성
mkdir -p "$PROJECT_PATH"

# 5) code 폴더 생성 및 Git clone
mkdir -p "$PROJECT_PATH/code"
git clone "$GITHUB_URL" "$PROJECT_PATH/code"

# 6) requirements.txt 파일 (초기엔 빈 파일)
#    레포에 requirements.txt가 이미 있을 수도 있지만
#    어쨌든 우리가 만드는 것도 상관없음 (중복 시 오버라이드하지 않는 선택지도 가능)
if [ -f "$PROJECT_PATH/code/requirements.txt" ]; then
    echo "requirements.txt already exists. Skipping creation."
else
    touch "$PROJECT_PATH/code/requirements.txt"
fi
code "$PROJECT_PATH/code/requirements.txt"

# 7) 레포 내부에 Dockerfile이 있는지 검사
#    (code/ 최상위에 있다고 가정)
if [ -f "$PROJECT_PATH/code/Dockerfile" ]; then
    echo "--------------------------------------------------"
    echo "A Dockerfile already exists in the cloned repository."
    # => 사용자가 별도의 명시(–skip-dockerfile) 없어도 스킵 가능
    REPO_DOCKERFILE="$PROJECT_PATH/code/Dockerfile"
    SKIP_DOCKERFILE=true
fi

# 8) 만약 skip-dockerfile이 false라면, 기본 스켈레톤 Dockerfile 생성
if [ "$SKIP_DOCKERFILE" = false ]; then
    cat << 'EOF' > "$PROJECT_PATH/Dockerfile"
# 연구실 공용 이미지를 베이스로 사용합니다.
FROM 9root3/ai-research-base:latest

# 이 프로젝트에만 필요한 추가적인 Python 라이브러리를 설치합니다.
# 먼저 requirements.txt를 복사하여 Docker 캐시를 활용합니다.
COPY ./code/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt || true

# 기본 작업 디렉토리를 /workspace로 설정
WORKDIR /workspace

EOF
    echo "Default Dockerfile created at '$PROJECT_PATH/Dockerfile'."
else
    echo "Skipped creating Dockerfile (either --skip-dockerfile given or Dockerfile found in repo)."
    mv "$REPO_DOCKERFILE" "$PROJECT_PATH/Dockerfile"
fi
code "$PROJECT_PATH/Dockerfile"
echo "--------------------------------------------------"

echo "Project '$PROJECT_NAME' created successfully at '$PROJECT_PATH'."
echo "code/ folder contains the cloned repo."
echo "requirements.txt also generated (empty)." 
echo "Please modify files as needed and build the image using 'bash utils/build_image.sh $PROJECT_NAME [<tag>]'."