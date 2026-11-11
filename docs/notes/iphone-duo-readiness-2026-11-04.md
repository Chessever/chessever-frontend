# iPhone Duo adaptation review

This work preserves the existing ChessEver UI. The changes concern available
space, safe areas, readable control sizes, scrolling, anchored overlays and
state retention. Existing typefaces, colors, artwork, labels and navigation
destinations remain the reference.

## Earlier work

PR #399 supplied useful resize propagation, Home subtree retention, analysis
panel storage and list/grid scroll retention. Those pieces were adapted onto
current `stable`. Its inferred hinge based on pixel density/window dimensions
and its release-workflow changes were not carried over. A window's dimensions
do not prove that a hinge exists.

## Shared behavior

- `AdaptiveWindowScope` keeps responsive values current below the Navigator
  without replacing route state. It accounts for horizontal safe insets and
  translates reported display features into content coordinates.
- Width determines compact/expanded navigation. Local constraints determine
  board workspaces and content grids. Existing typography and spacing scales
  are preserved; controls gain minimum tap areas and text-safe row heights.
- Reported vertical hinges inform board/pane separation. A reported horizontal
  obstruction gives the complete route a usable upper viewport. Without a
  posture signal the app uses the available window without inventing a fold.
- Open text fields, route stacks, dialogs, selected moves and panel choices
  survive resizing. List/grid swaps retain an approximate relative scroll
  position; this is not an exact visible-item anchor.
- Sheets account for the keyboard once. Anchored overlays use their receiving
  overlay's coordinate space.

## Surface coverage

| Area | Review and adaptation |
| --- | --- |
| Home, Today, Events, Search, Calendar | Preserve Home state; measure actual content width; match loading and loaded geometry; keep event titles/metadata inside cards. |
| Board, Explorer, position editor | Fit square board and analysis pane together; preserve move/panel state; constrain loading, picker, teaching and engine content. |
| Feed games, puzzles and skeletons | Keep a readable board in short landscape; scroll controls within the post and hand edge gestures back to native paging/refresh. News reader already scrolls. |
| Favorites, country/player games, Reports, Miniatures, Smart Events | Replace fixed landscape column counts with local width budgets. |
| Library, books, saved analyses, import and search | Fit folder/game grids; scroll book-preview loaded/missing/error bodies and create/rename dialogs. Existing import/recovery routes retained. |
| Prep | Fit Games grids; inspect scrolling profile/source/overview/opening/tree tabs and dialogs. |
| Auth and onboarding | Retain original visual treatments; add short-window/keyboard scroll fallbacks and controls that grow with text. |
| Premium, billing, subscription management | Inspect existing main paywall scrolling; make standalone billing/subscription sheets scroll and wrap action labels. |
| My Space | Inspect existing local grids, rails, edit state and provider retention; exercise real Add sheet with keyboard during resizing. Source-removal semantics retained. |
| Collections, Likes/My Likes, rankings, standings/team scorecards, bracket, Streaks | Inspect existing lazy/scrolling content, width constraints and persistent state. Existing route/access contracts retained. |
| Settings, My Profile, Inbox | Inspect constrained scrolling, expandable state and loading/empty/error branches. |
| Deep links, notifications and Back | Retain existing parsers/executors and access gates; exercise route/dialog/text-state retention through resizing and existing routing suites. |

This is source review plus automated Flutter unit/widget coverage. It is not a
claim that every live data state or native-service interaction has been seen
on the simulator. Native sign-in, purchases, keyboard/posture reporting, video
and final on-screen quality require the user's device pass.

## Device pass

Hot restart the existing Flutter session (`R`) on the Duo simulator so startup
clears any earlier orientation lock. Repeat the following on
all four configurations below, in both landscape directions, and after
refolding. Test each configuration immediately after a fresh start too.
Repeat key controls with larger accessibility text and in both themes. From
each of the four configurations, switch directly to each of the other three
with the current route or draft open: that is the 12-transition device pass.

1. From Home, scroll Today and Events; search; open a Calendar event. Fold with
   the drawer, a detail route or a dialog open, then use Back.
