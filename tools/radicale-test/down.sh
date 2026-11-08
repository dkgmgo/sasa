#!/usr/bin/env bash
# Stop and remove the throwaway Radicale.
set -euo pipefail
cd "$(dirname "$0")"

# Always use podman-compose.
export PODMAN_COMPOSE_PROVIDER="${PODMAN_COMPOSE_PROVIDER:-podman-compose}"
podman compose -f compose.yaml down
