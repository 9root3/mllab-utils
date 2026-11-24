"""GPU 조회 결과 -> Slack Block Kit 메시지. Slack/네트워크 의존성이 없어 단독 테스트가 가능하다."""
import re
import time
from collections import defaultdict

BAR_LEN = 10


def parse_query(text):
    """`/gpu` 인자 파싱.  예: '', 'free', 'node 72', 'user eklee', 'free 72'.
    반환: dict(free: bool, nodes: set[str], users: set[str])"""
    q = {"free": False, "nodes": set(), "users": set()}
    toks = (text or "").replace("@", " ").replace(",", " ").split()
    mode = None
    for t in toks:
        tl = t.lower()
        if tl in ("free", "idle", "빈", "유휴"):
            q["free"] = True
        elif tl in ("node", "nodes", "노드"):
            mode = "nodes"
        elif tl in ("user", "users", "사용자"):
            mode = "users"
        elif re.fullmatch(r"(mllab-)?\d+", tl):
            q["nodes"].add(tl.replace("mllab-", ""))
        elif mode == "users" or tl.isalpha() or re.fullmatch(r"[\w.-]+", tl):
            q["users"].add(tl)
    return q


def query_to_text(q):
    parts = []
    if q["free"]:
        parts.append("free")
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


def _status_emoji(idle, total):
    if idle == total:
        return "🟢"
    return "🔴" if idle == 0 else "🟡"


def _node_matches(q, node, gpus):
    if q["nodes"] and node not in q["nodes"]:
        return False
    if q["users"] and not any(set(g["users"]) & q["users"] for g in gpus):
        return False
    return True


def build_blocks(results, q=None, now=None):
    """results: fleet_gpu.collect() 결과. 반환: (blocks, fallback_text)"""
    q = q or parse_query("")
    now = int(now or time.time())
    ok = [(h, g) for h, g, _ in results if g]
    errs = [(h, e) for h, g, e in results if not g]

    total = sum(len(g) for _, g in ok)
    idle = sum(1 for _, g in ok for x in g if not x["users"])
    busy = total - idle
    users = defaultdict(lambda: defaultdict(list))
    for h, g in ok:
        for x in g:
            for u in x["users"]:
                users[u][_node(h)].append(x["idx"])

    fallback = f"mllab GPU: 전체 {total} · 사용 중 {busy} · 유휴 {idle}"
    title = "🖥️  mllab GPU 현황" + ("  ·  빈 GPU" if q["free"] else "")
    blocks = [
        {"type": "header", "text": {"type": "plain_text", "text": title, "emoji": True}},
        {"type": "section", "fields": [
            {"type": "mrkdwn", "text": f"*전체 GPU*\n{total}"},
            {"type": "mrkdwn", "text": f"*🟢 유휴*\n{idle}"},
            {"type": "mrkdwn", "text": f"*🔴 사용 중*\n{busy}"},
            {"type": "mrkdwn", "text": f"*👥 사용자*\n{len(users)}명"},
        ]},
        {"type": "context", "elements": [{"type": "mrkdwn", "text":
            f"전체 점유율 `{_bar(busy, total)}` {round(100 * busy / total) if total else 0}%"
            f"  ·  <!date^{now}^{{date_short_pretty}} {{time_secs}}|조회 시각>"}]},
        {"type": "divider"},
    ]

    shown = 0
    for host, gpus in ok:
        node = _node(host)
        if not _node_matches(q, node, gpus):
            continue
        n_idle = sum(1 for x in gpus if not x["users"])
        model = _short_model(gpus[0]["name"])
        vram = round(_gib(gpus[0]["total"]))
        head = f"{_status_emoji(n_idle, len(gpus))} *{node}*  ·  {model} ×{len(gpus)} ({vram}GB)  ·  유휴 *{n_idle}/{len(gpus)}*"
        rows = []
        for x in gpus:
            if q["free"] and x["users"]:
                continue
            if q["users"] and x["users"] and not (set(x["users"]) & q["users"]):
                continue
            if x["users"]:
                who = ", ".join(x["users"])
            else:
                who = "· idle" + (" ⚠ 프로세스 없이 메모리만 점유" if x["used"] >= 1024 else "")
            rows.append(f"GPU{x['idx']} {_bar(x['used'], x['total'])} "
                        f"{_gib(x['used']):5.1f}/{_gib(x['total']):.0f}G  {who}")
        if not rows:
            continue
        shown += 1
        blocks.append({"type": "section", "text": {"type": "mrkdwn",
                       "text": head + "\n```\n" + "\n".join(rows) + "\n```"}})

    if not shown:
        blocks.append({"type": "section", "text": {"type": "mrkdwn", "text": "_조건에 맞는 GPU가 없습니다._"}})

    # 요약: 사용자별 / 쓸 수 있는 GPU
    if not q["free"] and not q["nodes"] and not q["users"] and users:
        lines = []
        for u, locs in sorted(users.items()):
            where = "  ".join(f"`{n}` GPU {_rng(ix)}" for n, ix in sorted(locs.items(), key=lambda kv: int(kv[0])))
            lines.append(f"• *{u}*  {where}")
        blocks += [{"type": "divider"},
                   {"type": "section", "text": {"type": "mrkdwn", "text": "*👥 사용자별*\n" + "\n".join(lines)}}]

    free = defaultdict(list)
    for host, gpus in ok:
        for x in gpus:
            if not x["users"]:
                free[(_node(host), _short_model(x["name"]), round(_gib(x["total"])))].append(x["idx"])
    if free and not q["users"]:
        lines = [f"• `{n}`  GPU {_rng(ix)}  —  {m} · *{v}GB*"
                 for (n, m, v), ix in sorted(free.items(), key=lambda kv: int(kv[0][0]))
                 if not q["nodes"] or n in q["nodes"]]
        if lines:
            blocks += [{"type": "divider"},
                       {"type": "section", "text": {"type": "mrkdwn", "text": "*🟢 지금 쓸 수 있는 GPU*\n" + "\n".join(lines)}}]

    if errs:
        blocks.append({"type": "context", "elements": [{"type": "mrkdwn",
            "text": "⚠️ 조회 실패: " + ", ".join(f"`{_node(h)}` ({e[:60]})" for h, e in errs)}]})

    text = query_to_text(q)
    blocks.append({"type": "actions", "elements": [
        {"type": "button", "action_id": "gpu_refresh", "text": {"type": "plain_text", "text": "🔄 새로고침", "emoji": True},
         "value": text},
        {"type": "button", "action_id": "gpu_view_free", "text": {"type": "plain_text", "text": "🟢 빈 GPU만", "emoji": True},
         "value": "free", **({"style": "primary"} if q["free"] else {})},
        {"type": "button", "action_id": "gpu_view_all", "text": {"type": "plain_text", "text": "📋 전체", "emoji": True},
         "value": "", **({"style": "primary"} if not q["free"] else {})},
    ]})
    blocks.append({"type": "context", "elements": [{"type": "mrkdwn",
        "text": "스냅샷이며 예약이 아닙니다 · GPU compute 프로세스가 없으면 유휴  |  `/gpu free` `/gpu node 72` `/gpu user eklee`"}]})
    return blocks, fallback


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
    return ", ".join(out)
