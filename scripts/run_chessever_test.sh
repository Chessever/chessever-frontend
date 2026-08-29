#!/usr/bin/env bash
# Run ChessEver Test locally (Supabase test branch). Does not use production .env.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
ENV_FILE="${ENV_FILE:-$ROOT/.env.test}"
if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE — create it with SUPABASE_URL/ANON_KEY for odmekzlfunfocvedqusl" >&2
  exit 1
fi
# Sourced only to validate; the real values reach the build through
# --dart-define-from-file below, so every key in the file is passed (gamebase,
# RevenueCat, OneSignal, ...) instead of the four this script used to forward.
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a
: "${SUPABASE_URL:?}"
: "${SUPABASE_ANON_KEY:?}"
: "${GOOGLE_WEB_CLIENT_ID:?}"
: "${GOOGLE_IOS_CLIENT_ID:?}"

EXPECTED_GOOGLE_WEB_CLIENT_ID="537883311096-2vtod3ffbtcs3bhda8psl3m2muth70hb.apps.googleusercontent.com"
EXPECTED_GOOGLE_IOS_CLIENT_ID="537883311096-6j22655t8lfk67m6hkhnkguuen90smvh.apps.googleusercontent.com"

if [[ "$GOOGLE_WEB_CLIENT_ID" != "$EXPECTED_GOOGLE_WEB_CLIENT_ID" ]]; then
  echo "Refusing: GOOGLE_WEB_CLIENT_ID must use the ChessEver Test Firebase project" >&2
  exit 1
fi

if [[ "$GOOGLE_IOS_CLIENT_ID" != "$EXPECTED_GOOGLE_IOS_CLIENT_ID" ]]; then
  echo "Refusing: GOOGLE_IOS_CLIENT_ID must use the ChessEver Test Firebase project" >&2
  exit 1
fi

# Refuse production by accident
case "$SUPABASE_URL" in
  *odmekzlfunfocvedqusl*) ;;
  *)
    echo "Refusing: SUPABASE_URL must be test project odmekzlfunfocvedqusl, got $SUPABASE_URL" >&2
    exit 1
    ;;
esac

DEVICE="${1:-}"
shift_args=()
if [[ -n "$DEVICE" && "$DEVICE" != --* ]]; then
  shift_args+=(-d "$DEVICE")
  shift || true
fi

exec flutter run --flavor chessevertest -t lib/main_test.dart \
  --dart-define-from-file="$ENV_FILE" \
  "${shift_args[@]}" \
  "$@"
