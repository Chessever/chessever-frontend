#!/usr/bin/env bash
# Submit the production build for review. Release is always a separate manual
# action in the store consoles; this script has no automatic-release option.
set -euo pipefail

if [ "${GITHUB_REF:-}" != refs/heads/stable ]; then
  echo '::error::Store submissions must run from stable.'
  exit 1
fi

case "${1:-}" in
  android)
    # Google exposes no API for reading Managed publishing. The operator must
    # verify it in Play Console and explicitly attest on every workflow run.
    release_args=(
      bundles publish
      --bundle build/app/outputs/bundle/productionRelease/app-production-release.aab
      --track production
      --in-app-update-priority 5
      --release-notes @file:scripts/ci/mobile_release_notes.json
    )
    if [ "${ANDROID_SUBMIT_DRAFT:-}" = true ]; then
      release_args+=(--draft)
    elif [ "${MANAGED_PUBLISHING_CONFIRMED:-}" != true ]; then
      echo '::error::Google Play Managed publishing must be ON before submission.'
      exit 1
    fi
    google-play "${release_args[@]}"
    ;;
  ios)
    shopt -s nullglob
    packages=(build/ios/ipa/*.ipa)
    if [ "${#packages[@]}" -ne 1 ]; then
      echo '::error::Expected exactly one production IPA.'
      exit 1
    fi
    app-store-connect publish \
      --path "${packages[0]}" \
      --app-store \
      --platform IOS \
      --release-type MANUAL \
      --whats-new @file:scripts/ci/mobile_release_notes.txt \
      --max-find-build-wait 30 \
      --max-build-processing-wait 60
    ;;
  *)
    echo 'usage: mobile_store_submit.sh <android|ios>' >&2
    exit 1
    ;;
esac
