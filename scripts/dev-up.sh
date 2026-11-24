#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
PYTHON_BIN="${HARNESS_PYTHON:-${REPO_ROOT}/.venv/bin/python}"

cd "$REPO_ROOT"
"${PYTHON_BIN}" -m harness.cli.main init --name "$(basename "$REPO_ROOT")" --runtime python --no-template >/dev/null

echo "[dev-up] dev container workflow bootstrap ready"
echo "[dev-up] use: ./scripts/harness plan --config experiments/configs/baseline.yaml"
