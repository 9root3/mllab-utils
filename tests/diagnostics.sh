#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/bin" "$tmpdir/proc/111" "$tmpdir/proc/112" "$tmpdir/proc/222" "$tmpdir/proc/333" "$tmpdir/proc/555"
printf 'MLLAB_DATA_DIR=\n' > "$tmpdir/config.env"
export MLLAB_CONFIG_FILE="$tmpdir/config.env"
export MLLAB_PROC_ROOT="$tmpdir/proc"
export MOCK_CALLS="$tmpdir/calls"
export MOCK_CASE=success
export MOCK_STATUS=active
export MOCK_CONTAINER_ID
export MOCK_IMAGE_ID
MOCK_CONTAINER_ID=$(printf '%064d' 7)
MOCK_IMAGE_ID="sha256:$(printf '%064d' 8)"
cid_a=$(printf '%064d' 1)
cid_b=$(printf '%064d' 2)
cid_c=$(printf '%064d' 3)
printf '0::/system.slice/docker-%s.scope\n' "$cid_a" > "$tmpdir/proc/111/cgroup"
printf '0::/system.slice/docker-%s.scope\n' "$cid_a" > "$tmpdir/proc/112/cgroup"
printf '10:memory:/docker/%s\n' "$cid_b" > "$tmpdir/proc/222/cgroup"
printf '0::/user.slice/session.scope\n' > "$tmpdir/proc/333/cgroup"
printf '0::/docker/%s\n' "$cid_c" > "$tmpdir/proc/555/cgroup"

cat > "$tmpdir/bin/nvidia-smi" <<'MOCK'
#!/usr/bin/env bash
set -eu
case "$*" in
  *--query-gpu=index,uuid,name,memory.total,memory.used*)
    [ "$MOCK_STATUS" != inventory-failure ] || exit 1
    printf '0, GPU-zero, Mock GPU, 40960, 200\n1, GPU-one, Mock GPU, 40960, 10\n'
    ;;
  *--query-compute-apps=*)
    case "$MOCK_STATUS" in
      compute-failure) exit 1 ;;
      idle) exit 0 ;;
      *) printf 'GPU-zero, 111, 10\nGPU-zero, 112, 10\nGPU-zero, 222, 10\nGPU-zero, 333, 10\nGPU-zero, 444, 10\nGPU-zero, 555, 10\n' ;;
    esac
    ;;
  *--query-gpu=index,uuid*) printf '0, GPU-zero\n1, GPU-one\n' ;;
  *--query-gpu=index,name,memory.total*) printf '0, Mock GPU, 40960\n1, Mock GPU, 40960\n' ;;
  *--query-gpu=driver_version*) printf '999.0\n' ;;
  *) exit 91 ;;
esac
MOCK
cat > "$tmpdir/bin/docker" <<'MOCK'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$MOCK_CALLS"
case "$1" in
  info)
    [ "$MOCK_CASE" != daemon-failure ] || exit 1
    printf '{"nvidia":{"path":"nvidia-container-runtime"}}\n'
    ;;
  inspect)
    [ "$MOCK_STATUS" != docker-failure ] || exit 1
    case "${@: -1}" in
      *0001) printf '/alpha\n' ;;
      *0002) printf '/beta\n' ;;
      *) exit 1 ;;
    esac
    ;;
  image)
    [ "$MOCK_CASE" != missing-image ] || exit 1
    printf '%s\n' "$MOCK_IMAGE_ID"
    ;;
  create)
    [ "$MOCK_CASE" != create-failure ] || exit 1
    printf '%s\n' "$*" > "$MOCK_CALLS.create"
    printf '%s\n' "$MOCK_CONTAINER_ID"
    ;;
  start)
    [ "$MOCK_CASE" != start-failure ] || exit 1
    if grep -q 'NVIDIA_VISIBLE_DEVICES=void' "$MOCK_CALLS.create"; then
      printf 'MLLAB_DOCTOR_CPU_OK\n'
    elif [ "$MOCK_CASE" = wrong-gpu ]; then
      printf 'GPU-wrong\n'
    else
      printf 'GPU-zero\nGPU-one\n'
    fi
    ;;
  rm)
    [ "$*" = "rm -f $MOCK_CONTAINER_ID" ] || exit 92
    [ "$MOCK_CASE" != cleanup-failure ] || { echo 'daemon cleanup failure' >&2; exit 1; }
    ;;
  *) exit 93 ;;
