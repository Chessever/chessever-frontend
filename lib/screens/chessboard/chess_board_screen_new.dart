import 'dart:async';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:chessever2/providers/board_settings_provider.dart';
import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/move_impact_analyzer.dart';
import 'package:chessever2/screens/chessboard/analysis/simple_move_impact.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
// DISABLED: Move annotation overlay (requires move impact analysis)
// import 'package:chessever2/screens/chessboard/widgets/move_annotation_overlay.dart';
import 'package:chessever2/screens/chessboard/widgets/share_game_card_overlay.dart';
import 'package:chessever2/screens/chessboard/chess_board_settings_page.dart';
import 'package:chessever2/screens/group_event/providers/countryman_games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/utils/audio_player_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/string_utils.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/divider_widget.dart';
import 'package:flutter_svg/svg.dart';

/// Cached move impact results keyed by game id/signature to avoid recomputation
class CachedMoveImpact {
  final String signature;
  final Map<int, MoveImpactAnalysis> impacts;

  const CachedMoveImpact({required this.signature, required this.impacts});
}

class MoveImpactCacheNotifier
    extends StateNotifier<Map<String, CachedMoveImpact>> {
  MoveImpactCacheNotifier() : super(<String, CachedMoveImpact>{});

  CachedMoveImpact? lookup(String gameId) => state[gameId];

  void store(String gameId, CachedMoveImpact cached) {
    state = {...state, gameId: cached};
  }

  void invalidate(String gameId) {
    if (!state.containsKey(gameId)) return;
    final copy = {...state};
    copy.remove(gameId);
    state = copy;
  }
}

final moveImpactCacheProvider = StateNotifierProvider<
  MoveImpactCacheNotifier,
  Map<String, CachedMoveImpact>
>((ref) => MoveImpactCacheNotifier());

/// LAZY move impact provider - calculates impact for a SINGLE move only when needed
/// This is the NEW approach that doesn't block the eval bar
/// Returns the impact analysis for a specific move index in a game
class LazyMoveImpactParams {
  final ChessBoardProviderParams boardParams;
  final int moveIndex; // Which move to calculate impact for

