import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from harness.adapters.openclaw_invoker import OpenClawInvoker


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: python3 openclaw/action_runner.py '<payload_json>'", file=sys.stderr)
        return 2

    payload = json.loads(sys.argv[1])
    invoker = OpenClawInvoker(REPO_ROOT)

    action = payload.get("action")
    if action == "project-init":
        result = invoker.project_init(payload)
    elif action == "experiment-run":
        result = invoker.experiment_run(payload)
    else:
        print(json.dumps({"ok": False, "error": f"unknown action: {action}"}))
        return 3

    print(json.dumps(result, ensure_ascii=False))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
