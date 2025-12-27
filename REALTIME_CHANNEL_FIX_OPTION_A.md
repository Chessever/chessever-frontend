# Supabase Realtime Channel Rate Limit Fix (Option A)

> **Status:** IMPLEMENTED
> **Date:** December 2024
> **Issue:** "ChannelRateLimitReached: Too many channels"

---

## The Problem

When displaying game cards in a grid/list view, the app was hitting Supabase's channel rate limit:

```
ChannelRateLimitReached: Too many channels
```

**Symptoms:**
- Chess boards not displaying immediately when switching between grid/list views
- Delays in loading game cards
- Console errors about too many channels

---

## Root Cause

Each game card was creating its **own Realtime channel**:

```dart
// BEFORE: One channel PER GAME
Supabase.instance.client
    .from('games')
    .stream(primaryKey: ['id'])
    .eq('id', gameId)  // Creates individual channel for each game!
```

**Impact:**
```
50 games displayed = 50 Realtime channels = Rate limit hit!
100 games displayed = 100 Realtime channels = Severe throttling!
```

### Call Chain That Caused the Issue

```
GameCardWrapperWidget
    ↓
liveGameCardProvider((gameId, baseGame))
    ↓
gameUpdatesStreamProvider(gameId)
    ↓
gameStreamRepository.subscribeToGameUpdates(gameId)
    ↓
.stream(primaryKey: ['id']).eq('id', gameId)  ← PROBLEM: Individual channel per game
```

---

## The Solution (Option A)

Use Supabase's `inFilter` to batch multiple game subscriptions into **shared channels**:

```dart
// AFTER: ONE channel for up to 100 games
.onPostgresChanges(
  filter: PostgresChangeFilter(
    type: PostgresChangeFilterType.inFilter,
    column: 'id',
    value: gameIds,  // Up to 100 game IDs per channel
  ),
  callback: (payload) {
    // Route update to correct game card
  },
)
```

**Result:**
```
50 games  → 1 channel   (instead of 50)
150 games → 2 channels  (instead of 150)
500 games → 5 channels  (instead of 500)
```

---

## Files Modified

### 1. `lib/repository/supabase/game/game_stream_repository.dart`

Added `SharedGameStreamManager` class that:
- Batches game subscriptions into shared channels (max 100 games per channel)
- Routes incoming updates to the correct game card
- Debounces channel rebuilds during scrolling (100ms)
- Supports unlimited games via automatic batching

```dart
class SharedGameStreamManager {
  static const int _maxGamesPerChannel = 100;

  final SupabaseClient _client;
  final List<RealtimeChannel> _channels = [];
  final Set<String> _subscribedGameIds = {};
  final Map<String, StreamController<Map<String, dynamic>>> _gameControllers = {};

  Stream<Map<String, dynamic>?> getGameStream(String gameId) { ... }
  void removeGameStream(String gameId) { ... }
  void _rebuildChannels() { ... }  // Batches into groups of 100
}
```

### 2. `lib/screens/chessboard/provider/game_pgn_stream_provider.dart`

Updated `gameUpdatesStreamProvider` to use the shared manager:

```dart
final gameUpdatesStreamProvider =
    AutoDisposeStreamProvider.family<Map<String, dynamic>?, String>((
  ref,
  gameId,
) {
  final manager = ref.watch(sharedGameStreamManagerProvider);

  ref.onDispose(() {
    manager.removeGameStream(gameId);
  });

  return manager.getGameStream(gameId);
});
```

### 3. `lib/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart`

Simplified the provider to avoid Riverpod state modification errors:

```dart
final liveGameCardProvider =
    AutoDisposeProvider.family<GamesTourModel, LiveGameCardParams>((
  ref,
  params,
) {
  final (:gameId, :baseGame) = params;

  if (baseGame.gameStatus.isFinished) {
    return baseGame;
  }

  ref.keepAlive();
  final streamAsync = ref.watch(gameUpdatesStreamProvider(gameId));

  return streamAsync.when(
    data: (gameData) => /* merge with baseGame */,
    loading: () => baseGame,
    error: (_, __) => baseGame,
  );
});
```

---

## How It Works Now

```
┌─────────────────────────────────────────────────────────────┐
│  User views tournament with 150 games                       │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  SharedGameStreamManager collects all 150 game IDs          │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  Creates 2 channels:                                        │
│  - Channel 1: games 1-100 (inFilter)                        │
│  - Channel 2: games 101-150 (inFilter)                      │
└─────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────┐
│  When game #75 updates:                                     │
│  - Channel 1 receives the update                            │
│  - Callback routes to gameControllers['game-75']            │
│  - Game card #75 re-renders with new data                   │
└─────────────────────────────────────────────────────────────┘
```

---

## Console Output

You'll now see logs like:

```
🔄 SharedGameStreamManager: Subscribing to 150 games using 2 channel(s) (was 150 channels before fix)
✅ SharedGameStreamManager: Channel 0 (SUBSCRIBED) - 100 games
✅ SharedGameStreamManager: Channel 1 (SUBSCRIBED) - 50 games
```

---

## Benefits

| Metric | Before | After |
|--------|--------|-------|
| Channels for 50 games | 50 | 1 |
| Channels for 500 games | 500 | 5 |
| Rate limit errors | Yes | No |
| Board display delay | 2-5 seconds | Instant |
| Live streaming | Works | Works (unchanged) |

---

## Scalability

Option A is good for:
- **Thousands of live games** - handled via batching
- **Up to ~500 concurrent users** - RLS checks are simple (`USING (true)`)

For **thousands of concurrent users**, see `REALTIME_OPTION_B_SCALABILITY.md` for the database trigger approach.

---

## Bug Fix: Riverpod State Modification Error

During implementation, we encountered:

```
Providers are not allowed to modify other providers during their initialization.
```

**Cause:** The original implementation tried to update a cache provider inside another provider's build method.

**Fix:** Simplified to a single provider that directly watches the stream, removing the unnecessary caching layer.

---

## Related Files

- `REALTIME_OPTION_B_SCALABILITY.md` - Future scalability guide for thousands of users
- `lib/repository/supabase/game/game_stream_repository.dart` - Core implementation
- `lib/screens/chessboard/provider/game_pgn_stream_provider.dart` - Provider integration

---

*This fix was implemented to solve immediate rate limiting issues while maintaining full live streaming functionality.*
