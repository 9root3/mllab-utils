# MLLAB-UTILS

이 저장소는 연구실 SSH 서버에서 **코드 개발**과 **공식 실험 실행**을 안정적으로 분리하기 위한 운영 유틸리티 모음입니다.

중요: **OpenClaw는 서버 내부에서 상시 실행되는 컴포넌트가 아니라, 각 사용자 로컬에서 실행되는 오케스트레이션 도구**를 전제로 합니다.

핵심 목표는 다음 세 가지입니다.

1. 개발 컨테이너와 실험 컨테이너를 분리해 재현성과 안정성을 높인다.
2. 프로젝트마다 동일한 명령 체계(`init/plan/run/eval/status`)를 제공한다.
3. OpenClaw(로컬)가 SSH로 서버 wrapper shell을 호출해 실험을 표준 경로로 실행한다.

---

## 이 레포가 해결하는 문제

연구실 서버에서는 보통 아래 문제가 반복됩니다.

- 프로젝트마다 실행 방식이 달라서 인수인계가 어렵다.
- 개발 중 임시 수정과 공식 실험 결과가 섞여 재현성이 깨진다.
- 어떤 설정으로 돌렸는지(run metadata) 추적이 어렵다.

`mllab-utils`는 이 문제를 다음 방식으로 해결합니다.

- **개발용 루틴**: 빠른 확인(dev mode), 디버깅/테스트 중심
- **실험용 루틴**: 공식 실행(exp mode), 결과/메타데이터 표준 저장
- **OpenClaw 연동**: 로컬 OpenClaw가 SSH + 서버 wrapper 호출로 자동화

---

## 저장소 구성 요약

```text
openclaw/      # OpenClaw 액션 명세/스키마/러너
harness/       # 표준 CLI와 코어 로직
experiments/   # 실험 config/suite
artifacts/     # 실행별 결과물 저장 (artifacts/<run_id>/)
logs/          # 공용 로그 보관
scripts/       # 실행 편의 스크립트
docs/          # 구조/운영 문서
```

---

## 가장 중요한 사용 원칙

- `--mode dev`: 개발 컨테이너에서 빠른 사전 점검
- `--mode exp`: 공식 실험 경로 (결과 보관/추적 대상)
- 공식 기록이 필요한 실험은 반드시 `exp`로 실행
- 템플릿 엔진 기반 자동 보일러플레이트 생성은 사용하지 않음

운영 분리:

- **Control Plane(로컬)**: OpenClaw
- **Data Plane(서버)**: 실험 컨테이너 + wrapper shell + harness runner

---

## 연구실 서버에서 처음 시작할 때

아래 흐름은 `/home/gglee/<project>` 기준 권장 절차입니다.

### 1) 프로젝트 디렉터리 준비

```bash
cd /home/gglee
mkdir -p <project>
cd <project>
git clone <repo-url> .
```

### 2) Python 환경 준비

```bash
python3 -m venv .venv
./.venv/bin/pip install -r requirements-harness.txt
```

### 3) Harness 초기화

```bash
./scripts/harness init --name <project> --runtime python --no-template
```

---

## 일상 개발/실험 루틴 (권장)

### A. 개발 단계 (코딩 + 사전 점검)

```bash
./scripts/harness plan --config experiments/configs/baseline.yaml
./scripts/harness run --config experiments/configs/baseline.yaml --mode dev
```

- `plan`: config/schema 검증
- `run --mode dev`: 빠른 검증 실행

### B. 공식 실험 단계 (서버 wrapper 기준)

```bash
./scripts/exp-run.sh experiments/configs/baseline.yaml params.seed=42
```

OpenClaw를 쓰는 경우에도 본질은 동일합니다.

- OpenClaw는 로컬에서 실행
- SSH로 연구실 서버 접속
- 서버 내 **이미 정해진 wrapper shell script** 호출
- 실험마다 config/override만 교체

