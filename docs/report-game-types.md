# Report game types

Implemented in the frontend and `../chessever_cloudflare`. Production backend
rollout is recorded below; the frontend UI ships with the next app release.

## Behavior

Reports has one horizontal choice-chip row: All, Upside Down, Comeback,
One Blunder, Great Escape, Domination, Squeeze, Deadlock, Miniature, Marathon.
The marks use the existing rounded Material icon language and theme tokens.
Player search, date groups, layout switching, first-page caching, pagination,
and board navigation keep their existing behavior. Switching type starts at
the first matching page and ignores responses from the previous type.

Types can overlap. A game can match Upside Down and Comeback, and independently
match Miniature or Marathon. A primary story is stored with precedence:
Upside Down, Comeback, Great Escape, One Blunder, Squeeze, Domination, Deadlock.
The existing card layout stays intact; the chips filter every matching report
in the database, not only the pages loaded on the phone.

- Miniature: decisive, fewer than 25 moves. A final White move on move 25
  counts as 25. This does not change the separate Miniatures collection.
- Marathon: completed, at least 80 moves, including draws.
- Custom-position excerpts, live games and empty games get no length tags.

## Story rules, version 1

Rules use White-side centipawns, with signed mates and correct mate-zero side
handling. They do not run another engine, change move verdicts, or use ratings.
Every played position must have an evaluation before any story is assigned.
The initial evaluation may be absent in a hydrated PGN; an unknown sample is
never interpolated. A partial report may still have a valid length tag.

Control enters at a two-pawn advantage, persists down to 1.2 pawns, and needs
four consecutive plies to establish a winning/losing stretch.

| Story | Evidence |
| --- | --- |
| Upside Down | At least two reversals between established control stretches. |
| Comeback | The winner had an established losing stretch and finishes at least broadly balanced. |
| One Blunder | The loser's move changes a position within one pawn of equality to at least two pawns for the winner, a swing of at least two pawns. The advantage stays above 1.2 pawns thereafter. Short endings must finish at least three pawns ahead or in mate. Later mistakes in an already lost position do not erase the story. |
| Great Escape | An established winning stretch for either side followed by a draw finishing within one pawn of equality. |
| Domination | The winner's final continuous control lasts at least 12 plies and 30% of the game, starts within its first 60%, and follows no established losing stretch. |
| Squeeze | Three rising four-ply blocks, starting with a small edge, grow into the final control. No sudden increase over one pawn or reversal exceeding 0.6 pawns is allowed in those blocks, and no reset to equality is allowed before control. Final control lasts at least six plies and follows no established losing stretch. |
| Deadlock | A draw without established control; at least 80% of played positions stay within one pawn, and none exceed three pawns. |

These are conservative, versioned heuristics. Tests cover the rules and the
real Scholar mate reference; wider real-game calibration may refine them later.
Unclassified reports remain browsable in All.

## Additive storage and compatibility

The container adds optional `gameClassification` to report JSON, keeping
`schemaVersion: 1` and every existing field/PGN. Classification exceptions
produce null metadata rather than failing a successful report.

Supabase gets one nullable JSONB column, `games.report_game_classification`.
The new service-role-only writer atomically compares the exact annotated PGN
and final result before updating only that column. It adds the PGN's MD5 hash.
Existing override triggers remain installed. If a trigger changes any existing
game field during a metadata write, that write and its trigger effects roll
back, returning `stale` instead of changing the game.
Filters exclude metadata whose hash or result no longer matches the game.
Existing RLS policies remain in force. No triggers, PGN changes or changes to
the existing `store_prewarmed_report_pgn` signature are introduced.

The prewarmer writes metadata after its existing PGN write succeeds. Missing
RPCs and metadata network failures leave the report/PGN write successful and
are retried on the next cached prewarm writeback. Existing clients ignore the
extra JSON field; All keeps its original query on older backends. A missing
filter RPC displays a notice directing the reader to All.

## Test rollout

1. Verify the Supabase target is the test project `odmekzlfunfocvedqusl`.
2. Apply `supabase/migrations/20260930183029_report_game_classification.sql`.
   For bounded batch backfills also apply
   `supabase/migrations/20260930205935_report_game_classification_batch.sql`.
