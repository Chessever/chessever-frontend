#!/usr/bin/env bash
# Send the production build to a store destination. `testing` (the default
# workflow choice) uploads to TestFlight and Google Play internal testing with
# no review. `review` submits for review; release is always a separate manual
# action in the store consoles, and this script has no automatic-release option.
set -euo pipefail

if [ "${GITHUB_REF:-}" != refs/heads/stable ]; then
  echo '::error::Store submissions must run from stable.'
  exit 1
fi

platform="${1:-}"
destination="${2:-}"
case "$destination" in
  testing|review) ;;
  *)
    echo 'usage: mobile_store_submit.sh <android|ios> <testing|review>' >&2
    exit 1
    ;;
esac

case "$platform" in
  android)
    bundle=build/app/outputs/bundle/productionRelease/app-production-release.aab
    if [ "$destination" = testing ]; then
      # Internal testing is not covered by Managed publishing and skips review:
      # the release reaches the internal testers' list as soon as Play commits it.
      google-play bundles publish \
        --bundle "$bundle" \
        --track internal \
        --in-app-update-priority 5 \
        --release-notes @file:scripts/ci/mobile_release_notes.json
      exit 0
    fi
    # Google exposes no API for reading Managed publishing. The operator must
    # verify it in Play Console and explicitly attest on every workflow run.
    release_args=(
      bundles publish
      --bundle "$bundle"
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
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ "$destination" = testing ]; then
      python3 "$script_dir/testflight_upload.py" --package "${packages[0]}"
      exit 0
    fi
    python3 "$script_dir/app_store_review.py" --package "${packages[0]}" \
      --platform IOS --release-type MANUAL \
      --notes scripts/ci/mobile_release_notes.txt \
      --replace-pending "${REPLACE_PENDING_IOS_REVIEW:-false}"
    ;;
  *)
    echo 'usage: mobile_store_submit.sh <android|ios> <testing|review>' >&2
    exit 1
    ;;
esac
