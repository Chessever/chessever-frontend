# ChessEver Test release

ChessEver Test is a side-by-side mobile build of the same Dart application. Its
runtime entry point is `lib/main_test.dart`, and startup refuses any Supabase URL
whose project ref is not `odmekzlfunfocvedqusl`.

## App identities

- Android flavor: `chessevertest`
- Android application ID: `com.chessEver.app.test`
- iOS scheme: `chessevertest`
- iOS bundle ID: `com.chessever.app.test`
- Display name: `ChessEver Test`
- Firebase project: `chessever-test-2026`
- Supabase project ref: `odmekzlfunfocvedqusl`

## CI secrets

**Supabase is the only boundary this flavor isolates.** Every other service
reuses the production value so the test build behaves like the real app. Only
these are test-specific:

- `TEST_SUPABASE_ANON_KEY`
- `TEST_GOOGLE_SERVICES_JSON` (base64-encoded Android Firebase config, package
  `com.chessEver.app.test`, project `chessever-test-2026`)
- `TEST_GOOGLE_SERVICE_INFO_PLIST` (base64-encoded iOS Firebase config)

Everything else is the production variable already in the shared Codemagic
group: `GAMEBASE_API_KEY`, `CHESSEVER_CLOUDFLARE_API_BASE`, `RevenueCatAPIKey`,
`ONESIGNAL_APP_ID`, `AMPLITUDE`, `CLARITY_PROJECT_ID`, `APPSFLYER_DEV_KEY`,
`TELEGRAM_FEEDBACK_BOT_TOKEN`, `TELEGRAM_FEEDBACK_CHAT_ID`.

`SENTRY_FLUTTER` is **not** passed to this flavor. `main.dart` assigns
`options.dsn` from it, and an empty DSN makes the SDK a no-op, so omitting the
define is the entire off switch. Do not add a `TEST_SENTRY_DSN`.

Two known consequences of sharing production keys, accepted deliberately:

- **RevenueCat** purchases will not complete. The keys are bound to
  `com.chessEver.app` / `com.chessever.app`, and this flavor ships as `.test`.
  The paywall renders; buying fails at store validation.
- **OneSignal** test installs join the production audience, while their
  player-id rows are written to the *test* Supabase. The dispatcher reads the
  production database, so it will not find them.

The Firebase client IDs below are public OAuth identifiers, not secrets:

- Web: `537883311096-2vtod3ffbtcs3bhda8psl3m2muth70hb.apps.googleusercontent.com`
- iOS: `537883311096-6j22655t8lfk67m6hkhnkguuen90smvh.apps.googleusercontent.com`

## CI build commands

Both targets pass the identical define set. Keep the two lists in sync with each
other and with `.env.test`; a define missing here is silently empty at runtime,
which is how the opening explorer once shipped broken to TestFlight.

Write the defines to a file first so there is one list, not two:

```bash
cat > /tmp/chessevertest.env <<EOF
SUPABASE_URL=https://odmekzlfunfocvedqusl.supabase.co
SUPABASE_ANON_KEY=$TEST_SUPABASE_ANON_KEY
GOOGLE_WEB_CLIENT_ID=537883311096-2vtod3ffbtcs3bhda8psl3m2muth70hb.apps.googleusercontent.com
GOOGLE_IOS_CLIENT_ID=537883311096-6j22655t8lfk67m6hkhnkguuen90smvh.apps.googleusercontent.com
GAMEBASE_API_KEY=$GAMEBASE_API_KEY
CHESSEVER_CLOUDFLARE_API_BASE=$CHESSEVER_CLOUDFLARE_API_BASE
RevenueCatAPIKey=$RevenueCatAPIKey
ONESIGNAL_APP_ID=$ONESIGNAL_APP_ID
AMPLITUDE=$AMPLITUDE
CLARITY_PROJECT_ID=$CLARITY_PROJECT_ID
APPSFLYER_DEV_KEY=$APPSFLYER_DEV_KEY
TELEGRAM_FEEDBACK_BOT_TOKEN=$TELEGRAM_FEEDBACK_BOT_TOKEN
TELEGRAM_FEEDBACK_CHAT_ID=$TELEGRAM_FEEDBACK_CHAT_ID
EOF
```

