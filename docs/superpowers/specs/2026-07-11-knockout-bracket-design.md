# Knockout tournament bracket — design specification

**Date:** 2026-07-11  
**Status:** approved for implementation (the user delegated design decisions and requested uninterrupted implementation)  
**Scope:** individual knockout tournaments in the existing tournament-detail screen

## Problem

Knockout events currently use the same three tabs and cumulative standings as Swiss and round-robin events. That produces misleading results: eliminated players can remain prominent, a champion can appear as `2.5 / 4`, and men’s and women’s stages can be mixed when they are sibling tours in one broadcast group. The Games tab also treats legs such as `Round 3.1` and `Round 3.2` as separate rounds instead of one match round.

The repository already handles the 2025 FIDE World Cup reasonably well because each elimination stage is a sibling tour and games are grouped by player pairing. That structure should become the canonical model for every individual knockout feed.

## Goals

1. Individual knockout tournament tabs are:
   `About · Games · Bracket · Standings`.
2. The four-tab strip behaves like the team-event strip: it scrolls, automatically centers the selected tab, and displays at most three tab slots at once.
3. `Standings` remains available and unchanged; `Bracket` provides the meaningful elimination view.
4. Multi-leg matches are grouped under one logical stage. In particular, `Round X.1`, `Round X.2`, and that round’s tiebreaks become `Round X`.
5. Multi-tour events reuse the FIDE World Cup pattern: sibling stage tours become ordered bracket stages.
6. Men’s, women’s, open, and other parallel categories never leak into one another.
7. The bracket is designed exclusively for a portrait phone viewport. It supports one-finger pan, pinch zoom, explicit zoom controls, and a fit/reset action. It never asks the user to rotate the phone.
8. Partial or ambiguous feeds are rendered honestly. The app must not invent seeds, future players, winners, or connector edges.

## Chosen approach

Build a real bracket graph from normalized stages and matchups, then render it on a zoomable two-dimensional canvas.

Two alternatives were rejected:

- A vertically stacked list of rounds would be easy to read but would not communicate advancement or solve the requested FIFA-style bracket.
- A hard-coded bracket based on player count would look orderly but would fabricate byes and topology that the Lichess/Supabase payload does not provide.

The chosen graph is more work, but it represents only evidence present in sibling tours, round metadata, games, and later-stage participants. It therefore works across World Cups and national championships without event-specific IDs.

## Tournament-detail navigation

Add `bracket` to `TournamentDetailScreenMode`, but stop converting page indexes through `TournamentDetailScreenMode.values`. Each layout owns an explicit visible-mode list:

- regular individual: `[about, games, standings]`
- individual knockout: `[about, games, bracket, standings]`
- team: `[about, games, standings, players]`

All initialization, tab taps, page swipes, selected labels, and search visibility map through that active list. This removes the current prefix-only enum assumption.

Knockout layout detection is cached per selected tour once true, like team detection, so a temporary provider loading emission cannot change the page count from four to three and destroy child state. Selecting a genuinely different category recalculates the layout for that tour.

`SegmentedSwitcher.isScrollable` becomes `visibleModes.length > 3`, preserving the existing exact-three-slots geometry and auto-centering behavior.

The event search field is hidden on `About` and `Bracket`. It remains visible only on `Games`, `Standings`, and `Players`. The Bracket canvas owns horizontal gestures, so PageView swiping is disabled while Bracket is selected; the always-visible tab strip remains the way to leave that tab. Other pages keep their current swipe behavior.

## Normalized bracket domain

Introduce focused immutable models:

- `KnockoutBracket`: ordered stages, inferred connector edges, selected/current stage, and whether the graph is partial.
- `KnockoutStage`: stable key, label, source tour IDs/round IDs, chronological order, completion state, and matches.
- `KnockoutMatch`: stable stage-scoped key, two participants, ordered games, aggregate score, leader/winner state, minimum board order, and source identifiers.
- `BracketParticipant`: stable identity, display name, optional FIDE ID, federation, title, and rating.
- `KnockoutEdge`: source match and destination match plus the participant whose later appearance proves the connection.

Participant identity prefers FIDE ID. It falls back to a normalized title-free player name. A matchup key is unordered and always scoped to a stage, preventing a later rematch from being merged with an earlier match.

## Stage reconstruction

### Multi-tour events

All sibling tours under the current `group_broadcast_id` are examined, but only the current category lane is retained.

A stage descriptor separates a tour name into:

- event root;
- category lane, such as `Men`, `Women`, or `Open`;
- stage, such as `Round 1`, `Round of 16`, `Quarterfinals`, `Semifinals`, or `Finals`.

Examples:

- `FIDE World Cup 2025 | Round 3` → lane empty, stage `Round 3`
- `Azerbaijan Chess Championship 2026 | Men Quarterfinals` → lane `men`, stage `Quarterfinals`
- `French Chess Championship 2025 | Women | Finals` → lane `women`, stage `Finals`

Only individual knockout sibling tours in the same resolved lane are used. Stage order prefers explicit elimination semantics, then round number, then start date. Every leg and tiebreak inside a stage tour belongs to that stage.

### Single-tour events

Round **names** are authoritative when available; compact slugs are supporting evidence. Supported shapes include:

- `Round 3.1`, `Round 3.2`, `Round 3 | Tiebreaks` → `Round 3`
- `Quarterfinals | Game 1`, `Quarterfinals | Game 2`, `Quarterfinals | Tiebreaks` → `Quarterfinals`
- `quarter-finals--game-1` and similar stage-bearing slugs
- a tour whose own name is a stage and whose child rounds are only `Game 1`, `Game 2`, and tiebreaks

Generic PGN `[Round "3.1"]` tags are not parsed: their semantics differ between feeds. Grouping uses stored Lichess round records and repeated stage-scoped participant pairs.

