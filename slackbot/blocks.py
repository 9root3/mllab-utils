"""GPU 조회 결과 -> Slack Block Kit 메시지. Slack/네트워크 의존성이 없어 단독 테스트가 가능하다.

보기 방식(view)
  compact(기본) : 한 줄 요약 + 노드당 한 줄짜리 격자
  free          : 지금 쓸 수 있는 GPU만 (모델·VRAM 병기)
  detail        : GPU별 메모리 막대 (예전 상세 보기). node 필터를 주면 자동으로 상세.
"""
import re
import time
from collections import defaultdict

BAR_LEN = 10
BUSY, IDLE = "●", "○"


def parse_query(text):
    """`/gpu` 인자 파싱. 예: '', 'free', 'detail', 'node 72', 'user eklee'.
    반환: dict(view: compact|free|detail, nodes: set[str], users: set[str])"""
    q = {"view": "compact", "nodes": set(), "users": set()}
    toks = (text or "").replace("@", " ").replace(",", " ").split()
    mode = None
    for t in toks:
        tl = t.lower()
        if tl in ("all", "전체", "compact", "요약"):
            q["view"] = "compact"
        elif tl in ("free", "idle", "빈", "유휴"):
            q["view"] = "free"
        elif tl in ("detail", "details", "상세"):
            q["view"] = "detail"
        elif tl in ("node", "nodes", "노드"):
            mode = "nodes"
        elif tl in ("user", "users", "사용자"):
            mode = "users"
        elif re.fullmatch(r"(mllab-)?\d+", tl):
            q["nodes"].add(tl.replace("mllab-", ""))
        elif re.fullmatch(r"[\w.-]+", tl):
            q["users"].add(tl)
    if q["nodes"] and q["view"] == "compact":
        q["view"] = "detail"  # 특정 노드를 지목하면 자세히
    return q


def query_to_text(q):
    parts = []
    if q["view"] != "compact" and not (q["view"] == "detail" and q["nodes"]):
        parts.append(q["view"])
    if q["nodes"]:
        parts.append("node " + " ".join(sorted(q["nodes"], key=int)))
    if q["users"]:
        parts.append("user " + " ".join(sorted(q["users"])))
    return " ".join(parts)


def _gib(mib):
    return mib / 1024


def _bar(used, total):
    f = round(BAR_LEN * used / total) if total else 0
    if used >= 512:  # 0.5GiB 미만은 드라이버 기본 점유로 보고 0칸
        f = max(f, 1)
    return "▰" * f + "▱" * (BAR_LEN - f)


def _short_model(name):
    n = name.replace("NVIDIA ", "").replace("GeForce ", "").replace("-PCIE-40GB", "")
    return n.replace(" Blackwell Server Edition", "")


def _node(host):
    return host.replace("mllab-", "")


def _rng(v):
    v = sorted(v)
    out, s, p = [], v[0], v[0]
    for x in v[1:] + [None]:
        if x is not None and x == p + 1:
            p = x
            continue
        out.append(f"{s}" if s == p else f"{s}~{p}")
        if x is not None:
            s = p = x
    return ",".join(out)


def _node_matches(q, node, gpus):
    if q["nodes"] and node not in q["nodes"]:
        return False
    if q["users"] and not any(set(g["users"]) & q["users"] for g in gpus):
        return False
    return True


def _who(gpus):
    """노드의 사용자 표기. 한 명이면 이름만, 여러 명이면 이름(GPU범위)."""
    by = defaultdict(list)
    for g in gpus:
        for u in g["users"]:
            by[u].append(g["idx"])
    if not by:
        return "—"
    if len(by) == 1:
        return next(iter(by))
    return " ".join(f"{u}({_rng(ix)})" for u, ix in sorted(by.items()))


def _compact_grid(ok, q):
    rows = []
    maxg = max(len(g) for _, g in ok)
    for host, gpus in ok:
        node = _node(host)
        if not _node_matches(q, node, gpus):
            continue
        syms = " ".join(BUSY if g["users"] else IDLE for g in gpus)
        rows.append(f"{node:>3}  {syms:<{2 * maxg - 1}}  "
                    f"{_short_model(gpus[0]['name'])[:12]:<12} {round(_gib(gpus[0]['total'])):>3}G  {_who(gpus)}")
    return rows, maxg


def _free_groups(ok, q):
    free = defaultdict(list)
    for host, gpus in ok:
        if q["nodes"] and _node(host) not in q["nodes"]:
            continue
        for x in gpus:
            if not x["users"]:
                free[(_node(host), _short_model(x["name"]), round(_gib(x["total"])))].append(x["idx"])
    return sorted(free.items(), key=lambda kv: int(kv[0][0]))


