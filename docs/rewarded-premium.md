# Rewarded Premium access

## Ad diagnostics (36.2.1+3583)

Clarity's custom user ID is the Supabase account UUID for both guest and signed-in
accounts. Account changes start a fresh recording session; signed-out sessions
use `signed-out`. Clarity's generated User ID remains separate. Existing
recordings cannot be linked retroactively.

The `Rewarded Ad` Amplitude event records stage outcomes, timing, error codes,
and reward status. These events do not forward to AppsFlyer. Detailed failures
appear as `Rewarded ad failed: <stage>` warnings in Sentry, with `rewarded_stage`
and a `rewarded_ad` context containing the account UUID, flow ID, backend attempt
ID when available, recording URL when available, ad unit, and SDK error details
(domain, code, message, response ID and mediation response information). Session
capability tokens and request bodies are excluded. Clarity also receives custom
events named `rewarded_<stage>_<status>`.

Automatic consent refresh, SDK initialization, backend requests, and SSV option
setup time out after 30 seconds per step. Ad loading has a 45-second deadline
including the platform invocation. Late load callbacks cannot show an abandoned
ad. Human consent prompts and watching an ad have no deadline. Cached valid
consent remains usable when a refresh or form fails. Reward confirmation retries
keep their original attempt and do not require another ad.

Device check after release: as a guest, complete an ad and confirm Premium opens.
Find the recording using the custom account ID. Retry with network unavailable
and check the Sentry failure stage and SDK reason. Restore connectivity and retry.
For a delayed reward, Retry confirmation must not show another ad. Switch
accounts and verify the next recording uses the new account UUID.

Production Android/iOS only. ChessEver Test never requests ads or accepts
rewarded access. Rewarded access is enabled by default in production release builds. Debug and
profile builds require an explicit opt-in.

## Rewarded-interstitial fallback (36.2.1+3583)

When the primary rewarded ad fails to load or times out, the app offers one
rewarded-interstitial alternative. A brief intro explains the ten-minute reward
and offers Watch ad / Skip. Skip or dismissal never grants access. Known SDK
network errors, consent/setup failures, full-screen show failures, and early ad
closure do not trigger this fallback. Both formats still require Google's
signed SSV callback before granting Premium.

The fallback prepares a new backend attempt with the interstitial's own ad unit.
Its reward is confirmed using that new attempt. If SSV is delayed, Retry
confirmation keeps this attempt and never shows another ad. Failed fallback
loads have their own `interstitial_load` diagnostic stage and do not recurse.

Before release, configure both new AdMob units as **Rewarded interstitial**, with
"10 minutes of Premium" and the SSV URL below. Deploy both reward Edge Functions
with the shared four-unit allowlist. If production has `REWARDED_AD_UNIT_IDS`
set, update that override to include all four units before shipping the client.
No migration or change to the ten-minute reward policy is needed.

Device acceptance: force a no-fill failure for the primary rewarded placement
on a registered test device, accept the intro, finish the fallback ad, and
verify Premium opens. Repeat with Skip and early ad dismissal; neither should
grant access. Verify no intro appears after an ordinary successful rewarded ad,
and delayed fallback confirmation retries do not request another ad. The user
performs these live checks; agents must not run or drive the app.

## Configuration

The supplied production IDs are configured as defaults:

| Platform | App ID | Rewarded ad-unit ID | Rewarded-interstitial ad-unit ID |
| --- | --- | --- | --- |
| Android | `ca-app-pub-3681310687796023~4858872090` | `ca-app-pub-3681310687796023/8590975808` | `ca-app-pub-3681310687796023/2102597268` |
| iOS | `ca-app-pub-3681310687796023~5640461560` | `ca-app-pub-3681310687796023/8331032066` | `ca-app-pub-3681310687796023/1181317704` |

