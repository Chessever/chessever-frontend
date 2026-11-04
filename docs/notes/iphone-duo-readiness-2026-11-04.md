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

Keep the existing app running on the Duo simulator. Repeat the following on
the outer display, unfolded display in both orientations, and after refolding.
Repeat key controls with larger accessibility text and in both themes.

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

## Validation result

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
