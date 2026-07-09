# For You Live Board Priority Design

**Date:** 2026-07-10

## Goal

Make each For You event-card preview select actively playing boards before
finished boards while keeping board numbers ascending. Preserve the current
lightweight frontend and its existing position and clock streams.

## Scope

Change `public.get_for_you_top_games(text[], integer)` and add a small frontend
freshness coordinator around the existing RPC/cache path. Do not add a timer,
Realtime channel, ranking algorithm, or rendering path.

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

The database change adds a computed boolean/integer sort key to candidate rows
already loaded by the RPC. It introduces no table scan, join, response field,
or payload expansion. The existing RPC limit continues to reduce the payload
before it reaches Flutter. Automatic freshness adds one batched top-games call
per minute only while For You is visible; unchanged snapshots do not rebuild.

## Realtime behavior

The existing frontend remains responsible for streaming FEN/position, clocks,
last move, and completion status for selected cards. No Realtime publication
or subscription changes. Refresh coordination only reselects card IDs and
event membership at bounded intervals or on actual live-set changes.

## Automatic freshness follow-up

The event feed remains personalized on-device. Starred events and favorite-
player counts are user-specific, so the existing client ranking stays intact;
they are not passed into or recomputed by the feed RPC.

For You piggybacks the existing strict-live resolver's one-minute timer. It
adds no timer and no Realtime channel. While the For You route is selected,
current, and foregrounded, each tick performs one batched top-games RPC for
eligible events. It does not refetch favorite-player counts. The full event
feed remains capped at one refresh per five minutes.

Tab activation and route return immediately refresh top-game membership. App
resume continues to force the full catch-up path. An actual live event, tour,
or round-set change clears the session-order cache and re-runs the existing
client personalization once, allowing newly eligible starred/hearted events to
bubble without continuous sorting.

Heartbeat results are diffed against the snapshot cache. Equivalent snapshots
reuse the existing object and do not notify widgets; only events whose selected
boards changed rebuild. Card FEN/position and clock streams are unchanged.

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
- Test the one-minute/five-minute refresh decision and visible-route gating.
- Test that equivalent heartbeat snapshots preserve cache identity and changed
  events replace only their own cache entry.
- Run scoped `flutter analyze --no-pub` on every touched Flutter/test file.

## Non-goals

- No new frontend ranking algorithm or backend event personalization.
- No replacement of the existing user-specific client ranking.
- No changes to game-card streaming, clocks, or position updates.
- No per-move RPC refresh or background/off-route heartbeat work.
- No schema, RLS, index, or response-shape changes.