  const LazyMoveImpactParams({
    required this.boardParams,
    required this.moveIndex,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LazyMoveImpactParams &&
          boardParams == other.boardParams &&
          moveIndex == other.moveIndex;

  @override
  int get hashCode => boardParams.hashCode ^ moveIndex.hashCode;
}

final lazyMoveImpactProvider = FutureProvider.family
    .autoDispose<MoveImpactAnalysis?, LazyMoveImpactParams>((
      ref,
      params,
    ) async {
      // Get the board state to access position FENs
      final boardStateAsync = ref.watch(
        chessBoardScreenProviderNew(params.boardParams),
      );
      final boardState = boardStateAsync.valueOrNull;
      if (boardState == null) {
        return null;
      }

      final allMoves = boardState.allMoves;
      final moveSans = boardState.moveSans;
      final startingPosition = boardState.startingPosition;

      if (allMoves.isEmpty ||
          moveSans.isEmpty ||
          params.moveIndex >= moveSans.length) {
        return null;
      }

      // Generate position FENs for this specific move only
      final fensParams = PositionFensParams(
        allMoves: allMoves,
        startingPosition: startingPosition,
        gameId: params.boardParams.game.gameId,
      );
      final positionFens = ref.watch(positionFensProvider(fensParams));

      if (params.moveIndex >= positionFens.length - 1) {
        return null; // Invalid move index
      }

      // Create single move params
      final singleParams = SingleMoveImpactParams(
        fenBefore: positionFens[params.moveIndex],
        fenAfter: positionFens[params.moveIndex + 1],
        moveSan: moveSans[params.moveIndex],
        moveIndex: params.moveIndex,
        gameId: params.boardParams.game.gameId,
      );

      // Use the new lazy provider that doesn't block eval bar
      return ref.watch(singleMoveImpactProvider(singleParams).future);
    });

/// DEPRECATED: Provider that calculates move impacts - BULK ANALYSIS
/// This approach blocks the eval bar and should not be used
/// Use lazyMoveImpactProvider instead for individual moves
final gameMovesImpactProvider = FutureProvider.family.autoDispose<
  Map<int, MoveImpactAnalysis>?,
  ChessBoardProviderParams
>((ref, params) async {
  debugPrint(
    '🎨 gameMovesImpactProvider: START for game ${params.game.gameId}',
  );

  final link = ref.keepAlive();
  Timer? cleanupTimer;

  ref.onCancel(() {
    cleanupTimer = Timer(const Duration(seconds: 45), () {
      debugPrint(
        '🎨 gameMovesImpactProvider: releasing keepAlive for ${params.game.gameId}',
      );
      link.close();
    });
  });

  ref.onResume(() {
    cleanupTimer?.cancel();
    cleanupTimer = null;
  });

  ref.onDispose(() {
    cleanupTimer?.cancel();
  });

  // Use .select() to watch ONLY the moves data, not the entire state
  final allMoves = ref.watch(
    chessBoardScreenProviderNew(
      params,
    ).select((state) => state.valueOrNull?.allMoves),
  );
  final moveSans = ref.watch(
    chessBoardScreenProviderNew(
      params,
    ).select((state) => state.valueOrNull?.moveSans),
  );
  final startingPosition = ref.watch(
    chessBoardScreenProviderNew(
      params,
    ).select((state) => state.valueOrNull?.startingPosition),
  );

  if (allMoves == null || allMoves.isEmpty || moveSans == null) {
    debugPrint('🎨 gameMovesImpactProvider: NULL - no moves yet');
    return null;
  }

  debugPrint(
    '🎨 gameMovesImpactProvider: Got ${allMoves.length} moves, ${moveSans.length} SANs',
  );

  final cacheSignature = '${moveSans.length}:${moveSans.join('|')}';
  final cachedImpact = ref.read(moveImpactCacheProvider)[params.game.gameId];
  if (cachedImpact != null && cachedImpact.signature == cacheSignature) {
    debugPrint(
      '🎨 gameMovesImpactProvider: Using cached impacts for ${params.game.gameId}',
    );
    return cachedImpact.impacts;
  }

  // Generate position FENs (starting position + after each move)
  final fensParams = PositionFensParams(
    allMoves: allMoves,
    startingPosition: startingPosition,
    gameId: params.game.gameId,
  );
  final positionFens = ref.watch(positionFensProvider(fensParams));
  debugPrint(
    '🎨 gameMovesImpactProvider: Generated ${positionFens.length} position FENs',
  );

  // Determine which moves are white's
  final isWhiteMoves = List.generate(
    allMoves.length,
    (i) => i % 2 == 0, // Even indices = white's moves
  );

  // Use COMPREHENSIVE impact provider that analyzes alternatives
  final simpleParams = SimpleMoveImpactParams(
    positionFens: positionFens,
    isWhiteMoves: isWhiteMoves,
    moveSans: moveSans,
    gameId: params.game.gameId,
  );

  debugPrint('🎨 gameMovesImpactProvider: Calling simpleMoveImpactProvider...');
  final impacts = await ref.watch(
    simpleMoveImpactProvider(simpleParams).future,
  );
  debugPrint(
    '🎨 gameMovesImpactProvider: COMPLETE - got ${impacts.length} impacts',
  );

  ref
      .read(moveImpactCacheProvider.notifier)
      .store(
        params.game.gameId,
        CachedMoveImpact(
          signature: cacheSignature,
          impacts: Map.unmodifiable(impacts),
        ),
      );
  return impacts;
});

// Helper function to get move highlight color
Color getLastMoveHighlightColor(ChessBoardStateNew state) {
  if (state.currentMoveIndex < 0) return kPrimaryColor;

  // Determine if the current move (last move played) was by white or black
  // Move index 0 = white's first move, 1 = black's first move, etc.
  final isWhiteMove = state.currentMoveIndex % 2 == 0;

  return isWhiteMove ? kPrimaryColor : kChessBlackMoveColor;
}

// Helper function to get move highlight color for analysis mode
Color getAnalysisLastMoveHighlightColor(ChessBoardStateNew state) {
  if (state.analysisState.lastMove == null) return kPrimaryColor;

  // If it's black's turn, white made the last move, and vice versa.
  final isWhiteMove = state.analysisState.position.turn == Side.black;
  return isWhiteMove ? kPrimaryColor : kChessBlackMoveColor;
}

class ChessBoardScreenNew extends ConsumerStatefulWidget {
  final int currentIndex;
  final List<GamesTourModel> games;

  const ChessBoardScreenNew({
    required this.currentIndex,
    required this.games,
    super.key,
  });

  @override
  ConsumerState<ChessBoardScreenNew> createState() => _ChessBoardScreenState();
}

class _ChessBoardScreenState extends ConsumerState<ChessBoardScreenNew> {
  late PageController _pageController;
  bool analysisMode = false;
  int? _lastViewedIndex;
  int _currentPageIndex = 0;

  GamesTourModel _resolveGameForIndex(int index) {
    if (widget.games.isEmpty) {
      throw StateError('No games available to resolve');
    }

    final safeIndex = index.clamp(0, widget.games.length - 1);
    final fallbackGame = widget.games[safeIndex];
    final view = ref.read(chessboardViewFromProviderNew);

    final AsyncValue<GamesScreenModel> gamesAsync =
        view == ChessboardView.tour
            ? ref.read(gamesTourScreenProvider)
            : ref.read(countrymanGamesTourScreenProvider);

    final liveGames = gamesAsync.valueOrNull?.gamesTourModels;
    if (liveGames == null || liveGames.isEmpty) {
      return fallbackGame;
    }

    for (final game in liveGames) {
      if (game.gameId == fallbackGame.gameId) {
        return game;
      }
    }

    return fallbackGame;
  }

  @override
  void initState() {
    super.initState();
    // Defensive: Ensure currentIndex is within bounds of games list
    final safeIndex = widget.currentIndex.clamp(0, widget.games.length - 1);
    _pageController = PageController(initialPage: safeIndex);
    _currentPageIndex = safeIndex;

    // Note: We'll enable streaming in didChangeDependencies when ref is available
  }

  @override
  void didUpdateWidget(covariant ChessBoardScreenNew oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Set the initial visible page index - delayed to avoid modifying provider during build
    Future.microtask(() {
      if (mounted) {
        ref.read(currentlyVisiblePageIndexProvider.notifier).state =
            _currentPageIndex;

        // Analysis mode is already enabled by default in the provider initialization
        // No need to toggle it here
        try {
          final initialGame = _resolveGameForIndex(_currentPageIndex);
          final params = ChessBoardProviderParams(
            game: initialGame,
            index: _currentPageIndex,
          );
          final notifier =
              ref.read(chessBoardScreenProviderNew(params).notifier);
          unawaited(
            notifier.parseMoves().whenComplete(
              () => notifier.onBecameVisible(force: true),
            ),
          );
        } catch (e) {
          debugPrint('Error preparing initial game evaluation: $e');
        }
      }
    });
  }

  void _onPageChanged(int newIndex) {
    if (_currentPageIndex == newIndex) return;

    _lastViewedIndex = newIndex;
    final previousIndex = _currentPageIndex;

    // Update current page index immediately
    setState(() {
      _currentPageIndex = newIndex;
    });

    // CRITICAL: Update the global provider to track which page is visible
    // This prevents off-screen games from playing audio
    ref.read(currentlyVisiblePageIndexProvider.notifier).state = newIndex;

    // Cancel active evaluations on the board that just went off-screen
    try {
      final prevGame = _resolveGameForIndex(previousIndex);
      final prevParams = ChessBoardProviderParams(
        game: prevGame,
        index: previousIndex,
      );
      final prevNotifier =
          ref.read(chessBoardScreenProviderNew(prevParams).notifier);
      unawaited(prevNotifier.onBecameInvisible());
    } catch (e) {
      debugPrint('Error cancelling previous game evaluation: $e');
    }

    // OPTIMIZED: Don't read provider state during page changes - just manage the chess board providers
    // This prevents unnecessary provider lookups that could trigger rebuilds

    // Only pause if the previous provider should still be alive (within ±1 range)
    if ((newIndex - previousIndex).abs() <= 1) {
      try {
        final prevGame = _resolveGameForIndex(previousIndex);
        ref
            .read(
              chessBoardScreenProviderNew(
                ChessBoardProviderParams(game: prevGame, index: previousIndex),
              ).notifier,
            )
            .pauseGame();
      } catch (e) {
        // Provider was disposed, which is fine
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          final newGame = _resolveGameForIndex(newIndex);
          final params = ChessBoardProviderParams(
            game: newGame,
            index: newIndex,
          );
          final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
          unawaited(
            notifier.parseMoves().whenComplete(
              () => notifier.onBecameVisible(force: true),
            ),
          );
        } catch (e) {
          debugPrint('Error parsing moves for new index: $e');
        }
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _navigateToGame(int gameIndex) {
    if (gameIndex == _currentPageIndex) return;

    // OPTIMIZED: Don't read provider during navigation - just pause the current game
    try {
      final currentGame = _resolveGameForIndex(_currentPageIndex);
      ref
          .read(
            chessBoardScreenProviderNew(
              ChessBoardProviderParams(
                game: currentGame,
                index: _currentPageIndex,
              ),
            ).notifier,
          )
          .pauseGame();
    } catch (e) {
      debugPrint('Error pausing game during navigation: $e');
    }

    _pageController.animateToPage(
      gameIndex,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(chessboardViewFromProviderNew);
    AsyncValue<GamesScreenModel> gamesAsync;

    switch (view) {
      case ChessboardView.favScorecard:
        final selectedPlayer = ref.watch(selectedPlayerProvider);
        final games = ref.watch(playerGamesProvider(selectedPlayer!)).value!;
        gamesAsync = AsyncValue.data(
          GamesScreenModel(gamesTourModels: games, pinnedGamedIs: []),
        );
        break;
      case ChessboardView.tour:
        gamesAsync = ref.watch(gamesTourScreenProvider);
        break;
      case ChessboardView.countryman:
        gamesAsync = ref.watch(countrymanGamesTourScreenProvider);
        break;
    }

    if (!gamesAsync.hasValue || gamesAsync.value?.gamesTourModels == null) {
      return _LoadingScreen(
        games: widget.games.isNotEmpty ? widget.games : [widget.games.first],
        currentGameIndex: _currentPageIndex.clamp(0, widget.games.length - 1),
        onGameChanged: (index) {},
        lastViewedIndex: _lastViewedIndex,
      );
    }

    final liveGamesMap = Map.fromEntries(
      gamesAsync.value!.gamesTourModels.map((g) => MapEntry(g.gameId, g)),
    );
    final liveGames =
        widget.games
            .map(
              (originalGame) =>
                  liveGamesMap[originalGame.gameId] ?? originalGame,
            )
            .toList();

    final syncedGames = List<GamesTourModel>.from(liveGames);
    if (syncedGames.isEmpty) {
      return _LoadingScreen(
        games: widget.games.isNotEmpty ? widget.games : [widget.games.first],
        currentGameIndex: _currentPageIndex.clamp(0, widget.games.length - 1),
        onGameChanged: (index) {},
        lastViewedIndex: _lastViewedIndex,
      );
    }

    final visibleStart = (_currentPageIndex - 1).clamp(
      0,
      syncedGames.length - 1,
    );
    final visibleEnd = (_currentPageIndex + 1).clamp(0, syncedGames.length - 1);
    final Map<int, AsyncValue<ChessBoardStateNew>> visibleStates = {};
    for (int i = visibleStart; i <= visibleEnd; i++) {
      // CRITICAL: Provider handles ALL streaming internally via _setupPgnStreamListener()
      // It watches gameUpdatesStreamProvider, updates game reference, reparses moves, triggers evaluation
      // Widget should NOT also watch the stream - this causes race conditions and inconsistency
      // Single source of truth: provider's state.game

      final game = syncedGames[i];
      final params = ChessBoardProviderParams(game: game, index: i);
      visibleStates[i] = ref.watch(chessBoardScreenProviderNew(params));

      // Use state.game as source of truth - provider keeps it updated via streaming
      final state = visibleStates[i]?.valueOrNull;
      if (state != null) {
        syncedGames[i] = state.game;
      }
    }

    final currentGame = syncedGames[_currentPageIndex];

    ref.listen(
      chessBoardScreenProviderNew(
        ChessBoardProviderParams(game: currentGame, index: _currentPageIndex),
      ),
      (prev, next) {
        final prevState = prev?.valueOrNull;
        final nextState = next.valueOrNull;
        final prevIndex =
            prevState == null
                ? -1
                : (prevState.isAnalysisMode
                    ? prevState.analysisState.currentMoveIndex
                    : prevState.currentMoveIndex);
        final currentIndex =
            nextState == null
                ? -1
                : (nextState.isAnalysisMode
                    ? nextState.analysisState.currentMoveIndex
                    : nextState.currentMoveIndex);

        if (prevIndex != currentIndex && next.valueOrNull != null) {
          // CRITICAL FIX: Only play audio if this chess board screen is currently active
          // This prevents audio from playing when other games in the tournament get moves
          final route = ModalRoute.of(context);
          if (route == null || !route.isCurrent) {
            // Screen is not visible, don't play audio
            return;
          }

          final state = nextState!;

          // ENHANCED FIX: Verify this update is for the currently viewed game
          // Only play audio if the provider index matches the current page
          final providerGameIndex = _currentPageIndex;
          final viewGameId = widget.games[providerGameIndex].gameId;
          if (state.game.gameId != viewGameId) {
            // This update is for a different game, don't play audio
            return;
          }

          // Additional check: Only play audio for significant move index changes
          // This prevents audio from playing due to minor state updates
          if ((currentIndex - prevIndex).abs() != 1 && currentIndex != -1) {
            // Not a sequential move change, likely a background update
            return;
          }

          // Final check: Make sure we're viewing the correct page in PageView
          // Use a small tolerance for floating-point comparison
          final currentPage =
              _pageController.page ?? _currentPageIndex.toDouble();
          if ((currentPage - _currentPageIndex).abs() > 0.1) {
            // PageView is not on the current game, don't play audio
            return;
          }

          final audioService = AudioPlayerService.instance;

          // Determine if we're going forward or backward
          final isMovingForward = currentIndex > prevIndex;

          // For backward navigation, we want to play the sound of the move we just "undid"
          // For forward navigation, we want to play the sound of the move we just made
          final moveIndexForSound = isMovingForward ? currentIndex : prevIndex;

          final movesSan =
              state.isAnalysisMode
                  ? state.analysisState.moveSans
                  : state.moveSans;

          // Check if we have a valid move to play sound for
          if (moveIndexForSound >= 0 && moveIndexForSound < movesSan.length) {
            // Get the move notation for the appropriate move
            final moveSan = movesSan[moveIndexForSound];

            // Determine which sound to play based on PGN notation
            // Priority order matters: checkmate > check > special moves > capture > regular
            if (moveSan.contains('#')) {
              // Checkmate notation
              audioService.player.play(audioService.pieceCheckmateSfx);
            } else if (moveSan.contains('+')) {
              // Check notation (but not checkmate)
              audioService.player.play(audioService.pieceCheckSfx);
            } else if (moveSan == 'O-O' || moveSan == 'O-O-O') {
              // Castling (kingside or queenside) - exact match
              audioService.player.play(audioService.pieceCastlingSfx);
            } else if (moveSan.contains('=')) {
              // Pawn promotion (e.g., e8=Q)
              audioService.player.play(audioService.piecePromotionSfx);
            } else if (moveSan.contains('x')) {
              // Capture notation
              audioService.player.play(audioService.pieceTakeoverSfx);
            } else {
              // Regular move (no special notation)
              audioService.player.play(audioService.pieceMoveSfx);
            }
          } else if (currentIndex == -1 && prevIndex >= 0) {
            // Moving back to the starting position (before first move)
            // Play a regular move sound for the "undo" action
            audioService.player.play(audioService.pieceMoveSfx);
          } else if (currentIndex == movesSan.length && movesSan.isNotEmpty) {
            // We're at the end of the game, check for game-ending conditions
            final lastMoveSan = movesSan.last;

            if (lastMoveSan.contains('#')) {
              // Game ended with checkmate
              audioService.player.play(audioService.pieceCheckmateSfx);
            } else if (state.game.gameStatus == GameStatus.draw) {
              // Game ended in a draw
              audioService.player.play(audioService.pieceDrawSfx);
            } else {
              // Other game endings (resignation, time out, etc.)
              audioService.player.play(audioService.pieceMoveSfx);
            }
          } else {
            // Fallback for edge cases (shouldn't normally happen)
            audioService.player.play(audioService.pieceMoveSfx);
          }
        }
      },
      onError: (e, st) {
        debugPrint("Error in chessBoardScreenProviderNew listener: $e");
      },
    );
    // OPTIMIZED: Only watch for updates to games that are currently visible in the PageView
    // This prevents rebuilds when other games in the tournament get updated
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.of(context).pop(_lastViewedIndex);
        }
      },
      child: Scaffold(
        // REMOVED: RawGestureDetector was blocking PageView swipes
        body: PageView.builder(
          padEnds: true,
          allowImplicitScrolling: true,
          // PageView swiping enabled in all modes
          physics: const PageScrollPhysics(),
          controller: _pageController,
          onPageChanged: _onPageChanged,
          itemCount: syncedGames.length,
          itemBuilder: (context, index) {
            // Build current page and adjacent pages
            if (index == _currentPageIndex - 1 ||
                index == _currentPageIndex ||
                index == _currentPageIndex + 1) {
              try {
                final game = syncedGames[index];
                final params = ChessBoardProviderParams(
                  game: game,
                  index: index,
                );
                final stateAsync =
                    visibleStates[index] ??
                    ref.watch(chessBoardScreenProviderNew(params));
                return stateAsync?.when(
                  data: (chessBoardState) {
                    if (chessBoardState.isAnalysisMode != analysisMode) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_pageController.hasClients) {
                          setState(() {
                            analysisMode = chessBoardState.isAnalysisMode;
                          });
                        }
                      });
                    }
                    return _GamePage(
                      game:
                          chessBoardState
                              .game, // Use game from state which gets updated by streaming
                      state: chessBoardState,
                      games: syncedGames,
                      currentGameIndex: index,
                      currentPageIndex: _currentPageIndex,
                      onGameChanged: _navigateToGame,
                      lastViewedIndex: _lastViewedIndex,
                    );
                  },
                  error: (e, _) => ErrorWidget(e),
                  loading:
                      () => _LoadingScreen(
                        games: liveGames,
                        currentGameIndex: index,
                        onGameChanged: _navigateToGame,
                        lastViewedIndex: _lastViewedIndex,
                      ),
                );
              } catch (e) {
                // Fallback for when provider isn't ready
                return _LoadingScreen(
                  games: liveGames,
                  currentGameIndex: index,
                  onGameChanged: _navigateToGame,
                  lastViewedIndex: _lastViewedIndex,
                );
              }
            } else {
              return SizedBox.shrink();
            }
          },
        ),
      ),
    );
  }
}

