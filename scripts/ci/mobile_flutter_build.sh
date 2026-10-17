#!/usr/bin/env bash
# Build the production mobile app with its release dart-defines.
#
# Called by .github/workflows/mobile-release.yml. The define list and order
# match the build arguments of Codemagic's "Flutter-Default Workflow".
#
#   scripts/ci/mobile_flutter_build.sh appbundle
#   scripts/ci/mobile_flutter_build.sh ipa --export-options-plist "$RUNNER_TEMP/export_options.plist"
#
# This repo is public, so its Actions logs are too. GitHub masks a secret's
# literal value only, while Flutter hands every dart-define to Gradle and Xcode
# base64-encoded ("KEY=VALUE" -> base64), and a failing native step can print
# that encoded list. Each encoded define is registered as a mask before the
# build starts.
set -euo pipefail

target="${1:?usage: mobile_flutter_build.sh <appbundle|ipa> [flutter build args...]}"
shift

# dart-define name=environment variable holding its value.
defines=(
  SUPABASE_URL=SUPABASE_URL
  SUPABASE_ANON_KEY=SUPABASE_ANON_KEY
  GOOGLE_WEB_CLIENT_ID=GOOGLE_WEB_CLIENT_ID
  GOOGLE_IOS_CLIENT_ID=GOOGLE_IOS_CLIENT_ID
  RevenueCatAPIKey=REVENUECAT_API_KEY
  SENTRY_FLUTTER=SENTRY_FLUTTER
  AMPLITUDE=AMPLITUDE
  CLARITY_PROJECT_ID=CLARITY_PROJECT_ID
  ONESIGNAL_APP_ID=ONESIGNAL_APP_ID
  APPSFLYER_DEV_KEY=APPSFLYER_DEV_KEY
  GAMEBASE_API_KEY=GAMEBASE_API_KEY
  CHESSEVER_CLOUDFLARE_API_BASE=CHESSEVER_CLOUDFLARE_API_BASE
  ANALYSIS_API_BASE=ANALYSIS_API_BASE
  TELEGRAM_FEEDBACK_BOT_TOKEN=TELEGRAM_FEEDBACK_BOT_TOKEN
  TELEGRAM_FEEDBACK_CHAT_ID=TELEGRAM_FEEDBACK_CHAT_ID
)

args=()
missing=0
for entry in "${defines[@]}"; do
  key="${entry%%=*}"
  var="${entry#*=}"
  value="${!var:-}"
  if [ -z "$value" ]; then
    echo "::error::$var is not set (dart-define $key)"
    missing=1
    continue
  fi
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    printf '::add-mask::%s\n' "$(printf '%s=%s' "$key" "$value" | base64 | tr -d '\n')"
  fi
  args+=("--dart-define=$key=$value")
done
[ "$missing" -eq 0 ] || exit 1

flutter build "$target" --release "$@" "${args[@]}"
