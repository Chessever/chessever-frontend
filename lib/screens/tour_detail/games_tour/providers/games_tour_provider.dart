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

  void _startPeriodicRefresh() {
    _stopPeriodicRefresh();

    // Check for new rounds/games every 10 seconds
    // This handles: new games, status changes, game completions
    // Realtime updates for visible games are handled by liveGameCardProvider
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      await _checkForNewGames();
    });

    debugPrint(
      '🔥 GamesTourNotifier: Started periodic refresh (10s interval) for tour $tourId',
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
    try {
      final currentGames = state.valueOrNull;
      if (currentGames == null) return;

      // Fetch fresh games from the server
      final gamesLocalStorageProvider = ref.read(gamesLocalStorage);
      final freshGames = await gamesLocalStorageProvider.fetchAndSaveGames(
        tourId,
      );

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

        if (_hasGameChanged(current, fresh)) {
          hasChanges = true;
        }

        mergedGames.add(_mergeGameSnapshots(current, fresh));
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
      debugPrint('🔥 GamesTourNotifier: Error checking for new games: $error');
    }
  }

  bool _hasGameChanged(Games current, Games fresh) {
    return current.status != fresh.status ||
        current.lastMove != fresh.lastMove ||
        current.fen != fresh.fen ||
        current.lastMoveTime != fresh.lastMoveTime ||
        current.lastClockWhite != fresh.lastClockWhite ||
        current.lastClockBlack != fresh.lastClockBlack;
  }

  Games _mergeGameSnapshots(Games current, Games fresh) {
    final currentMoveTime = current.lastMoveTime;
    final freshMoveTime = fresh.lastMoveTime;
    final useFreshMove =
        currentMoveTime == null ||
        (freshMoveTime != null && freshMoveTime.isAfter(currentMoveTime));

    return fresh.copyWith(
      fen: useFreshMove ? fresh.fen : current.fen,
      lastMove: useFreshMove ? fresh.lastMove : current.lastMove,
      lastMoveTime: useFreshMove ? freshMoveTime : currentMoveTime,
      lastClockWhite:
          useFreshMove ? fresh.lastClockWhite : current.lastClockWhite,
      lastClockBlack:
          useFreshMove ? fresh.lastClockBlack : current.lastClockBlack,
      pgn: useFreshMove ? fresh.pgn : current.pgn,
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
