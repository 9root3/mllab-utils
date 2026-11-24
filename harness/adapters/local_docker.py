import datetime as dt
import subprocess
from pathlib import Path
from typing import Any, Dict


def resolve_image_digest(image: str) -> str:
    if not image:
        return "n/a"
    try:
        cmd = ["docker", "image", "inspect", image, "--format", "{{index .RepoDigests 0}}"]
        out = subprocess.check_output(cmd, text=True).strip()
        return out or "n/a"
    except Exception:
        return "n/a"


def run_experiment(spec: Dict[str, Any], repo_root: Path, run_id: str, mode: str) -> Dict[str, Any]:
    start = dt.datetime.now(dt.timezone.utc)
    entrypoint = spec["entrypoint"]
    result: Dict[str, Any] = {
        "status": "success",
        "mode": mode,
        "entrypoint": entrypoint,
        "stdout": "",
        "stderr": "",
    }

    if mode == "exp" and spec.get("container_image"):
        image = spec["container_image"]
        cmd = [
            "docker", "run", "--rm",
            "-v", f"{repo_root}:/workspace",
            "-w", "/workspace",
            image,
            "bash", "-lc", entrypoint,
        ]
    else:
        cmd = ["bash", "-lc", entrypoint]

    proc = subprocess.run(cmd, text=True, capture_output=True)
    result["stdout"] = proc.stdout
    result["stderr"] = proc.stderr
    if proc.returncode != 0:
        result["status"] = "failed"
        result["exit_code"] = proc.returncode

    end = dt.datetime.now(dt.timezone.utc)
    result["start_ts"] = start.isoformat()
    result["end_ts"] = end.isoformat()
    result["duration_ms"] = int((end - start).total_seconds() * 1000)
    return result
