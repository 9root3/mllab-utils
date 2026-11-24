import json
import tempfile
import unittest
from pathlib import Path

from harness.core.artifact import ArtifactStore
from harness.core.run_context import create_run_context


class TestCore(unittest.TestCase):
    def test_artifact_write_and_read(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            store = ArtifactStore(root)
            store.write_json("run-x", "result.json", {"status": "ok"})
            payload = store.read_json("run-x", "result.json")
            self.assertEqual(payload["status"], "ok")

    def test_run_context_required_fields(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            ctx = create_run_context(root, {"id": "a"}, "manual", "n/a")
            self.assertIn("run_id", ctx)
            self.assertIn("git_commit", ctx)
            self.assertIn("config_hash", ctx)


if __name__ == "__main__":
    unittest.main()
