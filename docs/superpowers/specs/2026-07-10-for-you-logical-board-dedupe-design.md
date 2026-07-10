# For You Logical Board Deduplication Design

**Date:** 2026-07-10

## Goal

Prevent one real chess game from occupying multiple cards in the For You event
preview when Lichess publishes that game through both a category broadcast
(such as Open or Women) and a Combined broadcast.

## Root cause

The event views correctly keep their source-tour game rows separate. The For
You RPC then combines category and Combined tours into one event preview and
ranks those equivalent rows independently because their tour average Elo values
place them in separate event categories. Lichess assigns a different game ID to
each broadcast copy, so ID-level uniqueness cannot detect the overlap.

For Dutch Championship 2026, one RPC call returns duplicate logical boards for
Tiviakov–Vrolijk and Van Foreest–Kazarian from the Combined and category tours.
The rows have different IDs but matching logical round, players, PGN Round tag,
position, and move stream.

## Scope

Change `public.get_for_you_top_games(text[], integer)` so it deduplicates
logical boards before applying the per-event rank and limit. Keep the function
arguments, return columns, permissions, placeholder filtering, live priority,
category discovery, ordering rules, and Flutter client unchanged.

Do not delete or merge stored game rows. Other screens may intentionally expose
the source tours separately, and changing canonical ownership belongs to a
separate data migration and broadcaster rollout.

## Logical game identity

Two candidate rows are copies of one logical board only when all of these
values match:

- requested event ID;
- normalized logical round slug/name plus round start time;
- normalized White player and Black player, preserving colors;
- a stable game discriminator.

Use the PGN `Round` header as the preferred discriminator. This distinguishes
legitimate multi-game tiebreaks between the same players inside one broadcast
round. If that header is unavailable, use the exact non-initial FEN. If neither
is available, fall back to the row ID and do not deduplicate speculatively.

## Selection and ranking

Add a deduplication rank over candidate games using the same deterministic
precedence already used for event ranking: live games, board number, source
priority, round recency, category Elo, existing board rank, player rating, and
game ID. Retain only the first copy of each logical game, then compute the final
per-event rank and limit. Deduplicating before the limit allows another unique
candidate to fill a preview slot when one is available.

## Validation

- Add a focused migration-source test that requires a deduplication CTE before
  final event ranking and checks the identity fields and PGN/FEN fallback.
- Run the production-data Dutch Championship repro before deployment and confirm
  it reports duplicate logical boards.
- Apply the migration through `supabase_chessever_main`.
- Re-run the Dutch Championship RPC and assert unique logical boards.
- Verify legitimate Dutch tiebreak games with different PGN Round values remain
  separate candidates.
- Run Supabase security and performance advisors and confirm the function stays
  `security invoker` and executable only by `authenticated`.
- Run the focused Flutter/Dart SQL-source test and scoped `flutter analyze`.

## Non-goals

- No Flutter-side filtering or cache changes.
- No changes to Realtime subscriptions or live-board refresh behavior.
- No deletion, reassignment, or backfill of existing game rows.
- No global game identity schema or broadcaster deployment in this fix.
