# Rewarded Premium access

Production Android/iOS only. ChessEver Test never requests ads or accepts
rewarded access. Live ads are disabled by default until configuration and
backend deployment are complete. No deployment is performed by this change.

## Configuration

The supplied production IDs are configured as defaults:

| Platform | App ID | Rewarded ad-unit ID |
| --- | --- | --- |
| Android | `ca-app-pub-3681310687796023~4858872090` | `ca-app-pub-3681310687796023/8590975808` |
| iOS | `ca-app-pub-3681310687796023~5640461560` | `ca-app-pub-3681310687796023/8331032066` |

Rewarded access remains disabled by default. After backend deployment and AdMob
verification/privacy setup, enable the production flavor with
`REWARDED_PREMIUM_ENABLED=true` as a Flutter Dart define.
The four `ADMOB_ANDROID_APP_ID`, `ADMOB_ANDROID_REWARDED_ID`,
`ADMOB_IOS_APP_ID`, and `ADMOB_IOS_REWARDED_ID` Dart defines can override these
defaults. Android's native SDK app ID reads the same override. If overriding
iOS, also create `ios/Flutter/AdMob-production.xcconfig` containing
`ADMOB_APP_ID = <the same ADMOB_IOS_APP_ID>`.
ChessEver Test retains sample native app IDs and cannot obtain rewarded access.
Debug uses Google's sample rewarded units. AdMob identifiers are public
configuration, not API secrets.

In AdMob, configure each rewarded unit with the reward description "10 minutes
of Premium", enable server-side verification, and point it to
`https://oelbsuggrzyqwzmvidju.supabase.co/functions/v1/rewarded-premium-ssv`.
Set up the applicable privacy messages in AdMob Privacy & messaging. UMP runs
before requesting the first ad of each app launch; required ad privacy options
appear in About after consent information is loaded. The existing ATT prompt
runs before requesting iOS ads; denying tracking does not itself deny access.
AdMob chooses the duration and may supply an ad pod; the app never promises
30 seconds or chains ads itself.

Both Edge Functions default to the two supplied production rewarded unit IDs.
No CLI secret setup is needed for these public identifiers. An optional
`REWARDED_AD_UNIT_IDS` environment variable overrides the defaults with a
comma-separated allowlist. For the supplied production units, its value is:

```text
REWARDED_AD_UNIT_IDS=ca-app-pub-3681310687796023/8590975808,ca-app-pub-3681310687796023/8331032066
```

The functions refuse other Supabase project hosts. Configure production units only for production. Never enable a bypass
that accepts client claims instead of Google's signed callback.

Debug binaries use Google sample rewarded units; do not expect a production
server allowlist to grant access to them. Offline unit/widget tests and the
AdMob SSV testing tool cover the verification flow. For device acceptance with
real configured units, supply `ADMOB_TEST_DEVICE_IDS` with the comma-separated test-device IDs
before testing; never generate live impressions during development.

## Deployment order (separately authorized)

1. Review/apply `20261001044952_rewarded_premium_sessions.sql` to production
   `oelbsuggrzyqwzmvidju`. It adds private grant storage, service-role-only
   prepare/verify/activate RPCs, a caller-scoped grant predicate, and additive
   report/ranking RPC overloads. Legacy subscription tables, predicates and
   RPC signatures remain intact.
2. Deploy the production Gamebase and chat changes from their reviewed local
   branches. `x-rewarded-session` is a bearer capability and must never be
   logged, persisted, or cached as a subscription. Gamebase requires the
   existing first-party API key and authenticated user; chat retains its
   full-account ownership requirement.
3. Deploy `rewarded-premium` and `rewarded-premium-ssv` with
   `--project-ref oelbsuggrzyqwzmvidju --no-verify-jwt`. Run the repository's
   Edge Function auth audit after deployment. The approved production allowlist is included in the functions. Configure
   the SSV callback before enabling the production app flag.
4. Supply the platform IDs and release the production flavor from `stable`.
   Roll back the app flag to disable new ad grants if needed. Existing grants
   expire naturally within ten minutes. Do not apply this to the test project.

The analysis worker's concurrent-job, global capacity, and per-user safety
ceilings continue to apply to both paid and rewarded callers. Chat uses the
existing premium daily allowance, then restores the free allowance at expiry;
usage is not erased by watching another ad. Existing sign-in requirements for
owned data still apply. Saved games/imports/favorites are never deleted when
a grant expires. The expiry popup retains the current screen and work while
the user renews or upgrades; explicit Go back opens a free screen while keeping the previous route and
drafts alive. Returning to the suspended route requires renewal or upgrade.

Attempts that remain pending can be confirmed for up to 24 hours, only from
the original process token. A successful activation starts ten minutes;
activation retries return the original deadline. Multiple concurrent attempts
cannot stack time. An expired attempt never creates a new window.
Older attempts may be removed by an administrator after seven days; callbacks
older than 24 hours are rejected, and deleting attempts cannot grant access.

## Verification

- `flutter analyze --no-pub <changed paths>`; never build/run the app for validation.
- `flutter test --no-pub test/rewarded_premium_session_test.dart` and the
  existing premium/collection regression tests.
- From `supabase/tests`, install its pinned dev dependency and run
  `npm run test:rewarded`. This uses an isolated in-memory PostgreSQL instance
  and synthetic WebCrypto signatures, with no production connection.
- Gamebase: its auth/collection access Node tests; chat: TypeScript check and
  `test/rewarded-access.test.ts`.

On Android and iOS, the user checks:

1. Free account or guest: tap a locked feature, see Watch ad and Upgrade.
   Cancel the chooser; nothing unlocks. Close an ad early; nothing unlocks.
2. Complete a test impression with the configured verification path: after
   confirmation the original action runs once and the top timer starts.
   Check another premium feature, rankings, reports, collections, save/import
   limits, and signed-in chat. Required account ownership prompts still apply.
3. Background the app; return before expiry and verify elapsed time is deducted.
   Return after expiry and verify one popup with three choices.
4. Renew twice and verify each later expiry prompts again. Upgrade and verify
   the timer disappears. Go back and verify a free screen with saved data intact.
5. Kill and relaunch the app before expiry; verify another ad is required.
   Switch accounts and verify the prior reward is unavailable.
6. Test no inventory, network loss during confirmation, and delayed SSV.
   Retry confirmation must not show another ad. Check required privacy options.
