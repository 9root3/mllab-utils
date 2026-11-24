import datetime as dt
import hashlib
import json
import os
import subprocess
import uuid
from pathlib import Path
from typing import Any, Dict


def _read_git_sha(repo_root: Path) -> str:
    try:
        out = subprocess.check_output(["git", "-C", str(repo_root), "rev-parse", "HEAD"], text=True)
        return out.strip()
    except Exception:
        return "unknown"


def _hash_config(config_obj: Dict[str, Any]) -> str:
    payload = json.dumps(config_obj, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def create_run_context(repo_root: Path, config_obj: Dict[str, Any], triggered_by: str, image_digest: str) -> Dict[str, Any]:
    now = dt.datetime.now(dt.timezone.utc)
    run_id = now.strftime("run-%Y%m%d-%H%M%S-") + uuid.uuid4().hex[:8]
    return {
        "run_id": run_id,
        "triggered_by": triggered_by,
        "start_ts": now.isoformat(),
        "git_commit": _read_git_sha(repo_root),
        "image_digest": image_digest,
        "config_hash": _hash_config(config_obj),
        "env_snapshot": {
            "python": os.environ.get("PYTHON_VERSION", "unknown"),
            "user": os.environ.get("USER", "unknown"),
            "host": os.uname().nodename,
        },
    }
