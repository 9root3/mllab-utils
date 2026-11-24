import json
from pathlib import Path
from typing import Any, Dict


class ArtifactStore:
    def __init__(self, repo_root: Path):
        self.repo_root = repo_root

    def run_dir(self, run_id: str) -> Path:
        path = self.repo_root / "artifacts" / run_id
        path.mkdir(parents=True, exist_ok=True)
        return path

    def write_json(self, run_id: str, filename: str, payload: Dict[str, Any]) -> Path:
        out_path = self.run_dir(run_id) / filename
        out_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        return out_path

    def read_json(self, run_id: str, filename: str) -> Dict[str, Any]:
        path = self.repo_root / "artifacts" / run_id / filename
        if not path.exists():
            raise FileNotFoundError(f"artifact not found: {path}")
        return json.loads(path.read_text(encoding="utf-8"))