class _GamePage extends StatelessWidget {
  final GamesTourModel game;
  final ChessBoardStateNew state;
  final List<GamesTourModel> games;
  final int currentGameIndex;
  final int currentPageIndex;
  final void Function(int) onGameChanged;
  final int? lastViewedIndex;

  const _GamePage({
    required this.game,
    required this.state,
    required this.games,
    required this.currentGameIndex,
    required this.currentPageIndex,
    required this.onGameChanged,
    this.lastViewedIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: _BottomNavBar(
        index: currentGameIndex,
        state: state,
        game: game,
      ),
      appBar: _AppBar(
        game: game,
        games: games,
        currentGameIndex: currentGameIndex,
        onGameChanged: onGameChanged,
        lastViewedIndex: lastViewedIndex,
      ),
      body: _GameBody(
        index: currentGameIndex,
        currentPageIndex: currentPageIndex,
        game: game,
        state: state,
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  final List<GamesTourModel> games;
  final int currentGameIndex;
  final void Function(int) onGameChanged;
  final int? lastViewedIndex;

  const _LoadingScreen({
    required this.games,
    required this.currentGameIndex,
    required this.onGameChanged,
    this.lastViewedIndex,
  });

  @override
  Widget build(BuildContext context) {
    final sideBarWidth = 20.w;
    final screenWidth = MediaQuery.of(context).size.width;
    final boardSize = screenWidth - sideBarWidth - 32.w;

    return Scaffold(
      appBar: _AppBar(
        game: games[currentGameIndex],
        games: games,
        currentGameIndex: currentGameIndex,
        onGameChanged: onGameChanged,
        isLoading: true,
        lastViewedIndex: lastViewedIndex,
      ),
      body: Skeletonizer(
        enabled: true,
        child: Column(
          children: [
            // Top player skeleton
            Container(
              margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              padding: EdgeInsets.all(8.sp),
              decoration: BoxDecoration(
                color: kBlack2Color,
                borderRadius: BorderRadius.circular(8.br),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40.w,
                    height: 40.h,
                    decoration: BoxDecoration(
                      color: kWhiteColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 120.w,
                          height: 14.h,
                          decoration: BoxDecoration(
                            color: kWhiteColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4.br),
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Container(
                          width: 60.w,
                          height: 12.h,
                          decoration: BoxDecoration(
                            color: kWhiteColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4.br),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 2.h),
            // Board skeleton
            Container(
              margin: EdgeInsets.symmetric(horizontal: 16.sp),
              child: Row(
                children: [
                  // Eval bar skeleton
                  Container(
                    width: sideBarWidth,
                    height: boardSize,
                    decoration: BoxDecoration(
                      color: kWhiteColor.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(4.br),
                    ),
                  ),
                  // Board skeleton
                  Container(
                    width: boardSize,
                    height: boardSize,
                    decoration: BoxDecoration(
                      color: kWhiteColor.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(4.br),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 2.h),
            // Bottom player skeleton
            Container(
              margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              padding: EdgeInsets.all(8.sp),
              decoration: BoxDecoration(
                color: kBlack2Color,
                borderRadius: BorderRadius.circular(8.br),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40.w,
                    height: 40.h,
                    decoration: BoxDecoration(
                      color: kWhiteColor.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 120.w,
                          height: 14.h,
                          decoration: BoxDecoration(
                            color: kWhiteColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4.br),
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Container(
                          width: 60.w,
                          height: 12.h,
                          decoration: BoxDecoration(
                            color: kWhiteColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4.br),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Moves area skeleton
            Expanded(
              child: Container(
                width: double.infinity,
                margin: EdgeInsets.only(top: 8.h),
                decoration: BoxDecoration(
                  color: kDarkGreyColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12.sp),
                    topRight: Radius.circular(12.sp),
                  ),
                ),
                padding: EdgeInsets.all(20.sp),
                child: Wrap(
                  spacing: 6.sp,
                  runSpacing: 6.sp,
                  children: List.generate(8, (index) {
                    return Container(
                      width: (35 + (index % 5) * 20).w,
                      height: 14.h,
                      decoration: BoxDecoration(
                        color: kWhiteColor.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(3.sp),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppBar extends ConsumerWidget implements PreferredSizeWidget {
  final GamesTourModel game;
  final List<GamesTourModel> games;
  final int currentGameIndex;
  final void Function(int) onGameChanged;
  final bool isLoading;
  final int? lastViewedIndex;

  const _AppBar({
    required this.game,
    required this.games,
    required this.currentGameIndex,
    required this.onGameChanged,
    this.isLoading = false,
    this.lastViewedIndex,
  });
  copyPgnBtnClicked(WidgetRef ref) async {
    final gameWithPgn = await ref
        .read(gameRepositoryProvider)
        .getGameById(game.gameId);
    String pgn = gameWithPgn.pgn ?? "";
    Clipboard.setData(ClipboardData(text: pgn));
  }

  void shareGameBtnClicked(BuildContext context, WidgetRef ref) async {
    // Get the board provider to access the current state
    final params = ChessBoardProviderParams(
      game: game,
      index: currentGameIndex,
    );
    final boardState = ref.read(chessBoardScreenProviderNew(params));

    // Only proceed if we have a valid state
    if (!boardState.hasValue || boardState.value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please wait for the game to load'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final state = boardState.value!;
    final gameWithPgn = await ref
        .read(gameRepositoryProvider)
        .getGameById(game.gameId);
    final pgn = gameWithPgn.pgn ?? "";

    // Show share overlay - we'll navigate to a full screen overlay
    if (context.mounted) {
      Navigator.of(context).push(
        PageRouteBuilder(
          opaque: false,
          barrierDismissible: true,
          barrierColor: Colors.transparent,
          pageBuilder:
              (context, animation, secondaryAnimation) =>
                  _ShareGameScreen(game: game, state: state, pgn: pgn),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppBar(
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: kWhiteColor),
        onPressed: () => Navigator.pop(context, lastViewedIndex),
      ),
      title: _GameSelectionDropdown(
        games: games,
        currentGameIndex: currentGameIndex,
        onGameChanged: onGameChanged,
        isLoading: isLoading,
      ),
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: kWhiteColor),
          enabled: !isLoading,
          onSelected: (value) {
            if (value == 'share') {
              shareGameBtnClicked(context, ref);
            } else if (value == 'board_settings') {
              Navigator.of(context).push(ChessBoardSettingsPage.route());
            }
          },
          itemBuilder:
              (context) => [
                PopupMenuItem(
                  value: 'board_settings',
                  child: Row(
                    children: [
                      Icon(Icons.settings, color: kWhiteColor),
                      SizedBox(width: 8.w),
                      const Text('Board Settings'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      Icon(Icons.share, color: kWhiteColor),
                      SizedBox(width: 8.w),
                      const Text('Share Game'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  onTap: () {
                    copyPgnBtnClicked(ref);
                  },
                  value: 'copy_pgn',
                  child: Row(
                    children: [
                      Icon(Icons.copy, color: kWhiteColor),
                      SizedBox(width: 8.w),
                      const Text('Copy PGN'),
                    ],
                  ),
                ),
              ],
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _GameSelectionDropdown extends StatelessWidget {
  final List<GamesTourModel> games;
  final int currentGameIndex;
  final void Function(int) onGameChanged;
  final bool isLoading;

  const _GameSelectionDropdown({
    required this.games,
    required this.currentGameIndex,
    required this.onGameChanged,
    this.isLoading = false,
  });

  String _formatName(String fullName, {double? maxWidth}) {
    List<String> nameParts =
        fullName.trim().split(' ').where((part) => part.isNotEmpty).toList();
    if (nameParts.length <= 1) return fullName;

    String familyName = nameParts.last;
    List<String> otherNames = nameParts.sublist(0, nameParts.length - 1);

    // Try full names first
    String fullVersion = '${otherNames.join(' ')} $familyName';

    // If no width constraint or it fits, return full version
    if (maxWidth == null) return fullVersion;

    // Estimate text width (rough approximation)
    double estimatedWidth =
        fullVersion.length * 6.0; // Approximate character width
    if (estimatedWidth <= maxWidth) return fullVersion;

    // If too long, progressively abbreviate from left to right
    List<String> displayNames = List.from(otherNames);

    for (int i = 0; i < displayNames.length; i++) {
      if (displayNames[i].length > 1) {
        displayNames[i] = '${displayNames[i][0]}.';
        String newVersion = '${displayNames.join(' ')} $familyName';
        double newEstimatedWidth = newVersion.length * 6.0;
        if (newEstimatedWidth <= maxWidth) {
          return newVersion;
        }
      }
    }

    // Fallback: all abbreviated
    return '${displayNames.join(' ')} $familyName';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32.h,
      constraints: BoxConstraints(maxWidth: 300.w),
      child: DropdownButton<int>(
        value: currentGameIndex,
        underline: Container(),
        icon: Icon(
          Icons.keyboard_arrow_down_outlined,
          color: kWhiteColor,
          size: 20.sp,
        ),
        dropdownColor: kBlack2Color,
        borderRadius: BorderRadius.circular(20.sp),
        isExpanded: true,
        style: AppTypography.textMdBold,
        onChanged:
            isLoading
                ? null
                : (int? newIndex) {
                  if (newIndex != null && newIndex != currentGameIndex) {
                    onGameChanged(newIndex);
                  }
                },
        selectedItemBuilder: (BuildContext context) {
          return games.asMap().entries.map<Widget>((entry) {
            final game = entry.value;

            return Container(
              padding: EdgeInsets.symmetric(horizontal: 12.sp),
              alignment: Alignment.center,
              child: Text(
                '${_formatName(game.whitePlayer.displayName, maxWidth: 120)} vs ${_formatName(game.blackPlayer.displayName, maxWidth: 120)}',
                style: AppTypography.textXsMedium.copyWith(color: kWhiteColor),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList();
        },
        items:
            games.asMap().entries.map<DropdownMenuItem<int>>((entry) {
              final index = entry.key;
              final game = entry.value;
              final isLast = index == games.length - 1;

              return DropdownMenuItem<int>(
                value: index,
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      _GameDropdownItem(
                        game: game,
                        gameNumber: index + 1,
                        isSelected: index == currentGameIndex,
                        isLoading: isLoading && index == currentGameIndex,
                      ),
                      if (!isLast)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 5.h),
                          child: DividerWidget(),
                        ),
                    ],
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }
}

class _GameDropdownItem extends StatelessWidget {
  final GamesTourModel game;
  final int gameNumber;
  final bool isSelected;
  final bool isLoading;

  const _GameDropdownItem({
    required this.game,
    required this.gameNumber,
    required this.isSelected,
    required this.isLoading,
  });

  String _formatName(String fullName, {double? maxWidth}) {
    List<String> nameParts =
        fullName.trim().split(' ').where((part) => part.isNotEmpty).toList();
    if (nameParts.length <= 1) return fullName;

    String familyName = nameParts.last;
    List<String> otherNames = nameParts.sublist(0, nameParts.length - 1);

    // Try full names first
    String fullVersion = '${otherNames.join(' ')} $familyName';

    // If no width constraint or it fits, return full version
    if (maxWidth == null) return fullVersion;

    // Estimate text width (rough approximation)
    double estimatedWidth =
        fullVersion.length * 5.0; // Approximate character width
    if (estimatedWidth <= maxWidth) return fullVersion;

    // If too long, progressively abbreviate from left to right
    List<String> displayNames = List.from(otherNames);

    for (int i = 0; i < displayNames.length; i++) {
      if (displayNames[i].length > 1) {
        displayNames[i] = '${displayNames[i][0]}.';
        String newVersion = '${displayNames.join(' ')} $familyName';
        double newEstimatedWidth = newVersion.length * 5.0;
        if (newEstimatedWidth <= maxWidth) {
          return newVersion;
        }
      }
    }

    // Fallback: all abbreviated
    return '${displayNames.join(' ')} $familyName';
  }

  String _getRoundLabel(GamesTourModel game) {
    final slug = game.roundSlug;
    if (slug == null || slug.isEmpty) {
      return 'R:';
    }

    // Try to extract number from various patterns
    // Examples: "round-12", "rapid-8", "blitz-8", "13", "game-4", "losers-r3--armageddon"
    final patterns = [
      RegExp(r'round[-\s]?(\d+)', caseSensitive: false), // round-12, round 12
      RegExp(r'rapid[-\s]?(\d+)', caseSensitive: false), // rapid-8
      RegExp(r'blitz[-\s]?(\d+)', caseSensitive: false), // blitz-8
      RegExp(r'^(\d+)$'), // just a number like "13"
      RegExp(r'r(\d+)', caseSensitive: false), // r3 in losers-r3
      RegExp(r'game[-\s]?(\d+)', caseSensitive: false), // game-4
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(slug);
      if (match != null) {
        final roundNumber = match.group(1);
        return 'R$roundNumber:';
      }
    }

    // If no pattern matches, return a simplified version
    return 'R:';
  }

  Widget _buildStatusIcon() {
    if (isLoading) {
      return SizedBox(
        width: 16.w,
        height: 16.h,
        child: const CircularProgressIndicator(
          strokeWidth: 1.5,
          color: kPrimaryColor,
        ),
      );
    }

    switch (game.gameStatus) {
      case GameStatus.whiteWins:
        return Container(
          width: 16.w,
          height: 16.h,
          alignment: Alignment.center,
          child: Text(
            '1',
            style: AppTypography.textXsBold.copyWith(
              color: kWhiteColor,
              fontSize: 12.sp,
            ),
          ),
        );
      case GameStatus.blackWins:
        return Container(
          width: 16.w,
          height: 16.h,
          alignment: Alignment.center,
          child: Text(
            '0',
            style: AppTypography.textXsBold.copyWith(
              color: kWhiteColor,
              fontSize: 12.sp,
            ),
          ),
        );
      case GameStatus.draw:
        return Container(
          width: 16.w,
          height: 16.h,
          alignment: Alignment.center,
          child: Text(
            '½',
            style: AppTypography.textXsBold.copyWith(
              color: kWhiteColor,
              fontSize: 12.sp,
            ),
          ),
        );
      case GameStatus.ongoing:
        return SvgPicture.asset(
          SvgAsset.selectedSvg,
          width: 16.w,
          height: 16.h,
        );
      case GameStatus.unknown:
        return SvgPicture.asset(
          SvgAsset.calendarIcon,
          width: 16.w,
          height: 16.h,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            '${_getRoundLabel(game)} ${_formatName(game.whitePlayer.name, maxWidth: 65)} vs ${_formatName(game.blackPlayer.name, maxWidth: 65)}',
            style: AppTypography.textXsRegular.copyWith(color: kWhiteColor70),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: 8.w),
        _buildStatusIcon(),
      ],
    );
  }
}

class _BottomNavBar extends ConsumerWidget {
  final int index;
  final ChessBoardStateNew state;
  final GamesTourModel game;

  const _BottomNavBar({
    required this.index,
    required this.state,
    required this.game,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final params = ChessBoardProviderParams(game: game, index: index);
    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
    // Analysis mode is always active, always use analysis state
    final canMoveForward = state.analysisState.canMoveForward;
    final canMoveBackward = state.analysisState.canMoveBackward;

    return ChessBoardBottomNavBar(
      gameIndex: index,
      onFlip: () => notifier.flipBoard(),
      toggleEngineVisibility: () => notifier.toggleEngineVisibility(),
      onEngineSettingsLongPress: () {
        Navigator.of(context).push(ChessBoardSettingsPage.route());
      },
      onRightMove:
          canMoveForward
              ? () {
                notifier.analysisStepForward();
                // Clear unseen indicator ONLY when reaching the last move
                if (state.hasUnseenMoves) {
                  // Check if we'll be at the last move after stepping forward
                  final willBeAtLastMove =
                      state.analysisState.currentMoveIndex + 1 >=
                      state.allMoves.length - 1;
                  if (willBeAtLastMove) {
                    notifier.markMovesAsSeen();
                  }
                }
              }
              : null,
      onLeftMove:
          canMoveBackward ? () => notifier.analysisStepBackward() : null,
      onLongPressBackwardStart: () => notifier.startLongPressBackward(),
      onLongPressBackwardEnd: () => notifier.stopLongPress(),
      onLongPressForwardStart: () => notifier.startLongPressForward(),
      onLongPressForwardEnd: () => notifier.stopLongPress(),
      canMoveForward: canMoveForward,
      canMoveBackward: canMoveBackward,
      showEngineAnalysis: state.showEngineAnalysis,
      showUnseenMoveBadge: state.hasUnseenMoves,
    );
  }
}

class _GameBody extends StatelessWidget {
  final int index;
  final int currentPageIndex;
  final GamesTourModel game;
  final ChessBoardStateNew state;

  const _GameBody({
    required this.index,
    required this.currentPageIndex,
    required this.game,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    // Analysis mode is always active, use analysis game body
    return _AnalysisGameBody(
      index: index,
      currentPageIndex: currentPageIndex,
      game: game,
      state: state,
    );
  }
}

class _AnalysisGameBody extends ConsumerWidget {
  final int index;
  final int currentPageIndex;
  final GamesTourModel game;
  final ChessBoardStateNew state;

  const _AnalysisGameBody({
    required this.index,
    required this.currentPageIndex,
    required this.game,
    required this.state,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _PlayerWidget(
          game: game,
          isFlipped: state.isBoardFlipped,
          blackPlayer: false,
          state: state,
        ),
        SizedBox(height: 2.h),
        _BoardWithSidebar(
          index: index,
          currentPageIndex: currentPageIndex,
          state: state,
          game: game,
        ),
        SizedBox(height: 2.h),
        _PlayerWidget(
          game: game,
          isFlipped: state.isBoardFlipped,
          blackPlayer: true,
          state: state,
        ),
        if (state.isAnalysisMode && state.showPrincipalVariations) ...[
          _PrincipalVariationList(index: index, state: state, game: game),
          // DISABLED: Analysis navigation arrows hidden
          // _AnalysisControlsRow(index: index, game: game),
        ],
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: kDarkGreyColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12.sp),
                topRight: Radius.circular(12.sp),
              ),
            ),
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollStartNotification) {
                  // placeholder hook
                }
                return false;
              },
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                physics: const ClampingScrollPhysics(),
                dragStartBehavior: DragStartBehavior.down,
                child: GestureDetector(
                  onHorizontalDragStart: (_) {},
                  onHorizontalDragUpdate: (_) {},
                  onHorizontalDragEnd: (_) {},
                  behavior: HitTestBehavior.translucent,
                  child: _MovesDisplay(
                    index: index,
                    currentPageIndex: currentPageIndex,
                    state: state,
                    game: game,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// DISABLED: Analysis navigation arrows widget completely hidden
// class _AnalysisControlsRow extends ConsumerWidget {
//   final int index;
//   final GamesTourModel game;
//
//   const _AnalysisControlsRow({required this.index, required this.game});
//
//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final params = ChessBoardProviderParams(game: game, index: index);
//     final state = ref.watch(chessBoardScreenProviderNew(params)).valueOrNull;
//     final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
//
//     // Use variants when available; default to first PV if none explicitly selected
//     // final hasVariant = state?.principalVariations.isNotEmpty ?? false;
//
//     // Respect PV count from settings in UI
//     // ... (omitted)
//   }
// }

class _PlayerWidget extends StatelessWidget {
  final GamesTourModel game;
  final bool isFlipped;
  final bool blackPlayer;
  final ChessBoardStateNew state;

  const _PlayerWidget({
    required this.game,
    required this.isFlipped,
    required this.blackPlayer,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    // Determine if this is the white player
    final isWhitePlayer =
        (blackPlayer && !isFlipped) || (!blackPlayer && isFlipped);

    final currentPosition =
        state.isAnalysisMode ? state.analysisState.position : state.position;

    // Check whose turn it is currently
    final currentTurn = currentPosition?.turn ?? Side.white;
    final isCurrentPlayer =
        (isWhitePlayer && currentTurn == Side.white) ||
        (!isWhitePlayer && currentTurn == Side.black);

    return PlayerFirstRowDetailWidget(
      isCurrentPlayer: isCurrentPlayer,
      isWhitePlayer: isWhitePlayer,
      playerView: PlayerView.boardView,
      gamesTourModel: game,
      chessBoardState: state, // Pass the state for move time calculation
    );
  }
}

class _BoardWithSidebar extends ConsumerWidget {
  final int index;
  final ChessBoardStateNew state;
  final int currentPageIndex;
  final GamesTourModel game;

  const _BoardWithSidebar({
    required this.index,
    required this.state,
    required this.currentPageIndex,
    required this.game,
  });

  // DISABLED: Only used for move annotation overlay
  // String? _getLastMoveSquare() {
  //   // Analysis mode is always active, always use analysis state
  //   final lastMove = state.analysisState.lastMove;
  //   if (lastMove == null) return null;
  //   if (lastMove is NormalMove) {
  //     return lastMove.to.name;
  //   }
  //   return null;
  // }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Read engine settings to control visibility
    final engineSettings = ref.watch(engineSettingsProviderNew).valueOrNull;
    final showEngineGauge = engineSettings?.showEngineGauge ?? true;

    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBarWidth = showEngineGauge ? 20.w : 0.w;
        final screenWidth = MediaQuery.of(context).size.width;
        final boardSize = screenWidth - sideBarWidth - 32.w;

        // Analysis mode is always active, always use analysis state
        // DISABLED: currentIndex only used for move impact analysis
        // final currentIndex = state.analysisState.currentMoveIndex;

        // DISABLED: Move impact analysis causes Lichess 429 rate limits
        // TODO: Re-enable when we have better rate limiting or use only Stockfish
        // // LAZY IMPACT: Only calculate impact for the CURRENT move, not all moves
        // // This prevents blocking the eval bar by not flooding Stockfish queue
        // MoveImpactAnalysis? currentMoveImpact;
        // if (index == currentPageIndex &&
        //     state.allMoves.isNotEmpty &&
        //     currentIndex >= 0) {
        //   final boardParams = ChessBoardProviderParams(
        //     game: game,
        //     index: index,
        //   );
        //   final lazyParams = LazyMoveImpactParams(
        //     boardParams: boardParams,
        //     moveIndex: currentIndex,
        //   );
        //   final impactAsync = ref.watch(lazyMoveImpactProvider(lazyParams));
        //   currentMoveImpact = impactAsync.whenOrNull(data: (data) => data);
        // }

        return Container(
          margin: EdgeInsets.symmetric(horizontal: 16.sp),
          child: Row(
            children: [
              // Conditionally show evaluation bar based on settings
              if (showEngineGauge)
                SizedBox(
                  width: sideBarWidth,
                  height: boardSize,
                  child: EvaluationBarWidget(
                    width: sideBarWidth,
                    height: boardSize,
                    evaluation: state.evaluation,
                    mate: state.mate,
                    isEvaluating: state.isEvaluating,
                    isFlipped: state.isBoardFlipped,
                  ),
                ),
              Stack(
                children: [
                  // Analysis mode is always active, always use analysis board
                  _AnalysisBoard(
                    size: boardSize,
                    chessBoardState: state,
                    isFlipped: state.isBoardFlipped,
                    index: index,
                    game: state.game,
                  ),
                  // DISABLED: Move annotation overlay (requires move impact analysis)
                  // // Add move annotation overlay - only show if impact is not normal and not exploring a variant
                  // if (currentMoveImpact != null &&
                  //     currentMoveImpact.impact != MoveImpactType.normal &&
                  //     state.selectedVariantIndex == null)
                  //   BoardMoveAnnotation(
                  //     moveImpact: currentMoveImpact,
                  //     boardSize: boardSize,
                  //     isFlipped: state.isBoardFlipped,
                  //     lastMoveSquare: _getLastMoveSquare(),
                  //   ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// REMOVED: _ChessBoardNew widget - analysis mode is always active, only _AnalysisBoard is used

class _AnalysisBoard extends ConsumerWidget {
  final double size;
  final ChessBoardStateNew chessBoardState;
  final bool isFlipped;
  final int index;
  final GamesTourModel game;

  const _AnalysisBoard({
    required this.size,
    required this.chessBoardState,
    this.isFlipped = false,
    required this.index,
    required this.game,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardSettingsValue = ref.watch(boardSettingsProvider);
    final boardTheme = ref
        .read(boardSettingsRepository)
        .getBoardTheme(boardSettingsValue.boardColor);
    // final params = ChessBoardProviderParams(game: game, index: index);
    // final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);

    // Read engine settings to control PV arrows visibility
    final engineSettings = ref.watch(engineSettingsProviderNew).valueOrNull;
    final showPvArrows = engineSettings?.showPvArrows ?? true;

    return Chessboard(
      size: size,
      settings: ChessboardSettings(
        enableCoordinates: true,

        animationDuration: const Duration(milliseconds: 200),
        dragFeedbackScale: 1,
        dragTargetKind: DragTargetKind.none,
        pieceShiftMethod: PieceShiftMethod.either,
        autoQueenPromotionOnPremove: false,
        pieceOrientationBehavior: PieceOrientationBehavior.facingUser,
        colorScheme: ChessboardColorScheme(
          lightSquare: boardTheme.lightSquareColor,
          darkSquare: boardTheme.darkSquareColor,
          background: SolidColorChessboardBackground(
            lightSquare: boardTheme.lightSquareColor,
            darkSquare: boardTheme.darkSquareColor,
          ),
          whiteCoordBackground: SolidColorChessboardBackground(
            lightSquare: boardTheme.lightSquareColor,
            darkSquare: boardTheme.darkSquareColor,
            coordinates: true,
            orientation: Side.white,
          ),
          blackCoordBackground: SolidColorChessboardBackground(
            lightSquare: boardTheme.lightSquareColor,
            darkSquare: boardTheme.darkSquareColor,
            coordinates: true,
            orientation: Side.black,
          ),
          lastMove: HighlightDetails(
            solidColor: getAnalysisLastMoveHighlightColor(chessBoardState),
          ),
          selected: const HighlightDetails(solidColor: kPrimaryColor),
          validMoves: kPrimaryColor,
          validPremoves: kPrimaryColor,
        ),
      ),
      orientation: isFlipped ? Side.black : Side.white,
      fen: chessBoardState.analysisState.position.fen,
      lastMove: chessBoardState.analysisState.lastMove,
      // Only show shapes (arrows) when BOTH conditions are met:
      // 1. Principal variations are enabled in board state
      // 2. PV arrows are enabled in engine settings
      shapes:
          (chessBoardState.showPrincipalVariations && showPvArrows)
              ? chessBoardState.shapes
              : const ISet.empty(),
      // DISABLED: Manual piece movement disabled in analysis mode
      // game: GameData(
      //   playerSide:
      //       chessBoardState.analysisState.position.turn == Side.white
      //           ? PlayerSide.white
      //           : PlayerSide.black,
      //   validMoves: chessBoardState.analysisState.validMoves,
      //   sideToMove: chessBoardState.analysisState.position.turn,
      //   isCheck: chessBoardState.analysisState.position.isCheck,
      //   promotionMove: chessBoardState.analysisState.promotionMove,
      //   onMove: notifier.onAnalysisMove,
      //   onPromotionSelection: notifier.onAnalysisPromotionSelection,
      // ),
      game: null, // Board is now read-only in analysis mode
    );
  }
}

class _MovesDisplay extends ConsumerStatefulWidget {
  final int index;
  final ChessBoardStateNew state;
  final GamesTourModel game;
  final int currentPageIndex;

  const _MovesDisplay({
    required this.state,
    required this.index,
    required this.game,
    required this.currentPageIndex,
  });

  @override
  ConsumerState<_MovesDisplay> createState() => _MovesDisplayState();
}

class _MovesDisplayState extends ConsumerState<_MovesDisplay> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _moveKeys = {};
  bool _hasInitiallyScrolled = false;

  @override
  void initState() {
    super.initState();
    _initializeMoveKeys();
    _scheduleEnsureInitialScroll();
  }

  @override
  void didUpdateWidget(_MovesDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Reinitialize keys if the number of moves changed
    // Analysis mode is always active, use analysis state
    final oldSans = oldWidget.state.analysisState.moveSans;
    final newSans = widget.state.analysisState.moveSans;
    final oldCurrentIndex = oldWidget.state.analysisState.currentMoveIndex;
    final newCurrentIndex = widget.state.analysisState.currentMoveIndex;

    // CRITICAL: Force rebuild when hasUnseenMoves flag changes
    // This ensures red dot indicators sync correctly between notation text and bottom nav
    if (oldWidget.state.hasUnseenMoves != widget.state.hasUnseenMoves) {
      debugPrint(
        '🔴 hasUnseenMoves changed: ${oldWidget.state.hasUnseenMoves} -> ${widget.state.hasUnseenMoves}',
      );
      // Trigger rebuild to update all _MoveNotationWidget children
      setState(() {});
    }

    if (oldSans.length != newSans.length) {
      _initializeMoveKeys();

      // Only reset scroll position if user was viewing the last move
      // This preserves scroll position when viewing historical moves
      final wasViewingLastMove = oldCurrentIndex >= oldSans.length - 1;
      final isNewMoveAdded = newSans.length > oldSans.length;

      if (isNewMoveAdded && wasViewingLastMove) {
        // User was following along, auto-scroll to new move
        _hasInitiallyScrolled = false;
        _scheduleEnsureInitialScroll();
      } else if (isNewMoveAdded && !wasViewingLastMove) {
        // User is viewing history, preserve scroll position
        // Don't reset _hasInitiallyScrolled, don't schedule scroll
        debugPrint(
          '📌 Preserving scroll position - user viewing move $oldCurrentIndex while new move arrived',
        );
      } else {
        // Move count decreased (unlikely) or other change, reset
        _hasInitiallyScrolled = false;
        _scheduleEnsureInitialScroll();
      }
    }

    // Auto-scroll when current move changes

    // Only trigger scroll if on current page and index changed
    if (widget.index == widget.currentPageIndex &&
        oldCurrentIndex != newCurrentIndex) {
      // For the very first scroll, use initial scroll logic
      final isFirstScroll = !_hasInitiallyScrolled;

      debugPrint(
        '🔄 Move index changed: $oldCurrentIndex -> $newCurrentIndex (isFirstScroll: $isFirstScroll, page: ${widget.index}/${widget.currentPageIndex})',
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        if (isFirstScroll) {
          // First scroll: jump to position without animation, aligned to bottom
          debugPrint('📍 Initial scroll to move $newCurrentIndex');
          _scrollToMove(newCurrentIndex, isInitialScroll: true, alignment: 1.0);
        } else {
          // Subsequent scrolls: check if out of sight and scroll smoothly if needed
          debugPrint('🎯 Checking visibility for move $newCurrentIndex');
          _scrollToMove(
            newCurrentIndex,
            isInitialScroll: false,
            alignment: 0.5,
          );
        }
      });
    } else {
      debugPrint(
        '⛔ Scroll conditions not met: pageMatch=${widget.index == widget.currentPageIndex}, indexChanged=${oldCurrentIndex != newCurrentIndex} ($oldCurrentIndex vs $newCurrentIndex)',
      );
    }

    final becameActive =
        widget.index == widget.currentPageIndex &&
        oldWidget.currentPageIndex != widget.currentPageIndex;
    if (becameActive) {
      _scheduleEnsureInitialScroll();
    }
  }

  void _initializeMoveKeys() {
    final sans = _getSans();

    _moveKeys.clear();
    for (int i = 0; i < sans.length; i++) {
      _moveKeys[i] = GlobalKey();
    }
  }

  List<String> _getSans() {
    // Analysis mode is always active, use analysis state
    return widget.state.analysisState.moveSans;
  }

  int? _resolveTargetMoveIndex(int moveCount) {
    if (moveCount == 0) return null;

    // Analysis mode is always active, use analysis state
    final rawIndex = widget.state.analysisState.currentMoveIndex;

    if (rawIndex >= 0 && rawIndex < moveCount) {
      return rawIndex;
    }

    if (rawIndex >= moveCount) {
      return moveCount - 1;
    }

    // When pointer is before the start, fall back to the last move (latest position)
    return moveCount - 1;
  }

  void _scheduleEnsureInitialScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureInitialScroll();
    });
  }

  void _ensureInitialScroll() {
    if (_hasInitiallyScrolled) return;
    if (widget.index != widget.currentPageIndex) return;

    final sans = _getSans();
    final targetIndex = _resolveTargetMoveIndex(sans.length);
    if (targetIndex == null) return;

    _scrollToMove(targetIndex, isInitialScroll: true, alignment: 1.0);
  }

  bool _scrollToMove(
    int moveIndex, {
    bool isInitialScroll = false,
    double alignment = 0.5,
  }) {
    if (!_scrollController.hasClients) {
      if (isInitialScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollToMove(moveIndex, isInitialScroll: true, alignment: alignment);
        });
      }
      return false;
    }
    if (moveIndex < 0 || moveIndex >= _moveKeys.length) return false;

    final key = _moveKeys[moveIndex];
    final context = key?.currentContext;
    if (context == null) {
      // Retry after a short delay if context isn't ready
      if (isInitialScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollToMove(moveIndex, isInitialScroll: true, alignment: alignment);
        });
      }
      return false;
    }

    try {
      // For initial scroll, jump without animation so the latest move is visible immediately
      if (isInitialScroll) {
        Scrollable.ensureVisible(
          context,
          duration: Duration.zero,
          alignment: alignment,
        );
        _hasInitiallyScrolled = true;
        return true;
      }

      // For subsequent scrolls, always animate to keep the focused move centered.
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        alignment: alignment,
      );
      _hasInitiallyScrolled = true;
      return true;
    } catch (e) {
      debugPrint('Scroll error for move $moveIndex: $e');
    }

    return false;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.state.isLoadingMoves) {
      return _buildMovesLoadingSkeleton();
    }

    // Analysis mode is always active, use analysis state
    final sans = widget.state.analysisState.moveSans;

    if (sans.isEmpty && !widget.state.isLoadingMoves) {
      return Container(
        alignment: Alignment.center,
        padding: EdgeInsets.all(20.sp),
        child: Text(
          "No moves available for this game",
          style: AppTypography.textXsMedium.copyWith(
            color: kWhiteColor70,
            fontWeight: FontWeight.normal,
          ),
        ),
      );
    }

    // LAZY IMPACT: Each move in the notation list lazily loads its own impact
    // This prevents flooding the Stockfish queue with 100+ positions at once
    final boardParams = ChessBoardProviderParams(
      game: widget.game,
      index: widget.index,
    );

    // Analysis mode is always active, use analysis state for current index
    final modeAwareCurrentIndex = widget.state.analysisState.currentMoveIndex;

    return SingleChildScrollView(
      controller: _scrollController,
      child: Container(
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.all(20.sp),
        child: Wrap(
          spacing: 2.sp,
          runSpacing: 2.sp,
          children:
              sans.asMap().entries.map((entry) {
                final moveIndex = entry.key;
                final move = entry.value;

                // Extract to separate widget with key to prevent layout shift
                return _MoveNotationWidget(
                  key:
                      _moveKeys[moveIndex] ??
                      ValueKey('move_${widget.game.gameId}_$moveIndex'),
                  game: widget.game,
                  index: widget.index,
                  currentPageIndex: widget.currentPageIndex,
                  moveIndex: moveIndex,
                  move: move,
                  modeAwareCurrentIndex: modeAwareCurrentIndex,
                  boardParams: boardParams,
                  totalMoveCount: sans.length,
                  hasUnseenMoves: widget.state.hasUnseenMoves,
                );
              }).toList(),
        ),
      ),
    );
  }

  Widget _buildMovesLoadingSkeleton() {
    return Container(
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.all(20.sp),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonContainer(height: 16.h, width: 80.w, borderRadius: 4.sp),
          SizedBox(height: 12.h),
          ...List.generate(6, (rowIndex) {
            return Padding(
              padding: EdgeInsets.only(bottom: 8.h),
              child: Wrap(
                spacing: 8.sp,
                children: [
                  _SkeletonContainer(
                    height: 14.h,
                    width: (60 + (rowIndex % 3) * 20).w,
                    borderRadius: 3.sp,
                  ),
                  _SkeletonContainer(
                    height: 14.h,
                    width: (45 + (rowIndex % 4) * 15).w,
                    borderRadius: 3.sp,
                  ),
                ],
              ),
            );
          }),
          SizedBox(height: 8.h),
          Wrap(
            spacing: 6.sp,
            runSpacing: 6.sp,
            children: List.generate(8, (index) {
              return _SkeletonContainer(
                height: 14.h,
                width: (35 + (index % 5) * 20).w,
                borderRadius: 3.sp,
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _PrincipalVariationList extends ConsumerStatefulWidget {
  final int index;
  final ChessBoardStateNew state;
  final GamesTourModel game;

  const _PrincipalVariationList({
    required this.index,
    required this.state,
    required this.game,
  });

  @override
  ConsumerState<_PrincipalVariationList> createState() =>
      _PrincipalVariationListState();
}

class _PrincipalVariationListState
    extends ConsumerState<_PrincipalVariationList> {
  late PageController _pageController;
  int _currentPage = 0;
  int? _lastUserSelectedIndex;
  int? _pendingPageJump;
  bool _pendingPageJumpAnimated = false;
  int? _pendingVariantSelectionIndex;
  List<AnalysisLine> _lastNonEmptyLines = const [];
  String? _lastPositionKey;

  @override
  void initState() {
    super.initState();
    final lines = widget.state.principalVariations.toList(growable: false);
    final initialIndex = widget.state.selectedVariantIndex ?? 0;
    // Ensure initial page is within bounds
    if (lines.isEmpty) {
      _currentPage = 0;
    } else if (initialIndex < 0) {
      _currentPage = 0;
    } else if (initialIndex >= lines.length) {
      _currentPage = lines.length - 1;
    } else {
      _currentPage = initialIndex;
    }
    _lastNonEmptyLines = lines;
    _lastUserSelectedIndex = lines.isEmpty ? null : _currentPage;
    _pageController = PageController(initialPage: _currentPage);
    _lastPositionKey = _derivePositionKey(widget.state);
  }

  @override
  void didUpdateWidget(_PrincipalVariationList oldWidget) {
    super.didUpdateWidget(oldWidget);

    final lines = widget.state.principalVariations.toList(growable: false);
    final pageCount = lines.length;
    _lastNonEmptyLines = lines;
    final positionKey = _derivePositionKey(widget.state);
    final positionChanged = positionKey != _lastPositionKey;
    _lastPositionKey = positionKey;

    // Preserve user selection reference when PV list temporarily empties
    if (pageCount == 0) {
      _lastUserSelectedIndex ??=
          oldWidget.state.selectedVariantIndex ?? _currentPage;
      _currentPage = 0;
      return;
    }

    final int maxIndex = pageCount - 1;

    if (_currentPage > maxIndex) {
      _currentPage = pageCount - 1;
    }

    final newSelectedIndex = widget.state.selectedVariantIndex;
    final userSelected = _lastUserSelectedIndex;

    int? targetIndex;

    if (positionChanged) {
      targetIndex = ((newSelectedIndex ?? 0).clamp(0, maxIndex)).toInt();
      _lastUserSelectedIndex = targetIndex;
    } else if (newSelectedIndex != null && newSelectedIndex <= maxIndex) {
      targetIndex = newSelectedIndex;
      _lastUserSelectedIndex = newSelectedIndex;
    } else if (userSelected != null && userSelected <= maxIndex) {
      targetIndex = userSelected;
    } else if (_currentPage > maxIndex) {
      targetIndex = maxIndex;
    }

    if (targetIndex != null) {
      if (targetIndex != _currentPage) {
        final animate = positionChanged
            ? false
            : (newSelectedIndex != null && newSelectedIndex == targetIndex);
        _currentPage = targetIndex;
        _jumpToPage(targetIndex, animate: animate);
      } else {
        _jumpToPage(_currentPage, animate: false);
      }

      if ((newSelectedIndex == null || newSelectedIndex != targetIndex) &&
          _lastUserSelectedIndex != null &&
          _lastUserSelectedIndex! <= maxIndex) {
        _scheduleVariantSelection(_lastUserSelectedIndex!);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final params = ChessBoardProviderParams(
      game: widget.game,
      index: widget.index,
    );
    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
    final position =
        widget.state.isAnalysisMode
            ? widget.state.analysisState.position
            : widget.state.position;
    final baseMoveNumber = position?.fullmoves ?? 1;
    final isWhiteToMove = (position?.turn ?? Side.white) == Side.white;

    // Get user's PV count setting (caps at 5)
    final engineSettings = ref.watch(engineSettingsProviderNew).valueOrNull;
    final multiPV = engineSettings?.multiPvForLichess() ?? 3;

    // Check if position is terminal (game over)
    final isGameOver = position?.isGameOver ?? false;

    const double basePvHeight = 78;
    final double pvCardHeight = basePvHeight.h;

    // Clamp PVs to user preference
    final clampedLines = (widget.state.principalVariations.length > multiPV)
        ? widget.state.principalVariations.take(multiPV).toList(growable: false)
        : widget.state.principalVariations.toList(growable: false);

    // Determine loading state for PV cards
    final showEndOfGame = isGameOver && widget.state.isAnalysisMode;
    final showSkeleton =
        !showEndOfGame && clampedLines.isEmpty && widget.state.isEvaluating;
    final pageCount = showSkeleton ? 1 : clampedLines.length;

    return Padding(
      padding: EdgeInsets.fromLTRB(20.sp, 8.sp, 20.sp, 8.sp),
      child: Column(
        key: ValueKey(
          clampedLines
              .map((line) => '${line.sanMoves.join(' ')}|${line.displayEval}')
              .join('|'),
        ),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: pvCardHeight,
            child:
                showEndOfGame
                    ? Center(
                      child: Container(
                        width: MediaQuery.of(context).size.width - 40.sp,
                        margin: EdgeInsets.symmetric(horizontal: 2.sp),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: kPrimaryColor.withValues(alpha: 0.3),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(6.sp),
                          color: kPrimaryColor.withValues(alpha: 0.1),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.sp,
                          vertical: 10.sp,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.flag_outlined,
                              color: kPrimaryColor,
                              size: 20.sp,
                            ),
                            SizedBox(width: 8.w),
                            Text(
                              'Game Over',
                              style: TextStyle(
                                color: kWhiteColor,
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    : PageView.builder(
                      controller: _pageController,
                      onPageChanged: (pageIndex) {
                        setState(() {
                          _currentPage = pageIndex;
                          _lastUserSelectedIndex = pageIndex;
                        });
                        // Update variant selection when page changes
                        notifier.selectVariant(pageIndex);
                      },
                      itemCount: pageCount,
                      itemBuilder: (context, index) {
                        if (showSkeleton) {
                          final activeVariantColor = notifier.getVariantColor(
                            0,
                            true,
                          );
                          final borderColor = activeVariantColor.withValues(
                            alpha: 0.7,
                          );
                          final backgroundColor = activeVariantColor.withValues(
                            alpha: 0.15,
                          );
                          final badgeBackgroundColor = activeVariantColor
                              .withValues(alpha: 0.3);
                          final badgeBorderColor = activeVariantColor
                              .withValues(alpha: 0.6);

                          return Container(
                            width: MediaQuery.of(context).size.width - 40.sp,
                            margin: EdgeInsets.symmetric(horizontal: 2.sp),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: borderColor,
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(6.sp),
                              color: backgroundColor,
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 12.sp,
                                vertical: 10.sp,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: EdgeInsets.only(right: 10.sp),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8.sp,
                                      vertical: 4.sp,
                                    ),
                                    decoration: BoxDecoration(
                                      color: badgeBackgroundColor,
                                      borderRadius: BorderRadius.circular(4.sp),
                                      border: Border.all(
                                        color: badgeBorderColor,
                                        width: 1.0,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '...',
                                      style: AppTypography.textXsMedium
                                          .copyWith(
                                            color: kWhiteColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '...',
                                      softWrap: true,
                                      style: AppTypography.textXsMedium
                                          .copyWith(
                                            color: kWhiteColor.withValues(
                                              alpha: 0.9,
                                            ),
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        final variantIndex = index;
                        final line = clampedLines[index];
                        final isSelected =
                            widget.state.selectedVariantIndex == variantIndex;

                        final sanMoves = _formatPv(
                          line.sanMoves,
                          baseMoveNumber,
                          isWhiteToMove,
                        );
                        final evalText = _formatEvalLabel(line);

                        // Get variant color matching the arrow color
                        final activeVariantColor = notifier.getVariantColor(
                          variantIndex,
                          true,
                        );
                        final borderColor = activeVariantColor.withValues(
                          alpha: 0.7,
                        );
                        final backgroundColor = activeVariantColor.withValues(
                          alpha: 0.15,
                        );
                        final badgeBackgroundColor = activeVariantColor
                            .withValues(alpha: 0.3);
                        final badgeBorderColor = activeVariantColor.withValues(
                          alpha: 0.6,
                        );

                        // Never darken cards - show data immediately and update silently

                        return GestureDetector(
                          // DISABLED: PV cards are now read-only
                          // onTap:
                          //     isEvaluating
                          //         ? null
                          //         : () {
                          //           HapticFeedback.selectionClick();
                          //           if (isSelected) {
                          //             notifier.playVariantMoveForward();
                          //           } else {
                          //             notifier.playPrincipalVariationMove(
                          //               line,
                          //             );
                          //           }
                          //         },
                          child: Container(
                            width: MediaQuery.of(context).size.width - 40.sp,
                            margin: EdgeInsets.symmetric(horizontal: 2.sp),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: borderColor,
                                width: isSelected ? 2.0 : 1.5,
                              ),
                              borderRadius: BorderRadius.circular(6.sp),
                              color: backgroundColor,
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.symmetric(
                                horizontal: 12.sp,
                                vertical: 10.sp,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    margin: EdgeInsets.only(right: 10.sp),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8.sp,
                                      vertical: 4.sp,
                                    ),
                                    decoration: BoxDecoration(
                                      color: badgeBackgroundColor,
                                      borderRadius: BorderRadius.circular(4.sp),
                                      border: Border.all(
                                        color: badgeBorderColor,
                                        width: 1.0,
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      child: Text(
                                        evalText,
                                        key: ValueKey(evalText),
                                        style: AppTypography.textXsMedium
                                            .copyWith(
                                              color: kWhiteColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      sanMoves.join(' '),
                                      softWrap: true,
                                      style: AppTypography.textXsMedium
                                          .copyWith(
                                            color: kWhiteColor.withValues(
                                              alpha: 0.9,
                                            ),
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
          ),
          if (pageCount > 1) ...[
            SizedBox(height: 8.h),
            Builder(
              builder: (context) {
                final safeIndex = _currentPage.clamp(0, pageCount - 1);
                final activeColor = notifier.getVariantColor(safeIndex, true);
                return SmoothPageIndicator(
                  controller: _pageController,
                  count: pageCount,
                  effect: ScrollingDotsEffect(
                    activeDotColor: activeColor,
                    dotColor: kWhiteColor.withValues(alpha: 0.3),
                    dotHeight: 6.w,
                    dotWidth: 6.w,
                    activeDotScale: 1.33,
                    spacing: 6.w,
                    maxVisibleDots: 5,
                  ),
                  onDotClicked: (index) {
                    _lastUserSelectedIndex = index;
                    _pageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  List<String> _formatPv(
    List<String> sanMoves,
    int baseMoveNumber,
    bool whiteToMove,
  ) {
    final formatted = <String>[];
    for (var i = 0; i < sanMoves.length; i++) {
      // Determine if the current move in the PV is a white move
      // If whiteToMove is true, then even indices (0, 2, 4...) are white moves
      // If whiteToMove is false, then odd indices (1, 3, 5...) are white moves
      final isWhiteMove = whiteToMove ? i.isEven : i.isOdd;

      // Calculate the full move number
      // When it's white to move, move i=0 is at baseMoveNumber, i=2 is at baseMoveNumber+1, etc.
      // When it's black to move, move i=0 is black's move at baseMoveNumber, i=1 is white's move at baseMoveNumber+1
      final moveNumber =
          whiteToMove
              ? baseMoveNumber +
                  (i ~/ 2) // White starts: 0,1 -> base, 2,3 -> base+1
              : baseMoveNumber +
                  ((i + 1) ~/ 2); // Black starts: 0 -> base, 1,2 -> base+1

      // Add move number prefix only for white moves
      if (isWhiteMove) {
        formatted.add('$moveNumber.');
      }

      // Add the move notation
      formatted.add(sanMoves[i]);
    }
    return formatted;
  }

  void _jumpToPage(int targetPage, {required bool animate}) {
    if (!mounted) return;
    if (_lastNonEmptyLines.isEmpty) return;
    final clampedTarget = targetPage.clamp(0, maxPageIndex);
    if (_pendingPageJump == clampedTarget &&
        _pendingPageJumpAnimated == animate) {
      return;
    }
    _pendingPageJump = clampedTarget;
    _pendingPageJumpAnimated = animate;

    void performJump() {
      if (!mounted) return;
      if (!_pageController.hasClients) {
        _pendingPageJump = null;
        return;
      }

      final current =
          _pageController.page?.round() ?? _pageController.initialPage;
      if (current == clampedTarget) {
        _pendingPageJump = null;
        return;
      }

      if (animate) {
        _pageController.animateToPage(
          clampedTarget,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        _pageController.jumpToPage(clampedTarget);
      }
      _pendingPageJump = null;
    }

    if (_pageController.hasClients) {
      performJump();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => performJump());
    }
  }

  void _scheduleVariantSelection(int index) {
    if (!mounted) return;
    if (_pendingVariantSelectionIndex == index) return;
    _pendingVariantSelectionIndex = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final params = ChessBoardProviderParams(
        game: widget.game,
        index: widget.index,
      );
      ref
          .read(chessBoardScreenProviderNew(params).notifier)
          .selectVariant(index);
      _pendingVariantSelectionIndex = null;
    });
  }

  int get maxPageIndex {
    final count = _lastNonEmptyLines.length;
    return count == 0 ? 0 : count - 1;
  }

  String _derivePositionKey(ChessBoardStateNew state) {
    final pos =
        state.isAnalysisMode ? state.analysisState.position : state.position;
    return pos?.fen ?? state.game.fen ?? '';
  }

  String _formatEvalLabel(AnalysisLine line) {
    if (line.isMate) {
      final mate = line.mate ?? 0;
      final absMate = mate.abs();
      final prefix = mate >= 0 ? '#+' : '#-';
      return '$prefix$absMate';
    }

    final eval = line.evaluation;
    if (eval == null) {
      return '--';
    }

    final formatted = eval.abs().toStringAsFixed(1);
    return eval >= 0 ? '+$formatted' : '-$formatted';
  }
}

/// Blinking red dot indicator widget to show unseen moves
class _BlinkingRedDot extends StatefulWidget {
  final double size;

  const _BlinkingRedDot({this.size = 8.0});

  @override
  State<_BlinkingRedDot> createState() => _BlinkingRedDotState();
}

class _BlinkingRedDotState extends State<_BlinkingRedDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: _animation.value),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: _animation.value * 0.5),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SkeletonContainer extends StatefulWidget {
  final double height;
  final double width;
  final double borderRadius;

  const _SkeletonContainer({
    required this.height,
    required this.width,
    required this.borderRadius,
  });

  @override
  State<_SkeletonContainer> createState() => _SkeletonContainerState();
}

class _SkeletonContainerState extends State<_SkeletonContainer>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _animationController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: kWhiteColor.withValues(alpha: _animation.value * 0.15),
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}

/// Isolated widget for each move notation to prevent layout shifts
/// Only this widget rebuilds when its impact calculation completes
class _MoveNotationWidget extends HookConsumerWidget {
  final GamesTourModel game;
  final int index;
  final int currentPageIndex;
  final int moveIndex;
  final String move;
  final int modeAwareCurrentIndex;
  final ChessBoardProviderParams boardParams;
  final int totalMoveCount;
  final bool hasUnseenMoves;

  const _MoveNotationWidget({
    super.key,
    required this.game,
    required this.index,
    required this.currentPageIndex,
    required this.moveIndex,
    required this.move,
    required this.modeAwareCurrentIndex,
    required this.boardParams,
    required this.totalMoveCount,
    required this.hasUnseenMoves,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCurrentMove = moveIndex == modeAwareCurrentIndex;
    final fullMoveNumber = (moveIndex / 2).floor() + 1;
    final isWhiteMove = moveIndex % 2 == 0;

    // Check if this is the last move and there are unseen moves
    final isLastMove = moveIndex == totalMoveCount - 1;
    final showUnseenIndicator = isLastMove && hasUnseenMoves;

    // DISABLED: Move impact calculation in notation list
    // This was causing eval bar to get stuck because it creates 100+ provider watchers
    // that all rebuild on every navigation, keeping isEvaluating = true
    // Move impacts are ONLY shown on the board overlay for the current move
    MoveImpactAnalysis? impact;

    final displayText = isWhiteMove ? '$fullMoveNumber. $move' : move;
    final impactSymbol = ''; // No impact symbols in notation list

    // Determine text color - PRIORITY: current move > default
    final params = ChessBoardProviderParams(game: game, index: index);
    Color textColor;

    if (isCurrentMove) {
      textColor = kWhiteColor;
    } else {
      textColor = ref
          .read(chessBoardScreenProviderNew(params).notifier)
          .getMoveColor(move, moveIndex);
    }

    return GestureDetector(
      onTap: () {
        unawaited(
          ref
              .read(chessBoardScreenProviderNew(params).notifier)
              .goToMove(moveIndex),
        );
        // If tapping on the last move, clear the unseen indicator
        if (isLastMove && hasUnseenMoves) {
          ref
              .read(chessBoardScreenProviderNew(params).notifier)
              .markMovesAsSeen();
        }
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6.sp, vertical: 2.sp),
            decoration: BoxDecoration(
              color:
                  isCurrentMove
                      ? kWhiteColor70.withValues(alpha: 0.4)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(4.sp),
              border: Border.all(
                color: isCurrentMove ? kWhiteColor : Colors.transparent,
                width: 0.5,
              ),
            ),
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: displayText,
                    style: AppTypography.textXsMedium.copyWith(
                      color: textColor,
                      fontWeight:
                          isCurrentMove ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  if (impactSymbol.isNotEmpty)
                    TextSpan(
                      text: impactSymbol,
                      style: AppTypography.textXsMedium.copyWith(
                        color: impact!.impact.color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Show red dot indicator on top-right corner if this is the last unseen move
          if (showUnseenIndicator)
            Positioned(
              top: -2.sp,
              right: -2.sp,
              child: _BlinkingRedDot(size: 6.sp),
            ),
        ],
      ),
    );
  }
}

// Share Game Screen Widget
class _ShareGameScreen extends ConsumerWidget {
  final GamesTourModel game;
  final ChessBoardStateNew state;
  final String pgn;

  const _ShareGameScreen({
    required this.game,
    required this.state,
    required this.pgn,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get board settings for creating the board widget
    final boardSettingsValue = ref.watch(boardSettingsProvider);
    final boardTheme = ref
        .read(boardSettingsRepository)
        .getBoardTheme(boardSettingsValue.boardColor);

    // Build board settings for the share overlay board (sized responsively inside the overlay)
    final boardSettings = ChessboardSettings(
      enableCoordinates: false,
      colorScheme: ChessboardColorScheme(
        lightSquare: boardTheme.lightSquareColor,
        darkSquare: boardTheme.darkSquareColor,
        background: SolidColorChessboardBackground(
          lightSquare: boardTheme.lightSquareColor,
          darkSquare: boardTheme.darkSquareColor,
        ),
        whiteCoordBackground: SolidColorChessboardBackground(
          lightSquare: boardTheme.lightSquareColor,
          darkSquare: boardTheme.darkSquareColor,
          coordinates: false,
          orientation: Side.white,
        ),
        blackCoordBackground: SolidColorChessboardBackground(
          lightSquare: boardTheme.lightSquareColor,
          darkSquare: boardTheme.darkSquareColor,
          coordinates: false,
          orientation: Side.black,
        ),
        lastMove: HighlightDetails(
          solidColor: boardTheme.lightSquareColor.withValues(alpha: 0),
        ),
        selected: HighlightDetails(
          solidColor: boardTheme.lightSquareColor.withValues(alpha: 0),
        ),
        validMoves: boardTheme.lightSquareColor.withValues(alpha: 0),
        validPremoves: boardTheme.lightSquareColor.withValues(alpha: 0),
      ),
      borderRadius: const BorderRadius.all(Radius.circular(0)),
      boxShadow: const [],
    );

    // Calculate clock times at current position (same logic as PlayerFirstRowDetailWidget)
    final effectiveMoveIndex = state.analysisState.currentMoveIndex;

    String? whiteTime;
    String? blackTime;

    if (state.moveTimes.isNotEmpty) {
      // Find white player's most recent move up to current position
      for (int i = effectiveMoveIndex; i >= 0; i--) {
        final isWhiteMove = i % 2 == 0;
        if (isWhiteMove && i < state.moveTimes.length) {
          whiteTime = state.moveTimes[i];
          break;
        }
      }

      // Find black player's most recent move up to current position
      for (int i = effectiveMoveIndex; i >= 0; i--) {
        final isBlackMove = i % 2 == 1;
        if (isBlackMove && i < state.moveTimes.length) {
          blackTime = state.moveTimes[i];
          break;
        }
      }
    }

    // Fallback to game model's time display
    whiteTime ??= game.whiteTimeDisplay;
    blackTime ??= game.blackTimeDisplay;

    // Format tournament and round names for better display
    final tournamentName =
        game.tourSlug != null ? StringUtils.slugToTitle(game.tourSlug!) : null;
    final roundInfo =
        game.roundSlug != null
            ? StringUtils.formatRoundLabel(game.roundSlug)
            : null;

    return ShareGameCardOverlay(
      boardSettings: boardSettings,
      positionFen: state.analysisState.position.fen,
      lastMove: state.analysisState.lastMove,
      pgn: pgn,
      moveSans:
          state
              .analysisState
              .moveSans, // Pass the actual move list from analysis state
      whitePlayerName: game.whitePlayer.name,
      blackPlayerName: game.blackPlayer.name,
      whitePlayerCountry: game.whitePlayer.federation,
      blackPlayerCountry: game.blackPlayer.federation,
      whitePlayerElo: game.whitePlayer.rating.toString(),
      blackPlayerElo: game.blackPlayer.rating.toString(),
      whitePlayerTitle: game.whitePlayer.title,
      blackPlayerTitle: game.blackPlayer.title,
      whitePlayerClock: whiteTime,
      blackPlayerClock: blackTime,
      tournamentName: tournamentName,
      roundInfo: roundInfo,
      currentMoveIndex: state.analysisState.currentMoveIndex,
      evaluation: state.evaluation,
      mate: state.mate ?? 0,
      isFlipped: state.isBoardFlipped,
      gameStatus: game.gameStatus,
      gameId: game.gameId, // Pass game ID for correct eval display
      onClose: () => Navigator.of(context).pop(),
    );
  }
}
