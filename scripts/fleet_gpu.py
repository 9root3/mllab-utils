#!/usr/bin/env python3
"""mllab-* 노드 전체의 GPU 사용 현황을 한 번에 조회해 격자/요약/빈 GPU 목록으로 출력한다.

- 대상: ~/.ssh/config 의 `Host mllab-*` 항목 (와일드카드 제외)
- 기준: 실제 GPU compute 프로세스가 있는 컨테이너 (docker top 의 호스트 PID 와 nvidia-smi PID 대조)
- 사용자: 컨테이너 이름 접두사 (첫 '_' 앞)
사용: python3 scripts/fleet_gpu.py [--hosts mllab-72,mllab-30] [--timeout 40]
"""
import argparse
import re
import subprocess
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REMOTE = r"""
declare -A P IDX OWN
for c in $(docker ps -q 2>/dev/null); do
  n=$(docker inspect -f '{{.Name}}' "$c" | sed 's|^/||')
  for p in $(docker top "$c" -eo pid 2>/dev/null | tail -n +2); do P[$p]=$n; done
done
while IFS=',' read -r i u; do IDX[$(echo $u)]=$(echo $i); done < <(nvidia-smi --query-gpu=index,uuid --format=csv,noheader)
while IFS=',' read -r u p; do
  u=$(echo $u); p=$(echo $p); i=${IDX[$u]}
  o=${P[$p]:-"?"}
  case ",${OWN[$i]}," in *",$o,"*) ;; *) OWN[$i]="${OWN[$i]:+${OWN[$i]},}$o" ;; esac
done < <(nvidia-smi --query-compute-apps=gpu_uuid,pid --format=csv,noheader)
nvidia-smi --query-gpu=index,name,memory.total,memory.used --format=csv,noheader,nounits | while IFS=',' read -r i n t u; do
  i=$(echo $i)
  echo "G|$i|$(echo $n)|$(echo $t)|$(echo $u)|${OWN[$i]}"
done
"""


def hosts_from_ssh_config():
    cfg = Path.home() / ".ssh" / "config"
    out = []
    for line in cfg.read_text().splitlines():
        m = re.match(r"\s*Host\s+(.+)", line, re.I)
        if m:
            out += [h for h in m.group(1).split() if h.startswith("mllab-") and "*" not in h]
    return out


def query(host, timeout):
    try:
        r = subprocess.run(
            ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", host, "bash -s"],
            input=REMOTE, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return host, None, "timeout"
    gpus = []
    for line in r.stdout.splitlines():
        if line.startswith("G|"):
            _, i, name, total, used, own = line.split("|", 5)
            users = sorted({o.split("_", 1)[0] if o != "?" else "?" for o in own.split(",") if o})
            ctrs = [o for o in own.split(",") if o]
            gpus.append(dict(idx=int(i), name=name.replace("NVIDIA ", ""), total=int(total),
                             used=int(used), users=users, ctrs=ctrs))
    if not gpus:
        return host, None, (r.stderr.strip().splitlines() or ["no GPU data"])[-1]
    return host, sorted(gpus, key=lambda g: g["idx"]), None


def collect(hosts=None, timeout=40):
    """모든 노드를 병렬 조회해 [(host, gpus|None, err|None)] 를 노드 번호순으로 반환한다."""
    hosts = hosts or hosts_from_ssh_config()
    with ThreadPoolExecutor(len(hosts)) as ex:
        results = list(ex.map(lambda h: query(h, timeout), hosts))
    results.sort(key=lambda r: int(re.sub(r"\D", "", r[0]) or 0))
    return results


def table(header, rows):
    w = [max(len(str(x)) for x in col) for col in zip(header, *rows)]
    fmt = "| " + " | ".join(f"{{:<{x}}}" for x in w) + " |"
    lines = [fmt.format(*header), "|" + "|".join("-" * (x + 2) for x in w) + "|"]
    lines += [fmt.format(*map(str, r)) for r in rows]
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--hosts", help="쉼표 구분 호스트 (기본: ssh config 의 mllab-*)")
    ap.add_argument("--timeout", type=int, default=40)
    a = ap.parse_args()
    hosts = a.hosts.split(",") if a.hosts else hosts_from_ssh_config()
    results = collect(hosts, a.timeout)

    maxg = max((len(g) for _, g, _ in results if g), default=0)
    grid, free, per_user, errors = [], [], defaultdict(lambda: defaultdict(list)), []
    for host, gpus, err in results:
        if gpus is None:
            errors.append((host, err))
            continue
        cells = [", ".join(g["users"]) if g["users"] else "·" for g in gpus]
        cells += [""] * (maxg - len(cells))
        idle = sum(1 for g in gpus if not g["users"])
        grid.append([host.replace("mllab-", "")] + cells + [f"{idle}/{len(gpus)}"])
        for g in gpus:
            if g["users"]:
                for u in g["users"]:
                    per_user[u][host.replace("mllab-", "")].append(g["idx"])
            else:
                free.append((host.replace("mllab-", ""), g))

    print("## 노드 × GPU (· = 유휴)\n")
    print(table(["노드"] + [f"GPU {i}" for i in range(maxg)] + ["유휴"], grid))

    def rng(v):
        v = sorted(v); out = []; s = p = v[0]
        for x in v[1:] + [None]:
            if x is not None and x == p + 1:
                p = x; continue
            out.append(f"{s}" if s == p else f"{s}~{p}")
            if x is not None:
                s = p = x
        return ", ".join(out)

    print("\n## 사용자별\n")
    print(table(["사용자", "위치"], [
        [u, " / ".join(f"{n} (GPU {rng(ix)})" for n, ix in sorted(locs.items(), key=lambda kv: int(kv[0])))]
        for u, locs in sorted(per_user.items())]))

    print("\n## 지금 쓸 수 있는 GPU\n")
    groups = defaultdict(list)
    for n, g in free:
        groups[(n, g["name"], g["total"])].append(g["idx"])
    print(table(["노드", "GPU", "모델", "VRAM"], [
        [n, rng(ix), name, f"{round(tot / 1024)} GB"] for (n, name, tot), ix in groups.items()]))

    if errors:
        print("\n## 조회 실패\n")
        for h, e in errors:
            print(f"- {h}: {e}")
    print("\n* 스냅샷이며 예약이 아님. GPU compute 프로세스가 없으면 유휴로 표시.")


if __name__ == "__main__":
    main()
