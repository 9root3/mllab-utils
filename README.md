# MLLAB-UTILS

`mllab-utils`는 [연구실 이름]의 AI/ML 연구 프로젝트를 위한 환경 구성 및 관리를 자동화하는 유틸리티 스크립트 모음입니다. 이 도구들은 Docker를 기반으로, 재현 가능하고 일관된 연구 환경을 신속하게 구축하는 것을 목표로 합니다.

## 🚀 워크플로우 개요

이 유틸리티들은 다음과 같은 체계적인 워크플로우를 지원합니다.

1.  **`init`**: Git 저장소를 기반으로 새로운 프로젝트 디렉토리 구조를 생성합니다. (`make_project.sh`)
2.  **`build`**: 프로젝트에 맞는 Docker 이미지를 빌드합니다. (`build_image.sh`)
3.  **`start`**: 빌드된 이미지를 사용하여 프로젝트 전용 Docker 컨테이너를 생성하고 실행합니다. (`create_container.sh`)

이 모든 과정은 단일 진입점인 `pm.sh` (Project Manager)를 통해 더욱 편리하게 관리할 수 있습니다.

-----

## 🛠️ 스크립트 소개

### 1\. `pm.sh` (Project Manager)

모든 유틸리티 스크립트를 총괄하는 메인 스크립트입니다. 대부분의 경우, 이 스크립트만 사용하게 됩니다.

**사용법:**

```bash
bash utils/pm.sh <command> [options]
```

**주요 명령어:**

  * `help`: 사용 가능한 모든 명령어를 보여줍니다.
  * `init <proj_name> <git_url>`: 새 프로젝트를 초기화합니다.
  * `build <proj_name> [<tag>]`: 프로젝트 이미지를 빌드합니다.
  * `start <proj_name> [options]`: 프로젝트 컨테이너를 생성하고 시작합니다.
  * `stop <proj_name>`: 프로젝트 컨테이너를 중지합니다.
  * `rm <proj_name>`: 프로젝트 컨테이너를 삭제합니다.

### 2\. `make_project.sh`

Git 저장소를 복제하여 표준 프로젝트 디렉토리 구조를 생성합니다.

**주요 기능:**

  * `git clone`을 통해 `code/` 디렉토리 생성
  * `Dockerfile` 및 `requirements.txt` 자동 생성 (레포지토리에 없을 경우)
  * 프로젝트 이름 소문자 강제 등 일관성 유지

### 3\. `build_image.sh`

프로젝트 디렉토리의 `Dockerfile`을 기반으로 Docker 이미지를 빌드합니다.

**주요 기능:**

  * `사용자명_프로젝트명:태그` 형식의 일관된 이미지 이름 생성
  * `.dockerignore` 파일을 자동으로 생성하여 빌드 효율성 최적화
  * `--no-cache` 빌드 옵션 지원 (`-c`)

### 4\. `create_container.sh`

빌드된 이미지를 사용하여 연구용 컨테이너를 생성합니다.

**주요 기능:**

  * `사용자명_프로젝트명` 형식의 컨테이너 이름 자동 생성
  * 프로젝트 코드, 공용 `utils` 폴더, 데이터셋 폴더 자동 마운트
  * 호스트의 `GEMINI_API_KEY`를 컨테이너에 안전하게 주입
  * GPU, 포트 등 다양한 옵션 커스터마이징 지원

-----

## 🏁 시작하기

### 1\. `utils` 저장소 클론

각 서버 노드에 처음 접속했을 때, 홈 디렉토리에 이 `utils` 저장소를 클론합니다.

```bash
cd ~
git clone git@github.com:9root3/mllab-utils.git utils
```

### 2\. API 키 설정

Gemini CLI를 사용하기 위해, 호스트 서버의 쉘 설정 파일에 API 키를 등록합니다.

```bash
echo 'export GEMINI_API_KEY="YOUR_API_KEY_HERE"' >> ~/.bashrc
source ~/.bashrc
```

### 3\. 새 프로젝트 시작하기

`pm.sh`를 사용하여 새 프로젝트를 시작하는 전체 과정입니다.

```bash
# 1. Git 레포로부터 'my-new-project'라는 이름의 프로젝트를 생성합니다.
bash utils/pm.sh init my-new-project https://github.com/user/repo.git

# 2. 프로젝트에 필요한 Python 라이브러리를 requirements.txt에 추가합니다.
cd my-new-project/code && vim(or code) requirements.txt

# 3. 프로젝트 전용 이미지를 빌드합니다. (태그: v1)
bash utils/pm.sh build my-new-project v1

# 4. 컨테이너를 생성하고 바로 접속합니다. (GPU 0, 1번 사용)
#    -i 옵션으로 방금 빌드한 이미지를 명시하거나, 공용 이미지를 사용할 수 있습니다.
bash utils/pm.sh start -g 0,1 -i 9root3/my-new-project:v1 my-new-project
```

이제 모든 설정이 완료된 컨테이너 내부에서 연구 개발을 시작할 수 있습니다.