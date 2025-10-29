import 'dart:async';

import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_fen_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_last_move_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_clock_stream_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_status_stream_provider.dart';
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

    print('🔥 GamesTourNotifier: Started periodic refresh (10s interval) for tour $tourId');
  }

  void _stopPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    print('🔥 GamesTourNotifier: Stopped periodic refresh for tour $tourId');
  }

  Future<void> _checkForNewGames() async {
    try {
      final currentGames = state.valueOrNull;
      if (currentGames == null) return;

      // Fetch fresh games from the server (bypassing cache)
      final gamesLocalStorageProvider = ref.read(gamesLocalStorage);
      final freshGames = await gamesLocalStorageProvider.fetchAndSaveGames(tourId);

      // Check if there are new games OR if games count changed
      if (freshGames.length != currentGames.length) {
        print('🔥 GamesTourNotifier: Detected game count change! Current: ${currentGames.length}, Fresh: ${freshGames.length}');

        if (freshGames.length > currentGames.length) {
          // Find the new games
          final currentGameIds = currentGames.map((g) => g.id).toSet();
          final newGames = freshGames.where((g) => !currentGameIds.contains(g.id)).toList();

          print('🔥 GamesTourNotifier: New games: ${newGames.map((g) => g.roundSlug).join(", ")}');

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
      print('🔥 GamesTourNotifier: Error checking for new games: $error');
    }
  }

  void _setupGameStreamListeners(List<Games> games) {
    // Clean up existing subscriptions
    _cleanupStreamSubscriptions();

    // Only proceed if streaming is enabled
    final shouldStream = ref.read(shouldStreamProvider);
    if (!shouldStream) {
      print('🔥 GamesTourNotifier: Streaming is disabled, skipping setup');
      return;
    }

    print('🔥 GamesTourNotifier: Setting up stream listeners for ${games.length} games');

    // Set up listeners for ALL games
    // - For ongoing games: listen to FEN, moves, clocks
    // - For all games (including finished): listen to status changes
    for (final game in games) {
      print('🔥 GamesTourNotifier: Game ${game.id} status: ${game.status}');
      if (game.status == "*") {
        print('🔥 GamesTourNotifier: Setting up streams for ongoing game ${game.id}');
        _listenToGameStreams(game.id, listenToMoves: true);
      } else {
        // For finished games, only listen to status in case it gets corrected
        print('🔥 GamesTourNotifier: Setting up status stream for finished game ${game.id}');
        _listenToGameStreams(game.id, listenToMoves: false);
      }
    }
  }

  void _listenToGameStreams(String gameId, {required bool listenToMoves}) {
    final subscriptions = <ProviderSubscription>[];

    // ALWAYS listen to status changes (for all games, live or finished)
    final statusSubscription = ref.listen<AsyncValue<String?>>(
      gameStatusStreamProvider(gameId),
      (previous, next) {
        next.whenData((statusData) {
          if (statusData != null) {
            _updateGameData(gameId, status: statusData);
          }
        });
      },
    );
    subscriptions.add(statusSubscription);

    // Only listen to moves/clocks for ongoing games
    if (listenToMoves) {
      // Listen to FEN stream
      final fenSubscription = ref.listen<AsyncValue<String?>>(
        gameFenStreamProvider(gameId),
        (previous, next) {
          next.whenData((fenData) {
            if (fenData != null) {
              _updateGameData(gameId, fen: fenData);
            }
          });
        },
      );
      subscriptions.add(fenSubscription);

      // Listen to last move stream
      final lastMoveSubscription = ref.listen<AsyncValue<String?>>(
        gameLastMoveStreamProvider(gameId),
        (previous, next) {
          next.whenData((lastMoveData) {
            _updateGameData(gameId, lastMove: lastMoveData);
          });
        },
      );
      subscriptions.add(lastMoveSubscription);

      // Listen to white clock stream
      final whiteClockSubscription = ref.listen<AsyncValue<int?>>(
        gameWhiteClockStreamProvider(gameId),
        (previous, next) {
          next.whenData((whiteClockData) {
            _updateGameData(gameId, whiteClockSeconds: whiteClockData);
          });
        },
      );
      subscriptions.add(whiteClockSubscription);

      // Listen to black clock stream
      final blackClockSubscription = ref.listen<AsyncValue<int?>>(
        gameBlackClockStreamProvider(gameId),
        (previous, next) {
          next.whenData((blackClockData) {
            _updateGameData(gameId, blackClockSeconds: blackClockData);
          });
        },
      );
      subscriptions.add(blackClockSubscription);

      // Listen to last move time stream
      final lastMoveTimeSubscription = ref.listen<AsyncValue<DateTime?>>(
        gameLastMoveTimeStreamProvider(gameId),
        (previous, next) {
          next.whenData((lastMoveTimeData) {
            _updateGameData(gameId, lastMoveTime: lastMoveTimeData);
          });
        },
      );
      subscriptions.add(lastMoveTimeSubscription);
    }

    // Store subscriptions for cleanup
    _streamSubscriptions[gameId] = subscriptions;
  }

  void _updateGameData(String gameId, {
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
      hasChanges = (fen != null && fen != targetGame.fen) ||
                  (lastMove != null && lastMove != targetGame.lastMove) ||
                  (whiteClockSeconds != null && whiteClockSeconds != targetGame.lastClockWhite) ||
                  (blackClockSeconds != null && blackClockSeconds != targetGame.lastClockBlack) ||
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
    print('🔥 GamesTourNotifier: Cleaning up ${_streamSubscriptions.length} stream subscriptions');
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
