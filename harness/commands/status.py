from pathlib import Path

from harness.core.artifact import ArtifactStore


def run_status(repo_root: Path, run_id: str) -> dict:
    store = ArtifactStore(repo_root)
    meta = store.read_json(run_id, "metadata.json")
    result = store.read_json(run_id, "result.json")
    return {
        "run_id": run_id,
        "phase": result.get("status"),
        "start_ts": meta.get("start_ts"),
        "end_ts": result.get("end_ts"),
        "mode": result.get("mode"),
    }
