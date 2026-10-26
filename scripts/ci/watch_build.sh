#!/usr/bin/env bash
# Build the Apple Watch companion that the iPhone app embeds
# (scripts/embed_watch_companion.sh). Called by
# .github/workflows/mobile-release.yml and watch-companion-check.yml.
#
#   scripts/ci/watch_build.sh toolchain        clone flutter-watchos at the commit pubspec.yaml
#                                              pins, signed in when FLUTTERWATCH_TOKEN is set
#   scripts/ci/watch_build.sh simulator        debug Simulator build; needs no account
#   scripts/ci/watch_build.sh release          AOT device build, left unsigned
#   scripts/ci/watch_build.sh sign             sign the release build with the App Store
#                                              profile `xcode-project use-profiles` assigned
#   scripts/ci/watch_build.sh check-ipa <ipa>  the IPA carries the signed watch app
#
# flutter-watchos signs every device build automatically. On a runner with no
# Xcode account that means a new development certificate per run, so `release`
# turns signing off and `sign` rebuilds the staged watch project with the
# distribution certificate and profile the iPhone build already uses.
set -euo pipefail

# flutter-watchos reports each release build (bundle id, version, build mode)
# to the flutterwatch.dev account. Nothing needs it, so CI sends nothing.
export FLUTTER_WATCHOS_BUILD_REGISTRY=0

WATCH_BUNDLE_ID=com.chessever.app.watchkitapp
toolchain_dir="${FLUTTER_WATCHOS_HOME:-${RUNNER_TEMP:-/tmp}/flutter-watchos}"
flutter_watchos="$toolchain_dir/bin/flutter-watchos"
release_app=build/watchos/Release-watchos/Runner.app

# FFI lookups do not create linker references. A successful build can still
# ship without the notification bridge, which used to crash on first launch.
check_native_bridge() {
  local app="$1" executable symbols
  executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Info.plist")"
  symbols="$(mktemp)"
  local binaries=("$app/$executable")
  if [ -f "$app/$executable.debug.dylib" ]; then
    binaries+=("$app/$executable.debug.dylib")
  fi
  if ! nm -gU "${binaries[@]}" > "$symbols"; then
    rm -f "$symbols"
    echo '::error::Could not inspect the watch native binary.'
    return 1
  fi
  local symbol
  for symbol in chessever_watch_listen chessever_watch_stop chessever_watch_free; do
    if ! grep -Eq "[[:space:]]_${symbol}$" "$symbols"; then
      rm -f "$symbols"
      echo "::error::Watch notification bridge symbol $symbol is missing. Check its watchos/Package.swift."
      return 1
    fi
  done
  rm -f "$symbols"
  echo 'Watch native notification bridge verified.'
}

# The watch CLI and the flutter_watchos package must come from one commit.
pinned_ref() {
  sed -n '/^  flutter_watchos:/,/^  [a-z]/s/^ *ref: *//p' pubspec.yaml | head -1
}

# The public anon key lets the watch read the feed before the phone first
# syncs. It is masked like every other define: Xcode logs carry it base64-encoded.
watch_defines() {
  if [ -z "${SUPABASE_ANON_KEY:-}" ]; then
    return
  fi
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    printf '::add-mask::%s\n' "$(printf 'SUPABASE_ANON_KEY=%s' "$SUPABASE_ANON_KEY" | base64 | tr -d '\n')" >&2
  fi
  printf '%s\n' "--dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY"
}

profile_field() {
  local decoded
  decoded="$(mktemp)"
  security cms -D -i "$1" > "$decoded"
  /usr/libexec/PlistBuddy -c "Print :$2" "$decoded"
  rm -f "$decoded"
}

