import 'dart:async';

import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/chessboard/provider/game_pgn_stream_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final shouldStreamProvider = StateProvider((ref) => true);
final gamesTourProvider = AutoDisposeStateNotifierProvider.family<
  GamesTourNotifier,
  AsyncValue<List<Games>>,
  String
>((ref, tourId) => GamesTourNotifier(ref: ref, tourId: tourId));

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
        _setupGameStreamListeners(state.valueOrNull ?? []);
        _startPeriodicRefresh();
      } else {
        _cleanupStreamSubscriptions();
        _stopPeriodicRefresh();
      }
    });
  }

  final Ref ref;
  final String tourId;
  final Map<String, List<ProviderSubscription>> _streamSubscriptions = {};
  ProviderSubscription? _shouldStreamListener;
  Timer? _refreshTimer;

  Future<void> _loadInitialGames() async {
    try {
      final gamesLocalStorageProvider = ref.read(gamesLocalStorage);
      final games = await gamesLocalStorageProvider.fetchAndSaveGames(tourId);

      if (mounted) {
        state = AsyncValue.data(games);

        // Only set up listeners if streaming is enabled
        final shouldStream = ref.read(shouldStreamProvider);
        if (shouldStream) {
          _setupGameStreamListeners(games);
          _startPeriodicRefresh();

          // Do an immediate check for new games (don't wait 30 seconds)
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

    // Check for new rounds/games every 10 seconds (more frequent)
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

      // Fetch fresh games from the server (bypassing cache)
      final gamesLocalStorageProvider = ref.read(gamesLocalStorage);
      final freshGames = await gamesLocalStorageProvider.fetchAndSaveGames(
        tourId,
      );

      // Check if there are new games OR if games count changed
      if (freshGames.length != currentGames.length) {
        debugPrint(
          '🔥 GamesTourNotifier: Detected game count change! Current: ${currentGames.length}, Fresh: ${freshGames.length}',
        );

        if (freshGames.length > currentGames.length) {
          // Find the new games
          final currentGameIds = currentGames.map((g) => g.id).toSet();
          final newGames =
              freshGames.where((g) => !currentGameIds.contains(g.id)).toList();

          debugPrint(
            '🔥 GamesTourNotifier: New games: ${newGames.map((g) => g.roundSlug).join(", ")}',
          );

          // Set up stream listeners for new games
          for (final game in newGames) {
            if (game.status == "*") {
              _listenToGameStreams(game.id, listenToMoves: true);
            } else {
              _listenToGameStreams(game.id, listenToMoves: false);
            }
          }
        }

        // Always update state with fresh games
        if (mounted) {
          state = AsyncValue.data(freshGames);
        }
      }
    } catch (error, _) {
      debugPrint('🔥 GamesTourNotifier: Error checking for new games: $error');
    }
  }

  void _setupGameStreamListeners(List<Games> games) {
    // Clean up existing subscriptions
    _cleanupStreamSubscriptions();

    // Only proceed if streaming is enabled
    final shouldStream = ref.read(shouldStreamProvider);
    if (!shouldStream) {
      debugPrint('🔥 GamesTourNotifier: Streaming is disabled, skipping setup');
      return;
    }

    debugPrint(
      '🔥 GamesTourNotifier: Setting up stream listeners for ${games.length} games',
    );

    // Set up listeners for ALL games
    // - For ongoing games: listen to FEN, moves, clocks
    // - For all games (including finished): listen to status changes
    for (final game in games) {
      debugPrint(
        '🔥 GamesTourNotifier: Game ${game.id} status: ${game.status}',
      );
      if (game.status == "*") {
        debugPrint(
          '🔥 GamesTourNotifier: Setting up streams for ongoing game ${game.id}',
        );
        _listenToGameStreams(game.id, listenToMoves: true);
      } else {
        // For finished games, only listen to status in case it gets corrected
        debugPrint(
          '🔥 GamesTourNotifier: Setting up status stream for finished game ${game.id}',
        );
        _listenToGameStreams(game.id, listenToMoves: false);
      }
    }
  }

  void _listenToGameStreams(String gameId, {required bool listenToMoves}) {
    final subscriptions = <ProviderSubscription>[];

    // CONSOLIDATED: Use ONE stream for ALL game data (reduces channels by 83%)
    // This single stream provides: fen, last_move, clocks, status, last_move_time
    debugPrint(
      '🔥 GamesTourNotifier: Setting up CONSOLIDATED stream for game $gameId (listenToMoves: $listenToMoves)',
    );

    final gameUpdatesSubscription = ref.listen<
      AsyncValue<Map<String, dynamic>?>
    >(gameUpdatesStreamProvider(gameId), (previous, next) {
      next.whenData((gameData) {
        if (gameData == null) return;

        final fen = gameData['fen'] as String?;
        final fenPreviewLength =
            fen == null ? 0 : (fen.length < 20 ? fen.length : 20);
        final fenPreview =
            fen == null ? '' : fen.substring(0, fenPreviewLength);
        final fenSuffix =
            fen != null && fen.length > fenPreviewLength ? '...' : '';
        debugPrint(
          '🔥 GamesTourNotifier: Stream update for game $gameId - status: ${gameData['status']}, fen: ${fenPreview.isNotEmpty ? fenPreview + fenSuffix : '—'}',
        );

        // Always update status (for all games, even finished ones)
        final status = gameData['status'] as String?;

        if (listenToMoves) {
          // For ongoing games: update everything
          _updateGameData(
            gameId,
            fen: gameData['fen'] as String?,
            lastMove: gameData['last_move'] as String?,
            whiteClockSeconds: (gameData['last_clock_white'] as num?)?.round(),
            blackClockSeconds: (gameData['last_clock_black'] as num?)?.round(),
            lastMoveTime:
                gameData['last_move_time'] != null
                    ? DateTime.tryParse(gameData['last_move_time'] as String)
                    : null,
            status: status,
          );
        } else {
          // For finished games: only update status
          if (status != null) {
            _updateGameData(gameId, status: status);
          }
        }
      });
    });
    subscriptions.add(gameUpdatesSubscription);

    // Store subscriptions for cleanup
    _streamSubscriptions[gameId] = subscriptions;
  }

  void _updateGameData(
    String gameId, {
    String? fen,
    String? lastMove,
    int? whiteClockSeconds,
    int? blackClockSeconds,
    DateTime? lastMoveTime,
    String? status,
  }) {
    final currentGames = state.valueOrNull;
    if (currentGames == null) return;

    // Check if any actual changes occurred
    bool hasChanges = false;
    Games? targetGame;

    for (final game in currentGames) {
      if (game.id == gameId) {
        targetGame = game;
        break;
      }
    }

    if (targetGame != null) {
      // Only update if values actually changed
      hasChanges =
          (fen != null && fen != targetGame.fen) ||
          (lastMove != null && lastMove != targetGame.lastMove) ||
          (whiteClockSeconds != null &&
              whiteClockSeconds != targetGame.lastClockWhite) ||
          (blackClockSeconds != null &&
              blackClockSeconds != targetGame.lastClockBlack) ||
          (lastMoveTime != null && lastMoveTime != targetGame.lastMoveTime) ||
          (status != null && status != targetGame.status);
    }

    if (!hasChanges) {
      // No actual changes, skip update to prevent unnecessary rebuilds
      return;
    }

    final updatedGames =
        currentGames.map((game) {
          if (game.id == gameId) {
            return game.copyWith(
              fen: fen ?? game.fen,
              lastMove: lastMove ?? game.lastMove,
              lastClockWhite: whiteClockSeconds ?? game.lastClockWhite,
              lastClockBlack: blackClockSeconds ?? game.lastClockBlack,
              lastMoveTime: lastMoveTime ?? game.lastMoveTime,
              status: status ?? game.status,
            );
          }
          return game;
        }).toList();

    if (mounted) {
      state = AsyncValue.data(updatedGames);
    }
  }

  void _cleanupStreamSubscriptions() {
    debugPrint(
      '🔥 GamesTourNotifier: Cleaning up ${_streamSubscriptions.length} stream subscriptions',
    );
    for (final subscriptions in _streamSubscriptions.values) {
      for (final subscription in subscriptions) {
        subscription.close();
      }
    }
    _streamSubscriptions.clear();
  }

  Future<void> refreshGames() async {
    await _loadInitialGames();
  }

  @override
  void dispose() {
    _stopPeriodicRefresh();
    _cleanupStreamSubscriptions();
    _shouldStreamListener?.close();
    super.dispose();
  }
}