esac
MOCK
cat > "$tmpdir/bin/timeout" <<'MOCK'
#!/usr/bin/env bash
set -eu
[ "$MOCK_CASE" != timeout ] || exit 124
shift 3
exec "$@"
MOCK
chmod +x "$tmpdir/bin/"*
export PATH="$tmpdir/bin:$PATH"

assert_absent() {
  if grep "$@"; then
    echo "Unexpected matching output: $*" >&2
    exit 1
  else
    result=$?
    [ "$result" -eq 1 ] || exit "$result"
  fi
}

: > "$MOCK_CALLS"
bash "$ROOT/pm.sh" status > "$tmpdir/status"
grep -q 'Compute-idle GPUs: 1/2' "$tmpdir/status"
grep -q 'alpha,beta,(unmapped PID),(exited/unreadable PID)' "$tmpdir/status"
assert_absent -q host-native "$tmpdir/status"
grep -q "$cid_a" "$MOCK_CALLS"
grep -q "$cid_b" "$MOCK_CALLS"
assert_absent -q '^ps' "$MOCK_CALLS"
MOCK_STATUS=idle bash "$ROOT/pm.sh" status > "$tmpdir/status"
grep -q 'Compute-idle GPUs: 2/2' "$tmpdir/status"
MOCK_STATUS=docker-failure bash "$ROOT/pm.sh" status > "$tmpdir/status"
grep -q '(unmapped PID)' "$tmpdir/status"
for failure in compute-failure inventory-failure; do
  if MOCK_STATUS=$failure bash "$ROOT/pm.sh" status > "$tmpdir/output" 2>&1; then
    echo "Status unexpectedly passed $failure" >&2; exit 1
  fi
  assert_absent -q 'Compute-idle GPUs:' "$tmpdir/output"
done

: > "$MOCK_CALLS"
bash "$ROOT/pm.sh" doctor --dry-run --gpu-backend gpus -g 0,1 > "$tmpdir/output"
[ ! -s "$MOCK_CALLS" ]
grep -Fq -- '--gpus \"device=0\,1\"' "$tmpdir/output"
for backend in runtime gpus; do
  : > "$MOCK_CALLS"
  bash "$ROOT/pm.sh" doctor --image mock:latest --gpu-backend "$backend" -g 0,1 > "$tmpdir/output"
  grep -q 'Doctor passed:' "$tmpdir/output"
  grep -q -- '--pull=never --rm' "$MOCK_CALLS"
  grep -qx "rm -f $MOCK_CONTAINER_ID" "$MOCK_CALLS"
  assert_absent -Eq -- '--mount|--volume|--publish|^pull ' "$MOCK_CALLS"
  if [ "$backend" = gpus ]; then grep -Fq -- '--gpus "device=0,1"' "$MOCK_CALLS"; fi
done
bash "$ROOT/pm.sh" doctor --image mock:latest -g none > "$tmpdir/output"
grep -q MLLAB_DOCTOR_CPU_OK "$tmpdir/output"
for failure in daemon-failure missing-image create-failure start-failure timeout wrong-gpu cleanup-failure; do
  : > "$MOCK_CALLS"
  if MOCK_CASE=$failure bash "$ROOT/pm.sh" doctor --image mock:latest --gpu-backend gpus -g 0,1 > "$tmpdir/output" 2>&1; then
    echo "Doctor unexpectedly passed $failure" >&2; exit 1
  fi
  case "$failure" in
    daemon-failure|missing-image|create-failure) assert_absent -q '^rm ' "$MOCK_CALLS" ;;
    *) grep -qx "rm -f $MOCK_CONTAINER_ID" "$MOCK_CALLS" ;;
  esac
done
for invalid in 'none,0' '0,' 'all'; do
  : > "$MOCK_CALLS"
  if bash "$ROOT/pm.sh" doctor --gpus "$invalid" > "$tmpdir/output" 2>&1; then exit 1; fi
  [ ! -s "$MOCK_CALLS" ]
done
printf 'Diagnostic tests passed.\n'