Production release builds enable rewarded access by default.
`REWARDED_PREMIUM_ENABLED=false` disables it at build time. Debug/profile
builds require `REWARDED_PREMIUM_ENABLED=true`. For end-to-end reward validation,
use a registered physical test device with:

```bash
flutter run --profile --dart-define-from-file=.env --dart-define=REWARDED_PREMIUM_ENABLED=true
```

Google sample units in debug builds cannot activate production rewards; the
production server accepts only the configured first-party rewarded units.
The `ADMOB_ANDROID_APP_ID`, `ADMOB_ANDROID_REWARDED_ID`,
`ADMOB_IOS_APP_ID`, `ADMOB_IOS_REWARDED_ID`,
`ADMOB_ANDROID_REWARDED_INTERSTITIAL_ID`, and
`ADMOB_IOS_REWARDED_INTERSTITIAL_ID` Dart defines can override these defaults.
An empty or malformed interstitial override disables fallback on that platform. Android's native SDK app ID reads the same override. If overriding
iOS, also create `ios/Flutter/AdMob-production.xcconfig` containing
`ADMOB_APP_ID = <the same ADMOB_IOS_APP_ID>`.
ChessEver Test retains sample native app IDs and cannot obtain rewarded access.
Debug uses Google's sample rewarded units. AdMob identifiers are public
configuration, not API secrets.

In AdMob, configure each rewarded unit with the reward description "10 minutes
of Premium", enable server-side verification, and point it to
`https://oelbsuggrzyqwzmvidju.supabase.co/functions/v1/rewarded-premium-ssv`.
AdMob console URL verification can leave User ID and Custom data blank. Signed
callbacks without a matching app attempt are acknowledged without granting access.
Set up the applicable privacy messages in AdMob Privacy & messaging. UMP runs
before requesting the first ad of each app launch; required ad privacy options
appear in About after consent information is loaded. The existing ATT prompt
runs before requesting iOS ads; denying tracking does not itself deny access.
AdMob chooses the duration and may supply an ad pod; the app never promises
30 seconds or chains ads itself.

Both Edge Functions share the four supplied production rewarded and
rewarded-interstitial unit IDs.
No CLI secret setup is needed for these public identifiers. An optional
`REWARDED_AD_UNIT_IDS` environment variable overrides the defaults with a
comma-separated allowlist. For the supplied production units, its value is:

