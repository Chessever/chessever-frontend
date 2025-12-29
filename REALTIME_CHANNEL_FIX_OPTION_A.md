# Supabase Realtime Channel Fix (Option A) - REVERTED

> **Status:** REVERTED
> **Date Implemented:** December 2024
> **Date Reverted:** December 2024
> **Reason:** Slow performance - batching approach caused delays in updates

---

## Why It Was Reverted

The batched channel approach (SharedGameStreamManager) was causing slow/delayed updates.
Reverted to individual streams per game with proper Riverpod `.autoDispose` behavior.

---

## Current Approach (Individual Streams)

Each game card now creates its own individual Realtime channel:

```dart
// One channel per game - auto-disposes when scrolled out of view
final gameUpdatesStreamProvider =
    AutoDisposeStreamProvider.family<Map<String, dynamic>?, String>((
  ref,
  gameId,
) {
  return ref.read(gameStreamRepositoryProvider).subscribeToGameUpdates(gameId);
});
```

**Benefits:**
- Instant updates (no batching delay)
- Clean auto-dispose when widgets scroll out of view
- Simpler code, easier to debug

**Trade-off:**
- More Realtime channels (one per visible game)
- May hit channel rate limits with 50+ games visible at once

---

## Files Modified (Reverted)

### 1. `lib/repository/supabase/game/game_stream_repository.dart`
- Removed `SharedGameStreamManager` class
- Removed `sharedGameStreamManagerProvider`
- Kept `GameStreamRepository` with individual stream methods

### 2. `lib/screens/chessboard/provider/game_pgn_stream_provider.dart`
- `gameUpdatesStreamProvider` now uses individual streams directly
- No more shared manager dependency

### 3. `lib/screens/tour_detail/games_tour/widgets/game_card_wrapper/live_game_card_provider.dart`
- Removed `ref.keepAlive()` to allow proper auto-dispose
- Streams clean up when game cards scroll out of view

---

## If Rate Limits Become an Issue Again

Consider:
1. **Upgrade Supabase plan** for higher channel limits
2. **Viewport-based streaming** - only stream games currently visible on screen
3. **Hybrid polling** - poll for updates instead of streaming for less critical games

---

*Reverted to prioritize update speed over channel efficiency.*
