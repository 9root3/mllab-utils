#!/usr/bin/env bash
# Release discovery is read-only; updates require an explicit command.
mllab_valid_version() {
  [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

mllab_version_newer() {
  local a b i
  mllab_valid_version "$1" && mllab_valid_version "$2" || return 1
  IFS=. read -r -a a <<< "$1"
  IFS=. read -r -a b <<< "$2"
  for i in 0 1 2; do
    [ "${#a[$i]}" -le 8 ] && [ "${#b[$i]}" -le 8 ] || return 1
    if (( a[i] > b[i] )); then return 0; fi
    if (( a[i] < b[i] )); then return 1; fi
  done
  return 1
}

mllab_latest_release() {
  local url version
  command -v curl >/dev/null 2>&1 || return 1
  url=$(curl --fail --silent --location --head --connect-timeout 2 --max-time 3 \
    --proto '=https' --proto-redir '=https' --output /dev/null --write-out '%{url_effective}' \
    https://github.com/9root3/mllab-utils/releases/latest) || return 1
  case "$url" in
    https://github.com/9root3/mllab-utils/releases/tag/v*) version=${url##*/v} ;;
    *) return 1 ;;
  esac
  mllab_valid_version "$version" || return 1
  printf '%s\n' "$version"
}

mllab_update_notice() {
  # Noninteractive use, CI and dry runs never contact the network.
  [ -t 2 ] || return 0
  [ "${MLLAB_NO_UPDATE_NOTIFIER:-0}" != 1 ] || return 0
  local arg now checked latest installed cache tmp
  for arg in "$@"; do
    case "$arg" in --dry-run|--help|-h) return 0 ;; esac
  done
  case "${1:-help}" in test|version|help|-h|--help|update) return 0 ;; esac
  cache="${XDG_CACHE_HOME:-$HOME/.cache}/mllab-utils/release"
  now=$(date +%s) || return 0
  checked=0 latest=''
  if [ -f "$cache" ]; then read -r checked latest < "$cache" || true; fi
  [[ "$checked" =~ ^(0|[1-9][0-9]{0,9})$ ]] || checked=0
  if (( now < checked || now - checked >= 86400 )); then
    latest=$(mllab_latest_release) || latest=''
    mkdir -p "${cache%/*}" 2>/dev/null || return 0
    tmp=$(mktemp "${cache}.XXXXXX") || return 0
    printf '%s %s\n' "$now" "$latest" > "$tmp"
    mv -f "$tmp" "$cache" || { rm -f "$tmp"; return 0; }
  fi
  installed=$(cat "$MLLAB_ROOT/VERSION") || return 0
  if mllab_version_newer "$latest" "$installed"; then
    printf 'mllab-utils update available: %s -> %s. Run: mllab update\n' "$installed" "$latest" >&2
  fi
  return 0
}

mllab_update() {
  case "${1:-}" in
    --help|-h) echo 'Usage: mllab update [--check]'; return 0 ;;
    ''|--check) ;;
    *) mllab_die 'Usage: mllab update [--check]' ;;
  esac
  [ "$#" -le 1 ] || mllab_die 'Usage: mllab update [--check]'
  local latest installed tag recorded
  latest=$(mllab_latest_release) || mllab_die 'Cannot check the latest release; repository unchanged'
  installed=$(cat "$MLLAB_ROOT/VERSION")
  if ! mllab_version_newer "$latest" "$installed"; then
    echo "Installed: $installed; latest release: $latest. No update needed."
    return 0
  fi
  if [ "${1:-}" = --check ]; then
    echo "Update available: $installed -> $latest. Run: mllab update"
    return 0
  fi
  command -v flock >/dev/null 2>&1 || mllab_die 'flock is required for safe updates'
  # The lock is on the checkout, so different installations remain independent.
  exec 9< "$MLLAB_ROOT"
  flock -n 9 || mllab_die 'Another update is running'
  [ -z "$(git -C "$MLLAB_ROOT" status --porcelain)" ] || mllab_die 'Local changes found; preserve them before updating'
  [ "$(git -C "$MLLAB_ROOT" symbolic-ref --short HEAD)" = main ] || mllab_die 'Update requires the main branch'
  tag="v$latest"
  git -C "$MLLAB_ROOT" fetch --no-tags https://github.com/9root3/mllab-utils.git "refs/tags/$tag:refs/tags/$tag" || mllab_die 'Release fetch failed'
  recorded=$(git -C "$MLLAB_ROOT" show "$tag:VERSION") || mllab_die 'Release VERSION is missing'
  [ "$recorded" = "$latest" ] || mllab_die 'Release tag and VERSION do not match'
  git -C "$MLLAB_ROOT" merge --ff-only "$tag" || mllab_die 'Cannot fast-forward; local history was preserved'
  echo "Updated mllab-utils to $latest. User config and containers were preserved."
}
