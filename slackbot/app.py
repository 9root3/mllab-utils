#!/usr/bin/env python3
"""mllab GPU 현황 Slack 봇 (Socket Mode: 공개 URL/포트 불필요).

- `/gpu [free | node 72 | user eklee]`  슬래시 명령
- `@봇 [같은 인자]`                     멘션
- 🔄/🟢/📋 버튼                          새로고침·뷰 전환 (메시지를 제자리에서 갱신)
- DIGEST_CHANNEL + DIGEST_TIMES          정해진 시각에 자동 게시
ssh 접속이 가능한 머신(~/.ssh/config 에 mllab-* 등록)에서 실행해야 한다.
"""
import importlib.util
import logging
import os
import threading
import time
from datetime import datetime
from pathlib import Path

from slack_bolt import App
from slack_bolt.adapter.socket_mode import SocketModeHandler

from blocks import build_blocks, parse_query

ROOT = Path(__file__).resolve().parent.parent
_spec = importlib.util.spec_from_file_location("fleet_gpu", ROOT / "scripts" / "fleet_gpu.py")
fleet = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fleet)

CACHE_TTL = int(os.environ.get("CACHE_TTL", "20"))      # 초: 이 안의 반복 조회는 캐시 사용
SSH_TIMEOUT = int(os.environ.get("SSH_TIMEOUT", "40"))
_cache = {"t": 0.0, "data": None}
_lock = threading.Lock()


def snapshot(force=False):
    """ssh 폭주를 막기 위해 짧게 캐시한다. 새로고침 버튼도 5초 안에는 캐시를 재사용."""
    with _lock:
        age = time.time() - _cache["t"]
        if _cache["data"] is None or age > (5 if force else CACHE_TTL):
            _cache["data"] = fleet.collect(timeout=SSH_TIMEOUT)
            _cache["t"] = time.time()
        return _cache["data"], _cache["t"]


def render(text, force=False):
    results, t = snapshot(force)
    return build_blocks(results, parse_query(text), now=t)


log = logging.getLogger("mllab-gpu")
app = App(token=os.environ["SLACK_BOT_TOKEN"])


@app.command("/gpu")
def on_gpu(ack, command, respond):
    log.info("/gpu from %s in %s: %r", command.get("user_name"), command.get("channel_name"), command.get("text"))
    ack("⏳ 노드 조회 중… (최대 수십 초)")  # 본인에게만 보이는 즉시 응답
    try:
        blocks, fb = render(command.get("text", ""))
        r = respond(blocks=blocks, text=fb, response_type="in_channel")
        log.info("respond -> %s %s", getattr(r, "status_code", "?"), str(getattr(r, "body", ""))[:300])
    except Exception as e:
        log.exception("/gpu failed")
        respond(text=f"⚠️ 조회 실패: {e}", response_type="ephemeral")


@app.event("app_mention")
def on_mention(event, say):
    text = " ".join(w for w in event.get("text", "").split() if not w.startswith("<@"))
    blocks, fb = render(text)
    say(blocks=blocks, text=fb, thread_ts=event.get("thread_ts") or event["ts"])


@app.action("gpu_refresh")
@app.action("gpu_view_free")
@app.action("gpu_view_all")
def on_button(ack, action, respond):
    ack()
    blocks, fb = render(action.get("value", ""), force=action["action_id"] == "gpu_refresh")
    r = respond(blocks=blocks, text=fb, replace_original=True)
    log.info("button respond -> %s %s", getattr(r, "status_code", "?"), str(getattr(r, "body", ""))[:300])


def digest_loop():
    channel = os.environ.get("DIGEST_CHANNEL")
    times = {t.strip() for t in os.environ.get("DIGEST_TIMES", "").split(",") if t.strip()}
    if not channel or not times:
        return
    last = None
    while True:
        now = datetime.now().strftime("%H:%M")
        if now in times and now != last:
            last = now
            try:
                blocks, fb = render(os.environ.get("DIGEST_QUERY", ""), force=True)
                app.client.chat_postMessage(channel=channel, blocks=blocks, text=fb)
            except Exception:
                logging.exception("digest failed")
        time.sleep(20)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    threading.Thread(target=digest_loop, daemon=True).start()
    SocketModeHandler(app, os.environ["SLACK_APP_TOKEN"]).start()
