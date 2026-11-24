import datetime as dt
from pathlib import Path
from typing import Dict

from harness.adapters.local_docker import resolve_image_digest, run_experiment
from harness.core.artifact import ArtifactStore
from harness.core.config import load_and_validate_experiment_config
from harness.core.errors import HarnessError
from harness.core.logger import JsonlLogger
from harness.core.run_context import create_run_context


def _apply_overrides(spec: Dict, pairs: list[str]) -> Dict:
    merged = dict(spec)
    for item in pairs:
        if "=" not in item:
            raise HarnessError("E104", f"invalid override format: {item} (use key=value)")
        key, raw = item.split("=", 1)
        key = key.strip()
        value = raw.strip()
        if key.startswith("params."):
            pkey = key.split(".", 1)[1]
            merged.setdefault("parameters", {})[pkey] = value
        else:
            merged[key] = value
    return merged


def run_run(repo_root: Path, config_rel: str, mode: str, triggered_by: str, overrides: list[str]) -> dict:
    if mode not in ("dev", "exp"):
        raise HarnessError("E105", f"unsupported mode: {mode}")

    cfg_path = repo_root / config_rel
    spec = load_and_validate_experiment_config(repo_root, cfg_path)
    spec = _apply_overrides(spec, overrides)

    image = spec.get("container_image", "") if mode == "exp" else ""
    image_digest = resolve_image_digest(image)
    run_ctx = create_run_context(repo_root, spec, triggered_by=triggered_by, image_digest=image_digest)

    run_id = run_ctx["run_id"]
    store = ArtifactStore(repo_root)
    run_dir = store.run_dir(run_id)
    logger = JsonlLogger(run_dir / "run.log.jsonl", run_id)

    logger.log("run", f"starting run mode={mode}", config=config_rel)
    result = run_experiment(spec, repo_root, run_id, mode)

    result.setdefault("metric_summary", {
        "status": result.get("status"),
        "duration_ms": result.get("duration_ms", 0),
    })

    end_ts = dt.datetime.now(dt.timezone.utc).isoformat()
    run_ctx["end_ts"] = end_ts

    store.write_json(run_id, "metadata.json", run_ctx)
    store.write_json(run_id, "result.json", result)

    logger.log("run", "run completed", duration_ms=result.get("duration_ms", 0), status=result.get("status"))
    return {
        "run_id": run_id,
        "status": result.get("status"),
        "artifact_dir": str(run_dir),
        "mode": mode,
    }