```text
REWARDED_AD_UNIT_IDS=ca-app-pub-3681310687796023/8590975808,ca-app-pub-3681310687796023/8331032066,ca-app-pub-3681310687796023/2102597268,ca-app-pub-3681310687796023/1181317704
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
   confirmation the original action runs once. Access lasts ten minutes without
   an on-screen countdown.
   Check another premium feature, rankings, reports, collections, save/import
   limits, and signed-in chat. Required account ownership prompts still apply.
3. Background the app; return before expiry and verify elapsed time is deducted.
   Return after expiry and verify one popup with three choices.
4. Renew twice and verify each later expiry prompts again. Upgrade and verify
   rewarded expiry prompts stop. Go back and verify a free screen with saved data intact.
5. Kill and relaunch the app before expiry; verify another ad is required.
   Switch accounts and verify the prior reward is unavailable.
6. Test no inventory, network loss during confirmation, and delayed SSV.
   Retry confirmation must not show another ad. Check required privacy options.


## Premium-only reports

As of 35.35.7+3534, generating any report (including the first) and opening a
cached/completed report require paid or active rewarded access. Browsing the
Reports archive is free; opening one of its boards requires access. The existing Watch ad / Upgrade chooser runs before those actions,
including in debug. Interrupted work does not resume without access.

Migration `20261002170755_premium_only_game_reports.sql` removes the server's
free first-report and same-game daily allowances in production. Both paid and
verified rewarded claims remain supported. Existing reports and claim history
are retained. The shared server claim policy also applies to older clients.

Device check: with a fresh free account, tap Generate Report or a board inside
Reports; dismiss the chooser and verify no board opens or report generates. Repeat for a cached
report. Complete an ad and verify both generation and viewing work until expiry;
subscribers should open directly. Saved reports remain after access expires.

## Followed-player limit

Rewarded access keeps the free limit of three followed players, including players
added from Countrymen. Only a paid subscription raises this limit. At the cap,
adding another player opens the subscription paywall without a rewarded option.
Existing follows remain intact, and removing a player is always allowed.

Device check: with three follows and active rewarded access, try to add a fourth
from Countrymen and a player profile. Both must show the subscription paywall
and keep the count at three. Remove one and confirm a replacement can be added.

Discovery → Reports remains browsable without Premium. Report cards look
the same for every tier (no greyscale, no padlock); tapping a card shows Watch
ad or Upgrade before opening the board.

## Premium PGN imports

PGN clipboard and file imports require paid or active rewarded access, including
Board Editor → Paste PGN and files opened/shared from outside the app. The
existing Watch ad / Upgrade chooser appears before importing. Preview board
opening and saving recheck access after expiry; parsed games stay intact.
FEN paste and previously saved library content are unchanged.

Device check: as a free user, try clipboard imports, file selection, Board
Editor PGN paste, and opening a PGN from Files. Dismissing the chooser must
prevent the import; completing an ad or subscribing must resume it. Let access
expire on the preview, then tap a game or Save and verify another prompt.

## Premium chooser design

The chooser follows the supplied charcoal mockup: compact Watch ad and Upgrade
buttons, a play icon, close and Not now actions, and button-local loading states.
The expiry dialog keeps Watch ad again / Upgrade / Go back and cannot be dismissed
with close or platform Back. All dismissal and secondary actions are disabled
while an ad, confirmation, or upgrade is in progress. Text wraps and the dialog
scrolls on narrow screens or large accessibility text. The app typeface is retained.

## Subscription-only home customization

Rewarded access does not unlock Settings → Customization → Start section /
Home page, or holding a phone bottom tab / tablet rail item to set the start
screen. Those actions require a paid subscription and show Upgrade without a
Watch ad option. Previously saved defaults are preserved.

Device check: during rewarded access, try both customization rows and hold a
navigation tab. None may open its picker/confirmation without a subscription.
Paid users should still be able to change and persist their defaults.

## Subscription-only database allowances

Ad-unlocked access keeps the free limits of three owned databases and ten saved
game rows across all databases. This includes nested database creation and
saving/bulk-saving imported PGNs. At either cap, only subscribing raises the
limit; the paywall does not offer Watch ad. PGN import itself still supports
rewarded access. Existing databases and saved games are preserved.

Device check: during rewarded access, try creating a fourth database from
Library, My Space, a folder, and the save/import pickers; each must be blocked.
With ten saved games, a new single or bulk save must request a subscription.

## Feed scrolling

Free viewers can open Feed and view its first post. Swiping or tapping Next
shows the Watch ad / Upgrade chooser before revealing subsequent posts.
Dismissal returns to the first post; confirmed paid or rewarded access continues
to the next post and allows scrolling. Free visits start on the first post
rather than restoring a previously unlocked position. Expiry returns scrolling
to the first-post allowance.

Device check: swipe after the first post and dismiss the chooser; the second
post must stay hidden. Try again and complete an ad; verify the second post
appears and further swipes work. Also verify a subscriber never sees the gate.

## Smart Events and My Likes game access

Both lists stay browsable, but opening any of their games requires paid or
active rewarded access. This includes the latest twenty My Likes games, every
card layout, context-menu Open, and Smart Event games reached through a player
scorecard. My Likes cards show a lock whenever game access is unavailable.
The existing archive window, search, removal, and stored likes remain intact.

Device check: on a free account, tap a recent like and Smart Event games in
list/board/grid modes, including the scorecard route. Dismiss Watch ad / Upgrade
and verify no board opens. Complete an ad and verify the selected game opens;
paid subscribers should bypass the popup.
