#!/bin/bash
# launchd 가 호출하는 봇 시작 스크립트. 토큰은 .env 에서만 읽는다(plist 에 넣지 않음).
# caffeinate -i -s : 봇이 떠 있는 동안 유휴/시스템 절전을 막는다 (-s 는 전원 어댑터 연결 시에만 유효).
set -euo pipefail
cd "$(dirname "$0")"
[ -r .env ] || { echo "ERROR: $(pwd)/.env 가 없습니다" >&2; exit 78; }
set -a; . ./.env; set +a
export PYTHONUNBUFFERED=1
exec /usr/bin/caffeinate -i -s "$(pwd)/.venv/bin/python" app.py