2. Open a game, select an earlier move, switch to Explorer, rotate and fold.
   Keep the move/line/panel selection. Open the game picker, live-stream
   coachmark, Like tag menu and share/report entry points.
3. Watch Feed. In short landscape, scroll the current game's controls, continue
   past its edge to the next/previous post, reverse a partial drag, and pull to
   refresh on the first post. Repeat on a puzzle and News article.
4. Open My Space Add, type in Search, fold with the keyboard visible, and use
   Done. Create/rename a Library folder, inspect a book preview and open Prep
   Games. Keep edits, selected filters and navigation context.
5. Inspect settings sections, Profile, Inbox, rankings, standings, bracket,
   collections, Likes, Reports, Miniatures and Streaks. Check empty/error/retry
   states when available and verify all controls remain reachable.
6. On a signed-out session, inspect onboarding, country/player selection and
   sign-in. Open Premium, billing and subscription management; reach dismissal
   controls with the keyboard and larger text.
7. Open a notification/deep link to a player, event, News article and a Premium
   destination. Fold before going Back; cancel a Premium prompt and confirm
   the existing destination/access behavior.

## Design review

The final diff is reviewed against the supplied design law with the user's
explicit preservation direction taking precedence. Checks cover visible
content defaults, clipped edges, gutters, parallel-column alignment, centered
controls, text contrast, touch areas, real controls, motion/reduced motion,
and consistency with existing assets and visual treatments. Existing branding
is not replaced as part of this device adaptation.

## Initial validation result (37.8.10)

- Canonical `flutter analyze --no-pub` on all 72 changed Dart files: no issues.
- Final full Flutter suite: **6,318 passed, 4 skipped, 17 failed**.
- All 17 failures were reproduced with the same test identities against an
  isolated source archive of committed `stable` at `c427395d`, before these
  changes. That comparison ran the 18 existing test files implicated by the
  initial full-suite report. The final failure set adds nothing to baseline.
- The baseline failures concern existing menu/source expectations, scorecard
  timers, Game Report access fixtures, captions, Likes routing, a skeleton
  height assertion and the old counter smoke test. They were not rewritten
  to make this device-adaptation change appear green.
- Focused regressions cover resize/state retention, actual My Space keyboard
  handling, enlarged event metadata, Feed edge-gesture handoff, asymmetric
  overlay insets, draft retention, and existing routing/access behavior.
- Formatting and `git diff --check` pass. No app build, launch, simulator
  automation, backend operation or release was performed for verification.

## Orientation correction and complete size matrix (37.8.12)

The user's sideways onboarding capture exposed an orientation-policy problem.
Version 37.8.11 used full display metrics rather than the constrained viewport,
but still imposed portrait on compact displays. That was incomplete: it excluded
folded landscape, including a cold start in that state. This correction
supersedes that policy and its earlier device-pass advice.

