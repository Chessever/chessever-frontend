# Olympiad standings and player-report freshness

Prepared on `feat/space-discovery`, including version `35.14.3+3488`.
This source change is not a released mobile build.

## Evidence

The reported image shows Denis Lazavik (FIDE 13515110) at 6.5/9, including his
round-10 win against Nikita Vitiugov (2676), but the headline rating change is
still +7. Applying the app's existing rating calculation to the nine listed
opponents gives +7 before that last win and +13 afterward. The final win adds
approximately 5.785 points; round only after summing the unrounded changes.

Read-only inspection on 26 September confirmed that the Direct server has the
latest result:

- Open tour: `nKADDSF2`; writer: `chessever_direct`.
- `GET /api/broadcast/nKADDSF2/players?q=Lazavik`: played 9, score 6.5,
  ratingDiff 13.
- The stored `public.tours.players` entry independently agrees: played 9,
  score 6.5, `ratingDiffs.standard` 13.
- The Open tour's official team snapshot was already at round 10, fetched
  `2026-09-26T17:42:28.354Z`.

This proves the current server data is correct. It does not reconstruct the
server's exact state when the original screenshot was taken. No production
data or server code was changed for this repair.

## Root cause

Game results and event metadata have different lifecycles in the app.
`gamesTourProvider` maintains the game catalog, while
`tourDetailScreenProvider` loaded `tours.players` and
`info.officialTeamStandings` on entry and explicit pull-to-refresh only.
Its live-tour listener changed liveness using the same existing Tour objects;
it did not reload either standings snapshot.

`buildStandingsFromData` intentionally prefers source scores, played counts,
rating changes and ranks. Rebuilding it after a game result therefore still
used the old roster. Team standings likewise kept preferring the old official
snapshot. The player report recomputed its result rows from games but preferred
the old nonzero `player.scoreChange` for its headline.

The September 20 repairs addressed server result reconciliation, player
identity and official ranking. They did not add this mobile metadata refresh.
The existing uncommitted player-report fix on this branch covered the headline
but did not refresh the standings tab. This change completes that path.

## Fix

- Refresh event metadata every 30 seconds while the event is visible and the
  app is active, and immediately on return. A timer is necessary because a
  server aggregate can land after the last game update.
- Apply the roster and official table together through the existing detail
  provider. Preserve source scoring, ranking and awarded points.
- Keep the selected category, including a category changed during the request.
  Do not repeat default-selection queries on each refresh.
- Retain the last good view after failure, empty responses or a response
  missing the selected category. Bound a refresh to 12 seconds, prevent
  concurrent refreshes, and ignore late responses after timeout/disposal.
- Skip unchanged metadata even if repository ordering differs. Stop timers
  when hidden, backgrounded, unobserved or disposed. Virtual gamebase events
  retain their existing path.
- Preserve and verify the branch's player-report change: total the same
  completed-game rows rendered in the report, round once, preserve zero as a
  valid value, and retain the source total if history or ratings are incomplete.

## Validation

The regression initially failed with `Expected: <13>, Actual: <7>` through
the real detail, player-standings and team-standings providers. It now observes
6.5/9 and +13 plus an official round-10 table without re-entering the event.

`standings_refresh_test.dart` also covers visibility/resume, failure and empty
responses, in-flight deduplication, category selection, disposal, unchanged
metadata, removal of the last listener, timeout and late responses.
`player_event_rating_diff_test.dart` covers the screenshot's nine games,
losses, rounding, zero, unfinished games, missing ratings and partial history.

The focused suite covers standings and report widgets, Elo calculation, game
merging, background work, search, category ordering, selection persistence and
tournament detail. Changed-file `flutter analyze --no-pub` is the static gate.
The initial focused suite passed 146 tests. The expanded format audit described
below passed **291 tests**. Changed-file analysis reported no issues and
`git diff --check` passed.

There is no visual redesign or new control. The UI-rule review found no new
type, palette, layout, decoration, animation, clipping or contrast changes to
audit visually. Existing content stays visible during refreshes.

