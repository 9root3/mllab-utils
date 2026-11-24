#!/bin/bash
# mllab-gpu 봇을 macOS launchd 서비스로 관리한다 (로그인 시 자동 시작, 죽으면 자동 재시작, 절전 방지).
# 사용: ./service.sh install | uninstall | restart | status | logs
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.mllab.gpu-bot"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/mllab-gpu-bot.log"
DOMAIN="gui/$(id -u)"

case "${1:-}" in
  install)
    [ -x "$DIR/.venv/bin/python" ] || { echo "먼저 가상환경을 만드세요: python3 -m venv .venv && .venv/bin/pip install -r requirements.txt" >&2; exit 1; }
    [ -r "$DIR/.env" ] || { echo ".env 가 없습니다" >&2; exit 1; }
    if pgrep -f "python3? app.py" >/dev/null; then
      echo "경고: 수동으로 띄운 봇이 실행 중입니다. 중복 실행하면 /gpu 응답이 불안정해지니 먼저 종료하세요." >&2; exit 1
    fi
    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$DIR/run.sh</string></array>
  <key>WorkingDirectory</key><string>$DIR</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>30</integer>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin</string>
  </dict>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict></plist>
EOF
    chmod 600 "$PLIST"
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$PLIST"
    echo "설치 완료. 로그: $LOG"
    ;;
  uninstall)
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$PLIST"; echo "제거 완료"
    ;;
  restart)
    launchctl kickstart -k "$DOMAIN/$LABEL"; echo "재시작 요청 완료"
    ;;
  status)
    launchctl print "$DOMAIN/$LABEL" 2>/dev/null | grep -E "state =|pid =|last exit code|runs =" || echo "등록되지 않음"
    pgrep -fl "caffeinate.*python" || true
    ;;
  logs)
    tail -n "${2:-50}" -f "$LOG"
    ;;
  *)
    echo "사용: $0 install|uninstall|restart|status|logs" >&2; exit 2
    ;;
esac
