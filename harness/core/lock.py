from pathlib import Path


class FileLock:
    def __init__(self, lock_path: Path):
        self.lock_path = lock_path

    def acquire(self) -> None:
        self.lock_path.parent.mkdir(parents=True, exist_ok=True)
        if self.lock_path.exists():
            raise RuntimeError(f"lock already exists: {self.lock_path}")
        self.lock_path.write_text("locked\n", encoding="utf-8")

    def release(self) -> None:
        if self.lock_path.exists():
            self.lock_path.unlink()

    def __enter__(self):
        self.acquire()
        return self

    def __exit__(self, exc_type, exc, tb):
        self.release()