Device validation remains with the owner under this repository's no-run/no-build
rule: install the updated app, open Olympiad Open, find Lazavik, and check the
round-10 snapshot shows 6.5/9 and +13 in the player row, scorecard and shared
image, with performance 2725 in the report. Leave Standings open across a published result, then background/resume
and switch Open/Women; source totals and official round labels should advance
without re-entry or a category jump. Later rounds naturally change those totals.

## Audit across event formats

The follow-up audit found that `_usesLiveEventData` allowed only Games and
Bracket. Standings and Players had neither the game-result safety net nor a
catalog-level Realtime subscription. Tests reproduced both frozen views before
changing the gate.

The format-independent catalog now listens to one tour-filtered games channel
per observed tour on Standings, Players and Bracket. It applies result
completions, corrections and retractions immediately. PGN, FEN and player-clock
changes do not rebuild aggregate state. Games keeps its visible-card streams.

A result burst triggers a coalesced roster/official-table fetch after 300 ms,
then a retry after 3 seconds for delayed aggregate writes. The 30-second metadata
poll catches independent official publications. The existing paginated safety
net (selected tour: 5 seconds; sibling stage: 45 seconds) repairs dropped events,
deletes and membership changes. Subscribe/reconnect also reconciles immediately.
It now includes rating, identity, team, custom points and board corrections,
without downloading every game's PGN. HTTP reads time out after 12 seconds;
a result arriving during a read prevents that older response overwriting it.
Hidden/background/unobserved views cancel channels and timers.

| Format/path | Audit and coverage |
| --- | --- |
| Individual Swiss/open | New results, losses, draws and retractions recompute scores and estimated Elo; source rankings/tiebreak order remain authoritative. |
| Round robin / double round robin | Repeat opponents and reversed colours are counted per game; the same realtime catalog has no format exclusion. |
| Team Swiss / team round robin | Board points advance on finished boards; match points wait for all present boards. Retractions remove provisional match points. Official ranks, byes and awards use the refreshed source snapshot. |
| Knockout / multi-stage / tiebreaks | Bracket providers already observe complete catalogs for their stages. Those catalogs now subscribe to results; existing round-metadata reconciliation and bracket tests remain passing. Standard and rapid/blitz rating pools are never summed into one estimated change. |
| Custom scoring / Armageddon | Stamped custom points enter fallback standings and signatures. Official score/rating totals remain authoritative; Armageddon is excluded from local Elo estimates. |
| Large / paginated events | Reconciliation explicitly tested with 2,400 games across three pages; no 100-board cap. Existing preview/full-catalog tests protect complete team matches. |
| Archived virtual gamebase events | Remain immutable historical views and do not open live channels. |

Additional report corrections:

- One shared Elo helper and K fallback serve standings and report rows. FIDE's
  published per-time-control K is preferred; ratings published with each event
  game are retained instead of replacing historical ratings with a newer monthly
  list. A PGN tiebreak time control can override the enclosing event category.
- A local total requires complete history and known ratings for every finished
  game. Missing data and mixed rating pools preserve the source total or leave
  the estimate unavailable. A real zero is represented separately from missing
  data and survives model serialization.
- Performance uses the FIDE dp table also used by Direct, replacing the mobile
  linear approximation. The screenshot's nine opponents give 2725. Missing
  opponent ratings no longer become an invented 1500 for performance.
- Report scores retain published byes/custom awards when the source covers the
  visible games. The single-player scorecard also receives refreshed standings.

Reference: [FIDE rating regulations, dp table](https://handbook.fide.com/chapter/B022024)
and [rapid/blitz time controls](https://handbook.fide.com/chapter/B02RBRegulations2024).

### Boundaries

These changes keep the client current with published data. They cannot publish
an organizer's result or official team table before the source supplies it.
The official table advances on its own source cadence, with at most the normal
metadata polling interval added while the view is active. No production schema,
publication, data or deployment was changed. Realtime uses the existing games
publication, with HTTP recovery if the socket is unavailable.

Local Elo remains a broadcast estimate when the source does not supply a total;
it is not a guarantee of the eventual FIDE rating list. Career K history,
registration/rated eligibility, forfeits, and source omissions cannot all be
recovered from ordinary broadcast rows. Custom formats retain source authority
rather than fabricating missing official information.
