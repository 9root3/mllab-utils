import json
from pathlib import Path
from typing import Any, Dict, Tuple

from harness.core.errors import HarnessError


def _load_yaml(config_path: Path) -> Dict[str, Any]:
    try:
        import yaml  # type: ignore
    except ImportError as exc:
        raise HarnessError("E100", "PyYAML is required. Install with: pip install pyyaml") from exc

    data = yaml.safe_load(config_path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise HarnessError("E101", "config root must be an object")
    return data


def _validate_with_jsonschema(config: Dict[str, Any], schema: Dict[str, Any]) -> Tuple[bool, str]:
    try:
        import jsonschema  # type: ignore
    except ImportError:
        required = schema.get("required", [])
        missing = [key for key in required if key not in config]
        if missing:
            return False, f"missing required keys (fallback validator): {missing}"
        return True, "validated with fallback validator (jsonschema missing)"

    try:
        jsonschema.validate(config, schema)
    except Exception as exc:
        return False, str(exc)
    return True, "ok"


def load_and_validate_experiment_config(repo_root: Path, config_path: Path) -> Dict[str, Any]:
    if not config_path.exists():
        raise HarnessError("E102", f"config file not found: {config_path}")

    config = _load_yaml(config_path)
    schema_path = repo_root / "harness" / "specs" / "experiment_spec.schema.json"
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    ok, reason = _validate_with_jsonschema(config, schema)
    if not ok:
        raise HarnessError("E103", f"config validation failed: {reason}")
    return config