예시(개념):

```bash
ssh gglee@<lab-server> "cd /home/gglee/<project> && ./scripts/exp-run.sh experiments/configs/baseline.yaml params.seed=42"
```

### C. 결과 확인/평가

```bash
./scripts/harness status --run-id <run_id>
./scripts/harness eval --run-id <run_id>
```

결과는 항상 `artifacts/<run_id>/`에 기록됩니다.

---

## Harness 명령 레퍼런스

직접 실행:

```bash
python3 -m harness.cli.main init --name <project> --runtime <python|node> --no-template
python3 -m harness.cli.main plan --config experiments/configs/<x>.yaml
python3 -m harness.cli.main run --config experiments/configs/<x>.yaml --mode <dev|exp>
python3 -m harness.cli.main eval --run-id <id>
python3 -m harness.cli.main status --run-id <id>
```

스크립트 실행:

```bash
./scripts/harness plan --config experiments/configs/baseline.yaml
./scripts/dev-test.sh
./scripts/exp-run.sh experiments/configs/baseline.yaml params.seed=42
```

---

## OpenClaw 연동 포인트 (정정)

- OpenClaw 실행 위치: **사용자 로컬 머신**
- 서버 역할: SSH 진입점 + wrapper shell 실행 환경
- 실험 실행 인터페이스: 서버 내 wrapper(`scripts/exp-run.sh` 또는 연구실 표준 wrapper)

이 저장소의 `openclaw/` 디렉터리는 서버 상주 서비스가 아니라,

- 액션 계약 문서화
- 로컬/테스트용 호출 인터페이스 참고

를 위한 참조 구현입니다.

예시 payload(로컬 OpenClaw가 보유):

```json
{
  "action": "experiment-run",
  "project": "mllab-utils",
  "config": "experiments/configs/baseline.yaml",
  "mode": "exp",
  "overrides": {
    "params.lr": 0.0005,
    "params.seed": 42
  }
}
```

---

## 실행 산출물(재현성/추적성)

각 실행은 `artifacts/<run_id>/`에 저장됩니다.

- `metadata.json`: `run_id`, `git_commit`, `image_digest`, `start_ts/end_ts`, `config_hash`
- `result.json`: 실행 상태/출력/요약
- `run.log.jsonl`: JSON Lines 실행 로그

이 정보로 “어떤 코드/환경/설정으로 나온 결과인지”를 역추적할 수 있습니다.

---

## 보안 운영 가이드 (필독)

### 주의해야 할 위험

- `experiments/configs/*.yaml`의 `entrypoint`는 쉘 명령으로 실행됩니다.
- 신뢰되지 않은 `container_image` 사용 시 악성 코드 위험이 있습니다.
- 레거시 `create_container.sh`는 `GEMINI_API_KEY`를 컨테이너로 전달할 수 있습니다.

### 권장 정책

- 실험 config는 리뷰 후 병합된 것만 사용
- 컨테이너 이미지는 digest 고정(`repo/image@sha256:...`)
- 민감정보는 최소 전달(필요 시에만 export)
- 공식 실험은 서버 wrapper + `--mode exp` 경로로만 수행
- `umask 027` 등으로 `artifacts/`, `logs/` 접근권한 제한

추가 권장:

- OpenClaw에서 서버 실행 시 허용된 wrapper만 호출(allowlist)
- SSH 키 기반 인증 + 최소 권한 계정 사용

---

## 이 레포의 스크립트 체계

### 1) 표준 경로 (권장)

- `scripts/harness`
- `scripts/dev-test.sh`
- `scripts/exp-run.sh`

### 2) 레거시 경로 (하위 호환)

- `pm.sh`, `build_image.sh`, `create_container.sh`, `start_container.sh` 등

레거시 스크립트는 기존 사용자 흐름 유지 목적이며, 새 프로젝트는 Harness/OpenClaw 경로를 우선 권장합니다.