case "${1:-}" in
  toolchain)
    ref="$(pinned_ref)"
    if ! [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
      echo "::error::pubspec.yaml must pin flutter_watchos to a full commit SHA (found '$ref')."
      exit 1
    fi
    if [ ! -d "$toolchain_dir/.git" ]; then
      git init -q "$toolchain_dir"
      git -C "$toolchain_dir" remote add origin https://github.com/flutterwatch/flutter-watchos.git
    fi
    git -C "$toolchain_dir" fetch -q --depth 1 origin "$ref"
    git -C "$toolchain_dir" checkout -q --detach FETCH_HEAD
    if [ -n "${FLUTTERWATCH_TOKEN:-}" ]; then
      # What `flutter-watchos login` writes. Never run `logout` here: it
      # revokes the token for every machine.
      (
        umask 077
        mkdir -p "$HOME/.flutter-watchos"
        python3 -I -c 'import json, os; print(json.dumps({"token": os.environ["FLUTTERWATCH_TOKEN"]}))' \
          > "$HOME/.flutter-watchos/credentials.json"
      )
    fi
    "$flutter_watchos" precache
    "$flutter_watchos" doctor -v || echo '::warning::flutter-watchos doctor reported a problem; see above.'
    ;;

  simulator)
    defines=()
    while IFS= read -r define; do defines+=("$define"); done < <(watch_defines)
    "$flutter_watchos" build watchos --simulator --target lib/main_watch.dart ${defines[@]+"${defines[@]}"}
    check_native_bridge build/watchos/Debug-watchsimulator/Runner.app
    ;;

  release)
    if [ -z "${FLUTTERWATCH_TOKEN:-}" ]; then
      echo '::error::FLUTTERWATCH_TOKEN is not set. Release watch engines need a flutterwatch.dev account (docs/watch-companion.md).'
      exit 1
    fi
    if [ -z "${SUPABASE_ANON_KEY:-}" ]; then
      echo '::error::SUPABASE_ANON_KEY is not set.'
      exit 1
    fi
    defines=()
    while IFS= read -r define; do defines+=("$define"); done < <(watch_defines)
    unsigned="$(mktemp -d)/unsigned.xcconfig"
    printf 'CODE_SIGNING_ALLOWED = NO\nCODE_SIGNING_REQUIRED = NO\n' > "$unsigned"
    XCODE_XCCONFIG_FILE="$unsigned" \
      "$flutter_watchos" build watchos --release --target lib/main_watch.dart ${defines[@]+"${defines[@]}"}
    check_native_bridge "$release_app"
    if ! git diff --quiet -- watchos ios/Runner.xcodeproj; then
      echo '::warning::flutter-watchos rewrote the watch wiring; commit what it changed:'
      git diff --stat -- watchos ios/Runner.xcodeproj
    fi
    ;;

  check-native)
    check_native_bridge "${2:?usage: watch_build.sh check-native <Runner.app>}"
    ;;

  sign)
    if [ ! -d "$release_app" ]; then
      echo "::error::$release_app is missing; run the release step first."
      exit 1
    fi
    if ! grep -q 'PROVISIONING_PROFILE_SPECIFIER' watchos/Runner.xcodeproj/project.pbxproj; then
      echo "::error::No App Store profile was assigned to $WATCH_BUNDLE_ID. Register the bundle ID and rerun code signing setup."
      exit 1
    fi
    symroot="$PWD/build/watchos"
    project=(-project Runner.xcodeproj)
    if [ -d watchos/Runner.xcworkspace ]; then
      project=(-workspace Runner.xcworkspace)
    fi
    (
      cd watchos
      xcodebuild "${project[@]}" -scheme Runner -configuration Release -sdk watchos \
        -destination 'generic/platform=watchOS' \
        SYMROOT="$symroot" COMPILER_INDEX_STORE_ENABLE=NO build
    )
    codesign --verify --strict --deep "$release_app"
    app_id="$(profile_field "$release_app/embedded.mobileprovision" Entitlements:application-identifier)"
    case "$app_id" in
      *."$WATCH_BUNDLE_ID") ;;
      *)
        echo "::error::The watch app is signed for '$app_id', not $WATCH_BUNDLE_ID."
        exit 1
        ;;
    esac
    echo "Watch profile: $(profile_field "$release_app/embedded.mobileprovision" Name)"
    echo "Watch app ID:  $app_id"
    ;;

  check-ipa)
    ipa="${2:?usage: watch_build.sh check-ipa <ipa>}"
    check_dir="$(mktemp -d)"
    unzip -q "$ipa" -d "$check_dir"
    phone="$check_dir/Payload/Runner.app"
    watch="$phone/Watch/Runner.app"
    if [ ! -d "$watch" ]; then
      echo '::error::The IPA does not contain the Apple Watch app.'
      exit 1
    fi
    bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$watch/Info.plist")"
    companion="$(/usr/libexec/PlistBuddy -c 'Print :WKCompanionAppBundleIdentifier' "$watch/Info.plist")"
    if [ "$bundle" != "$WATCH_BUNDLE_ID" ] || [ "$companion" != com.chessever.app ]; then
      echo "::error::The embedded watch app is $bundle (companion $companion)."
      exit 1
    fi
    for key in CFBundleShortVersionString CFBundleVersion; do
      phone_value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$phone/Info.plist")"
      watch_value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$watch/Info.plist")"
      if [ "$phone_value" != "$watch_value" ]; then
        echo "::error::$key differs: iPhone $phone_value, watch $watch_value."
        exit 1
      fi
    done
    app_id="$(profile_field "$watch/embedded.mobileprovision" Entitlements:application-identifier)"
    case "$app_id" in
      *."$WATCH_BUNDLE_ID") ;;
      *)
        echo "::error::The embedded watch app is signed for '$app_id'."
        exit 1
        ;;
    esac
    codesign --verify --strict --deep "$watch"
    echo "Watch app:     $bundle $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$watch/Info.plist") ($app_id)"
    rm -rf "$check_dir"
    ;;

  *)
    echo 'usage: watch_build.sh <toolchain|simulator|release|sign|check-native <app>|check-ipa <ipa>>' >&2
    exit 1
    ;;
esac
