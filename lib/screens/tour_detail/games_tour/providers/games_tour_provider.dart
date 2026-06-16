import 'dart:async';

import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final shouldStreamProvider = StateProvider((ref) => true);
final gamesTourProvider = AutoDisposeStateNotifierProvider.family<
  GamesTourNotifier,
  AsyncValue<List<Games>>,
  String
>((ref, tourId) => GamesTourNotifier(ref: ref, tourId: tourId));

/// Notifier that manages the list of games for a tournament.
///
/// **Architecture (Post-Revert):**
/// - This provider holds ALL games in memory as a list
/// - It does NOT maintain individual Supabase Realtime streams per game
/// - Instead, it uses periodic polling (every 10 seconds) to fetch updates
/// - Individual game cards use `liveGameCardProvider` with `.autoDispose`
///   to get realtime updates only for VISIBLE games
/// - When a game card scrolls out of view, its stream is disposed
///
/// This approach minimizes Supabase Realtime connections while still
/// providing instant updates for games the user is actively viewing.
class GamesTourNotifier extends StateNotifier<AsyncValue<List<Games>>> {
  GamesTourNotifier({required this.ref, required this.tourId})
    : super(const AsyncValue.loading()) {
    _loadInitialGames();

    // Listen to shouldStreamProvider changes
    _shouldStreamListener = ref.listen<bool>(shouldStreamProvider, (
      previous,
      next,
    ) {
      if (next) {
        _startPeriodicRefresh();
      } else {
        _stopPeriodicRefresh();
      }
    });
  }

  final Ref ref;
  final String tourId;
  ProviderSubscription? _shouldStreamListener;
  Timer? _refreshTimer;

  Future<void> _loadInitialGames() async {
    try {
      final gamesLocalStorageProvider = ref.read(gamesLocalStorage);
      final games = await gamesLocalStorageProvider.fetchAndSaveGames(tourId);

      if (mounted) {
        state = AsyncValue.data(games);

        // Only start periodic refresh if streaming is enabled
        final shouldStream = ref.read(shouldStreamProvider);
        if (shouldStream) {
          _startPeriodicRefresh();

          // Do an immediate check for new games (don't wait 10 seconds)
          Future.delayed(const Duration(seconds: 2), () {
            if (!mounted) return;
            _checkForNewGames();
          });
        }
      }
    } catch (error, stackTrace) {
      if (mounted) {
        state = AsyncValue.error(error, stackTrace);
      }
    }
  }

  // Per-MOVE updates for visible games come from batched Supabase Realtime
  // channels (see liveGameCardProvider / LiveGamesBatchKey), NOT this poll.
  // This timer is only a slow safety net for set-level changes the per-game
  // streams don't cover: newly added games, round rollovers, completions that
  // arrive while a card is off-screen. Keep the historical 10s cadence, while
  // per-move updates still come from realtime instead of this poll.
  static const Duration _safetyNetInterval = Duration(seconds: 10);

  void _startPeriodicRefresh() {
    _stopPeriodicRefresh();

    _refreshTimer = Timer.periodic(_safetyNetInterval, (_) async {
      await _checkForNewGames();
    });

    debugPrint(
      '🔥 GamesTourNotifier: Started safety-net refresh '
      '(${_safetyNetInterval.inSeconds}s interval) for tour $tourId',
    );
  }

  void _stopPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    debugPrint(
      '🔥 GamesTourNotifier: Stopped periodic refresh for tour $tourId',
    );
  }

  Future<void> _checkForNewGames() async {
    if (!mounted) return;
    try {
      final currentGames = state.valueOrNull;
      if (currentGames == null) return;

      // Fetch fresh games from the server
      final gamesLocalStorageProvider = ref.read(gamesLocalStorage);
      final freshGames = await gamesLocalStorageProvider.fetchAndSaveGames(
        tourId,
      );
      if (!mounted) return;

      final currentById = {for (final game in currentGames) game.id: game};
      final freshIds = <String>{};
      bool hasChanges = freshGames.length != currentGames.length;
      final mergedGames = <Games>[];

      if (freshGames.length != currentGames.length) {
        debugPrint(
          '🔥 GamesTourNotifier: Detected game count change! Current: ${currentGames.length}, Fresh: ${freshGames.length}',
        );
      }

      for (final fresh in freshGames) {
        freshIds.add(fresh.id);
        final current = currentById[fresh.id];

        if (current == null) {
          // New game added
          hasChanges = true;
          mergedGames.add(fresh);
          continue;
        }

        if (_hasSafetyNetChange(current, fresh)) {
          hasChanges = true;
        }

        mergedGames.add(_mergeSafetyNetSnapshot(current, fresh));
      }

      // Check for removed games
      for (final removedId in currentById.keys) {
        if (!freshIds.contains(removedId)) {
          hasChanges = true;
        }
      }

      if (hasChanges && mounted) {
        state = AsyncValue.data(mergedGames);
      }
    } catch (error, _) {
      // Suppress noise from races where the notifier is disposed mid-await.
      if (!mounted) return;
      debugPrint('🔥 GamesTourNotifier: Error checking for new games: $error');
    }
  }

  bool _hasSafetyNetChange(Games current, Games fresh) {
    // Per-move fields (FEN/PGN/last_move/clocks) are intentionally excluded
    // here. Visible cards receive those through batched realtime streams; if
    // the poll writes them into the parent list every 10s, the whole Games tab
    // rebuilds and can disturb scrolling. The poll only owns set-level changes
    // plus status/round movement for off-screen cards.
    return (fresh.status != null && current.status != fresh.status) ||
        current.roundId != fresh.roundId ||
        current.roundSlug != fresh.roundSlug;
  }

  Games _mergeSafetyNetSnapshot(Games current, Games fresh) {
    return current.copyWith(
      roundId: fresh.roundId,
      roundSlug: fresh.roundSlug,
      status: fresh.status ?? current.status,
    );
  }

  Future<void> refreshGames() async {
    await _loadInitialGames();
  }

  @override
  void dispose() {
    _stopPeriodicRefresh();
    _shouldStreamListener?.close();
    super.dispose();
  }
}
