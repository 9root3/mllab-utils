import json
import time
from pathlib import Path
from typing import Any, Dict


class JsonlLogger:
    def __init__(self, log_path: Path, run_id: str):
        self.log_path = log_path
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        self.run_id = run_id

    def log(self, phase: str, message: str, duration_ms: int = 0, level: str = "INFO", **extra: Any) -> None:
        record: Dict[str, Any] = {
            "timestamp": int(time.time() * 1000),
            "level": level,
            "run_id": self.run_id,
            "phase": phase,
            "message": message,
            "duration_ms": duration_ms,
        }
        record.update(extra)
        with self.log_path.open("a", encoding="utf-8") as fp:
            fp.write(json.dumps(record, ensure_ascii=False) + "\n")
