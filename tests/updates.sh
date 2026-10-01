#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export MLLAB_ROOT="$tmp/checkout" XDG_CACHE_HOME="$tmp/cache"
mkdir -p "$MLLAB_ROOT" "$tmp/bin"
echo 0.3.2 > "$MLLAB_ROOT/VERSION"
touch "$MLLAB_ROOT/pm.sh"
# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"
# shellcheck source=scripts/update.sh
source "$ROOT/scripts/update.sh"
mllab_version_newer 0.10.0 0.9.9
mllab_version_newer 1.0.0 0.99.9
if mllab_version_newer 0.3.2 0.3.2 || mllab_version_newer 0.3.1 0.3.2 || mllab_version_newer 0.03.3 0.3.2; then exit 1; fi
export CURL_CALLS="$tmp/curl-calls" GIT_CALLS="$tmp/git-calls"
export RELEASE_URL=https://github.com/9root3/mllab-utils/releases/tag/v0.3.3
cat > "$tmp/bin/curl" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_CALLS"
[ "${CURL_FAIL:-0}" = 0 ] || exit 22
printf '%s' "$RELEASE_URL"
MOCK
cat > "$tmp/bin/git" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GIT_CALLS"
shift 2
case "$1" in
  status) printf '%s' "${DIRTY:-}" ;;
  symbolic-ref) echo "${BRANCH:-main}" ;;
  show) echo "${TAG_VERSION:-0.3.3}" ;;
  fetch) exit "${FETCH_FAIL:-0}" ;;
  merge) exit "${MERGE_FAIL:-0}" ;;
  *) exit 1 ;;
esac
MOCK
cat > "$tmp/bin/flock" <<'MOCK'
#!/usr/bin/env bash
exit "${LOCK_FAIL:-0}"
MOCK
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH"
[ "$(mllab_latest_release)" = 0.3.3 ]
export RELEASE_URL=https://example.com/releases/tag/v9.0.0
if mllab_latest_release; then exit 1; fi
export RELEASE_URL=https://github.com/9root3/mllab-utils/releases/tag/v0.3.3-rc.1
if mllab_latest_release; then exit 1; fi
export RELEASE_URL=https://github.com/9root3/mllab-utils/releases/tag/v0.3.3
: > "$CURL_CALLS"
mllab_update_notice status
[ ! -s "$CURL_CALLS" ]

# A real pseudo-terminal exercises the interactive-only path without a GPU or network.
export UPDATE_SOURCE="$ROOT/scripts/update.sh"
python3 - <<'PY'
import os, pty, subprocess

def notice(args='status', env=None):
    master, slave = pty.openpty()
    result = subprocess.Popen(['bash', '-c', 'source "$UPDATE_SOURCE"; mllab_update_notice "$@"', 'test', *args.split()], stderr=slave, stdout=subprocess.PIPE, env=env)
    os.close(slave)
    chunks=[]
    try:
        while True:
            chunk=os.read(master, 4096)
            if not chunk: break
            chunks.append(chunk)
    except OSError:
        pass
    finally:
        os.close(master)
    result.wait(); assert result.returncode == 0
    return b''.join(chunks).decode()

assert '0.3.2 -> 0.3.3' in notice()
assert '0.3.2 -> 0.3.3' in notice()
assert len(open(os.environ['CURL_CALLS']).readlines()) == 1
assert not notice('start --dry-run')
assert not notice('test')
assert not notice(env=dict(os.environ, MLLAB_NO_UPDATE_NOTIFIER='1'))
cache=os.path.join(os.environ['XDG_CACHE_HOME'], 'mllab-utils', 'release')
open(cache, 'w').write('0 0.3.3\n')
assert not notice(env=dict(os.environ, CURL_FAIL='1'))
# A failed lookup is also cached, avoiding repeated network delays.
assert not notice(env=dict(os.environ, CURL_FAIL='1'))
assert len(open(os.environ['CURL_CALLS']).readlines()) == 2
PY
: > "$GIT_CALLS"
mllab_update --check > "$tmp/output"
grep -q 'Update available' "$tmp/output"
[ ! -s "$GIT_CALLS" ]
expect_update_failure() {
  : > "$GIT_CALLS"
  if (mllab_update) > "$tmp/output" 2>&1; then exit 1; fi
  grep -q '^Error:' "$tmp/output"
}
export DIRTY=' M scripts/local.sh'
expect_update_failure
if grep -q 'fetch\|merge' "$GIT_CALLS"; then exit 1; fi
unset DIRTY
export BRANCH=experiment
expect_update_failure
if grep -q 'fetch\|merge' "$GIT_CALLS"; then exit 1; fi
unset BRANCH
export LOCK_FAIL=1
expect_update_failure
[ ! -s "$GIT_CALLS" ]
unset LOCK_FAIL
export CURL_FAIL=1
expect_update_failure
[ ! -s "$GIT_CALLS" ]
unset CURL_FAIL
export TAG_VERSION=0.9.0
expect_update_failure
if grep -q merge "$GIT_CALLS"; then exit 1; fi
unset TAG_VERSION
export MERGE_FAIL=1
expect_update_failure
unset MERGE_FAIL
: > "$GIT_CALLS"
(mllab_update) > "$tmp/output"
grep -q 'merge --ff-only v0.3.3' "$GIT_CALLS"
grep -q 'Updated mllab-utils to 0.3.3' "$tmp/output"
export RELEASE_URL=https://github.com/9root3/mllab-utils/releases/tag/v0.3.2
: > "$GIT_CALLS"
mllab_update > "$tmp/output"
[ ! -s "$GIT_CALLS" ]
echo 'Update tests passed.'
