# For You Live Board Priority Design

**Date:** 2026-07-10

## Goal

Make each For You event-card preview select actively playing boards before
finished boards while keeping board numbers ascending. Preserve the current
lightweight frontend and its existing position and clock streams.

## Scope

Change only the `public.get_for_you_top_games(text[], integer)` database RPC.
There will be no new frontend query, client-side sort, provider, subscription,
or rendering work.

## Selection and ranking

A candidate is live only when both conditions are true:

- Its selected round comes from `settings.live_round_ids`.
- Its normalized game status is `*` or `ongoing`.

Requiring the configured live round prevents old unfinished game rows from
being promoted merely because their stored result is `*`.

For each event, rank eligible candidates by:

1. Live game first.
2. Board number ascending, with missing board numbers last.
3. The existing source priority, round recency, category average Elo, player
   rating, and stable ID tie-breakers.

The RPC will continue returning no more than `p_boards_per_event` rows for an
event. Its arguments, return columns, permissions, `security invoker` behavior,
placeholder filtering, and live-round/fallback-round discovery stay unchanged.

## Performance

The change adds a computed boolean/integer sort key to candidate rows already
loaded by the RPC. It introduces no table scan, join, network request, response
field, or frontend operation. The existing RPC limit continues to reduce the
payload before it reaches Flutter.

## Realtime behavior

The existing frontend remains responsible for streaming FEN/position, clocks,
last move, and completion status for the selected cards. This change only
chooses and orders the initial card IDs. No Realtime publication, subscription,
or refresh behavior changes.

## Validation

- Add a focused SQL migration regression assertion that the per-event ranking
  places the live-game key before board number and keeps board number ascending.
- Run the focused Flutter test file that inspects the latest RPC migration.
- Apply the migration through `supabase_chessever_main`.
- Query the deployed function definition and current live-round data to verify
  that returned live cards precede finished cards and have ascending board
  numbers.
- Run Supabase security and performance advisors and confirm this function
  remains `security invoker` and executable only by `authenticated`.

## Non-goals

- No frontend sorting or over-fetching.
- No changes to game-card streaming, clocks, or position updates.
- No changes to event ordering in the For You feed.
- No schema, RLS, index, or response-shape changes.
