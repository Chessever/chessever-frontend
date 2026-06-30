# Realtime Live Card Handoff - 2026-06-30

## Situation

Community events such as Titled Tuesday can start a new round immediately after
the previous one finishes. The mobile app must show each newly live game and
every move as soon as the `games` row changes in Supabase Realtime.

This repo uses the same live-card direction as desktop:

- card/list surfaces share small game-id batch streams
- focused game screens keep a single-game stream
- finished cards do not open realtime streams
- scroll/pause behavior must not freeze mounted realtime row updates

Current pushed baselines before this handoff doc:

- Mobile: `chessever-frontend` on `dev`,
  `ede24e5c7822da817345952526f92c0ea252135f`
- Desktop: `chessever_frontend_desktop` on `main`,
  `e15770324439e3103ea4a01faa68c15e407a8e85`

Desktop has the matching handoff at:

```text
/Users/berkay/projects/chessever_frontend_desktop/docs/realtime_live_card_handoff_2026-06-30.md
```

## Why This Direction

Supabase Realtime has channel and join-rate limits. A per-card channel model can
feel immediate while under limits, but it becomes fragile when many live games
are mounted at once or when users scroll quickly through mixed live/finished
lists.

Batching is only a transport/channel-sharing mechanism. Every game row still
updates independently. A move in one game should reach that game's mounted card
and open board immediately when Supabase emits the row change.

Expected mobile channel shape:

- open game screen: one single-game stream for that game
- card/list context: one stream per small game-id batch
- finished game: no card-owned realtime stream
- static/non-live/database game: no realtime stream

## Core Invariants

Do not reintroduce hidden round/tour fallbacks for mobile live cards.

Good:

- `LiveGamesBatchKey(scopeId: ..., gameIds: visibleOrContextIds)`
- wrappers passing an explicit `liveBatchKey`
- wrappers deriving a context key with `liveContextBatchKeyForGame(...)`
- `gameUpdatesStreamProvider(gameId)` only for focused board/game screen usage

Bad:

- one `gameUpdatesStreamProvider(gameId)` per mounted card in a list
- `LiveGamesBatchKey(... roundId: game.roundId)` as an implicit card fallback
- `LiveGamesBatchKey(... tourId: game.tourId)` as an implicit card fallback
- round-wide/tour-wide card streams for mixed event views
- disabling mounted realtime PGN/FEN/clock/status updates during scroll

Scroll pause can suppress expensive visual work. It must not stop the row stream
for mounted live cards.

## Shared Stream Providers

File: `lib/screens/chessboard/provider/game_pgn_stream_provider.dart`

- `gameUpdatesStreamProvider(gameId)` is an `AutoDisposeStreamProvider.family`
  for focused board/game screens.
- `liveGameUpdateStreamProvider(gameId)` is the typed single-game provider.
- `gameUpdatesBatchStreamProvider(batchKey)` is the multi-game card/list
  provider.
- `LiveGamesBatchKey` equality is based on `scopeId`, optional round/tour, and
  sorted `gameIds`.
- Current card/list paths should build game-id batch keys, not implicit
  round/tour keys.

Repository stream implementation:

File: `lib/repository/supabase/game/game_stream_repository.dart`

- `subscribeToLiveGameUpdate(gameId)` streams one `games.id`.
- `subscribeToLiveGameUpdatesBatch(gameIds)` streams `games.id IN (...)`.
- The comment now reflects the actual model: batching live games rendered in a
  visible/context surface into a few scoped channels.

## Live Card Provider

File:
`lib/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart`

Important pieces:

- `baseGameProvider` is `autoDispose` and stores the latest base/merged game per
  game id while cards/providers are mounted.
- `kLiveContextBatchSize = 25`
- `liveContextBatchKeyForGame(...)` builds a chunk key from a provided context
  list.
- `shouldSubscribeToLiveGame(game)` requires:
  - Supabase source
  - non-empty game id
  - not finished
- `_liveWatchParamsForGame(...)` disables streaming if no explicit/context batch
  key exists.
- `_watchLiveUpdate(...)` watches `gameUpdatesBatchStreamProvider(batchKey)` and
  uses `select(...)` to project only this game's update for the active merge
  mode.

This is the central place to preserve card behavior. If a card does not pass a
batch key and has no context list, it should not silently open a round/tour-wide
stream.

## Mobile Card/List Surfaces

The mobile repo has several wrappers. Keep them on shared batch keys.

### Event game list

File: `lib/screens/tour_detail/games_tour/widgets/games_list_view.dart`

- Builds a gameId -> `LiveGamesBatchKey` map for the list.
- Passes those keys down into wrappers.
- This is the main event "Games" tab path.

### Event match/group cards

Files:

- `lib/screens/tour_detail/games_tour/widgets/group_event_match_card.dart`
- `lib/screens/tour_detail/games_tour/widgets/group_event_games_card.dart`
- `lib/screens/tour_detail/games_tour/widgets/group_event_games_tour_content_body.dart`

These carry `liveBatchKeyByGameId` or derive a context key. Do not replace that
with per-card single-game streams.

### Generic game card wrappers

Files:

- `lib/screens/tour_detail/games_tour/widgets/game_card_wrapper/game_card_wrapper_widget.dart`
- `lib/screens/tour_detail/games_tour/widgets/game_card_wrapper/grid_game_card_wrapper_widget.dart`
- `lib/screens/tour_detail/games_tour/widgets/game_card_wrapper/board_game_card_wrapper_widget.dart`

