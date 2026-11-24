from pathlib import Path


def run_init(repo_root: Path, name: str, runtime: str, no_template: bool) -> dict:
    for rel in [
        "openclaw/commands",
        "openclaw/schemas",
        "harness/cli",
        "harness/commands",
        "harness/core",
        "harness/adapters",
        "harness/specs",
        "experiments/configs",
        "experiments/suites",
        "artifacts",
        "logs",
        "docs",
        "scripts",
    ]:
        (repo_root / rel).mkdir(parents=True, exist_ok=True)

    (repo_root / "artifacts" / ".gitkeep").touch(exist_ok=True)
    (repo_root / "logs" / ".gitkeep").touch(exist_ok=True)

    workflow = repo_root / "docs" / "workflow.md"
    if not workflow.exists():
        workflow.write_text(
            "# Workflow\n\n- project-init completed\n",
            encoding="utf-8",
        )

    return {
        "project": name,
        "runtime": runtime,
        "no_template": no_template,
        "status": "initialized",
    }
