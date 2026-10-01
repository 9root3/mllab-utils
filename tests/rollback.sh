#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export XDG_CACHE_HOME="$tmp/cache" MLLAB_CONFIG_FILE="$tmp/config.env"
unset MLLAB_MANAGER_ROOT MLLAB_ROOT MLLAB_NO_UPDATE_NOTIFIER
mkdir -p "$tmp/bin" "$tmp/source/config"
: > "$MLLAB_CONFIG_FILE"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$tmp/gitconfig"
git config --global user.name 'Release Test'
git config --global user.email release-test@example.invalid
# All Git operations use this local fixture, never GitHub.
git config --global "url.$tmp/source.insteadOf" https://github.com/9root3/mllab-utils.git
git init --quiet --initial-branch=main "$tmp/source"
cp "$ROOT/config/default.env" "$tmp/source/config/default.env"
printf '0.3.1\n' > "$tmp/source/VERSION"
cat > "$tmp/source/pm.sh" <<'OLD'
#!/usr/bin/env bash
set -euo pipefail
root=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
case "${1:-}" in
  version) cat "$root/VERSION" ;;
  *) echo 'Old CLI has no update command'; exit 1 ;;
esac
OLD
chmod +x "$tmp/source/pm.sh"
git -C "$tmp/source" add .
git -C "$tmp/source" commit --quiet -m 'Fixture older release'
git -C "$tmp/source" tag v0.3.1
mkdir -p "$tmp/source/scripts"
cp "$ROOT/pm.sh" "$ROOT/install.sh" "$tmp/source/"
cp "$ROOT/scripts/"*.sh "$tmp/source/scripts/"
printf '0.3.3\n' > "$tmp/source/VERSION"
git -C "$tmp/source" add .
git -C "$tmp/source" commit --quiet -m 'Fixture managed release'
git -C "$tmp/source" tag v0.3.3
git clone --quiet "$tmp/source" "$tmp/manager"
cat > "$tmp/bin/curl" <<'MOCK'
#!/usr/bin/env bash
printf '%s' https://github.com/9root3/mllab-utils/releases/tag/v0.3.3
MOCK
chmod +x "$tmp/bin/curl"
if ! command -v flock >/dev/null 2>&1; then
  # Linux CI exercises real flock; macOS can still verify the version-switch path.
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/flock"
  chmod +x "$tmp/bin/flock"
fi
export PATH="$tmp/bin:$PATH"
bash "$tmp/manager/install.sh" --prefix "$tmp/bin" > /dev/null
cli="$tmp/bin/mllab"
[ "$("$cli" version)" = 0.3.3 ]
manager_head=$(git -C "$tmp/manager" rev-parse HEAD)
"$cli" rollback 0.3.1 > "$tmp/output" 2>&1 || { cat "$tmp/output" >&2; exit 1; }
[ "$("$cli" version)" = 0.3.1 ]
[ "$(git -C "$tmp/manager" rev-parse HEAD)" = "$manager_head" ]
active=$(cat "$tmp/manager/.git/mllab-active")
[ "$(git -C "$active" rev-parse 'v0.3.1^{commit}')" = "$(git -C "$active" rev-parse HEAD)" ]
[ -z "$(git -C "$active" status --porcelain)" ]
"$cli" update --check > "$tmp/output"
grep -q '0.3.1 -> 0.3.3' "$tmp/output"
# Launcher still provides interactive notices when the old CLI has no notifier.
export TEST_CLI="$cli"
python3 - <<'PY'
import os,pty,subprocess
master,slave=pty.openpty()
p=subprocess.Popen([os.environ['TEST_CLI'],'config'],stdout=subprocess.DEVNULL,stderr=slave)
os.close(slave)
parts=[]
try:
    while True:
        part=os.read(master,4096)
        if not part: break
        parts.append(part)
except OSError:
    pass
finally:
    os.close(master)
p.wait()
assert '0.3.1 -> 0.3.3' in b''.join(parts).decode()
PY
# Preserve local changes in a selected older checkout.
echo keep > "$active/local.txt"
if "$cli" update > "$tmp/output" 2>&1; then exit 1; fi
[ "$("$cli" version)" = 0.3.1 ]
[ "$(cat "$active/local.txt")" = keep ]
rm "$active/local.txt"
"$cli" update > "$tmp/output" 2>&1 || { cat "$tmp/output" >&2; exit 1; }
[ "$("$cli" version)" = 0.3.3 ]
[ "$(cat "$tmp/manager/.git/mllab-active")" = "$(readlink -f "$tmp/manager")" ]
[ -d "$active" ]
[ -z "$(git -C "$tmp/manager" status --porcelain)" ]
# Invalid, unavailable and dirty-manager rollback attempts never switch versions.
for target in 0.3.3 '../../bad' 0.3.0; do
  if "$cli" rollback "$target" > "$tmp/output" 2>&1; then exit 1; fi
  [ "$("$cli" version)" = 0.3.3 ]
done
echo keep > "$tmp/manager/local.txt"
if "$cli" rollback 0.3.1 > "$tmp/output" 2>&1; then exit 1; fi
[ "$("$cli" version)" = 0.3.3 ]
[ "$(cat "$tmp/manager/local.txt")" = keep ]
# Only the completed older checkout remains; failed partial clones are cleaned.
[ "$(find "$tmp/manager-releases" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" = 1 ]
# Exercise update fixtures under the environment exported by installed launchers.
MLLAB_MANAGER_ROOT="$tmp/manager" MLLAB_NO_UPDATE_NOTIFIER=1 bash "$ROOT/tests/updates.sh"
echo 'Rollback integration tests passed.'
