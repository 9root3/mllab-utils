from pathlib import Path

from harness.core.config import load_and_validate_experiment_config


def run_plan(repo_root: Path, config_rel: str) -> dict:
    cfg_path = repo_root / config_rel
    spec = load_and_validate_experiment_config(repo_root, cfg_path)
    return {
        "status": "ok",
        "config": config_rel,
        "experiment_id": spec["id"],
        "entrypoint": spec["entrypoint"],
        "resources": spec.get("resources", {}),
        "timeout": spec.get("timeout", 0),
    }
