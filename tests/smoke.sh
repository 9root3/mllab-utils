#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

printf 'MLLAB_DATA_DIR=\n' > "$tmpdir/config.env"
export MLLAB_CONFIG_FILE=$tmpdir/config.env
export MLLAB_PROJECTS_DIR=$tmpdir

mkdir -p "$tmpdir/sample/code"
printf 'FROM busybox\n' > "$tmpdir/sample/Dockerfile"
printf '' > "$tmpdir/sample/code/requirements.txt"

bash "$ROOT/pm.sh" help >/dev/null
bash "$ROOT/pm.sh" config >/dev/null
bash "$ROOT/pm.sh" preflight --help >/dev/null
bash "$ROOT/pm.sh" build --dry-run sample vtest >/dev/null
[ ! -e "$tmpdir/sample/.dockerignore" ]
bash "$ROOT/pm.sh" start --dry-run -g 0 -p 9999 sample >/dev/null
bash "$ROOT/pm.sh" start --dry-run --gpu-backend gpus --host-user -g 0 -p 9999 sample >/dev/null
gpus_command="$tmpdir/gpus-command.txt"
bash "$ROOT/pm.sh" create --dry-run --gpu-backend gpus -g 0 -p 9999 sample > "$gpus_command"
gpus_command_contents=$(cat "$gpus_command")
case "$gpus_command_contents" in
  *'--gpus device=0'*) ;;
  *) echo "GPU device selection was not forwarded." >&2; exit 1 ;;
esac
multi_gpus_command="$tmpdir/multi-gpus-command.txt"
bash "$ROOT/pm.sh" create --dry-run --gpu-backend gpus -g 0,1 -p 9999 sample > "$multi_gpus_command"
multi_gpus_command_contents=$(cat "$multi_gpus_command")
case "$multi_gpus_command_contents" in
  *'--gpus \"device=0\,1\"'*) ;;
  *) echo "Multi-GPU device selection was not quoted for Docker." >&2; exit 1 ;;
esac
bash "$ROOT/pm.sh" create --dry-run -g none -p 9999 sample >/dev/null
bash "$ROOT/pm.sh" create --dry-run --host-user -g none -p 9999 sample >/dev/null
bash "$ROOT/pm.sh" attach --dry-run --host-user sample_container >/dev/null
bash "$ROOT/install.sh" --dry-run >/dev/null

while IFS= read -r script; do
  bash -n "$script"
done < <(find "$ROOT" -maxdepth 2 -type f \( -name '*.sh' -o -name 'pm.sh' -o -name 'install.sh' \))

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$ROOT"/pm.sh "$ROOT"/install.sh "$ROOT"/*.sh "$ROOT"/scripts/*.sh
else
  echo "shellcheck not found; skipped."
fi

echo "Smoke tests passed."
