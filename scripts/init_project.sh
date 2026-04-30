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
  mllab init <project_name> <git_url> [--skip-dockerfile]

Options:
  --skip-dockerfile   Do not generate a default Dockerfile if the repo has none.
EOF
}

skip_dockerfile=false
positional=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --skip-dockerfile)
      skip_dockerfile=true
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

[ "${#positional[@]}" -ge 2 ] || { usage >&2; exit 1; }

project_name=${positional[0]}
git_url=${positional[1]}

if [[ "$project_name" =~ [A-Z] ]]; then
  mllab_die "<project_name> must be lowercase only"
fi

project_path=$(mllab_project_path "$project_name")
code_path="$project_path/$MLLAB_CODE_DIR"

[ ! -d "$project_path" ] || mllab_die "Project directory '$project_path' already exists"

mkdir -p "$code_path"
git clone "$git_url" "$code_path"

if [ -f "$code_path/requirements.txt" ]; then
  echo "requirements.txt already exists. Skipping creation."
else
  : > "$code_path/requirements.txt"
fi

if [ -f "$code_path/Dockerfile" ]; then
  mv "$code_path/Dockerfile" "$project_path/Dockerfile"
  echo "Moved repository Dockerfile to '$project_path/Dockerfile'."
elif $skip_dockerfile; then
  echo "Skipped creating Dockerfile. Create '$project_path/Dockerfile' before build."
else
  sed \
    -e "s|__MLLAB_BASE_IMAGE__|$MLLAB_BASE_IMAGE|g" \
    -e "s|__MLLAB_CODE_DIR__|$MLLAB_CODE_DIR|g" \
    -e "s|__MLLAB_CONTAINER_WORKDIR__|$MLLAB_CONTAINER_WORKDIR|g" \
    "$MLLAB_ROOT/templates/Dockerfile" > "$project_path/Dockerfile"
  echo "Default Dockerfile created at '$project_path/Dockerfile'."
fi

if mllab_bool "$MLLAB_OPEN_EDITOR"; then
  if command -v "$MLLAB_EDITOR_CMD" >/dev/null 2>&1; then
    "$MLLAB_EDITOR_CMD" "$code_path/requirements.txt" "$project_path/Dockerfile" >/dev/null 2>&1 || true
  else
    echo "Editor '$MLLAB_EDITOR_CMD' was not found. Skipping editor open."
  fi
fi

echo "Project '$project_name' created successfully at '$project_path'."
echo "Next: mllab build $project_name [tag]"
