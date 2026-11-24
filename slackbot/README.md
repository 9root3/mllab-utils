# mllab GPU Slack 봇

`scripts/fleet_gpu.py`의 조회 결과를 Slack Block Kit으로 보여 주는 봇입니다. Socket Mode라서 공개 URL이나 포트 개방이 필요 없습니다.

## 사용법

| 입력 | 결과 |
|---|---|
| `/gpu` | 전체 요약 + 노드별 GPU 막대 + 사용자별 + 쓸 수 있는 GPU |
| `/gpu free` | 빈 GPU만 |
| `/gpu node 72` | 특정 노드만 |
| `/gpu user eklee` | 특정 사용자가 쓰는 GPU만 |
| `@mllab-gpu free` | 멘션도 같은 인자, 스레드로 답함 |
| 🔄 / 🟢 / 📋 버튼 | 새로고침, 빈 GPU만, 전체 (메시지를 제자리에서 갱신) |

정해진 시각에 채널로 자동 게시하는 다이제스트도 지원합니다.

## 설치

1. <https://api.slack.com/apps> → **Create New App → From a manifest** → `manifest.yaml` 붙여넣기 → 워크스페이스에 설치.
2. **Basic Information → App-Level Tokens** 에서 `connections:write` 스코프로 토큰 생성 (`xapp-...`).
3. **OAuth & Permissions** 의 Bot User OAuth Token (`xoxb-...`) 복사.
4. 환경 설정:

```bash
cd slackbot
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env     # 토큰 입력 (.env 는 커밋하지 않음)
set -a; . ./.env; set +a
python3 app.py
```

## 실행 위치

노드 조회는 `ssh mllab-*`로 하므로 **ssh 키로 비밀번호 없이 접속되는 머신**에서 실행해야 합니다 (`~/.ssh/config`에 `Host mllab-*` 등록). 봇이 항상 떠 있어야 하면 상시 켜 둘 수 있는 머신에서 `tmux`/`launchd`/`systemd`로 돌리세요. 노트북에서 돌리면 노트북이 꺼질 때 봇도 멈춥니다.

## 환경변수

| 이름 | 필수 | 설명 |
|---|---|---|
| `SLACK_BOT_TOKEN` | ✓ | `xoxb-...` |
| `SLACK_APP_TOKEN` | ✓ | `xapp-...` (Socket Mode) |
| `DIGEST_CHANNEL` | | 자동 게시할 채널 ID 또는 `#이름` |
| `DIGEST_TIMES` | | 자동 게시 시각(로컬 시간), 예: `09:00,18:00` |
| `DIGEST_QUERY` | | 자동 게시에 쓸 인자, 예: `free` |
| `CACHE_TTL` | | 조회 캐시 초 (기본 20). 연타해도 ssh가 폭주하지 않음 |
| `SSH_TIMEOUT` | | 노드별 조회 제한 초 (기본 40) |

## 동작 기준

- GPU compute 프로세스가 실제로 있는 컨테이너만 "사용 중"으로 봅니다. 떠 있기만 한 컨테이너는 무시합니다.
- 사용자는 컨테이너 이름의 첫 `_` 앞 접두사입니다.
- 결과는 스냅샷이며 예약이 아닙니다.
- 읽기 전용입니다. 노드에는 `nvidia-smi`, `docker ps/top/inspect` 조회만 실행합니다.
