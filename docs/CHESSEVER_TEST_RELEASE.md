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

Keep these in the ChessEver Test workflow only. Never reuse the production
Supabase, RevenueCat, OneSignal, or analytics values.

- `TEST_SUPABASE_ANON_KEY`
- `TEST_GOOGLE_SERVICES_JSON` (base64-encoded Android Firebase config)
- `TEST_GOOGLE_SERVICE_INFO_PLIST` (base64-encoded iOS Firebase config)
- `TEST_REVENUECAT_ANDROID_API_KEY`
- `TEST_REVENUECAT_IOS_API_KEY`
- `TEST_ONESIGNAL_APP_ID` (optional until the isolated OneSignal app exists)
- `TEST_SENTRY_DSN` (optional)

The Firebase client IDs below are public OAuth identifiers, not secrets:

- Web: `537883311096-2vtod3ffbtcs3bhda8psl3m2muth70hb.apps.googleusercontent.com`
- iOS: `537883311096-6j22655t8lfk67m6hkhnkguuen90smvh.apps.googleusercontent.com`

## Android App Bundle

```bash
flutter build appbundle --release --flavor chessevertest -t lib/main_test.dart \
  --dart-define=SUPABASE_URL="https://odmekzlfunfocvedqusl.supabase.co" \
  --dart-define=SUPABASE_ANON_KEY="$TEST_SUPABASE_ANON_KEY" \
  --dart-define=GOOGLE_WEB_CLIENT_ID="537883311096-2vtod3ffbtcs3bhda8psl3m2muth70hb.apps.googleusercontent.com" \
  --dart-define=GOOGLE_IOS_CLIENT_ID="537883311096-6j22655t8lfk67m6hkhnkguuen90smvh.apps.googleusercontent.com" \
  --dart-define=RevenueCatAPIKey="$TEST_REVENUECAT_ANDROID_API_KEY" \
  --dart-define=ONESIGNAL_APP_ID="$TEST_ONESIGNAL_APP_ID" \
  --dart-define=SENTRY_FLUTTER="$TEST_SENTRY_DSN"
```

## iOS archive

```bash
flutter build ipa --release --flavor chessevertest -t lib/main_test.dart \
  --dart-define=SUPABASE_URL="https://odmekzlfunfocvedqusl.supabase.co" \
  --dart-define=SUPABASE_ANON_KEY="$TEST_SUPABASE_ANON_KEY" \
  --dart-define=GOOGLE_WEB_CLIENT_ID="537883311096-2vtod3ffbtcs3bhda8psl3m2muth70hb.apps.googleusercontent.com" \
  --dart-define=GOOGLE_IOS_CLIENT_ID="537883311096-6j22655t8lfk67m6hkhnkguuen90smvh.apps.googleusercontent.com" \
  --dart-define=RevenueCatAPIKey="$TEST_REVENUECAT_IOS_API_KEY" \
  --dart-define=ONESIGNAL_APP_ID="$TEST_ONESIGNAL_APP_ID" \
  --dart-define=SENTRY_FLUTTER="$TEST_SENTRY_DSN"
```

Production remains the `default-flavor`, backed by Android's `production`
flavor and the iOS `production` scheme. Existing production CI commands that
omit `--flavor` therefore keep working; explicit production commands may use
`--flavor production -t lib/main.dart`.
The two flavors use different package IDs, Firebase configs, OAuth redirect
schemes, Supabase auth storage keys, and distribution records.
