#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
MLLAB_ROOT=${MLLAB_ROOT:-$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)}
export MLLAB_ROOT

# shellcheck source=scripts/lib.sh
source "$MLLAB_ROOT/scripts/lib.sh"
mllab_load_config

usage() {
  cat <<'EOF'
Usage:
  mllab build [options] <project> [tag]

Options:
  -c, --no-cache   Build without using Docker layer cache.
  -d, --dry-run    Print the Docker command without executing it.
EOF
}

no_cache=false
dry_run=false
positional=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -c|--no-cache)
      no_cache=true
      shift
      ;;
    -d|--dry-run)
      dry_run=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      positional+=("$@")
      break
      ;;
    -*)
      mllab_die "Unknown option: $1"
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

[ "${#positional[@]}" -ge 1 ] || { usage >&2; exit 1; }

project=${positional[0]}
tag=${positional[1]:-$MLLAB_DEFAULT_TAG}
project_path=$(mllab_project_path "$project")
dockerfile_path="$project_path/Dockerfile"
dockerignore_path="$project_path/.dockerignore"
image_name=$(mllab_image_name "$project" "$tag")

[ -d "$project_path" ] || mllab_die "Project directory not found: '$project_path'"
[ -f "$dockerfile_path" ] || mllab_die "Dockerfile not found at '$dockerfile_path'"

if [ ! -f "$dockerignore_path" ] && $dry_run; then
  echo "Would create default .dockerignore at '$dockerignore_path'."
elif [ ! -f "$dockerignore_path" ]; then
  cp "$MLLAB_ROOT/templates/dockerignore" "$dockerignore_path"
  echo "Created default .dockerignore at '$dockerignore_path'."
fi

cmd=(docker build)
if $no_cache; then
  cmd+=(--no-cache)
fi
cmd+=(-t "$image_name" -f "$dockerfile_path" "$project_path")

echo "--- Building Docker Image ---"
echo "  Image Name:    $image_name"
echo "  Dockerfile:    $dockerfile_path"
echo "  Build Context: $project_path"
echo "  No Cache:      $no_cache"
echo "  Dry Run:       $dry_run"
echo "-----------------------------"

if $dry_run; then
  echo "Would run:"
  mllab_print_command "${cmd[@]}"
else
  "${cmd[@]}"
  echo "Image '$image_name' built successfully."
fi
