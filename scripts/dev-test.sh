#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
PYTHON_BIN="${HARNESS_PYTHON:-${REPO_ROOT}/.venv/bin/python}"
cd "$REPO_ROOT"

"${PYTHON_BIN}" -m harness.cli.main plan --config experiments/configs/baseline.yaml
"${PYTHON_BIN}" -m harness.cli.main run --config experiments/configs/baseline.yaml --mode dev
