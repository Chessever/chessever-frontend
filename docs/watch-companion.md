# ChessEver Apple Watch companion

This adds a compact companion to the production iPhone app. It uses
[flutter-watchos](https://flutterwatch.dev/), pinned to
`ad4dffc3550ffb8b44004c08fab406a695ce8fbc`, and the toolchain's
[`flutter_watch_link`](https://github.com/flutterwatch/plugins/tree/main/packages/flutter_watch_link)
WatchConnectivity implementation.

## What is on the watch

- Current events from `group_broadcasts_current`, in the phone feed's Elo order.
  Followed events move to the front, and the list has explicit pagination.
- Event sections, rounds, paginated pairings, and complete player scorecards.
- Published scores, ranks, performance, and rating changes. Published ranks win
  over inferred sorting; equal scores retain the source ordering.
- A full chessboard in the first game viewport, actual Cburnett piece assets,
  last-move highlighting, board flipping, and reported relay clocks.
- Followed-event and followed-player filters, account status, and the phone's
  event/player/reminder alert preferences.
- An acknowledged game handoff to iPhone, native Crown scrolling, selection
  haptics, Cupertino route transitions, VoiceOver semantics, and Dynamic Type.
- A static privacy face for Always On. Polling and tickers pause while inactive
  or dimmed; raising the wrist preserves the existing navigation stack.

The watch's clocks are **reported relay values**, not interpolated countdowns.
The game screen states when it fetched them. A visible live game refreshes every
15 seconds; the root event list refreshes every 45 seconds. Other data screens
have working Refresh actions. Failures retain already-loaded data with an error.
Missing configuration or empty data never produces sample games.

## Phone account and alerts

The phone remains the authentication and notification owner. On startup,
resume, favorite changes, preference changes, auth changes, and watch sync
requests, it publishes a revisioned snapshot. Application context repairs a
cold/disconnected watch; reachable devices also get an immediate message.
Offline watch sync requests use a bounded background queue. The receiver rejects
duplicates and older revisions. Sign-out/account switching clears the previous
display without waiting for an in-flight network request.

The snapshot contains the account ID, display name, favorite identities, three
alert preferences, and the **public** production API key. It never contains an
access token, refresh token, email, service-role key, or secret key. Private
database reads remain on the authenticated phone. The watch reads only the
public production feed and stores its last display snapshot in local settings.
Disconnected devices catch up when WatchConnectivity next delivers context.

Notifications use Apple's existing companion forwarding, preserving the phone
account's subscriptions and OS settings. There is no second push registration
or duplicate watch alert scheduler. The native FFI bridge observes the
FlutterWatch host's notification delegate, including cold-launch replay; it
does not replace that delegate. Taps recognize FCM, OneSignal, and ChessEver
game/event URLs. They validate the event against Current before opening it;
historical/unrelated alerts point the user back to iPhone.

Apple controls where and when a forwarded alert appears. Enable ChessEver in
the iPhone Watch app under Notifications, with **Mirror my iPhone**. See
[Apple's forwarding guidance](https://developer.apple.com/documentation/watchos-apps/taking-advantage-of-notification-forwarding).

## Device setup and distribution

Use the production iPhone and watch halves from this worktree together:

| Setting | Value |
| --- | --- |
| iPhone bundle | `com.chessever.app` |
| Watch bundle | `com.chessever.app.watchkitapp` |
| Apple team | `N8J7TUZMYR` |
| Deployment | watchOS 26.0+ |
| Supported hardware | Series 9+, Ultra 2+, SE 3+ |
| Companion mode | `WKCompanionAppBundleIdentifier`, no `WKWatchOnly` |
| Watch entrypoint | `lib/main_watch.dart` |

The default `lib/main.dart` also detects watchOS before phone startup, but use
the separate entrypoint for the smaller watch Dart snapshot. It excludes phone
analytics, purchases, ads, database initialization, and Stockfish. The toolchain
skips native-assets hooks and plugins without a watch implementation.

The checked-out toolchain is at `../flutter-watchos`. Simulator engines need no
account; **physical-device/profile/release engines require `flutter-watchos
login`** and then `flutter-watchos precache`. This machine was not signed in
when implementation began. See the official
[setup](https://github.com/flutterwatch/flutter-watchos/blob/main/doc/get-started.md)
and [account](https://github.com/flutterwatch/flutter-watchos/blob/main/doc/accounts.md)
guides.

For user-run simulator validation, pair an iPhone and watch Simulator, install
and launch the production phone app first, then use:

```sh
../flutter-watchos/bin/flutter-watchos run --target lib/main_watch.dart -d <watch-id>
```

The public API key can arrive from the phone snapshot. Alternatively supply
`--dart-define=SUPABASE_ANON_KEY=...`; use only the production publishable/anon
key. The watch's URL is fixed to `https://oelbsuggrzyqwzmvidju.supabase.co`.
For a physical watch, use `--profile` and a signed-in toolchain.

Releases go through GitHub Actions: run **Mobile release** on `stable` with
`watch` on. The iOS job builds this watch app with flutter-watchos, signs it
with an App Store profile for `com.chessever.app.watchkitapp`, embeds it in
the IPA and checks it there. `docs/ci/github-actions-release.md` has the
steps and the one secret this needs, `FLUTTERWATCH_TOKEN` (from
`flutter-watchos login`). With `watch` off the IPA ships iPhone-only.

The embed phase (`scripts/embed_watch_companion.sh`) checks the bundle IDs and
version/build and rejects a missing or stale release watch. CI sets
`CHESSEVER_WATCH=require` or `skip`; unset, a Release or archive build requires
the watch and a local debug phone build continues without it, with a warning.
Simulator phone builds select the simulator watch artifact, including
`Debug-production`. The retired test flavor skips production watch embedding.
Archive and distribute the real **iPhone** app; the generated watch-only
HostApp container is unused in this companion project.

To archive by hand instead, build the watch first, with the same version as
the iPhone:

```sh
../flutter-watchos/bin/flutter-watchos build watchos --release --target lib/main_watch.dart
```

flutter-watchos rewrites `watchos/Runner/Info.plist` to its companion keys on
every build (`WKRunsIndependentlyOfCompanionApp` is always `true`); the file in
the repository already matches, so a build leaves it unchanged.

The **Watch companion check** workflow compiles the watch app for the Simulator
and embeds it in a Simulator iPhone build whenever the watch code changes. It
needs no account or secret.

## Checks for the user on a paired device

1. Open production ChessEver on iPhone and sign in. Open the watch app, then
   My iPhone. Confirm the account name, favorites, and alert preferences arrive.
2. Browse Current, a section, a round, and a game. The full board should fit
   below the system clock. Use the Crown to reach clocks and actions; flip the
   board and open each player's card. Check results against the phone.
3. Add/remove an event and a player on iPhone, then change an alert preference.
   Confirm the watch's filters/stars/preferences update. Sign out and sign into
   another account; the prior account's favorites must disappear.
4. Open on iPhone from a watch game. Confirm the phone opens that actual game.
   With the phone unavailable, confirm the watch asks you to open it first.
5. Lock iPhone and wear/unlock the watch. Use an existing subscribed event or
   player notification. Confirm one forwarded alert appears and its tap opens
   the current event/game. Repeat with the watch app closed, then with it open.
   Apple's lock state, Focus, and mirroring settings affect delivery.
6. Lower the wrist. Confirm the privacy face hides account information; raise
   it and confirm the same game/route returns. Test VoiceOver and larger text.
7. Disconnect/reconnect the phone and briefly disable networking. Confirm sync
   catches up, requests do not accumulate, and feed failures show a clear state.

## Code and design review

Validation uses analysis and unit/widget tests, not a running app. The widget
tests click navigation, sync, filters, refresh, board flip, handoff, and back
controls at 162×197, 184×224, and 211×257 points, plus doubled text size. The
board is checked to fit wholly beneath the clock. Optional offscreen review
renders are in `build/watch-review/`; their data is explicitly test-fixture
data. macOS SF Compact is loaded only for those local test renders and is not
redistributed as an asset.

The focused suite passes **16 tests** and changed-file analysis is clean.
The final full mobile suite reports **5,004 passed, 4 skipped, and 49 failed**.
All 49 failing test names also failed on the unchanged starting commit
`29c5b95c` (4,988 passed, 4 skipped, 49 failed). Those unrelated failures were
preserved.

Code/widget HIG review: **9/10**. Paired-device VoiceOver, Crown/haptic,
Always-On, and notification verification is the remaining step for 10/10.

```sh
flutter analyze --no-pub lib/watch lib/main_watch.dart lib/services/watch_companion_service.dart lib/main.dart lib/providers/favorite_events_provider.dart lib/providers/favorite_players_provider.dart lib/providers/notification_preferences_provider.dart packages/chessever_watch_bridge/lib test/watch
flutter test test/watch
```

The native notification source passed watch Simulator SDK syntax checking;
plists and both project files passed `plutil`; the embed script passed seven
filesystem smoke cases. Read-only production requests verified every event,
section, round, game, and JSON containment scorecard projection. There were no
backend mutations. Device delivery, native Crown/haptics, native linking, and
App Store packaging still require the paired-device checks above.

The supplied design law was reviewed in full, with its website defaults scoped
to this native watch brief. The intentional identity is a real chess position
on a wrist, using genuine ChessEver and Cburnett assets. OLED black, SF system
type, tonal full-row targets, and Cupertino navigation serve the platform.

| Law points checked | Result |
| --- | --- |
| Lucide defaults; oversized icons; logos/icons in tiles; fake or missing marks; custom-looking generic outline sets; gradient logo lockups | Genuine ChessEver icons and chess assets; bare, functional Cupertino glyphs; no invented marks or decorative icon row. |
| Em dashes; excessive/filler copy; decorative quote marks; fake testimonials and metrics | Brief functional copy; real feed values; no testimonials, quote decoration, or marketing claims. |
| Fraunces/Work Sans; Space Grotesk; Cormorant; Didones; Sora; JetBrains Mono; Syne; Archivo; Inter identity; the full Google rotation; safe designer font swaps; reused house pairings | Explicit system Cupertino text/display families for native watchOS. No web display font, Google import, mono house voice, or unrelated font pairing. |
| Hero eyebrow pills; gradient/icon pills; category/tag chips everywhere; inner glow badges; pulsing live dots | Plain status/metadata text. No pills, glow badges, or pulsing indicators. |
| Glowing pill buttons; primary/ghost pairs; default CTA pairs; jumping buttons; underline fills; botched fills; card hover lift | Functional full-row targets and tonal pressed states. No paired CTAs, hover movement, animated underlines, or decorative fill animation. |
| Floating cards/tags; accent-bar cards; kitchen-sink cards; pricing tiers; quote cards; gradient initials; pre-footer CTA slabs | None present. Data rows have one clear purpose and no decorative card machinery. |
| Faux macOS windows; fake code panels; crude CSS/SVG illustrations; empty product artifacts | The board uses actual positions and established chess-piece artwork. No mock dashboard, fake code, or placeholder illustration. |
| Purple/blue gradients; background glow; clipped glow; radial object halos; candy washes/auroras; cool blue-charcoal defaults; cream/beige and UI-kit gray defaults; saturated accents | Chosen OLED black, neutral tonal rows, readable white/gray type, and restrained chessboard green. No gradients, glows, or unrelated swatches. |
| Hairline light borders; accent rules; eyebrow ticks; graph-paper sheets; decorative rails; unrounded hairlines | No decorative lines, full-page grids, or contrasting card outlines. Tone and spacing establish structure. |
| Blanket shadows; fake offset-box shadows; boxy/hard-edged shadows; blurred copies of elements | No shadow effects or duplicate panels. |
| Botched glass; blur banding/leak/pop; resting halos; grain over content; undithered gradients | No glass, blur, grain, or gradient effects. Text and controls stay crisp. |
| Hidden entrance content; fixed backgrounds pretending to move; gratuitous floating motion; dead-looking controls | Content is visible immediately. Motion is Crown scrolling and native route/press feedback; Always On deliberately masks private content without destroying state. |
| Cut edges and overlaps; text at edges; off-center glyphs; cramped display numbers; off-center strike lines | Clock/corner gutters; board-only rounded clipping; full-height squares while images load; centered genuine pieces; spaced score separators; no strike/cut effects. |
| Ragged comparison columns; content scattered to far edges; unbalanced footer columns; default giant/footer wordmarks | Single-column watch hierarchy with consistent gutters. No comparison grid, footer, oversized wordmark, or edge-flung clusters. |
| Active-nav dots; sun/moon theme pills; fake countdowns | Native navigation, watchOS dark appearance, explicit live/result text, and reported relay clocks. No decorative nav mark or urgency timer. |
| Split heroes; default hero stacks; right-hand panels; dangling accented headlines; small-label/large-H2 section heads; serif statement blocks | No landing-page sections. Current opens with actual events; a game opens with its actual board; a scorecard opens with real scores. |
| Inset enquiry islands; pill email forms; image-caption card presets; numbered steps on rails; SaaS meta-skeletons; repeated/recolored house layouts; stacking preset sections | None present. Each watch route follows its data/navigation purpose. |
| Hard image/color seams; lifeless post-hero flat bands; clipping the next section at the fold | No hero/photo bands. The game board wholly owns its first usable viewport; subsequent details scroll normally. |
| Unreadable text/filled-button labels; duplicated tiny label treatment | Primary/secondary text clears tonal rows at 15.80:1 / 8.59:1. Different weights/sizes identify headings, data, and notes; no tracked-caps costume. |
| Dead tabs/toggles/buttons; no-icons overcorrection; avoiding the checklist without a signature | Pointer-tested controls; necessary native glyphs; the real, populated chessboard is the signature. No decorative controls. |
| Premium craft: real artifact, atmosphere, layered structure, bespoke silhouette, cohesive type/nav, specificity, honest marks and deliberate motion | Applied as a watch interface: actual chess, restrained board corner geometry, genuine branding, platform navigation and Crown motion. Glass, licensed display fonts, logo walls, canvas backgrounds, hero overlap, and giant footer treatments would add overhead without serving this native brief. |

Review corrections included the signing team and embed selection, immediate
account clearing, updated scorecard statistics on Refresh, canonical favorite
aliases, server-side scorecard filtering and chronological round order, actual
SF family selection, full board-square geometry while images decode, and the
first-viewport board composition. Live visual verification remains with the user.
