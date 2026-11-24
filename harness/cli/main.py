import argparse
import json
import sys
from pathlib import Path

from harness.commands.eval import run_eval
from harness.commands.init import run_init
from harness.commands.plan import run_plan
from harness.commands.run import run_run
from harness.commands.status import run_status
from harness.core.errors import HarnessError


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="harness")
    sub = parser.add_subparsers(dest="command", required=True)

    p_init = sub.add_parser("init")
    p_init.add_argument("--name", required=True)
    p_init.add_argument("--runtime", required=True, choices=["python", "node"])
    p_init.add_argument("--no-template", action="store_true")

    p_plan = sub.add_parser("plan")
    p_plan.add_argument("--config", required=True)

    p_run = sub.add_parser("run")
    p_run.add_argument("--config", required=True)
    p_run.add_argument("--mode", required=True, choices=["dev", "exp"])
    p_run.add_argument("--triggered-by", default="manual", choices=["manual", "openclaw", "schedule"])
    p_run.add_argument("--set", action="append", default=[])

    p_eval = sub.add_parser("eval")
    p_eval.add_argument("--run-id", required=True)

    p_status = sub.add_parser("status")
    p_status.add_argument("--run-id", required=True)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    repo_root = _repo_root()

    try:
        if args.command == "init":
            out = run_init(repo_root, args.name, args.runtime, args.no_template)
        elif args.command == "plan":
            out = run_plan(repo_root, args.config)
        elif args.command == "run":
            out = run_run(repo_root, args.config, args.mode, args.triggered_by, args.set)
        elif args.command == "eval":
            out = run_eval(repo_root, args.run_id)
        elif args.command == "status":
            out = run_status(repo_root, args.run_id)
        else:
            raise HarnessError("E199", f"unknown command: {args.command}")

        print(json.dumps(out, ensure_ascii=False))
        return 0
    except HarnessError as exc:
        print(json.dumps({"error": str(exc)}), file=sys.stderr)
        return 2
    except FileNotFoundError as exc:
        print(json.dumps({"error": f"[E404] {exc}"}), file=sys.stderr)
        return 4
    except Exception as exc:
        print(json.dumps({"error": f"[E500] {exc}"}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
