#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck disable=SC1091
source "$ROOT_DIR/tool/patrol_env.sh"

DEVICE="${1:-${PATROL_DEVICE:-}}"

boot_patrol_ios_simulator "$DEVICE"

base_args=(
  patrol
  test
  "--test-server-port=${PATROL_TEST_SERVER_PORT}"
  "--app-server-port=${PATROL_APP_SERVER_PORT}"
  --dart-define=E2E=true
  --dart-define=E2E_SUPPRESS_PROMPTS=true
  "--dart-define=E2E_TEST_EMAIL=${E2E_TEST_EMAIL}"
  "--dart-define=E2E_TEST_PASSWORD=${E2E_TEST_PASSWORD}"
)

for key in "${PATROL_REQUIRED_ENVS[@]}"; do
  base_args+=("--dart-define=${key}=${!key}")
done

if [[ -n "$DEVICE" ]]; then
  base_args+=(-d "$DEVICE")
fi

run_case() {
  local target="$1"
  local reset_onboarding="$2"

  echo "Running ${target} (E2E_RESET_ONBOARDING=${reset_onboarding})"
  "${base_args[@]}" \
    --dart-define="E2E_RESET_ONBOARDING=${reset_onboarding}" \
    -t "$target"
}

run_case "patrol_test/onboarding_smoke_test.dart" "true"
run_case "patrol_test/signed_in_smoke_test.dart" "false"