`WindowOrientationScope` now clears the app's orientation restriction once at
startup, including after hot restart. Orientation follows the OS and the native
supported-orientation list, which already permits portrait and both landscape
directions. Compact screens, including ordinary phones, may rotate too; there
is no device-model or pixel-density heuristic that could lock a folded Duo.
Layout continues to use actual available space. This follows Flutter's
[orientation guidance](https://api.flutter.dev/flutter/services/SystemChrome/setPreferredOrientations.html).

The shared test fixture comes from the installed iPhone Duo simulator profile:
`iPhone Duo.simdevicetype/Contents/Resources/capabilities.plist`. The outer
display is 1398×2034 pixels and the inner display is 2007×2853, both at 3×.
These sizes are test inputs only, never production device identification.

| Configuration | Logical size |
| --- | --- |
| Folded portrait | 466×678 |
| Folded landscape | 678×466 |
| Unfolded portrait | 669×951 |
| Unfolded landscape | 951×669 |

All four configurations are covered as initial sizes. The shared transition
iterator produces all 12 directed pairs of different configurations, including
combined fold-and-rotate changes. Root tests also cover delayed display/viewport
updates, letterboxing, mirrored landscape side insets, keyboard occlusion,
retained edits, an open dialog and the Navigator Back stack. Native orientation
configuration has a separate assertion for both landscape directions.
Content and workspace fixtures also apply conservative stress insets to both
`padding` and `viewPadding`: 59/34 points at the portrait top/bottom, and
62/20 points at the landscape sides plus 21 at the bottom, with the sides
mirrored at the destination. These inset values are test bounds, not a claim
about what a particular native posture reports. Feed additionally reserves
110 points to stress the remaining local width without double-counting
system insets.

The stricter matrix found layout defects in addition to the orientation lock:

- The folded portrait board consumed height needed by its player rows, PVs and
  notation. Its existing square board now has an available-height limit.
- Standalone Explorer similarly caps its stacked board to leave space for
  engine content and the lower panels.
- Feed's short-window scroll fallback required a wide local aspect ratio.
  Navigation-rail and safe-area space could prevent it from activating in
  folded landscape. It now uses available height, retaining the existing
  content-first scrolling and gesture handoff at post edges.
- Feed exploration controls could overflow their height-limited board column.
  When that column is too narrow, the same controls use the existing wider
  row space rather than shrinking labels or hiding actions.

Board, Explorer and editor tests include asymmetric side insets in both
landscape directions; folded landscape then exercises the compact branch
below 600 points as well. Main-board transitions run with both pending and
five populated PV results in each existing engine-line presentation.

Additional matrix fixtures exercise actual Events/Search loading, loaded,
empty and error surfaces; Calendar state and query retention; Feed game,
puzzle, News and placeholder states; event cards with larger text;
Miniatures filters; Collections tabs; all five onboarding pages; auth and
country selection; My Space Add; Library previews and rename; settings;
signed-in/guest profile; Inbox states/detail; Prep forms; and subscription
sheets. Tests retain relevant queries, selections, providers, drafts, scroll
or route state through resizing. This does not simulate every native auth,
purchase, notification, video or live-data service. Existing routing/access
suites remain part of the full validation gate.

The source changes only affect orientation, size budgets and the short-window
scroll fallback. Existing components, typography scales, colors, assets,
labels and destinations are preserved. The supplied design law was rechecked
point by point against that preservation scope: no new decorative styling,
fonts, icons, shadows, effects, copy or interactions were introduced. The
checks concentrate on visible content, clipping, gutters, alignment, centered
controls and working existing actions. Final native visual and posture
verification remains the user's device pass, per project instructions.

## Matrix correction validation

- Focused root/orientation/board/Explorer/editor coverage: **122 passed**.
- Focused content and gesture coverage with the shared stress insets:
  **383 passed**.
- Focused workspace matrix coverage with the same stress insets:
  **45 passed**.
- Canonical `flutter analyze --no-pub` on all 27 changed/new Dart files:
  **no issues**.
- Final full Flutter suite: **6,676 passed, 4 skipped, 17 failed**.
- The final 17 failing test identities exactly match the confirmed baseline
  from `c427395d`; there are no additional failures or missing baseline cases.
- `dart format` and `git diff --check` pass. Native app execution, simulator
  control, builds, backend operations and release actions were not performed.
- The correction is local on `stable`, version **37.8.12+3796**. Use a hot
  restart before the four-state/12-transition device pass above.

## Re-check after user feedback (38.2.1, 2026-11-11)

A user on 37.9.4 asked for iPhone Duo support. 37.9.4 already contains
37.8.12, so the Duo work was released before that report; it was not waiting
on a merge. PR #399 remains open only as the superseded source of that work.

- The full Duo matrix and adaptive suites still pass on 38.2.0 (644 tests).
- The paywall was rewritten after 37.8.12 (`PremiumPaywallView`) and had no
  Duo coverage. Its pinned checkout could not shrink: folded landscape with
  1.3× text and an error line overflowed by 80 px, hiding Get Premium and the
  legal links. The checkout now stays pinned but is capped at 70% of the
  screen height and scrolls within itself. `test/duo_paywall_matrix_test.dart`
  covers all four Duo states × two text scales × with/without errors.
- Simulator pass: the Duo simulator exists locally (iOS 27.2), but the device
  tooling did not expose it, so on-screen verification remains the user's
  device pass above.
