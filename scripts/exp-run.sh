#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <config> [key=value ...]"
  exit 1
fi

CONFIG="$1"
shift

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
PYTHON_BIN="${HARNESS_PYTHON:-${REPO_ROOT}/.venv/bin/python}"
cd "$REPO_ROOT"

CMD=("${PYTHON_BIN}" -m harness.cli.main run --config "$CONFIG" --mode exp --triggered-by openclaw)
for kv in "$@"; do
  CMD+=(--set "$kv")
done

"${CMD[@]}"
