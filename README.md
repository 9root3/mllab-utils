# MLLAB-UTILS

`mllab-utils`는 여러 연구실 서버 노드에서 같은 방식으로 ML 연구 환경을 만들고 실행하기 위한 작은 Bash CLI입니다. 공식 진입점은 `pm.sh`이며, 설치 후에는 `mllab` 명령으로 사용할 수 있습니다.

## 구조

```text
mllab-utils/
  pm.sh                    # 공식 단일 진입점
  install.sh               # ~/.local/bin/mllab symlink 설치
  VERSION                  # 배포/태그 기준 버전
  config/default.env       # 기본 설정값
  templates/               # 생성되는 Dockerfile, .dockerignore 템플릿
  scripts/                 # pm.sh가 호출하는 내부 구현
  tests/smoke.sh           # 최소 문법/dry-run 검증
```

기존 `build_image.sh`, `create_container.sh`, `make_project.sh` 같은 루트 스크립트는 호환성을 위해 남겨둔 얇은 wrapper입니다. 새 문서와 운영 기준은 모두 `mllab` 또는 `pm.sh`를 기준으로 합니다.

## 설치

각 서버에서 저장소를 클론한 뒤:

```bash
cd ~/mllab-utils
bash install.sh
```

기본 설치 결과는 다음 symlink입니다.

```text
~/.local/bin/mllab -> ~/mllab-utils/pm.sh
```

`~/.local/bin`이 `PATH`에 없다면 쉘 설정에 추가합니다.

```bash
export PATH="$HOME/.local/bin:$PATH"
```

설치하지 않고 바로 쓰려면 다음처럼 실행해도 됩니다.

```bash
bash ~/mllab-utils/pm.sh help
```

## 서버별 설정

서버마다 다른 값은 코드가 아니라 config 파일에 둡니다.

```bash
mkdir -p ~/.config/mllab-utils
cp ~/mllab-utils/config/default.env ~/.config/mllab-utils/config.env
vim ~/.config/mllab-utils/config.env
```

주요 설정값:

```bash
MLLAB_PROJECTS_DIR=$HOME
MLLAB_IMAGE_NAMESPACE=$(whoami)
MLLAB_BASE_IMAGE=9root3/ai-research-base:latest
MLLAB_DEFAULT_TAG=latest
MLLAB_DEFAULT_PORT=8888
MLLAB_DEFAULT_GPUS=0,1,2,3
MLLAB_DATA_DIR=/media/data2
MLLAB_CONTAINER_WORKDIR=/workspace
MLLAB_UTILS_MOUNT=/utils
MLLAB_CODE_DIR=code
MLLAB_CONTAINER_PREFIX=$(whoami)_
```

예를 들어 어떤 노드의 데이터 디렉터리가 `/data/shared`라면 그 서버의 `config.env`에만 다음처럼 적습니다.

```bash
MLLAB_DATA_DIR=/data/shared
```

현재 적용되는 설정은 언제든 확인할 수 있습니다.

```bash
mllab config
```

## 기본 워크플로우

새 프로젝트 생성:

```bash
mllab init my-project https://github.com/user/repo.git
```

프로젝트 이미지를 빌드:

```bash
mllab build my-project v1
```

컨테이너를 생성하고 접속:

```bash
mllab start -g 0,1 -p 8888 my-project
```

다른 사용자의 이미지를 바로 사용:

```bash
mllab start -g 0 -i someuser/pytorch:latest my-project
```

기존 컨테이너에 다시 접속:

```bash
mllab attach "$(whoami)_my-project"
```

컨테이너 중지/삭제:

```bash
mllab stop my-project
mllab rm my-project
```

## 명령어

```text
mllab help
mllab version
mllab config
mllab init <project> <git_url> [--skip-dockerfile]
mllab build [-c|--no-cache] [--dry-run] <project> [tag]
mllab start [options] <project>
mllab create [options] <project>
mllab attach <container_name>
mllab stop [-n name] <project>
mllab rm [-n name] <project>
mllab gpu
mllab sizes
mllab test
```

`mllab start`와 `mllab create`의 주요 옵션:

```text
-p, --port PORT
-t, --tag TAG
-n, --name NAME
-g, --gpus GPUS
-i, --image IMAGE
-r, --replace
-d, --dry-run
```

`--dry-run`은 Docker 명령을 실제 실행하지 않고, 실행될 명령만 출력합니다.

## GPU/컨테이너 보조 도구

GPU 사용 프로세스와 Docker 컨테이너 이름 확인:

```bash
mllab gpu
```

실행 중인 컨테이너의 크기 정보 확인:

```bash
mllab sizes
```

## 검증

로컬 변경 후 최소 검증:

```bash
bash tests/smoke.sh
```

이 테스트는 `bash -n`, `mllab help/config`, `build --dry-run`, `start --dry-run`, `install --dry-run`을 확인합니다. `shellcheck`가 설치되어 있으면 추가 lint도 실행합니다.

설치 후에는 같은 검증을 다음처럼 실행할 수도 있습니다.

```bash
mllab test
```

## 배포 운영

여러 서버 노드에서 같은 버전을 쓰려면 Git tag를 기준으로 배포합니다.

```bash
git tag v0.2.0
git push origin v0.2.0
```

각 서버에서는 필요한 버전으로 checkout합니다.

```bash
cd ~/mllab-utils
git fetch --tags
git checkout v0.2.0
```

버전 문자열은 `VERSION` 파일과 `mllab version`으로 확인합니다.
