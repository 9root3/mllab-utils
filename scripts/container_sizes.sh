#!/usr/bin/env bash
set -euo pipefail

docker ps -as --format "table {{.ID}}\t{{.Names}}\t{{.Size}}" | sort -rh -k3
