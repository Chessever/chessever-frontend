#!/bin/bash
# The production iPhone archive owns distribution; the watch target is prebuilt
# by flutter-watchos. Refuse a missing/stale watch rather than ship half a pair.
set -euo pipefail

if [[ "${PRODUCT_BUNDLE_IDENTIFIER:-}" != "com.chessever.app" ]]; then
  exit 0
fi
# Mobile release sets CHESSEVER_WATCH: "require" when it built the watch app,
# "skip" for an iPhone-only build. Unset keeps the local rules below.
case "${CHESSEVER_WATCH:-}" in
  skip)
    echo "note: CHESSEVER_WATCH=skip, so this iPhone build ships without the watch companion."
    exit 0
    ;;
  require | "") ;;
  *)
    echo "error: CHESSEVER_WATCH must be 'require' or 'skip', not '${CHESSEVER_WATCH}'."
    exit 1
    ;;
esac
: "${SRCROOT:?Xcode must provide SRCROOT}"
: "${BUILT_PRODUCTS_DIR:?Xcode must provide BUILT_PRODUCTS_DIR}"
: "${CONTENTS_FOLDER_PATH:?Xcode must provide CONTENTS_FOLDER_PATH}"

if [[ "${PLATFORM_NAME:-}" == "iphonesimulator" ]]; then
  watch_configuration="Debug-watchsimulator"
else
  watch_configuration="Release-watchos"
fi
watch_source="${SRCROOT}/../build/watchos/${watch_configuration}/Runner.app"
watch_destination="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Watch"

if [[ ! -d "$watch_source" ]]; then
  if [[ "${CHESSEVER_WATCH:-}" == "require" || "${ACTION:-}" == "install" || "${CONFIGURATION:-}" == Release* ]]; then
    echo "error: ChessEver watch companion is missing. Prepare the release watch app with flutter-watchos and --target lib/main_watch.dart before archiving the production iPhone app."
    exit 1
  fi
  echo "warning: ChessEver watch companion is not prebuilt; this local phone run will omit it."
  exit 0
fi

watch_bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$watch_source/Info.plist")
watch_companion=$(/usr/libexec/PlistBuddy -c 'Print :WKCompanionAppBundleIdentifier' "$watch_source/Info.plist")
if [[ "$watch_bundle" != "com.chessever.app.watchkitapp" || "$watch_companion" != "com.chessever.app" ]]; then
  echo "error: Prebuilt watch app does not belong to the production ChessEver iPhone app."
  exit 1
fi

package_version=$(sed -n 's/^version: //p' "${SRCROOT}/../pubspec.yaml")
expected_name="${FLUTTER_BUILD_NAME:-${package_version%%+*}}"
expected_number="${FLUTTER_BUILD_NUMBER:-${package_version#*+}}"
watch_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$watch_source/Info.plist")
watch_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$watch_source/Info.plist")
if [[ "$watch_name" != "$expected_name" || "$watch_number" != "$expected_number" ]]; then
  echo "error: Prebuilt watch version ($watch_name+$watch_number) does not match iPhone ($expected_name+$expected_number). Rebuild the watch companion."
  exit 1
fi

mkdir -p "$watch_destination"
# ditto replaces the existing bundle's contents without nesting Runner.app.
rm -rf "${watch_destination}/Runner.app"
ditto "$watch_source" "${watch_destination}/Runner.app"
echo "Embedded ChessEver watch companion $watch_name+$watch_number."
