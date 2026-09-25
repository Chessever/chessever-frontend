# Tournament standings audit, 20 September 2026

Status: production server fix approved by the owner and deployed. All four stale Women’s round-1 results were repaired through the normal ingest writer. The public API now reports Brazil at 6 MP / 12 GP after round 4. The app fixes below are prepared for release 35.6.3+3458.

## Official reference

[Women's Olympiad standings after round 4](https://s1.chess-results.com/tnr1469896.aspx?lan=1&art=0&rd=4&flag=NO), retrieved 20 September 2026:

| Team | Rank | Matches | Wins | Draws | Losses | Match points | Olympiad SB | Board points |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Brazil | 35 | 4 | 3 | 0 | 1 | 6 | 34 | 12 |

[Brazil's match results](https://s1.chess-results.com/tnr1469896.aspx?lan=1&art=20&snr=44&flag=NO): 4-0 against Mauritania, 3-1 against Jamaica, 1-3 against England, 4-0 against Albania. The reported four match points are incorrect for the completed fourth round.

## Confirmed frontend defects fixed locally

Implementation: `lib/screens/standings/standings_builder.dart`.
Regression tests: `test/screens/standings/standings_identity_test.dart`.

1. Roster entries were merged by FIDE ID, but game scores and opponent scores were indexed by name. A single player with a changed name therefore lost games; different players sharing a name inherited each other's games. One shared identity resolver now keys all three operations by positive FIDE ID. Missing IDs resolve only through unambiguous name/team evidence collected before merging.
2. Duplicate roster entries were discarded wholesale. When a later entry supplied the missing FIDE ID, that ID was lost. A subsequent game with the same ID and another spelling created a duplicate player. Merging now preserves missing identity fields while retaining authoritative score/rank values.
3. Standings marked `useExternalOrder` were nevertheless re-sorted by score/rating when explicit rank numbers were missing. They now retain source order. Complete explicit ranks still take precedence.

Initial failing regressions showed a renamed player's `2 / 2` becoming `1 / 1`, a homonym's `1 / 1` becoming `1 / 2`, an expected two-player roster growing to three, and official tied players reversing order. All now pass. Added coverage includes missing IDs, feed order reversal, unidentified homonyms on different teams, ambiguous identities, and preserving official custom scoring.

The follow-up review also caught an overly broad fallback in the patch: a teamless roster entry could bridge two same-named game players from different teams. A new regression reproduced that merge. The resolver now requires unambiguous team evidence for a match through missing team metadata; an explicit FIDE ID remains authoritative.

## Confirmed team-ranking defect and authoritative source integration

`lib/screens/standings/team_standings_builder.dart` hardcodes match points, then board points, then team name. The official Olympiad order is match points, Olympiad Sonneborn-Berger excluding the lowest result (Chennai), board points, then adjusted opponent match points excluding the lowest result.

Applying the app's sort to the official round-4 table places Brazil 14th instead of 35th, India 4th instead of 7th, and England 16th instead of 13th. This comparison uses official totals, not production app records. Fixing a missing game result cannot fix this ordering rule. An authoritative standings contract or event-specific tiebreak policy is required; it must not be guessed from generic game totals.

## Server root causes and recovery

The Direct writer stopped polling Women’s round 1 at 18:43:14 UTC on 16 September. Four stored results remained unfinished while FIDE’s current PGN had final results. Nunes–Fatima (`GGHkIKQF-r93iof`) was one of those, suppressing Brazil’s entire two match points from round 1. The server release replays recent expired rounds at a bounded 15-minute cadence for 14 days, one background round at a time, through the existing fenced writer. All four statuses and PGN results were verified corrected on their existing IDs.

A separate ingest optimization discarded late player ID/team metadata when position/result/clocks did not change. That now checks metadata before skipping. The server’s SQL standings, roster, cards and form strips also share positive-ID/unambiguous name-team resolution instead of splitting missing/zero IDs into duplicate players.

## Official team standings

The broadcasting server now imports validated complete Chess-Results team tables into `tours.info.officialTeamStandings`. The snapshot includes source, source URL, round, fetched time and ordered team rows. It preserves official ranks, tied ranks, MP, GP and W/D/L, including awarded points absent from PGNs. Malformed/partial tables and older rounds cannot overwrite a valid snapshot. Source configuration and writer ownership are rechecked transactionally. No public schema changes.

This app reads the same snapshot and labels the table “Official standings · after round N”. It does not mix official ranks with live PGN-derived totals. Unsupported/legacy events retain their existing computation. A collision in the fallback’s concatenated team-pair key was also fixed: A/BC and AB/C can no longer collapse into one encounter.

The official round-4 reference contains 189 women’s teams and 206 open teams; registration metadata includes extra entries. Complete official lists, not registration counts or the default first 150 rows, are used.

## Environment and validation

The owner explicitly approved the production server fix after the initial test-only audit. Production target `oelbsuggrzyqwzmvidju` and broadcasting host `64.23.142.144` were verified before writes/deployment. The retired test project contains metadata but no Olympiad games and cannot reproduce the live issue.

Backend regressions include all four captured production PGNs, real PostgreSQL identity/admission/snapshot-transaction tests, parser rejection cases and official API output. The server’s detailed audit is `chessever-broadcasting-standings/docs/STANDINGS_INTEGRITY_2026_09_20.md`.

Frontend validation uses scoped analysis and standings unit/widget tests. Whole standings-directory analysis additionally reports six pre-existing diagnostics in untouched files; the changed-file check is the release gate. No app was built, started or driven. The UI change uses the existing list, theme and responsive spacing; its content is visible by default, wraps naturally, and introduces no decorative styling or new controls. The supplied UI rules were rechecked for the changed surface.

Device checks after installing 35.6.3+3458:

1. Refresh Women’s Olympiad. Verify the official round label; for the round-4 snapshot, Brazil is 35th with 6 MP / 12 GP.
2. Verify tied ranks and teams with awarded points match the linked official table.
3. Check that a player with multiple source spellings appears once and includes all games; same-named players with distinct FIDE IDs stay separate.
4. Search for a team and expand its row; the official round label remains clear and search/expansion still work.

Server result repairs benefit existing app versions immediately on refresh. Official team ordering and the client identity changes require the app release. Automatic server reconciliation is bounded to recent delegated events; older archives and unsupported official source formats are not claimed universally repaired.