If no trustworthy stage boundary can be resolved, all games remain in one clearly labeled stage rather than being split into fake stages.

## Scores, winners, and edges

Match scores are summed from decided games (`1-0`, `0-1`, and draw encodings). Unfinished games do not add points.

The model distinguishes a current leader from a proven winner:

- Appearance in the next stage is the strongest advancement proof.
- A terminal or completed stage may declare a winner only when all published games are decided and the aggregate is not tied.
- A tied match with no published tiebreak remains undecided.

Edges are inferred only when a participant in a later stage also appears in a match in the nearest earlier stage. This supports main brackets, third-place/placement branches, and byes without pretending the source exposes explicit `next_match_id` data. A bye or missing earlier feed simply produces a later card without an incoming edge.

## Portrait bracket experience

The Bracket page keeps the normal tournament app bar, category dropdown, and four-tab strip. The remaining height is a dedicated canvas.

### Canvas

- Stages are vertical columns from earliest on the left to latest on the right.
- A stage header stays attached to its column.
- Compact match cards use the existing dark popup surface, hairline borders, rounded corners, typography, federation flags, and restrained semantic colors.
- Each card has two player rows and right-aligned aggregate scores. A proven winner is high-emphasis; an eliminated player is muted. Live/unfinished matches receive the existing live accent and dot treatment.
- Connector lines use muted theme borders and brighten subtly for the path belonging to a focused match.
- Matches are ordered by board number and feed order. Later columns use proportional vertical spacing so normal power-of-two brackets align naturally; evidence-backed connector lines remain correct when byes or placement matches make the geometry irregular.

### Camera and controls

- `InteractiveViewer` provides one-finger pan and pinch zoom.
- The initial camera uses a readable scale and focuses the live stage, otherwise the latest incomplete stage, otherwise the final. It does not shrink a large bracket into illegible text.
- A compact floating control cluster provides zoom out, fit overview/reset, and zoom in. Buttons use the app’s existing floating-control visual language and haptics.
- Fit overview may make text tiny; it is an orientation aid. One tap on reset/current-stage returns to a readable camera.
- A small in-canvas hint, `Drag to move · Pinch to zoom`, appears on the first visit and fades after interaction. No landscape or rotation message appears.
- The `TransformationController` is owned by the keep-alive Bracket screen so pan/zoom state survives tab changes and live data refreshes.

### Match interaction

Tapping a card opens a themed bottom sheet without losing the camera position. It shows the aggregate result and ordered legs (`Game 1`, `Game 2`, rapid/blitz tiebreaks) with per-game results. Tapping a game uses the existing chessboard navigation path. Missing or unpublished games are not synthesized.

## Data flow

`knockoutBracketProvider` watches the selected tour metadata and:

1. determines whether it is an individual knockout;
2. resolves the selected category lane and relevant sibling stage tours;
3. fetches all relevant rounds and games using existing repositories;
4. normalizes stages and matchups in pure functions;
5. derives scores, proven winners, and evidence-backed edges;
6. emits one immutable `KnockoutBracket` consumed by the screen.

The pure builder has no Riverpod, Supabase, or widget dependency. Provider orchestration, graph construction, graph layout, and rendering remain separate modules.

Live data follows the existing tournament providers. The Bracket provider refreshes when relevant game membership/status changes but does not start per-game board streams; detailed live boards remain the responsibility of the Games tab.

## Loading, partial, empty, and error states

- Loading: themed skeleton columns and cards, without briefly showing standings.
- Partial: render all proven stages/matches and omit unknown cards/edges. A subtle `Pairings appear as they are published` note explains missing future rounds.
- Empty knockout: show `Bracket pairings aren’t available yet` and retain the tab so the layout does not churn when pairings arrive.
- Unsupported/ambiguous stage names: use one chronological stage and match grouping, never cumulative standings as a substitute.
- Error: use the existing user-facing error formatter and a retry action that invalidates only the bracket provider.

## Compatibility and scope boundaries

- Regular events remain three tabs with no behavior change.
- Existing team events remain `About · Games · Standings · Players`; team knockout brackets are not silently modeled as player brackets.
- The existing Standings page, sharing behavior, and `?tab=standings` deep link remain intact.
- Add `?tab=bracket` handling so a bracket link opens the correct fourth-tab layout when the selected category is an individual knockout; otherwise it safely falls back to Games.
- Phone orientation remains portrait-only. Tablet orientation behavior is untouched, but the same canvas adapts to its larger viewport.

## Validation

Pure tests cover:

1. FIDE World Cup multi-tour stages and chronological order.
2. Azerbaijan men/women sibling-lane separation.
3. Dutch single-tour `Stage | Game N` grouping.
4. Turkish `Round X.1`/`Round X.2`/tiebreak grouping.
5. stage-scoped rematches, score aggregation, undecided ties, winner proof, byes, and connector inference.
6. explicit visible-mode lists and index mapping for regular, knockout, and team layouts.
7. graph layout positions remain finite, ordered, and non-overlapping.
8. Bracket loading, empty, partial, and populated widget states plus zoom controls.

Run focused Dart/Flutter tests and `flutter analyze --no-pub` on every touched path. Per project rules, do not run `flutter build`, `flutter run`, or attach to a live app. Final portrait interaction verification is handed to the user with exact on-device checks.

## Self-review

- No placeholders or unresolved product decisions remain.
- The tab order preserves the user’s explicit requirement that Bracket and existing Standings coexist.
- The design does not infer topology the source cannot prove.
- Portrait-only behavior is explicit and consistent with the app’s global phone orientation policy.
- Data normalization addresses both known feed families without hard-coded tournament IDs.
- Team and regular event behavior remain intentionally isolated.