These are generic card entry points. They should keep using
`liveContextBatchKeyForGame(...)` or an explicit `liveBatchKey`.

### For You

Files:

- `lib/screens/group_event/widget/for_you_games_widget.dart`
- `lib/providers/for_you_games_provider.dart`

For You uses explicit batch keys for displayed games and provider-side watching
only for games that `shouldSubscribeToLiveGame(...)`. It should not open streams
for finished-only panels.

### Countrymen / Favorites / Player Profile / Search

Files:

- `lib/screens/countrymen/tabs/countrymen_games_tab.dart`
- `lib/screens/countryman_games_screen.dart`
- `lib/screens/favorites/tabs/favorites_games_tab.dart`
- `lib/screens/favorites/player_games/favorites_combined_games_screen.dart`
- `lib/screens/player_profile/tabs/player_games_tab.dart`
- `lib/screens/library/widgets/live_gamebase_search_game_card.dart`

These surfaces must keep using shared context keys for mounted cards. Finished
and database-only games should remain display-only.

## Focused Game Screen / Latest Position Contract

File: `lib/screens/chessboard/chess_board_screen_new.dart`

On lifecycle resume, this screen invalidates:

- `gameUpdatesStreamProvider`
- `liveGameUpdateStreamProvider`
- `gameUpdatesBatchStreamProvider`

File: `lib/screens/chessboard/provider/chess_board_screen_provider_new.dart`

- listens to `gameUpdatesStreamProvider(game.gameId)` for ongoing games
- handles PGN/FEN/clock/status updates in `_handleGameStreamUpdate(...)`
- seeds from the cached stream value immediately when available

Do not batch the focused board stream. A user who taps a game card should get a
single-game stream for the opened game so `chess_board_screen_new.dart` always
matches the latest position for that game.

The card and board should never disagree for long:

- card surfaces merge row updates into `baseGameProvider`
- board surfaces seed/listen through `gameUpdatesStreamProvider(gameId)`
- resume invalidation prevents stale provider instances after app backgrounding

## Supabase / Performance Notes

If workers show fresh rows but the app still lags, inspect Supabase Realtime
logs before changing frontend behavior:

- `too_many_channels`
- `too_many_joins`
- `tenant_events`
- WebSocket disconnect/reconnect loops

Do not solve a frontend channel leak by only increasing dashboard limits. First
verify that mounted cards are sharing batch streams and finished cards are not
subscribed.

## Validation Already Run For The Realtime Changes

Mobile:

```bash
flutter analyze --no-pub lib/providers/for_you_games_provider.dart lib/screens/group_event/widget/for_you_games_widget.dart lib/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart lib/screens/tour_detail/games_tour/widgets/games_list_view.dart lib/screens/tour_detail/games_tour/widgets/group_event_match_card.dart test/live_game_card_provider_test.dart
flutter test --no-pub test/live_game_card_provider_test.dart test/for_you_games_provider_test.dart
flutter test --no-pub test/live_game_position_resolver_test.dart test/chess_board_live_fen_placeholder_test.dart
```

Latest doc/comment-only follow-up:

```bash
flutter analyze --no-pub lib/repository/supabase/game/game_stream_repository.dart
```

Desktop:

```bash
flutter analyze --no-pub lib/providers/for_you_games_provider.dart lib/screens/group_event/widget/for_you_games_widget.dart lib/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart lib/desktop/widgets/event_games_table.dart lib/desktop/panes/tournaments_pane.dart test/live_game_card_provider_test.dart test/desktop/event_games_table_test.dart
flutter test --no-pub test/live_game_card_provider_test.dart test/for_you_games_provider_test.dart
flutter test --no-pub test/desktop/event_games_table_test.dart --plain-name 'event rail uses shown game ids for realtime tournament rows'
flutter test --no-pub test/chess_board_live_fen_placeholder_test.dart test/pgn_clock_parsing_test.dart
```

Known unrelated desktop issue:

- Full `test/desktop/event_games_table_test.dart` has a standalone failure in
  "Shift click ranges from the active event game across rounds" around line 985.
  The realtime-specific event rail test passes.

## Follow-up Audit Checklist

Use these searches before changing anything:

```bash
rg -n "watchLiveGame\\(" lib/screens lib/providers
rg -n "gameUpdatesStreamProvider\\(" lib/screens lib/providers
rg -n "gameUpdatesBatchStreamProvider|LiveGamesBatchKey\\(" lib/screens lib/providers test
rg -n "implicit_round|implicit_tour|roundId: game.roundId|tourId: game.tourId" lib test
```

For every mobile surface:

- card/list context: shared `LiveGamesBatchKey`
- focused board: `gameUpdatesStreamProvider(gameId)`
- finished games: no card-owned realtime stream
- mixed live/finished lists: live games update, finished games remain stable
- scroll/pagination: no per-card channel storms during fast scrolling
- game card tap: opened board position must match the latest card position
- round transition: newly live games appear from the fresh row stream, not only
  cyclic backfill

Manual checks worth doing:

- mobile event view "Games" tab
- mobile card tap into `chess_board_screen_new.dart`
- mobile For You event panels
- mobile Countrymen
- mobile Favorites
- mobile player profile games
- fast scroll through mixed live/finished game lists
- a quick community event round transition where the next round starts seconds
  after the previous round finishes

The desired result: when Supabase emits a changed `games` row, every mounted card
for that game and the opened game screen for that game should show the same
latest PGN/FEN/clock/status without waiting for cyclic backfill.
