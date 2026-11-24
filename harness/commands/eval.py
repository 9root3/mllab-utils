from pathlib import Path

from harness.core.artifact import ArtifactStore


def run_eval(repo_root: Path, run_id: str) -> dict:
    store = ArtifactStore(repo_root)
    result = store.read_json(run_id, "result.json")
    meta = store.read_json(run_id, "metadata.json")
    return {
        "run_id": run_id,
        "status": result.get("status"),
        "duration_ms": result.get("duration_ms"),
        "git_commit": meta.get("git_commit"),
        "metric_summary": result.get("metric_summary", {}),
    }
