import json
import os
import subprocess
from pathlib import Path
from typing import Any, Dict


class OpenClawInvoker:
    def __init__(self, repo_root: Path):
        self.repo_root = repo_root
        default_python = str(repo_root / ".venv" / "bin" / "python")
        self.python_bin = os.environ.get("HARNESS_PYTHON", default_python)

    def project_init(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        cmd = [
            self.python_bin, "-m", "harness.cli.main",
            "init",
            "--name", payload["project"],
            "--runtime", payload.get("runtime", "python"),
            "--no-template",
        ]
        proc = subprocess.run(cmd, cwd=self.repo_root, text=True, capture_output=True)
        return {
            "ok": proc.returncode == 0,
            "stdout": proc.stdout,
            "stderr": proc.stderr,
            "code": proc.returncode,
        }

    def experiment_run(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        mode = payload.get("mode", "exp")
        cmd = [
            self.python_bin, "-m", "harness.cli.main",
            "run",
            "--config", payload["config"],
            "--mode", mode,
        ]
        for key, value in payload.get("overrides", {}).items():
            cmd.extend(["--set", f"{key}={value}"])

        proc = subprocess.run(cmd, cwd=self.repo_root, text=True, capture_output=True)
        response = {
            "ok": proc.returncode == 0,
            "stdout": proc.stdout,
            "stderr": proc.stderr,
            "code": proc.returncode,
        }
        try:
            response["parsed"] = json.loads(proc.stdout)
        except Exception:
            response["parsed"] = None
        return response
