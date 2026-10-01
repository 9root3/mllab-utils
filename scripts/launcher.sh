#!/usr/bin/env bash
set -euo pipefail
# Keep release management available even when the selected CLI predates it.
LAUNCHER_PATH=$(readlink -f "${BASH_SOURCE[0]}")
MLLAB_MANAGER_ROOT=$(cd "$(dirname "$LAUNCHER_PATH")/.." && pwd)
export MLLAB_MANAGER_ROOT
# shellcheck source=scripts/lib.sh
source "$MLLAB_MANAGER_ROOT/scripts/lib.sh"
# shellcheck source=scripts/update.sh
source "$MLLAB_MANAGER_ROOT/scripts/update.sh"
MLLAB_ROOT=$(mllab_active_root)
export MLLAB_ROOT
mllab_load_config
mllab_update_notice "$@" || true
export MLLAB_NO_UPDATE_NOTIFIER=1
case "${1:-help}" in
  update|rollback|help|-h|--help) exec "$MLLAB_MANAGER_ROOT/pm.sh" "$@" ;;
  *) exec "$MLLAB_ROOT/pm.sh" "$@" ;;
esac
