#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck disable=SC1091
source "$ROOT_DIR/tool/patrol_env.sh"

DEVICE="${1:-${PATROL_DEVICE:-}}"

boot_patrol_ios_simulator "$DEVICE"

args=(
  patrol
  test
  "--test-server-port=${PATROL_TEST_SERVER_PORT}"
  "--app-server-port=${PATROL_APP_SERVER_PORT}"
  --dart-define=E2E=true
  --dart-define=E2E_SUPPRESS_PROMPTS=true
  --dart-define=E2E_RESET_ONBOARDING=false
  "--dart-define=E2E_TEST_EMAIL=${E2E_TEST_EMAIL}"
  "--dart-define=E2E_TEST_PASSWORD=${E2E_TEST_PASSWORD}"
  -t
  patrol_test/vasif_regression_smoke_test.dart
)

for key in "${PATROL_REQUIRED_ENVS[@]}"; do
  args+=("--dart-define=${key}=${!key}")
done

if [[ -n "$DEVICE" ]]; then
  args+=(-d "$DEVICE")
fi

echo "Running patrol_test/vasif_regression_smoke_test.dart"
"${args[@]}"
