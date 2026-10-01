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
~/.local/bin/mllab -> ~/mllab-utils/scripts/launcher.sh
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
MLLAB_GPU_BACKEND=auto
MLLAB_NVIDIA_DRIVER_CAPABILITIES=compute,utility
MLLAB_DATA_DIR=/media/data2
MLLAB_CONTAINER_WORKDIR=/workspace
MLLAB_UTILS_MOUNT=/utils
MLLAB_CODE_DIR=code
MLLAB_CONTAINER_PREFIX=$(whoami)_
MLLAB_RUN_AS_HOST_USER=false
MLLAB_CONTAINER_HOME=/workspace/.home
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

root-owned 파일 생성을 피하며 접속:

```bash
mllab attach --host-user "$(whoami)_my-project"
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
mllab status
mllab doctor [--image IMAGE] [-g IDS] [--gpu-backend auto|runtime|gpus] [--dry-run]
mllab sizes
mllab preflight [options]
mllab test
```

`mllab start`와 `mllab create`의 주요 옵션:

```text
-p, --port PORT
-t, --tag TAG
-n, --name NAME
-g, --gpus GPUS
--gpu-backend auto|runtime|gpus
-i, --image IMAGE
--host-user
--root
-r, --replace
-d, --dry-run
```

`--dry-run`은 Docker 명령을 실제 실행하지 않고, 실행될 명령만 출력합니다.

GPU 작업을 시작하기 전에 노드의 Docker daemon, NVIDIA runtime, driver, GPU ID, data directory를 확인하려면:

```bash
mllab preflight -g 0,1
```

CPU-only 컨테이너는 다음처럼 확인합니다.

```bash
mllab preflight -g none
```

GPU 없이 CPU-only 컨테이너를 만들고 싶다면 `-g none`을 사용합니다.

```bash
mllab create -g none my-project
```

GPU backend 기본값은 `auto`입니다. 실행 시 Docker의 runtime 목록에 `nvidia`가 등록되어 있으면 `runtime`, 없으면 `gpus`를 선택합니다. 노드 이름이나 GPU 모델에 의존하지 않고 Docker 설정을 읽으며, 서버 설정을 변경하거나 진단 container를 자동 생성하지 않습니다. 보통 `--gpu-backend`를 지정할 필요가 없습니다. 특수 환경에서는 `--gpu-backend runtime` 또는 `gpus`로 고정할 수 있습니다. 다중 GPU 선택의 Docker quoting은 내부적으로 처리합니다. `auto`의 dry-run은 Docker daemon에 접속하지 않고 두 후보 명령과 선택 조건을 표시합니다. Backend 탐지나 실행이 실패하면 명확하게 오류를 반환하며 다른 backend로 container 작업을 자동 재시도하지 않습니다.

컨테이너 안에서 코딩하면서 root-owned 파일 생성을 피하고 싶다면 `--host-user`를 사용합니다.

```bash
mllab create --host-user my-project
```

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

이 테스트는 `bash -n`, help/config, build/start/create/attach/install/doctor의 dry-run 및 인자 검증을 확인합니다. status/doctor의 mock regression tests도 실행하며 실제 GPU나 Docker daemon은 필요하지 않습니다. `shellcheck`가 설치되어 있으면 source 파일과 tests를 포함해 lint도 실행합니다.

설치 후에는 같은 검증을 다음처럼 실행할 수도 있습니다.

```bash
mllab test
```

## GPU 상태와 실행 진단

```bash
mllab status
# mllab gpu도 같은 상태를 표시합니다.
```

GPU index, 모델, VRAM/사용량, compute 점유 여부와 실제 compute PID의 container 이름을 표시합니다. `/proc/<pid>/cgroup`의 전체 64자리 ID를 `docker inspect`로 확인하며, 매핑하지 못한 PID는 `unmapped`로 남깁니다. `Compute-idle`은 조회 시점에 compute PID가 없다는 뜻이며, GPU 예약이나 그래픽 작업·메모리 여유를 보장하지 않습니다. Compute 조회 실패를 idle로 표시하지 않습니다.

실제 container 시작과 선택한 GPU의 UUID가 일치하는지 검사하려면:

```bash
mllab doctor --dry-run --image pytorch/pytorch:2.7.1-cuda12.8-cudnn9-devel -g 0,1
mllab doctor --image pytorch/pytorch:2.7.1-cuda12.8-cudnn9-devel -g 0,1
# CPU-only: 이미지에 /bin/sh가 있어야 합니다.
mllab doctor --image ubuntu:22.04 -g none
```

이미지는 이미 해당 노드에 있어야 하며 자동으로 pull하지 않습니다. 기본값은 `MLLAB_BASE_IMAGE`, GPU/backend 기본값은 노드 config를 사용합니다. Backend는 기본적으로 `auto`가 선택하므로 노드마다 지정할 필요가 없습니다. 기존 config에서 backend를 고정했다면 `MLLAB_GPU_BACKEND=auto`로 바꾸면 됩니다. 명령은 preflight 후 임시 container에서 `nvidia-smi` 또는 CPU marker만 실행합니다. Network, host mount, port 노출 없이 실행하며 성공·실패·timeout 시 자신이 만든 container ID만 정리합니다. GNU `timeout`이 필요하고, 시작 timeout은 기본 30초(`--timeout 1..300`)입니다. GPU compute 또는 PyTorch/CUDA 호환성을 검증하는 명령은 아닙니다.

