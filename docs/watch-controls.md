# Watch controls

The Crown handles vertical browsing throughout ChessEver. Enter **Review moves** from a game to use it as a move dial. Touch controls remain available on every surface.

| Surface | Crown | Touch buttons |
| --- | --- | --- |
| Current events | Scroll events; overscroll the top to refresh | Event, My iPhone, followed filter, more events, Refresh |
| Event boards | Scroll one board at a time; top overscroll refreshes | Board tools, round/section chooser, standings, more boards, back |
| Round and section chooser | Scroll choices | Select a round/section; back |
| Standings and scorecard | Scroll players/games; top overscroll refreshes | Player, game, followed filter, back, Refresh |
| Game tools | Scroll board details; top overscroll refreshes | Review moves, flip, Open on iPhone, back, Refresh |
| Move review | Forward/back through recorded moves, with detents | Previous, next, last recorded move; tap board or Crown mode row to switch to scrolling; Done |
| My iPhone | Scroll account details; top overscroll requests sync | Sync with iPhone, back, Refresh |
| Empty/error views | Scroll when content exceeds the display | Back and a retry where an update can help |

Digital Crown presses and the side button retain watchOS system behavior. The simulator’s Action Button is unavailable for this app. No unsupported hardware-button interception was added.

## Move review behavior

- PGN loads on demand from the same production games table as mobile. Board feeds and 15-second polling do not download history.
- Review uses a fixed snapshot. Incoming relay updates cannot move the position being inspected. The last-move button means the last **recorded** move, not a live clock or a claim that the relay is current.
- A quarter Crown unit advances a ply; small rotations accumulate. Travel clamps at each end and reverses immediately. Haptic clicks are limited to one per 70 ms during fast turns.
- The Crown returns to scrolling when review closes, another route covers it, the app becomes inactive or Always On dims the screen. It resumes review on return only if review mode is still selected.
- Previous/next/last touch targets are at least 44 points. VoiceOver increase/decrease actions also step through the board. Missing or malformed history has an honest empty state and retry, with ordinary Crown scrolling.
- The replay board fits with its move label in the first viewport, including the smallest watch. Other controls retain full size below it. Navigation and action buttons have distinct affordances: only navigation has a forward chevron.

## Validation, 27 October 2026

**30 focused watch tests pass**, and scoped Flutter analysis is clean. The full mobile suite was rerun: its 22 failures match the previous audit exactly, all outside watch tests.

Focused tests cover legal mainline/FEN-start history, missing/illegal PGN, on-demand queries, dial limits and reversal, native input routing, touch parity, mode toggle, Done, covered routes, inactive/Always On transitions and retry. The shared flow exercises replay and account pull-to-sync at 162×197, 184×224 and 211×257 with the Mac’s SF Compact font.

The live audit uses public production games on the watch simulator. It sends a simulated Crown delta through the native FFI bridge and verifies a changed board, then tests touch advancement and return to scrolling. The simulator side button opened and closed watchOS Control Center, and pressing the Crown returned to the watch face. The normal app entrypoint was restored after the tour.

This verifies the input path; physical Crown sensitivity, haptics and VoiceOver still need a real-watch check before release. Phone handoff was not acknowledged in this pass; watchOS Control Center showed its phone-disconnected indicator. This pass therefore does not renew the prior audit’s successful handoff claim.

Design recheck follows the complete grouped review in [the release audit](watch-release-audit-2026-10-26.md): real populated chess remains the visual anchor; system type, neutral surfaces, existing piece artwork and bare control glyphs stay cohesive. No decorative imagery, gradients, shadows, entrance-hidden controls or new template layouts were introduced. Small-screen move labels, readable mode labels, button sizing, disabled end states and misleading chevrons were reviewed and fixed.
