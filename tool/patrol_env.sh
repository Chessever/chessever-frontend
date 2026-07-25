#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PATROL_ENV_FILE="${PATROL_ENV_FILE:-.env.e2e}"
PATROL_LOADED_ENV_FILE=""

if [[ -f "$PATROL_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$PATROL_ENV_FILE"
  set +a
  PATROL_LOADED_ENV_FILE="$PATROL_ENV_FILE"
elif [[ -f ".env" ]]; then
  set -a
  # shellcheck disable=SC1090
  source ".env"
  set +a
  PATROL_LOADED_ENV_FILE=".env"
fi

PATROL_REQUIRED_ENVS=(
  SUPABASE_URL
  SUPABASE_ANON_KEY
  GOOGLE_WEB_CLIENT_ID
  GOOGLE_IOS_CLIENT_ID
  GAMEBASE_API_KEY
  RevenueCatAPIKey
  SENTRY_FLUTTER
  AMPLITUDE
  CLARITY_PROJECT_ID
  ONESIGNAL_APP_ID
)

PATROL_REQUIRED_E2E_ENVS=(
  "${PATROL_REQUIRED_ENVS[@]}"
  E2E_TEST_EMAIL
  E2E_TEST_PASSWORD
)

for key in "${PATROL_REQUIRED_E2E_ENVS[@]}"; do
  : "${!key:?${key} must be set in ${PATROL_LOADED_ENV_FILE:-environment}}"
done

find_free_patrol_port() {
  local candidate="${1:?starting port is required}"

  while command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:"$candidate" -sTCP:LISTEN >/dev/null 2>&1; do
    candidate=$((candidate + 1))
  done

  echo "$candidate"
}

PATROL_TEST_SERVER_PORT="${PATROL_TEST_SERVER_PORT:-$(find_free_patrol_port 18081)}"
PATROL_APP_SERVER_PORT="${PATROL_APP_SERVER_PORT:-$(find_free_patrol_port 18082)}"

if [[ "$PATROL_APP_SERVER_PORT" == "$PATROL_TEST_SERVER_PORT" ]]; then
  PATROL_APP_SERVER_PORT="$(find_free_patrol_port $((PATROL_TEST_SERVER_PORT + 1)))"
fi

export PATROL_TEST_SERVER_PORT
export PATROL_APP_SERVER_PORT

boot_patrol_ios_simulator() {
  local device_name="${1:-}"

  if [[ -z "$device_name" ]] || ! command -v xcrun >/dev/null 2>&1; then
    return
  fi

  local simulator_udid
  simulator_udid="$(
    xcrun simctl list devices available 2>/dev/null \
      | grep -F "$device_name" \
      | head -n 1 \
      | sed -E 's/.*\(([0-9A-F-]+)\) \((Booted|Shutdown)\).*/\1/'
  )"

  if [[ -z "$simulator_udid" ]]; then
    return
  fi

  xcrun simctl boot "$simulator_udid" >/dev/null 2>&1 || true
  open -a Simulator >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$simulator_udid" -b >/dev/null 2>&1 || true
}