def build_blocks(results, q=None, now=None):
    """results: fleet_gpu.collect() 결과. 반환: (blocks, fallback_text)"""
    q = q or parse_query("")
    now = int(now or time.time())
    ok = [(h, g) for h, g, _ in results if g]
    errs = [(h, e) for h, g, e in results if not g]

    total = sum(len(g) for _, g in ok)
    idle = sum(1 for _, g in ok for x in g if not x["users"])
    busy = total - idle
    users = {u for _, g in ok for x in g for u in x["users"]}

    fallback = f"mllab GPU: 전체 {total} · 사용 중 {busy} · 유휴 {idle}"
    blocks = [
        {"type": "section", "text": {"type": "mrkdwn", "text":
            f"*🖥️ mllab GPU*   🟢 *{idle}* 유휴   🔴 *{busy}* 사용 중   전체 {total}   👥 {len(users)}명"}},
    ]

    view = q["view"]
    if not ok:
        blocks.append({"type": "section", "text": {"type": "mrkdwn", "text": "_조회된 노드가 없습니다._"}})

    elif view == "compact":
        rows, maxg = _compact_grid(ok, q)
        if rows:
            head = f"{'node':>3}  {'GPUs':<{2 * maxg - 1}}  {'model':<12} {'VRAM':>4}  user"
            blocks.append({"type": "section", "text": {"type": "mrkdwn",
                           "text": "```\n" + head + "\n" + "\n".join(rows) + "\n```"}})
        else:
            blocks.append({"type": "section", "text": {"type": "mrkdwn", "text": "_조건에 맞는 노드가 없습니다._"}})
        groups = _free_groups(ok, q)
        if groups:
            blocks.append({"type": "section", "text": {"type": "mrkdwn", "text":
                "🟢 *빈 GPU*  " + "  ".join(f"`{n}`:{_rng(ix)}" for (n, _, _), ix in groups)}})

    elif view == "free":
        groups = _free_groups(ok, q)
        if groups:
            lines = [f"`{n:>3}`  GPU {_rng(ix)}  ·  {m}  *{v}GB*" for (n, m, v), ix in groups]
            blocks.append({"type": "section", "text": {"type": "mrkdwn",
                           "text": "🟢 *지금 쓸 수 있는 GPU*\n" + "\n".join(lines)}})
        else:
            blocks.append({"type": "section", "text": {"type": "mrkdwn", "text": "_지금 비어 있는 GPU가 없습니다._"}})

    else:  # detail
        shown = 0
        for host, gpus in ok:
            node = _node(host)
            if not _node_matches(q, node, gpus):
                continue
            n_idle = sum(1 for x in gpus if not x["users"])
            vram = round(_gib(gpus[0]["total"]))
            head = f"*{node}*  ·  {_short_model(gpus[0]['name'])} ×{len(gpus)} ({vram}GB)  ·  유휴 *{n_idle}/{len(gpus)}*"
            rows = []
            for x in gpus:
                if q["users"] and x["users"] and not (set(x["users"]) & q["users"]):
                    continue
                if x["users"]:
                    who = ", ".join(x["users"])
                else:
                    who = "· idle" + (" ⚠ 프로세스 없이 메모리만 점유" if x["used"] >= 1024 else "")
                rows.append(f"GPU{x['idx']} {_bar(x['used'], x['total'])} "
                            f"{_gib(x['used']):5.1f}/{_gib(x['total']):.0f}G  {who}")
            if rows:
                shown += 1
                blocks.append({"type": "section", "text": {"type": "mrkdwn",
                               "text": head + "\n```\n" + "\n".join(rows) + "\n```"}})
        if not shown:
            blocks.append({"type": "section", "text": {"type": "mrkdwn", "text": "_조건에 맞는 GPU가 없습니다._"}})

    if errs:
        blocks.append({"type": "context", "elements": [{"type": "mrkdwn",
            "text": "⚠️ 조회 실패: " + ", ".join(f"`{_node(h)}` ({e[:60]})" for h, e in errs)}]})

    def btn(action_id, label, value, active):
        b = {"type": "button", "action_id": action_id, "value": value or "all",
             "text": {"type": "plain_text", "text": label, "emoji": True}}
        if active:
            b["style"] = "primary"
        return b

    detail_all = view == "detail" and not q["nodes"]
    blocks.append({"type": "actions", "elements": [
        btn("gpu_refresh", "🔄 새로고침", query_to_text(q), False),
        btn("gpu_view_all", "📋 요약", "", view == "compact"),
        btn("gpu_view_free", "🟢 빈 GPU", "free", view == "free"),
        btn("gpu_view_detail", "📊 상세", "detail", detail_all),
    ]})
    blocks.append({"type": "context", "elements": [{"type": "mrkdwn", "text":
        f"{BUSY} 사용 중  {IDLE} 유휴  ·  <!date^{now}^{{time_secs}}|조회 시각> 기준 스냅샷, 예약 아님"
        "  ·  `/gpu free` `/gpu node 72` `/gpu user eklee`"}]})
    return blocks, fallback