## 배포 운영

여러 서버 노드에서 같은 버전을 쓰려면 Git tag를 기준으로 배포합니다.

```bash
git tag -a v0.3.1 -m "Release v0.3.1"
git push origin v0.3.1
```

각 서버에서는 필요한 버전으로 checkout합니다.

```bash
cd ~/mllab-utils
git fetch --tags
git checkout v0.3.1
```

버전 문자열은 `VERSION` 파일과 `mllab version`으로 확인합니다.

## LLM/Agent Usage

When asked to create a project container, prefer this sequence:

1. Run `mllab config` to inspect server defaults.
2. Run `mllab test` if this is a fresh clone.
3. Run `mllab preflight -g <gpus>` before a GPU workload.
4. If the project does not exist, run:
   `mllab init <project> <git_url>`
5. Build the image:
   `mllab build <project> <tag>`
6. Preview container creation first:
   `mllab start --dry-run -g <gpus> -p <port> <project>`
7. If the dry-run looks correct, run:
   `mllab start -g <gpus> -p <port> <project>`

Do not use `--replace`, `mllab rm`, or destructive Docker commands unless explicitly requested.

## 업데이트 알림과 Release 업데이트

터미널에서 `mllab`을 사용할 때 GitHub의 최신 stable Release를 하루 한 번 확인합니다. 새 버전이 있으면 stderr에 설치 버전, 최신 버전, `mllab update` 안내를 표시합니다. 결과는 `${XDG_CACHE_HOME:-$HOME/.cache}/mllab-utils/release`에 캐시하며 조회 실패도 하루 동안 캐시합니다. 네트워크 조회는 최대 3초이며 실패해도 원래 명령을 계속 실행합니다.

CI/비대화형 실행, `--dry-run`, help/version/test 명령에서는 자동 조회하지 않습니다. `MLLAB_NO_UPDATE_NOTIFIER=1`로 자동 알림을 끌 수 있습니다. GitHub에 stable Release를 발행해야 새 버전으로 안내됩니다. Main push만으로는 알리지 않습니다.

```bash
mllab update --check  # 캐시를 우회하여 최신 Release 확인
mllab update          # 최신 Release tag로 fast-forward
```

업데이트는 관리용 저장소에서 수행하며 main branch와 clean 작업 트리가 필요합니다. 선택된 구버전 저장소도 clean이어야 합니다. Local 수정이나 분기된 이력은 덮어쓰지 않습니다. `flock`으로 동시 업데이트를 막으며 사용자 config, 설치 symlink, 다른 파일, container는 변경하지 않습니다. Git과 curl이 필요하고, 업데이트 실행에는 Linux의 flock이 필요합니다. 자동 알림에는 Python/GitHub CLI가 필요하지 않습니다.


## 이전 Release로 롤백

```bash
mllab rollback 0.3.2  # 이전 버전으로 전환 (v0.3.2도 허용)
mllab version        # 실제 선택된 CLI 버전 확인
mllab update --check # 선택된 버전과 최신 Release 비교
mllab update         # 최신 Release로 복귀
```

v0.3.3부터 설치 symlink는 작은 launcher를 가리킵니다. Launcher는 관리용 저장소에 남아 알림·update·rollback을 처리하고, 다른 명령은 선택된 Release의 CLI에서 실행합니다. 그래서 알림이나 업데이트 명령이 없던 이전 버전으로 내려가도 알림과 최신 버전 복귀가 가능합니다. v0.3.2 이하에서 처음 업데이트한 경우 `bash install.sh`를 한 번 실행하여 launcher를 설치합니다. `bash pm.sh` 직접 호출에는 이 구버전 관리 기능이 적용되지 않습니다.

롤백은 요청한 stable version tag를 `${관리용_저장소}-releases/` 아래 별도 clone으로 설치한 후 관리용 저장소의 `.git/mllab-active`에 선택 경로를 atomic하게 기록합니다. 현재 저장소의 파일·이력을 되돌리거나 삭제하지 않으며, 사용자 config와 container도 바꾸지 않습니다. 완료된 구버전 clone은 설치본으로 보존하고 실패한 부분 clone만 정리합니다. Local 수정이 있거나 tag/VERSION이 다르면 전환하지 않습니다. 오래된 Release의 옵션·GPU backend·동작은 해당 버전을 따르므로 현재 config와의 호환성을 확인해야 합니다.

SSH 접속 자체는 최신 버전을 확인하지 않습니다. `mllab` 사용 시 launcher가 선택된 설치본의 `VERSION`과 GitHub 최신 stable Release를 비교하며, 즉시 확인하려면 `mllab update --check`를 실행합니다. 자동 조회는 하루 캐시를 사용하고 네트워크 장애가 원래 명령을 막지 않습니다.
