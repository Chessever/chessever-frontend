# Watch controls

The Crown scrolls lists and reviews moves immediately when a game opens. On the board, a scroll wheel also reviews moves; finger drags scroll to the game details. Touch controls remain available throughout.

| Surface | Crown | Touch buttons |
| --- | --- | --- |
| Current events | Scroll events; overscroll the top to refresh | Event, My iPhone, followed filter, more events, Refresh |
| Event boards | Scroll one board at a time; top overscroll refreshes | Board tools, round/section chooser, standings, more boards, back |
| Round and section chooser | Scroll choices | Select a round/section; back |
| Standings and scorecard | Scroll players/games; top overscroll refreshes | Player, game, followed filter, back, Refresh |
| Game board | Forward/back through recorded moves, with detents | Overlaid previous/next arrows; hold for first/last recorded move; swipe sideways between games |
| Game details | Continues reviewing moves; finger-scroll to details | Player scorecards, flip, Open on iPhone, back, Refresh |
| My iPhone | Scroll account details; top overscroll requests sync | Sync with iPhone, back, Refresh |
| Empty/error views | Scroll when content exceeds the display | Back and a retry where an update can help |

Digital Crown presses and the side button retain watchOS system behavior. The simulator’s Action Button is unavailable for this app. No unsupported hardware-button interception was added.

## Move review behavior

- PGN loads on demand from the same production games table as mobile. Board feeds and 15-second polling do not download history.
- Reviewing an earlier move holds that move as relay updates arrive. At the last move, the board follows new recorded moves. Holding the next arrow returns to the last **recorded** move; it does not assert that the relay is current. Player clocks are reported relay clocks, not historical move clocks.
- A quarter Crown unit advances a ply; small rotations accumulate. Travel clamps at each end and reverses immediately. Haptic clicks are limited to one per 70 ms during fast turns.
- The Crown returns to scrolling when the game closes, another route covers it, the app becomes inactive or Always On dims the screen. It resumes move review when the game becomes active again.
- Previous/next overlay targets are at least 44 points in each dimension, centered vertically and separated even on the smallest board. The glyphs sit in the side gutters while their touch targets reach over the board edges. Disabled ends remain visible. VoiceOver increase/decrease actions also review moves. Missing or malformed history keeps the relay position visible, with ordinary Crown scrolling and Refresh below.
- Wheel travel over the board and player strips accumulates into moves, clamps at either end and reverses immediately. The same event cannot also scroll the page. Wheel travel elsewhere retains ordinary page scrolling.
- The board stays square. Both player strips, the board and its aligned 6-point engine bar fit within the normal first viewport, below the clock and clear of the rounded display corners. At large accessibility sizes, text and 44-point controls retain their size and finger scrolling reveals the rest. Full names remain available to VoiceOver and in the detail rows; flags yield space to names and clocks on narrow screens.
- Unknown evaluation uses a neutral track. A new position clears the old score immediately while its own cloud evaluation loads. Cached scores return immediately, and no local engine runs on the watch.

## Layout and evaluation update, 13 November 2026

The chosen layout reserves the system clock, player-line heights and bottom safe area before sizing a centered square board. Stretching the board would preserve more area at the cost of distorted squares; a separate button dock would consume the space needed by names. The requested overlay arrows keep navigation within reach without adding a dock.

The watch checkout's gutter-arrow layout is preserved. The finished change lives on production `stable` in the existing `chessever-frontend` worktree, following the project branch rules; the watch mirror checkout and its local draft are left untouched.

Automated coverage checks square geometry, safe margins, player order, engine alignment, centered gutter glyphs and nonoverlapping 44-point targets at 162×197, 176×215, 184×224, 198×242, 205×251 and 211×257. It also covers 200% text with long names and relay clocks, Crown/touch/wheel parity, end limits and reversal, stale-score clearing, and cloud-request completion. The evaluation source had returned its pending future from its own completion callback; it now removes that entry without returning it, so callers finish normally.

All **73 watch tests pass**, including result coloring, bundled phone audio, sound precedence, deterministic throttling, Crown/touch/wheel sound parity, live-follow behavior, quiet initial history, inactive playback and draw deduplication. The Crown now brings the board back into view when history first arrives after scrolling. No app was launched or attached for this validation.

Scoped `flutter analyze --no-pub --no-fatal-infos lib/watch lib/main_watch.dart packages/chessever_watch_bridge/lib test/watch` reports no errors or warnings. A concurrent session upgraded the shared SDK to Flutter 3.51 beta during validation; it now emits 13 informational deprecations for existing `package:flutter/cupertino.dart` imports. Local package metadata was regenerated for that SDK, and the repository's dependency lockfile was preserved. Migrating the app's UI packages is outside this watch change.