No `SENTRY_FLUTTER` line — see CI secrets above.

```bash
# Android App Bundle
flutter build appbundle --release --flavor chessevertest -t lib/main_test.dart \
  --dart-define-from-file=/tmp/chessevertest.env

# iOS archive
flutter build ipa --release --flavor chessevertest -t lib/main_test.dart \
  --export-options-plist=/Users/builder/export_options.plist \
  --dart-define-from-file=/tmp/chessevertest.env
```

### Shorebird must stay off for this flavor

`shorebird.yaml` declares a single `app_id`
(`b14b4d03-902e-48ec-96be-f138b5e7d02e`) with no per-flavor mapping. A
`shorebird release` from the test workflow would therefore register the build
against the **production** Shorebird app, putting test code in the patch stream
production installs pull from. Use plain `flutter build` here. If test builds
ever need patching, add a `flavors:` block to `shorebird.yaml` with a separate
app id first.

Production remains the `default-flavor`, backed by Android's `production`
flavor and the iOS `production` scheme. Existing production CI commands that
omit `--flavor` therefore keep working; explicit production commands may use
`--flavor production -t lib/main.dart`.
The two flavors use different package IDs, Firebase configs, OAuth redirect
schemes, Supabase auth storage keys, and distribution records.

## Local debug (simulator / device)

Test flavor **does not** read production `.env` for Supabase. All test-flavor
values live in a single untracked file, **`.env.test`** — there is no
`.env.test.local`; one file is the whole story.

Supabase is the only boundary this flavor isolates. Every other service key in
`.env.test` is deliberately identical to `.env`, so the test app talks to the
same gamebase, RevenueCat, OneSignal, analytics and Cloudflare backends as
production. Sentry is the one exception: `SENTRY_FLUTTER` is omitted on purpose,
which leaves `options.dsn` empty and makes the SDK a no-op. Do not add it back.

Release builds resolve these only through `String.fromEnvironment` — the dotenv
fallback in `main.dart` is gated on `kDebugMode && !AppEnvironment.isTest`, so a
key omitted from `.env.test` is permanently empty in this flavor, silently.

```bash
./scripts/run_chessever_test.sh            # picks a device interactively via flutter
./scripts/run_chessever_test.sh <deviceId> # specific simulator or phone

# equivalent by hand, and how to run a release build:
flutter run --release --flavor chessevertest -t lib/main_test.dart \
  --dart-define-from-file=.env.test
```

The script forwards the file wholesale via `--dart-define-from-file`, so adding a
key to `.env.test` is enough — nothing to mirror in the script.

Startup refuses any Supabase host other than `odmekzlfunfocvedqusl.supabase.co`,
in the script and again in `AppEnvironment.validateSupabaseUrl`.

## App Store Connect / TestFlight

- ASC app id: `6798829510` · bundle `com.chessever.app.test`
- Internal group: **Internal Testers** (`0b253c27-7a19-4171-9397-77072f917b8b`)
- Members: `devberkay@icloud.com`, `durarbayli@gmail.com`
- Invites stay `NOT_INVITED` until the first processed build exists

## Codemagic auto-deploy (honest status)

The **ChessEver Test** Codemagic workflow is a Workflow Editor clone of
production with test dart-defines and Shorebird off. Auto-publish is **not**
guaranteed until each of these is true in the Codemagic UI:

| Target | Required |
|---|---|
| TestFlight | iOS signing + App Store Connect integration pointed at `com.chessever.app.test` / app `6798829510`; publish enabled |
| Play internal | Separate Play Console app for `com.chessEver.app.test` + service account + internal track publish enabled |

Production Play internal (`com.chessEver.app`) must never receive test builds.
Do not reuse the production Play integration for ChessEver Test until the
package id on that integration is the `.test` one.
