#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

printf 'MLLAB_DATA_DIR=\nMLLAB_CONTAINER_PREFIX=smoke_\n' > "$tmpdir/config.env"
export MLLAB_CONFIG_FILE=$tmpdir/config.env
export MLLAB_PROJECTS_DIR=$tmpdir

mkdir -p "$tmpdir/sample/code"
printf 'FROM busybox\n' > "$tmpdir/sample/Dockerfile"
printf '' > "$tmpdir/sample/code/requirements.txt"

bash "$ROOT/pm.sh" help >/dev/null
bash "$ROOT/pm.sh" config >/dev/null
bash "$ROOT/pm.sh" preflight --help >/dev/null
bash "$ROOT/pm.sh" status --help >/dev/null
bash "$ROOT/pm.sh" doctor --help >/dev/null
bash "$ROOT/pm.sh" doctor --dry-run --gpu-backend gpus -g 0,1 >/dev/null
bash "$ROOT/pm.sh" doctor --dry-run -g none >/dev/null
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

bash "$ROOT/pm.sh" start --dry-run -- sample >/dev/null
bash "$ROOT/pm.sh" create --dry-run -- sample >/dev/null
bash "$ROOT/pm.sh" build --dry-run -- sample vtest >/dev/null

mkdir -p "$tmpdir/bin"
cat > "$tmpdir/bin/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DOCKER_CALLS"
EOF
cat > "$tmpdir/bin/git" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GIT_CALLS"
EOF
chmod +x "$tmpdir/bin/docker" "$tmpdir/bin/git"
export PATH="$tmpdir/bin:$PATH"
export DOCKER_CALLS="$tmpdir/docker-calls.txt"
export GIT_CALLS="$tmpdir/git-calls.txt"

expect_invalid_args() {
  : > "$DOCKER_CALLS"
  : > "$GIT_CALLS"
  if bash "$ROOT/pm.sh" "$@" > "$tmpdir/invalid-output.txt" 2>&1; then
    echo "Unexpected success: mllab $*" >&2
    exit 1
  fi
  if ! grep -q '^Error:' "$tmpdir/invalid-output.txt"; then
    echo "Missing argument error: mllab $*" >&2
    cat "$tmpdir/invalid-output.txt" >&2
    exit 1
  fi
  if [ -s "$DOCKER_CALLS" ]; then
    echo "Docker was called for invalid arguments: mllab $*" >&2
    exit 1
  fi
  if [ -s "$GIT_CALLS" ]; then
    echo "Git was called for invalid arguments: mllab $*" >&2
    exit 1
  fi
}

expect_invalid_args start sample other
expect_invalid_args start --replace sample other
expect_invalid_args start -- sample other
expect_invalid_args start sample -- other
expect_invalid_args create sample other
expect_invalid_args create --replace sample other
expect_invalid_args create -- sample other
expect_invalid_args init newproject https://example.com/repo.git other
expect_invalid_args init -- newproject https://example.com/repo.git other
[ ! -e "$tmpdir/newproject" ]
expect_invalid_args build sample vtest other
expect_invalid_args build -- sample vtest other
expect_invalid_args stop sample other
expect_invalid_args stop -- sample other
expect_invalid_args stop -n custom sample other
expect_invalid_args rm sample other
expect_invalid_args rm -- sample other
expect_invalid_args rm -n custom sample other
expect_invalid_args stop --bogus sample
expect_invalid_args rm --bogus sample

: > "$DOCKER_CALLS"
bash "$ROOT/pm.sh" stop -- sample >/dev/null
bash "$ROOT/pm.sh" rm -n custom >/dev/null
grep -qx 'stop smoke_sample' <(head -n 1 "$DOCKER_CALLS")
grep -qx 'rm custom' <(tail -n 1 "$DOCKER_CALLS")

while IFS= read -r script; do
  bash -n "$script"
done < <(find "$ROOT" -maxdepth 2 -type f \( -name '*.sh' -o -name 'pm.sh' -o -name 'install.sh' \))

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck --external-sources --source-path="$ROOT" "$ROOT"/pm.sh "$ROOT"/install.sh "$ROOT"/*.sh "$ROOT"/scripts/*.sh "$ROOT"/tests/*.sh
else
  echo "shellcheck not found; skipped."
fi

bash "$ROOT/tests/diagnostics.sh"

echo "Smoke tests passed."