The full app suite completed with **7,734 passed, 11 skipped and 19 failed**. All 19 failures are outside the watch tests, in existing mobile menus, My Space, Likes, Gamebase previews, discovery/reports, search, hub captions, feed refresh and the legacy counter smoke test. The earlier audit also recorded 19 failures outside the watch suite; this change adds eight passing watch tests.

The complete design law was rechecked point by point against the existing grouped audit in [watch-companion.md](watch-companion.md#code-and-design-review). For this change:

- Type, palette, assets and signature: native system text, the established green-black palette, genuine pieces and actual game positions remain cohesive. The winner's `1` alone uses the phone's exact brand teal (`#0FB4E5`), as requested; names, losses, draws and clocks retain their normal tones. All font-default, gradient, fake-artifact, fake-logo and marketing-layout entries were checked; none were introduced.
- Spacing, clipping and alignment: text has safe-area plus 12-point side gutters; board/bar geometry shares a centered group; the bar and board share top and bottom edges. Player rows have vertical breathing room, and the lower strip clears the corner inset. The only clipping shapes contain board pixels and the evaluation track, not names or controls.
- Controls, centering and motion: bare chevrons are mathematically centered in the side gutters and at board mid-height, remain visible at rest, and respect Reduce Motion. They need no shadow on the OLED background. There are no tiles, glows, hover lifts, entrance-hidden controls or decorative animations. Large detail text wraps its figures instead of overflowing.
- Data and interaction: every action has an existing real handler. Wheel input uses Flutter's pointer-signal resolver; Crown state respects covered/inactive/Always On routes. Unknown scores are explicit, old scores are cleared and haptic clicks are emitted once per move.
- Page-template, hero/footer, form, pricing, quote, ornament, texture, glass and logo-wall rules: checked as inapplicable to this operational watch screen; none were added as decoration. The real populated chess position remains the visual anchor.

Live on-watch verification remains with the user, per the project rules. Check a game on the smallest supported watch: both names/clocks should clear the clock and screen corners; tap each arrow, hold each arrow, turn the Crown slowly and quickly in both directions, flip the board and check the engine direction, then increase text size and finger-scroll the details. A real-watch check is still needed for optical placement, physical Crown sensitivity and haptics.

### Phone sounds and teal results

The winner's `1` is teal in the board list and game player strips for either color. Move review uses the same seven `assets/sfx/piece_*.wav` files as the phone: move, capture, castling, promotion, check, checkmate and draw. Forward navigation uses the move's SAN with the phone's precedence; backward navigation uses the ordinary move clip. A followed live move sounds once; opening history, reviewing while a relay move arrives and repeated final results stay quiet.

The watch host plays the bundled bytes with `AVAudioPlayer` in an ambient session, following [Apple's foreground short-audio guidance](https://developer.apple.com/design/human-interface-guidelines/playing-audio). Routing and muting remain with watchOS. Fast navigation admits one clip per 90 ms and pauses the preceding clip. Covering the game, lowering the wrist or leaving the app stops playback; the native main-queue handler also checks `WKApplication` state before playing. There is no background-audio capability or replacement phone audio engine. Both device and simulator native sources pass SDK syntax checking with warnings treated as errors.

The new FFI symbols require a fresh watch binary; hot reload alone cannot install them. On a real watch, verify an ordinary move and capture with the arrows and Crown, then a check/castle/promotion where available. Check speaker/headphone routing and Silent Mode, and lower the wrist or leave the app during a clip to confirm it stops. Confirm a White win and a Black win each color only the winning `1` teal.

## Validation, 27 October 2026

**30 focused watch tests pass**, and scoped Flutter analysis is clean. The full mobile suite was rerun: its 22 failures match the previous audit exactly, all outside watch tests.

Focused tests cover legal mainline/FEN-start history, missing/illegal PGN, on-demand queries, dial limits and reversal, native input routing, touch parity, mode toggle, Done, covered routes, inactive/Always On transitions and retry. The shared flow exercises replay and account pull-to-sync at 162×197, 184×224 and 211×257 with the Mac’s SF Compact font.

The live audit uses public production games on the watch simulator. It sends a simulated Crown delta through the native FFI bridge and verifies a changed board, then tests touch advancement and return to scrolling. The simulator side button opened and closed watchOS Control Center, and pressing the Crown returned to the watch face. The normal app entrypoint was restored after the tour.

This verifies the input path; physical Crown sensitivity, haptics and VoiceOver still need a real-watch check before release. Phone handoff was not acknowledged in this pass; watchOS Control Center showed its phone-disconnected indicator. This pass therefore does not renew the prior audit’s successful handoff claim.

Design recheck follows the complete grouped review in [the release audit](watch-release-audit-2026-10-26.md): real populated chess remains the visual anchor; system type, neutral surfaces, existing piece artwork and bare control glyphs stay cohesive. No decorative imagery, gradients, shadows, entrance-hidden controls or new template layouts were introduced. Small-screen move labels, readable mode labels, button sizing, disabled end states and misleading chevrons were reviewed and fixed.
