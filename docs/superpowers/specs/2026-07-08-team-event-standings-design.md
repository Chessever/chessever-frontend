# Team-event standings — design spec

**Date:** 2026-07-08
**Status:** proposed (awaiting user review)
**Scope:** Event view (`TournamentDetailScreen`), team display mode only.

## Problem

The event view has three display modes — **regular**, **knockout**, **team** — sharing one tab set: `About · Games · Standings`. For team events the `Standings` tab shows **individual** player performances, which is wrong for a team competition: the primary ranking a team-event viewer wants is the **team table**.

## Goal

For **team events only**:

1. Tabs become horizontally scrollable and gain a 4th tab. New order:
   `About · Games · Standings · Players`
2. **Standings** = new **team** table — same visual style as today's standings, one row per team, showing that team's collected score. Each row is **expandable** to reveal its players as rows that are visually **identical to today's individual standings rows**.
3. **Players** = today's individual standings table, moved here **unchanged**.

Regular and knockout events are **untouched** (3 fixed tabs, individual standings on `Standings`).

## Scoring (chess team-event standard)

Verified against the live `53rd Greek Team Championship 2026` (`tour_id=4JGSRsEC`, format `7-round FIDE-rated Team Swiss`). Data shape: each `games.players` jsonb entry carries `team`; `games.status` ∈ {`1-0`, `0-1`, `½-½`, `*`}; `board_nr` orders boards; within a round a team faces exactly one opponent over a fixed board count (10 here), colors alternating board-to-board.

**Definitions**

- **Board points (GP)** — per game: white gets `1-0`→1, `½-½`→0.5, `0-1`→0 (black the complement); `*` (unfinished) contributes nothing. A team's GP = sum of its players' board results across all rounds.
- **Match** — the set of games in one round between one unordered pair of teams. Grouping key = `(round_slug, {teamA, teamB})`.
- **Match points (MP)** — within a match compare the two teams' board points: higher → **2**, equal → **1**, lower → **0**.

**Ranking order:** `MP desc`, then `GP desc`. (This is the FIDE / chess-results / lichess team-Swiss convention.)

**Live behaviour:** unfinished boards (`*`) are excluded, so both GP and MP are **provisional** and tick up as games finish. A match with any decided board still counts (provisional MP from decided boards).

**Validation (live snapshot, mid round 5):**

| # | Team | MP | GP | W-D-L |
|---|------|----|----|-------|
| 1 | ΠΑΝΑΘΗΝΑΪΚΟΣ ΑΟ | 9 | 31.0 | 4-1-0 |
| 2 | ΣΟ ΚΑΒΑΛΑΣ | 9 | 26.5 | 4-1-0 |
| 3 | ΟΦΗ | 7 | 26.5 | 3-1-1 |

Both leaders on 9 MP; Panathinaikos ranks first on the GP tiebreak — matches chess-results ordering.

**Out of scope (v1):** tertiary tiebreaks beyond GP (Sonneborn-Berger for teams, direct encounter), byes/forfeit-specific MP rules, and separating a single lichess tour that merges multiple divisions into one team table. Rank purely by `MP → GP`.

## Data model changes

`PlayerStandingModel` (`lib/screens/standings/player_standing_model.dart`) currently **drops** team. Add:

- `final String? team;`
- carry it through `PlayerStandingModel.fromPlayer` (source `TournamentPlayer.team` already exists).

No other change to individual-standings logic — the individual pipeline (`buildStandingsFromData`, `playerTourScreenProvider`) is reused as-is and simply gains the `team` field on each row.

New model `TeamStandingModel` (`lib/screens/standings/team_standing_model.dart`):

```dart
class TeamStandingModel {
  final String teamName;
  final int rank;
  final int matchPoints;      // MP
  final double gamePoints;    // GP (board points)
  final int matchesWon;
  final int matchesDrawn;
  final int matchesLost;
  final int boardsPlayed;     // decided boards, for display/debug
  final List<PlayerStandingModel> players; // that team's individuals, pre-ranked
}
```

## Provider design

New `teamStandingsProvider` — `AutoDisposeAsyncNotifierProvider.family<..., List<TeamStandingModel>, TeamStandingsKey>` mirroring `playerTourScreenProvider`'s inputs (same tour + live games source).

Build algorithm:

1. Gather the same games the individual pipeline uses for this tour (all related rounds + live games).
2. From games, per round, group by unordered team pair → per-team board totals → MP (2/1/0).
3. Aggregate per team: `MP`, `GP`, `matchesWon/Drawn/Lost`, `boardsPlayed`.
4. Take the **already-computed** individual `List<PlayerStandingModel>` (now team-tagged), group by `team`, sort each group by the individual ranking already applied.
5. Sort teams by `MP → GP`; assign ranks (mirror `assignOverallRanks` semantics used for players).
6. Emit `List<TeamStandingModel>`.

