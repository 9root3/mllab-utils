#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
MLLAB_ROOT=$(cd "$(dirname "$SCRIPT_PATH")" && pwd)

prefix="$HOME/.local/bin"
name="mllab"
dry_run=false

usage() {
  cat <<'EOF'
Usage:
  bash install.sh [--prefix DIR] [--name NAME] [--dry-run]

Creates a symlink to pm.sh. Default:
  ~/.local/bin/mllab -> <repo>/pm.sh
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --prefix)
      [ "$#" -ge 2 ] || { echo "Missing value for --prefix" >&2; exit 1; }
      prefix=$2
      shift 2
      ;;
    --name)
      [ "$#" -ge 2 ] || { echo "Missing value for --name" >&2; exit 1; }
      name=$2
      shift 2
      ;;
    -d|--dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

target="$prefix/$name"

if $dry_run; then
  echo "Would run:"
  printf '%q ' mkdir -p "$prefix"
  printf '\n'
  printf '%q ' ln -sf "$MLLAB_ROOT/pm.sh" "$target"
  printf '\n'
else
  mkdir -p "$prefix"
  ln -sf "$MLLAB_ROOT/pm.sh" "$target"
  echo "Installed: $target -> $MLLAB_ROOT/pm.sh"
  echo "Make sure '$prefix' is on PATH."
fi