3. Install `supabase/manual/20260930183029_report_game_classification_index_concurrently.sql`
   outside a transaction. The concurrent index avoids blocking broadcast writes.
4. Deploy analysis from a verified test Worker configuration. The repository's
   default Worker configuration targets an existing live service, so do not use
   an unqualified deploy command for this test-app work. Report cache algorithm
   is 24; story rules are independently versioned at 1.
5. From `../chessever_cloudflare/apps/analysis/container/dart`, run
   `dart run tool/backfill_game_stories.dart` for a dry run, then add `--write`
   to persist. Supply the test URL and server key through environment variables.
   By default the tool refuses other hosts and plaintext HTTP. An explicitly
   authorized production run requires `--project-ref=oelbsuggrzyqwzmvidju`
   and the matching HTTPS URL. It uses the same PGN rules
   as hydration, no engine calls, 100-row batches, and an ID cursor. It skips
   unchanged classified inputs; restart with the printed `--after=ID` cursor.
   Add `--batch-write` with `--write` for at most 100 guarded updates per
   transaction. The optional service-only batch RPC preserves the original
   single-game writer and bounds row-lock waits to two seconds.
6. Release frontend version `35.27.1+3506` using the intended test configuration.

On-device checks belong to the user: open Discovery > Reports, swipe to
Marathon, select each category, switch quickly between categories, return to
All, search a player, paginate and refresh, and try both card layouts/themes.
Include a narrow phone and a larger accessibility text size.

## Production rollout: 2026-09-30 UTC / 2026-10-01 Istanbul

The user explicitly authorized Supabase `oelbsuggrzyqwzmvidju` and the live
`chessever-analysis` Worker. Both metadata migrations and the concurrent index
were applied. No other pending repository migrations were applied.

- Worker algorithm 24, engine `sf_18`; version
  `ab8ddaf6-d847-4088-8bef-921aab75f19e`.
- Container rollout completed on all three instances, with no reported errors.
  Existing bindings, secrets, resource sizes, limits and schedules were retained.
- 9,752 unique reports have metadata; 6,907 match at least one label. There
  are no stale PGN/result bindings. Games can match multiple labels.
- Two games with existing admin overrides were skipped: applying those
  overrides during a metadata update would change existing fields. The guard
  rolled the writes back, preserving those games. They remain available in All.
- Five of the 9,759 games in the before snapshot changed PGNs before they
  received any metadata and no longer carry the ChessEver report marker.
  They were excluded. None of the original snapshot games were deleted.
  Metadata writes enforce equality of every existing field, including the PGN.
- Existing game RLS policies, triggers and their function definitions, and the
  existing PGN writer were compared against the before snapshot and preserved.
- All nine anonymous filter queries and All succeeded; timestamp pagination
  passed eight pages, and ID pagination passed 21 pages / 2,066 unique games
  without duplicates. The initial dry-run count included repeated boundary
  rows caused by quoted direct scalar cursors; that tool cursor is corrected.
- The report cache version bump follows the analysis repository's required
  invalidation rule. Old cache rows expire normally; a subsequent report request
  may regenerate a cached report. The backfill itself uses no engine calls.

| Label | Matching reports |
| --- | ---: |
| Upside Down | 54 |
| Comeback | 709 |
| One Blunder | 2,397 |
| Great Escape | 465 |
| Domination | 2,066 |
| Squeeze | 601 |
| Deadlock | 1,272 |
| Miniature | 513 |
| Marathon | 535 |

The frontend code is ready at `35.27.1+3506`; no app release was triggered.

## Validation

- Scoped `flutter analyze --no-pub` and Reports repository/cache/pagination/widget tests.
- `pnpm analysis check` and `pnpm analysis test`.
- Container `dart analyze`, `dart test`, and the local real-game pipeline.
- Disposable PostgreSQL test: `supabase/tests/report_game_classification.sql`,
  covering unchanged data, idempotence, stale PGN/result exclusion, RLS,
  service-only writes/backfill, backfill skipping, and an indexed inline query.

No Flutter app build, launch, attachment or live UI automation is required.