Team detection reuses the **single existing discriminator**. `KnockoutTournamentState` already computes `isTeamEvent` internally (`formatSaysTeam || (!formatSaysPlayer && allPlayersHaveTeam)`, and not knockout); expose it as a field on that state and add a thin `isTeamEventProvider` so tabs, games mode, and team standings all read one source of truth. No new/divergent detection logic.

Expansion state: `StateProvider<Set<String>>` keyed to expanded team names (allows multiple open; survives list rebuilds during live updates).

## Widget design

- **`FigmaTeamCard`** (`lib/widgets/figma_team_card.dart`) — same skeleton as `FigmaPlayerCard`:
  `[rank] [team-initials avatar] [Expanded: team name (bold) + sub-row] [right: MP] [chevron]`
  - initials avatar: reuse the `PlayerInitialsAvatar` visual, initials derived from the team name (up to ~2–3 letters from significant words).
  - sub-row (where a player row shows flag + rating + ratingΔ): `"{GP} board pts · {W}-{D}-{L}"`, GP rendered with a ½ glyph for halves (e.g. `26½`).
  - right-side primary number = **MP** (integer), matching where the player row shows `matchScore`.
  - tapping the row (or chevron) toggles expansion.
- **Expanded content** — that team's players rendered with the **exact current `FigmaPlayerCard`** (`showFavoriteButton: false`, so each shows individual board score `4.5 / 6`, rating, ratingΔ, flag), indented slightly, tapping a player still routes to `/scorecard_screen`.
- **Header** — reuse `FigmaStandingsHeader` with columns `# / Team / Pts`.
- **List screen** — `TeamStandingsScreen` (`lib/screens/tour_detail/team_tour/team_tour_screen.dart`) mirroring `PlayerTourScreen`/`_StandingsList`: `ListView.builder` of `FigmaTeamCard`, same loading skeleton (`FigmaPlayerCard` in `SkeletonWidget`), same search bar wiring (search filters teams by name in v1).

## Tab mechanics (`tournament_detail_screen.dart`)

- Add `players` to `TournamentDetailScreenMode` enum (`tour_detail_mode_provider.dart`).
- Build a **dynamic** `List<TournamentDetailScreenMode> visibleModes`:
  - team → `[about, games, standings, players]`
  - else → `[about, games, standings]` (unchanged)
- Labels map extended: `standings → 'Standings'`, `players → 'Players'`.
- `PageView.builder` `itemCount = visibleModes.length`; builder switches on `visibleModes[index]`:
  - `about → AboutTourScreen`
  - `games → GamesTourScreen`
  - `standings → team? TeamStandingsScreen : PlayerTourScreen`
  - `players → PlayerTourScreen`
- `SegmentedSwitcher` (`lib/widgets/segmented_switcher.dart`): add an `isScrollable` variant. When true (team, 4 tabs), lay segments in a horizontal `SingleChildScrollView` with intrinsic widths instead of `Expanded` thirds; keep the animated selected pill. When false, today's fixed equal-width behaviour is unchanged.
- `_handleTabSelection`, `_handlePageChanged`, `_mappedName` updated to use `visibleModes` + the extended label map. `selectedTourModeProvider` default `.games` remains valid (index 1 in both layouts).

## Files touched

New:
- `lib/screens/standings/team_standing_model.dart`
- `lib/screens/tour_detail/team_tour/team_tour_screen.dart` (+ provider file)
- `lib/widgets/figma_team_card.dart`

Modified:
- `lib/screens/standings/player_standing_model.dart` (add `team`)
- `lib/screens/standings/standings_builder.dart` (pass `team` into `fromPlayer`)
- `lib/screens/tour_detail/provider/tour_detail_mode_provider.dart` (enum + label map)
- `lib/screens/tour_detail/tournament_detail_screen.dart` (dynamic tabs/pages)
- `lib/widgets/segmented_switcher.dart` (scrollable variant)
- `lib/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart` (expose `isTeamEvent`) + thin `isTeamEventProvider`

## Validation

- `flutter analyze` clean on touched files (canonical check per CLAUDE.md).
- Team standings numbers cross-checked against the SQL computation above for the live GTC.
- No behavioural change for regular/knockout events (3 fixed tabs, individual standings).
- Runtime/on-device verification delegated to the user.

## Decisions locked (default; overridable in review)

1. **Scoring:** Match Points primary, Board Points tiebreak.
2. **Team avatar:** initials avatar reusing the player-row avatar slot (layout stays identical).
