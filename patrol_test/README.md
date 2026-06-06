# Patrol E2E Test Suite

This repository uses Patrol for signed-in mobile end-to-end coverage on the
real Flutter application.

The suite runs the app in a dedicated `E2E` mode, signs in with a real
Supabase email/password account, suppresses interruptive prompts, and exercises
live-data routes with stable selectors.

## Goals

- Cover every major signed-in page root and all named routes that can be
  navigated safely under test.
- Validate board behavior, not just page rendering.
- Assert engine output is visible and refreshes after position changes.
- Traverse games and positions through taps, swipes, notation interactions,
  move buttons, and game selection controls.
- Keep test-only behavior isolated from production behavior.

## Test Layers

- `patrol_test/onboarding_smoke_test.dart`
  Signed-in bootstrap plus onboarding completion.
- `patrol_test/signed_in_smoke_test.dart`
  Fast PR coverage for major roots, detail pages, search, filters, and a core
  board flow.
- `patrol_test/vasif_regression_smoke_test.dart`
  Regular bug-report regression coverage for the flows that have been most
  fragile in manual QA: signed-in startup, tab switching, search/filter reset,
  Library buttons, Favorites/Player Games search, saved-library detail routes,
  and board engine/navigation stability.
- `patrol_test/signed_in_deep_test.dart`
  Exhaustive route traversal, board-entry permutations, notation taps, move
  traversal, game swipes, route jumping, and repeated search/filter mutation.

## Coverage Model

The suite targets these areas:

- Shell roots:
  Events, Calendar, Library, Players, Favorites, Countrymen, Premium,
  Settings, Auth shell, Onboarding, Player Selection.
- Named routes:
  `/`, `/home_screen`, `/group_event_screen`, `/calendar_screen`,
  `/library_screen`, `/favorites_screen`, `/player_list_screen`,
  `/countryman_games_screen`, `/standings`, `/calendar_detail_screen`,
  `/Board_sheet`, `/auth_screen`, `/onboarding`, `/player_selection_screen`.
- Detail flows:
  Tournament Detail, Calendar Detail, Calendar Event Detail, Player Profile,
  Scorecard, Folder Contents, Book Preview, TWIC Contents, Premium Games.
- Board-entry flows:
  tournament games, favorites games, countrymen games, library game results,
  premium games, board editor, opening explorer, and synthetic multi-game
  boards used for deterministic engine/navigation stress.
- Board interactions:
  engine eval bar visibility, PV visibility, move-forward/back navigation,
  notation taps, page swipes between games, board flip, and selector-based
  game jumps.

The deep route matrix explicitly walks every named route registered in
`MaterialApp.routes`, then covers widget-only surfaces that do not have named
routes:

- Settings dialog
- Premium screen
- Premium favorites games
- Premium countrymen games
- TWIC contents
- Board editor
- Opening explorer
- Shared-book preview
- Scorecard

Tournament detail has three logical sections:

- `About`
- `Games`
- `Players`

The UI label is currently `Players`, but that tab is the standings surface and
is asserted with the `e2e_standings_root` selector.

## Isolation Rules

The suite must stay isolated from normal app operation.

- `E2E=true` enables the dedicated startup path.
- Supabase sign-in is performed only in E2E mode.
- interruptive prompts are suppressed only in E2E mode
- onboarding reset is controlled only by `E2E_RESET_ONBOARDING`
- premium remains available through the app's existing debug behavior
- production startup and production navigation keep their normal behavior

The code paths for this live under:

- `lib/e2e/e2e_config.dart`
- `lib/e2e/e2e_ids.dart`
- `lib/main.dart`
- `lib/screens/splash/splash_screen.dart`
- `lib/screens/splash/splash_screen_provider.dart`

## Required Environment

The Patrol scripts load `.env.e2e` by default through `tool/patrol_env.sh`.
They fall back to `.env` only if `.env.e2e` does not exist.

Required application env vars:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `GOOGLE_WEB_CLIENT_ID`
- `GOOGLE_IOS_CLIENT_ID`
- `GAMEBASE_API_KEY`
- `RevenueCatAPIKey`
- `SENTRY_FLUTTER`
- `AMPLITUDE`
- `CLARITY_PROJECT_ID`
- `ONESIGNAL_APP_ID`

Required E2E account vars:

- `E2E_TEST_EMAIL`
- `E2E_TEST_PASSWORD`

Optional runner vars:

- `PATROL_ENV_FILE`
- `PATROL_DEVICE`
- `PATROL_TEST_SERVER_PORT`
- `PATROL_APP_SERVER_PORT`

Use `.env.e2e.example` as the template for a local `.env.e2e`.

## Local Setup

1. Install Flutter and platform toolchains.

```bash
flutter doctor
```

2. Install dependencies.

```bash
flutter pub get
```

3. Install Patrol CLI if it is not already available.

```bash
dart pub global activate patrol_cli
patrol doctor
```

4. Create `.env.e2e` from `.env.e2e.example` and fill in real values.

5. Use a dedicated confirmed E2E user for `E2E_TEST_EMAIL` and
   `E2E_TEST_PASSWORD`.

6. Start a device or simulator.

## Running Locally

Run the PR smoke suite:

```bash
./tool/patrol_smoke.sh
```

Run the bug-report regression suite regularly (recommended after bug fixes and before release QA):

```bash
./tool/patrol_regression.sh
```

Run the deep suite:

```bash
./tool/patrol_deep.sh
```

Run against a specific device or simulator:

