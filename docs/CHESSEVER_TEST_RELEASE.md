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

`ANALYSIS_API_BASE` is the one define with no Codemagic variable behind it: the
report Worker's URL is public, so the build passes the literal. It is a
*different* service from `CHESSEVER_CLOUDFLARE_API_BASE` — the GIF Worker serves
`/v1/gif-jobs` and nothing else, so crossing the two 404s every Game Report and
drops each review to the phone's own engine. Omitting the define is safe (the
client falls back to the same production URL); pointing it at the GIF Worker is
not.

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

### Android Google Sign-In (Play App Signing)

Android Google Sign-In for this package is package-name + SHA-1 based. Supabase
only needs the **Web** client ID (same as iOS). The Play install path needs the
**App signing** SHA-1 registered on Firebase project `chessever-test-2026` for
`com.chessEver.app.test`.

Fingerprints currently registered (Firebase → Project settings → Android app):

| Source | SHA-1 |
|---|---|
| Local debug keystore | `68:A8:CC:6B:…:34:76` |
| Upload / local release (`my-release-key.jks`) | `DC:83:1A:5D:…:A9:F9` |
| Play App signing (current) | `76:36:BE:7B:…:A3:72` |
| Play App signing (previous, Aug 2026) | `D9:7B:69:0B:…:27:C9` |

When Play rotates the app signing key, add the new SHA-1 in Firebase, re-download
`android/app/src/chessevertest/google-services.json`, and if CI injects
`TEST_GOOGLE_SERVICES_JSON`, re-base64 the updated file into that secret.
Propagation can take a few minutes (rarely longer). Production Firebase
(`chessever-53078` / `com.chessEver.app`) is intentionally untouched.

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
ANALYSIS_API_BASE=https://chessever-analysis.young-sun-69a8.workers.dev
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

`shorebird.yaml` maps only the `production` flavor to the production Shorebird
app. The `chessevertest` flavor is intentionally absent, so a Shorebird release
for it fails instead of putting test code in the patch stream production
installs pull from. Use plain `flutter build` here. If test builds ever need
patching, add `chessevertest` with a separate Shorebird app id first.

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
production with test dart-defines and Shorebird off. Workflow id:
`6a74e4eb68ba776b681ec344` under app `68eadad7aefafda5702248a0`.

### Must-be-true checklist (audited)

| Check | Expected |
|---|---|
| Shorebird | **Disabled** (never Release/Patch) |
| Android build args | `--flavor chessevertest -t lib/main_test.dart` + test dart-defines |
| iOS build args | same flavor/entry/defines |
| `SUPABASE_URL` | `https://odmekzlfunfocvedqusl.supabase.co` |
| `GOOGLE_WEB_CLIENT_ID` / `GOOGLE_IOS_CLIENT_ID` | test Firebase project `537883311096-…` |
| `GOOGLE_SERVICES_JSON` | base64 of **test** `google-services.json` (`com.chessEver.app.test`, includes Play App signing SHA-1 `7636be7b…`) |
| Post-clone script | writes JSON to `android/app/src/chessevertest/google-services.json` **and** validates package/project/Play SHA |
| Google Play publish | Internal track only, package comes from the AAB (`.test`) |
| TestFlight | ASC app `6798829510` / `com.chessever.app.test` |

### Refresh `GOOGLE_SERVICES_JSON` after Firebase SHA changes

```bash
base64 -i android/app/src/chessevertest/google-services.json | pbcopy
```

Paste into Codemagic → ChessEver Test → Environment variables →
`GOOGLE_SERVICES_JSON` (secret). Next build’s post-clone script fails loudly if
the secret is still the old file without the Play App signing SHA.

Auto-publish is **not** guaranteed until each of these is true in the Codemagic UI:

| Target | Required |
|---|---|
| TestFlight | iOS signing + App Store Connect integration pointed at `com.chessever.app.test` / app `6798829510`; publish enabled |
| Play internal | Separate Play Console app for `com.chessEver.app.test` + service account + internal track publish enabled |

Production Play internal (`com.chessEver.app`) must never receive test builds.
Do not reuse the production Play integration for ChessEver Test until the
package id on that integration is the `.test` one.
