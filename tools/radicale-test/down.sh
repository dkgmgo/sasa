#!/usr/bin/env bash
# Stop and remove the throwaway Radicale.
set -euo pipefail
cd "$(dirname "$0")"
podman compose -f compose.yaml down