```bash
PATROL_DEVICE="iPhone 17 Pro" ./tool/patrol_smoke.sh
PATROL_DEVICE="iPhone 17 Pro" ./tool/patrol_deep.sh
```

Run a single target directly:

```bash
source ./tool/patrol_env.sh
patrol test \
  --test-server-port="$PATROL_TEST_SERVER_PORT" \
  --app-server-port="$PATROL_APP_SERVER_PORT" \
  --dart-define=E2E=true \
  --dart-define=E2E_SUPPRESS_PROMPTS=true \
  --dart-define=E2E_RESET_ONBOARDING=false \
  --dart-define="E2E_TEST_EMAIL=$E2E_TEST_EMAIL" \
  --dart-define="E2E_TEST_PASSWORD=$E2E_TEST_PASSWORD" \
  --dart-define="SUPABASE_URL=$SUPABASE_URL" \
  --dart-define="SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY" \
  --dart-define="GOOGLE_WEB_CLIENT_ID=$GOOGLE_WEB_CLIENT_ID" \
  --dart-define="GOOGLE_IOS_CLIENT_ID=$GOOGLE_IOS_CLIENT_ID" \
  --dart-define="GAMEBASE_API_KEY=$GAMEBASE_API_KEY" \
  --dart-define="RevenueCatAPIKey=$RevenueCatAPIKey" \
  --dart-define="SENTRY_FLUTTER=$SENTRY_FLUTTER" \
  --dart-define="AMPLITUDE=$AMPLITUDE" \
  --dart-define="CLARITY_PROJECT_ID=$CLARITY_PROJECT_ID" \
  --dart-define="ONESIGNAL_APP_ID=$ONESIGNAL_APP_ID" \
  -d "$PATROL_DEVICE" \
  -t patrol_test/signed_in_deep_test.dart
```

## What The Scripts Do

`tool/patrol_env.sh`

- loads `.env.e2e`
- validates all required app and E2E env vars
- allocates Patrol ports dynamically to avoid local conflicts
- boots a requested iOS simulator if one is provided

`tool/patrol_smoke.sh`

- runs onboarding smoke with `E2E_RESET_ONBOARDING=true`
- runs signed-in smoke with `E2E_RESET_ONBOARDING=false`
- is intended for PR validation and fast local confidence checks

`tool/patrol_regression.sh`

- runs `vasif_regression_smoke_test.dart` with onboarding already completed
- is intended for regular bug-fix verification, pre-release QA, and catching
  regressions from repeated manual bug-report patterns

`tool/patrol_deep.sh`

- runs the deep signed-in suite with onboarding already completed
- is intended for nightly, manual, or pre-release route and engine regression
  checks

## Codemagic Integration

This repository does not currently commit a `codemagic.yaml`, so the expected
Codemagic setup is:

1. Configure Flutter/Xcode/Android in the Codemagic app.
2. Add the required env vars in Codemagic variables or an environment group.
3. Provide the E2E account credentials there as secrets.
4. Run the smoke suite in a scripted step.
5. Run the regression suite after bug-fix PRs and on pre-release QA builds.
6. Run the deep suite on a nightly or manual workflow.

Recommended Codemagic variables:

- all required app env vars listed above
- `E2E_TEST_EMAIL`
- `E2E_TEST_PASSWORD`
- `PATROL_DEVICE` when device selection must be explicit

Suggested smoke step:

```bash
flutter pub get
dart pub global activate patrol_cli
export PATH="$PATH:$HOME/.pub-cache/bin"
./tool/patrol_smoke.sh
```

Suggested regression step:

```bash
flutter pub get
dart pub global activate patrol_cli
export PATH="$PATH:$HOME/.pub-cache/bin"
./tool/patrol_regression.sh
```

Suggested deep step:

```bash
flutter pub get
dart pub global activate patrol_cli
export PATH="$PATH:$HOME/.pub-cache/bin"
./tool/patrol_deep.sh
```

Example Codemagic script step:

```yaml
scripts:
  - name: Install Flutter dependencies
    script: flutter pub get
  - name: Install Patrol CLI
    script: |
      dart pub global activate patrol_cli
      export PATH="$PATH:$HOME/.pub-cache/bin"
      patrol doctor
  - name: Run Patrol smoke suite
    script: |
      export PATH="$PATH:$HOME/.pub-cache/bin"
      ./tool/patrol_smoke.sh
```

Recommended workflow split:

- PR workflow:
  run `./tool/patrol_smoke.sh`
- Bug-fix and pre-release QA workflow:
  run `./tool/patrol_regression.sh`
- Nightly or manual workflow:
  run `./tool/patrol_deep.sh`

Recommended artifacts:

- Patrol logs
- Flutter test output
- Xcode `.xcresult` bundle for iOS
- Android instrumentation output when running on Android

## How To Add More Coverage

When adding new routes or board surfaces:

1. Add a stable `ValueKey` in `lib/e2e/e2e_ids.dart`.
2. Put the key on the page root or important control.
3. Add a helper in `patrol_test/support/e2e_test_support.dart` if the action is
   reused.
4. Prefer asserting visibility first, then behavior.
5. For board features, always prove engine output is visible and changes after
   navigation.

## Debugging Failures

Common failure classes:

- env loading
- startup gating
- live data availability
- engine readiness
- simulator/device wiring
- stale selector coverage after UI refactors
- dynamic list screens returning no live rows for a route

Useful commands:

```bash
flutter analyze patrol_test lib/e2e
patrol doctor
flutter test --coverage
```

If a route is dynamic, prefer seeded test data or the first-visible-valid-card
pattern already used by the support helpers.
