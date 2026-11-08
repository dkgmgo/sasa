#!/usr/bin/env bash
# Format check, static analysis and every package's tests. Used locally and in CI.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos

for pkg in packages/core packages/caldav packages/research apps/cli; do
  echo "== dart test: $pkg"
  (cd "$pkg" && dart test)
done

for pkg in packages/davx_bridge packages/saf_folder apps/app; do
  echo "== flutter test: $pkg"
  (cd "$pkg" && flutter test)
done
