#!/usr/bin/env bash
# Build and start the throwaway Radicale, wait until it answers, then seed it.
set -euo pipefail
cd "$(dirname "$0")"

# Always use podman-compose.
export PODMAN_COMPOSE_PROVIDER="${PODMAN_COMPOSE_PROVIDER:-podman-compose}"

port="${SASA_RADICALE_PORT:-5232}"
podman compose -f compose.yaml up -d --build

echo "Waiting for Radicale on 127.0.0.1:${port}..."
for _ in $(seq 1 30); do
  if curl -fsS -o /dev/null "http://127.0.0.1:${port}/.web/" 2>/dev/null; then
    exec ./seed.sh
  fi
  sleep 1
done
echo "Radicale did not start in time." >&2
podman compose -f compose.yaml logs >&2
exit 1
