import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:chessever2/screens/standings/score_card_screen.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/repository/local_storage/board_settings_repository/board_settings_repository.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/move_impact_analyzer.dart';
import 'package:chessever2/screens/chessboard/analysis/simple_move_impact.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/notation/notation_cache.dart';
import 'package:chessever2/screens/chessboard/notation/notation_pointer.dart';
import 'package:chessever2/screens/chessboard/notation/notation_tree.dart';
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
import 'package:collection/collection.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/divider_widget.dart';
import 'package:flutter_svg/svg.dart';
import 'package:heroine/heroine.dart';

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

bool _gameHasCustomVariations(ChessGame? game) {
  if (game == null) return false;
  bool found = false;

  void visit(List<ChessMove> moves) {
    for (final move in moves) {
      final variations = move.variations ?? const <ChessLine>[];
      if (variations.isNotEmpty) {
        found = true;
        return;
      }
      for (final variation in variations) {
        if (found) return;
        visit(variation);
      }
    }
  }

  visit(game.mainline);
  return found;
}

Future<bool?> _showAnalysisConfirmationDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  Color? confirmColor,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: kBlack2Color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.br),
        ),
        title: Text(
          title,
          style: AppTypography.textMdBold.copyWith(color: kWhiteColor),
        ),
        content: Text(
          message,
          style: AppTypography.textSmRegular.copyWith(
            color: kWhiteColor.withValues(alpha: 0.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: AppTypography.textSmMedium.copyWith(
                color: kWhiteColor.withValues(alpha: 0.7),
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(true);
            },
            child: Text(
              confirmLabel,
              style: AppTypography.textSmMedium.copyWith(
                color: confirmColor ?? kPrimaryColor,
              ),
            ),
          ),
        ],
      );
    },
  );
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
  final Set<String> _syncedLatestPositions = <String>{};
  bool _isRevertingPage = false;

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

  void _ensureLatestMoveSelected({
    required WidgetRef ref,
    required int pageIndex,
    required ChessBoardStateNew state,
  }) {
    if (pageIndex != _currentPageIndex) return;
    if (state.isLoadingMoves) return;

    final gameId = state.game.gameId;
    if (_syncedLatestPositions.contains(gameId)) {
      return;
    }

    final totalMoves = state.analysisState.allMoves.length;
    if (totalMoves == 0) {
      return; // Wait until we have at least one move before syncing
    }

    final lastMoveIndex = totalMoves - 1;
    final currentIndex = state.analysisState.currentMoveIndex;

    if (currentIndex >= lastMoveIndex) {
      _syncedLatestPositions.add(gameId);
      return;
    }

    final params = ChessBoardProviderParams(game: state.game, index: pageIndex);
    final targetGameId = gameId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_currentPageIndex != pageIndex) {
        _syncedLatestPositions.remove(targetGameId);
        return;
      }
      final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
      notifier.goToMove(lastMoveIndex);
    });

    _syncedLatestPositions.add(gameId);
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
          final notifier = ref.read(
            chessBoardScreenProviderNew(params).notifier,
          );
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
    unawaited(_handlePageChange(newIndex));
  }

  Future<bool> _confirmLeaveAnalysisIfNeeded(int pageIndex) async {
    if (!mounted) return true;
    if (pageIndex < 0 || pageIndex >= widget.games.length) {
      return true;
    }

    final game = _resolveGameForIndex(pageIndex);
    final params = ChessBoardProviderParams(game: game, index: pageIndex);
    final state = ref.read(chessBoardScreenProviderNew(params)).valueOrNull;
    final analysisGame = state?.analysisState.game;

    if (analysisGame == null) {
      return true;
    }

    final hasCustomAnalysis = _gameHasCustomVariations(analysisGame);
    if (!hasCustomAnalysis) {
      return true;
    }

    final confirmed = await _showAnalysisConfirmationDialog(
          context: context,
          title: 'Leave analysis?',
          message:
              'You have local analysis variations for this game. Leaving now will discard your move tree progress.',
          confirmLabel: 'Leave',
          confirmColor: kRedColor,
        ) ??
        false;
    return confirmed;
  }

  Future<void> _handlePageChange(int newIndex) async {
    if (_isRevertingPage) {
      _isRevertingPage = false;
      return;
    }

    if (_currentPageIndex == newIndex) return;

    final previousIndex = _currentPageIndex;
    final canLeave = await _confirmLeaveAnalysisIfNeeded(previousIndex);
    if (!mounted) return;

    if (!canLeave) {
      _isRevertingPage = true;
      _pageController.animateToPage(
        previousIndex,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
      return;
    }

    _lastViewedIndex = newIndex;

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
      final prevNotifier = ref.read(
        chessBoardScreenProviderNew(prevParams).notifier,
      );
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
          final notifier = ref.read(
            chessBoardScreenProviderNew(params).notifier,
          );
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
                    _ensureLatestMoveSelected(
                      ref: ref,
                      pageIndex: index,
                      state: chessBoardState,
                    );
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
    String? pgn;
    final params = ChessBoardProviderParams(
      game: game,
      index: currentGameIndex,
    );
    final boardState = ref.read(chessBoardScreenProviderNew(params));
    final analysisGame = boardState.valueOrNull?.analysisState.game;
    if (analysisGame != null) {
      pgn = exportGameToPgn(analysisGame);
    }
    pgn ??=
        (await ref.read(gameRepositoryProvider).getGameById(game.gameId)).pgn ??
        '';
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
    ChessGameNavigatorState? navigatorState;
    final analysisGame = state.analysisState.game;
    if (analysisGame != null) {
      navigatorState = ref.watch(chessGameNavigatorProvider(analysisGame));
    }
    final canMoveForward =
        navigatorState?.canGoForward ?? state.analysisState.canMoveForward;
    final canMoveBackward =
        navigatorState?.canGoBackward ?? state.analysisState.canMoveBackward;

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
    final params = ChessBoardProviderParams(game: game, index: index);
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
          Stack(
            clipBehavior: Clip.none,
            children: [
              _PrincipalVariationList(index: index, state: state, game: game),
              Positioned(
                top: 0,
                right: -12.sp,
                child: _AnalysisActionButtons(
                  params: params,
                  alignWithPvArea: true,
                ),
              ),
            ],
          ),
          // DISABLED: Analysis navigation arrows hidden
          // _AnalysisControlsRow(index: index, game: game),
        ],
        Expanded(
          child: _MovesDisplay(
            index: index,
            currentPageIndex: currentPageIndex,
            state: state,
            game: game,
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
                  child: Builder(
                    builder: (context) {
                      final activePosition =
                          state.isAnalysisMode
                              ? state.analysisState.position
                              : state.position;
                      final bool isWhiteToMove =
                          activePosition?.turn != Side.black;

                      return EvaluationBarWidget(
                        width: sideBarWidth,
                        height: boardSize,
                        evaluation: state.evaluation,
                        mate: state.mate,
                        isEvaluating: state.isEvaluating,
                        isFlipped: state.isBoardFlipped,
                        isWhiteToMove: isWhiteToMove,
                        positionKey: activePosition?.fen,
                      );
                    },
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
    final boardSettingsAsync = ref.watch(boardSettingsProviderNew);
    final boardSettings =
        boardSettingsAsync.valueOrNull ?? const BoardSettingsNew();
    final boardTheme = ref
        .read(boardSettingsRepository)
        .getBoardTheme(boardSettings.boardColorValue);
    final params = ChessBoardProviderParams(game: game, index: index);
    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);

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
        pieceShiftMethod: PieceShiftMethod.tapTwoSquares,
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
      game: GameData(
        playerSide:
            chessBoardState.analysisState.position.turn == Side.white
                ? PlayerSide.white
                : PlayerSide.black,
        validMoves: chessBoardState.analysisState.validMoves,
        sideToMove: chessBoardState.analysisState.position.turn,
        isCheck: chessBoardState.analysisState.position.isCheck,
        promotionMove: chessBoardState.analysisState.promotionMove,
        onMove: notifier.onAnalysisMove,
        onPromotionSelection: notifier.onAnalysisPromotionSelection,
      ),
    );
  }
}

class _SkeletonContainer extends StatelessWidget {
  final double height;
  final double width;
  final double borderRadius;

  const _SkeletonContainer({
    required this.height,
    required this.width,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: kWhiteColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
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
  static const int _autoCollapseDepth = 3;
  static const int _autoCollapseMoveThreshold = 12;
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _moveKeys = {};
  final ListEquality<int> _pointerEquality = const ListEquality<int>();
  final Set<String> _collapsedVariationIds = <String>{};
  final Set<String> _expandedVariationIds = <String>{};
  bool _hasInitiallyScrolled = false;
  String? _lastSignature;
  ChessMovePointer? _lastPointer;

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

    final analysisGame = widget.state.analysisState.game;
    if (analysisGame == null) {
      return Container(
        alignment: Alignment.center,
        padding: EdgeInsets.all(20.sp),
        child: Text(
          'No moves available for this game',
          style: AppTypography.textXsMedium.copyWith(
            color: kWhiteColor70,
            fontWeight: FontWeight.normal,
          ),
        ),
      );
    }

    final params = ChessBoardProviderParams(
      game: widget.game,
      index: widget.index,
    );
    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
    final navigatorState = ref.watch(chessGameNavigatorProvider(analysisGame));
    final signature = notationGameSignature(navigatorState.game);

    if (_lastSignature != signature) {
      _moveKeys.clear();
      _hasInitiallyScrolled = false;
      _lastSignature = signature;
    }

    final notationParams = NotationTreeParams(
      game: navigatorState.game,
      signature: signature,
    );
    final tree = ref.watch(notationTreeProvider(notationParams));

    final hasMoves = tree.mainline.isNotEmpty;
    final tailNode = hasMoves ? tree.mainline.last : null;
    final tailPointerId =
        tailNode != null ? NotationPointer.encode(tailNode.pointer) : null;

    ChessMovePointer pointerCandidate = navigatorState.movePointer;
    if (pointerCandidate.isEmpty &&
        widget.state.analysisState.movePointer.isNotEmpty) {
      pointerCandidate = widget.state.analysisState.movePointer;
    }
    final hasPointer = pointerCandidate.isNotEmpty;
    final isAtTailByIndex =
        hasMoves &&
        widget.state.analysisState.currentMoveIndex == tree.mainline.length - 1;
    final shouldFallbackToTail =
        !hasPointer && isAtTailByIndex && tailNode != null;

    final pointerForHighlightId =
        hasPointer
            ? NotationPointer.encode(pointerCandidate)
            : shouldFallbackToTail
            ? tailPointerId
            : null;
    final pointerForScroll =
        hasPointer
            ? pointerCandidate
            : shouldFallbackToTail
            ? List<Number>.of(tailNode.pointer)
            : const <Number>[];

    if (pointerForScroll.isNotEmpty) {
      _schedulePointerScroll(pointerForScroll, pointerForHighlightId);
    }

    final forcedOpenIds = <String>{};
    _collectVariationAncestors(
      pointerForHighlightId,
      tree.mainline,
      forcedOpenIds,
    );

    final pointerMap = <String, NotationMoveNode>{};
    final tokens = _buildTokens(
      tree.mainline,
      depth: 0,
      pointerMap: pointerMap,
      forcedOpenIds: forcedOpenIds,
    );

    if (tokens.isEmpty) {
      return Container(
        alignment: Alignment.center,
        padding: EdgeInsets.all(20.sp),
        child: Text(
          'No moves available for this game',
          style: AppTypography.textXsMedium.copyWith(
            color: kWhiteColor70,
            fontWeight: FontWeight.normal,
          ),
        ),
      );
    }

    final currentNode =
        pointerForHighlightId != null
            ? pointerMap[pointerForHighlightId]
            : null;
    final currentPly = currentNode?.ply ?? -1;

    final notationContent = SingleChildScrollView(
      controller: _scrollController,
      child: Container(
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.all(20.sp),
        child: Wrap(
          spacing: 2.sp,
          runSpacing: 2.sp,
          children:
              tokens.map((token) {
                switch (token.type) {
                  case _NotationTokenType.move:
                    return _buildMoveChip(
                      token,
                      params,
                      notifier,
                      currentPly,
                      pointerForHighlightId,
                      tailPointerId,
                    );
                  case _NotationTokenType.openParen:
                  case _NotationTokenType.closeParen:
                  case _NotationTokenType.ellipsis:
                  case _NotationTokenType.variationPlaceholder:
                    return _buildAuxToken(token);
                }
              }).toList(),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: kDarkGreyColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12.sp),
          topRight: Radius.circular(12.sp),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: notationContent),
          // Full overlay when preview is active
          if (widget.state.isPvPreviewActive)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  // Tap anywhere on overlay to exit preview
                  ref
                      .read(chessBoardScreenProviderNew(params).notifier)
                      .clearPvPreview();
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: kBlackColor.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12.sp),
                      topRight: Radius.circular(12.sp),
                    ),
                  ),
                ),
              ),
            ),
          if (widget.state.isPvPreviewActive)
            Positioned(
              top: 16.sp,
              left: 20.sp,
              right: 20.sp,
              child: _PreviewBanner(
                onExit: () {
                  ref
                      .read(chessBoardScreenProviderNew(params).notifier)
                      .clearPvPreview();
                },
              ),
            ),
          if (!widget.state.showPrincipalVariations)
            Positioned(
              top: 0,
              right: -12.sp,
              child: _AnalysisActionButtons(params: params),
            ),
        ],
      ),
    );
  }

  Widget _buildMoveChip(
    _NotationDisplayToken token,
    ChessBoardProviderParams params,
    ChessBoardScreenNotifierNew notifier,
    int currentPly,
    String? currentPointerId,
    String? tailPointerId,
  ) {
    final pointerId = token.pointerId;
    final key =
        pointerId == null
            ? null
            : _moveKeys.putIfAbsent(pointerId, () => GlobalKey());
    final isCurrent = pointerId != null && pointerId == currentPointerId;
    final isTail =
        pointerId != null &&
        tailPointerId != null &&
        pointerId == tailPointerId;
    final color = _resolveMoveColor(token, notifier, currentPly);

    return GestureDetector(
      key: key,
      onTap: () {
        final pointer = token.pointer;
        if (pointer == null) return;
        ref
            .read(chessBoardScreenProviderNew(params).notifier)
            .goToMovePointer(pointer);
        if (isTail && widget.state.hasUnseenMoves) {
          ref
              .read(chessBoardScreenProviderNew(params).notifier)
              .markMovesAsSeen();
        }
      },
      onLongPress: () {
        if (token.isVariationHead &&
            token.variationHeadPointer != null &&
            token.variationMoves != null) {
          _showVariationMenu(
            context,
            params,
            token.variationHeadPointer!,
            token.variationMoves!,
          );
        } else {
          _showMoveMenu(context, params, token.pointer);
        }
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 6.sp, vertical: 2.sp),
            decoration: BoxDecoration(
              color:
                  isCurrent
                      ? kWhiteColor70.withValues(alpha: 0.25)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(4.sp),
              border: Border.all(
                color: isCurrent ? kWhiteColor : Colors.transparent,
                width: 0.7,
              ),
            ),
            child: Text(
              token.text,
              style: AppTypography.textXsMedium.copyWith(
                color: color,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (isTail && widget.state.hasUnseenMoves)
            Positioned(
              top: -2.sp,
              right: -2.sp,
              child: _BlinkingRedDot(size: 6.sp),
            ),
        ],
      ),
    );
  }

  Widget _buildAuxToken(_NotationDisplayToken token) {
    final isVariationToken =
        token.variation != null && token.type != _NotationTokenType.ellipsis;

    Widget child;
    if (token.type == _NotationTokenType.variationPlaceholder) {
      child = Container(
        padding: EdgeInsets.symmetric(horizontal: 6.sp, vertical: 2.sp),
        decoration: BoxDecoration(
          color: kWhiteColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4.sp),
        ),
        child: Text(
          token.text,
          style: AppTypography.textXsMedium.copyWith(
            color: kWhiteColor70,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    } else {
      child = Text(
        token.text,
        style: AppTypography.textXsMedium.copyWith(
          color: kWhiteColor.withValues(
            alpha: (0.6 - token.depth * 0.05).clamp(0.3, 0.7),
          ),
          fontStyle:
              token.type == _NotationTokenType.ellipsis
                  ? FontStyle.normal
                  : FontStyle.italic,
        ),
      );
    }

    if (!isVariationToken || token.variation == null) {
      return child;
    }

    return GestureDetector(
      onTap: () => _toggleVariationCollapse(token),
      child: child,
    );
  }

  void _toggleVariationCollapse(_NotationDisplayToken token) {
    final variation = token.variation;
    if (variation == null || token.isForcedOpen) {
      HapticFeedback.lightImpact();
      return;
    }

    final variationId = variation.id;
    final defaultCollapsed = token.defaultsToCollapsed;

    setState(() {
      if (defaultCollapsed) {
        if (_expandedVariationIds.remove(variationId)) {
          // revert to default collapsed
        } else {
          _expandedVariationIds.add(variationId);
          _collapsedVariationIds.remove(variationId);
        }
      } else {
        if (_collapsedVariationIds.remove(variationId)) {
          // revert to expanded state
        } else {
          _collapsedVariationIds.add(variationId);
          _expandedVariationIds.remove(variationId);
        }
      }
    });
    HapticFeedback.selectionClick();
  }

  Color _resolveMoveColor(
    _NotationDisplayToken token,
    ChessBoardScreenNotifierNew notifier,
    int currentPly,
  ) {
    final node = token.node;
    if (node == null) {
      return kWhiteColor70;
    }

    if (token.pointerId == null) {
      return kWhiteColor70;
    }

    final isPast = currentPly >= 0 && node.ply <= currentPly;
    if (node.isMainline) {
      return isPast ? kWhiteColor : kWhiteColor70;
    }

    final colorIndex = token.variationIndex ?? 0;
    final baseColor = notifier.getVariantColor(colorIndex, false);
    return baseColor.withValues(alpha: isPast ? 0.95 : 0.65);
  }

  List<_NotationDisplayToken> _buildTokens(
    List<NotationMoveNode> moves, {
    required int depth,
    NotationVariationNode? variationContext,
    required Map<String, NotationMoveNode> pointerMap,
    required Set<String> forcedOpenIds,
  }) {
    final tokens = <_NotationDisplayToken>[];
    for (var i = 0; i < moves.length; i++) {
      final node = moves[i];
      final pointerList = List<Number>.of(node.pointer);
      final pointerId = NotationPointer.encode(pointerList);
      pointerMap[pointerId] = node;
      final isVariationHead = variationContext != null && i == 0;

      final text = _formatMoveText(
        node,
        suppressBlackMovePrefix: isVariationHead,
      );
      final variationMovesList = variationContext?.moves;
      final variationHeadPointer =
          isVariationHead && (variationMovesList?.isNotEmpty ?? false)
              ? List<Number>.of(variationMovesList!.first.pointer)
              : null;
      tokens.add(
        _NotationDisplayToken(
          type: _NotationTokenType.move,
          text: text,
          depth: depth,
          pointerId: pointerId,
          node: node,
          pointer: pointerList,
          variationIndex: variationContext?.variationIndex,
          isVariationHead: isVariationHead,
          variationHeadPointer: variationHeadPointer,
          variationMoves: variationMovesList,
        ),
      );

      for (final variation in node.variations) {
        final defaultCollapsed = _shouldCollapseByDefault(variation);
        final forcedOpen = forcedOpenIds.contains(variation.id);
        final manuallyCollapsed = _collapsedVariationIds.contains(variation.id);
        final manuallyExpanded = _expandedVariationIds.contains(variation.id);

        bool collapsed = defaultCollapsed;
        if (forcedOpen) {
          collapsed = false;
        } else if (defaultCollapsed) {
          if (manuallyExpanded) {
            collapsed = false;
          } else {
            collapsed = true;
          }
        } else {
          collapsed = manuallyCollapsed;
        }

        tokens.add(
          _NotationDisplayToken(
            type: _NotationTokenType.openParen,
            text: '(',
            depth: variation.depth,
            pointerId: null,
            variationIndex: variation.variationIndex,
            variation: variation,
            isCollapsed: collapsed,
            defaultsToCollapsed: defaultCollapsed,
            isForcedOpen: forcedOpen,
          ),
        );
        if (collapsed) {
          tokens.add(
            _NotationDisplayToken(
              type: _NotationTokenType.variationPlaceholder,
              text: '... ${variation.moves.length} moves',
              depth: variation.depth,
              pointerId: null,
              variationIndex: variation.variationIndex,
              variation: variation,
              isCollapsed: true,
              defaultsToCollapsed: defaultCollapsed,
              isForcedOpen: forcedOpen,
            ),
          );
        } else {
          tokens.addAll(
            _buildTokens(
              variation.moves,
              depth: variation.depth,
              variationContext: variation,
              pointerMap: pointerMap,
              forcedOpenIds: forcedOpenIds,
            ),
          );
        }
        tokens.add(
          _NotationDisplayToken(
            type: _NotationTokenType.closeParen,
            text: ')',
            depth: variation.depth,
            pointerId: null,
            variationIndex: variation.variationIndex,
            variation: variation,
            isCollapsed: collapsed,
            defaultsToCollapsed: defaultCollapsed,
            isForcedOpen: forcedOpen,
          ),
        );
      }
    }
    return tokens;
  }

  bool _shouldCollapseByDefault(NotationVariationNode variation) {
    if (variation.depth >= _autoCollapseDepth) {
      return true;
    }
    if (variation.moves.length >= _autoCollapseMoveThreshold) {
      return true;
    }
    return false;
  }

  String _formatMoveText(
    NotationMoveNode node, {
    bool suppressBlackMovePrefix = false,
  }) {
    final buffer = StringBuffer();
    if (node.showMoveNumber) {
      final useEllipsis = !node.isWhiteMove && !suppressBlackMovePrefix;
      final separator = useEllipsis ? '... ' : '. ';
      buffer.write('${node.moveNumber}$separator');
    }
    buffer.write(node.move.san);
    return buffer.toString();
  }

  void _schedulePointerScroll(ChessMovePointer pointer, String? pointerId) {
    if (widget.index != widget.currentPageIndex) return;
    if (pointerId == null) return;
    if (_lastPointer != null &&
        _pointerEquality.equals(_lastPointer!, pointer)) {
      return;
    }
    _lastPointer = List.of(pointer);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToPointer(
        pointerId,
        isInitialScroll: !_hasInitiallyScrolled,
        alignment: _hasInitiallyScrolled ? 0.5 : 1.0,
      );
    });
  }

  void _scrollToPointer(
    String pointerId, {
    bool isInitialScroll = false,
    double alignment = 0.5,
  }) {
    if (!_scrollController.hasClients) {
      if (isInitialScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollToPointer(
            pointerId,
            isInitialScroll: true,
            alignment: alignment,
          );
        });
      }
      return;
    }

    final key = _moveKeys[pointerId];
    final context = key?.currentContext;
    if (context == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToPointer(
          pointerId,
          isInitialScroll: isInitialScroll,
          alignment: alignment,
        );
      });
      return;
    }

    final targetContext = context;
    Future.microtask(() {
      if (!mounted) return;
      if (!targetContext.mounted) return;
      Scrollable.ensureVisible(
        targetContext,
        duration:
            isInitialScroll
                ? const Duration(milliseconds: 1)
                : const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        alignment: alignment,
      );
      _hasInitiallyScrolled = true;
    });
  }

  bool _collectVariationAncestors(
    String? pointerId,
    List<NotationMoveNode> moves,
    Set<String> output,
  ) {
    if (pointerId == null) {
      return false;
    }

    for (final node in moves) {
      final nodeId = NotationPointer.encode(node.pointer);
      if (nodeId == pointerId) {
        return true;
      }
      for (final variation in node.variations) {
        if (_collectVariationAncestors(pointerId, variation.moves, output)) {
          output.add(variation.id);
          return true;
        }
      }
    }
    return false;
  }

  Widget _buildMovesLoadingSkeleton() {
    return Container(
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.all(20.sp),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
      ),
    );
  }

  Future<void> _showMoveMenu(
    BuildContext context,
    ChessBoardProviderParams params,
    ChessMovePointer? pointer,
  ) async {
    if (pointer == null) return;
    final action = await showModalBottomSheet<_MoveAction>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.play_arrow),
                title: const Text('Continue from here'),
                onTap: () => Navigator.of(context).pop(_MoveAction.goTo),
              ),
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('Add null move after'),
                onTap: () => Navigator.of(context).pop(_MoveAction.nullMove),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
    switch (action) {
      case _MoveAction.goTo:
        notifier.goToMovePointer(pointer);
        break;
      case _MoveAction.nullMove:
        notifier.goToMovePointer(pointer);
        await notifier.insertNullMoveAfterCurrent();
        if (!context.mounted) return;
        _showInfoSnack(context, 'Null move inserted');
        break;
    }
  }

  Future<void> _showVariationMenu(
    BuildContext context,
    ChessBoardProviderParams params,
    ChessMovePointer headPointer,
    List<NotationMoveNode> moves,
  ) async {
    final action = await showModalBottomSheet<_VariationAction>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.call_split),
                title: const Text('Start from here'),
                onTap: () => Navigator.of(context).pop(_VariationAction.start),
              ),
              ListTile(
                leading: const Icon(Icons.arrow_circle_up),
                title: const Text('Promote to mainline'),
                onTap:
                    () => Navigator.of(context).pop(_VariationAction.promote),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete variation'),
                onTap: () => Navigator.of(context).pop(_VariationAction.delete),
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy line'),
                onTap: () => Navigator.of(context).pop(_VariationAction.copy),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
    switch (action) {
      case _VariationAction.start:
        notifier.goToMovePointer(headPointer);
        break;
      case _VariationAction.promote:
        final snapshot = notifier.navigatorStateSnapshot();
        await notifier.promoteVariationAtPointer(headPointer);
        if (!context.mounted) return;
        if (snapshot != null) {
          _showUndoSnackBar(context, params, snapshot, 'Variation promoted');
        } else {
          _showInfoSnack(context, 'Variation promoted');
        }
        break;
      case _VariationAction.delete:
        final snapshot = notifier.navigatorStateSnapshot();
        await notifier.deleteVariationAtPointer(headPointer);
        if (!context.mounted) return;
        if (snapshot != null) {
          _showUndoSnackBar(context, params, snapshot, 'Variation deleted');
        } else {
          _showInfoSnack(context, 'Variation deleted');
        }
        break;
      case _VariationAction.copy:
        final text = _formatVariationText(moves);
        await Clipboard.setData(ClipboardData(text: text));
        if (!context.mounted) return;
        _showInfoSnack(context, 'Variation copied');
        break;
    }
  }

  void _showUndoSnackBar(
    BuildContext context,
    ChessBoardProviderParams params,
    ChessGameNavigatorState snapshot,
    String message,
  ) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            ref
                .read(chessBoardScreenProviderNew(params).notifier)
                .restoreNavigatorState(snapshot);
          },
        ),
      ),
    );
  }

  void _showInfoSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatVariationText(List<NotationMoveNode> moves) {
    final buffer = StringBuffer();
    var isFirstNode = true;
    for (final node in moves) {
      buffer.write(
        '${_formatMoveText(
          node,
          suppressBlackMovePrefix: isFirstNode,
        )} ',
      );
      isFirstNode = false;
    }
    return buffer.toString().trim();
  }
}

class _AnalysisActionButtons extends ConsumerWidget {
  final ChessBoardProviderParams params;
  final bool alignWithPvArea;

  const _AnalysisActionButtons({
    required this.params,
    this.alignWithPvArea = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chessBoardScreenProviderNew(params)).valueOrNull;
    final analysisGame = state?.analysisState.game;
    final hasCustomAnalysis = _gameHasCustomVariations(analysisGame);
    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RibbonAnalysisButton(
          icon: Icons.auto_delete_outlined,
          color: kRedColor,
          enabled: hasCustomAnalysis,
          onPressed:
              !hasCustomAnalysis
                  ? null
                  : () async {
                    HapticFeedback.selectionClick();
                    final confirmed =
                        await _showAnalysisConfirmationDialog(
                              context: context,
                              title: 'Clear analysis?',
                              message:
                                  'This will remove every custom branch, including nested subvariants. This action cannot be undone.',
                              confirmLabel: 'Clear',
                              confirmColor: kRedColor,
                            ) ??
                            false;
                    if (!confirmed) return;
                    HapticFeedback.heavyImpact();
                    await notifier.clearUserAnalysis();
                  },
        ),
        SizedBox(height: alignWithPvArea ? 10.sp : 12.sp),
        _RibbonAnalysisButton(
          icon: Icons.control_point_duplicate_rounded,
          color: kPrimaryColor,
          onPressed: () {
            HapticFeedback.mediumImpact();
            notifier.insertNullMoveAfterCurrent();
          },
        ),
      ],
    );
  }
}

class _PreviewBanner extends StatelessWidget {
  final VoidCallback onExit;

  const _PreviewBanner({required this.onExit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 12.sp),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            kPrimaryColor.withValues(alpha: 0.85),
            kPrimaryColor.withValues(alpha: 0.65),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10.sp),
        border: Border.all(
          color: kPrimaryColor.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(6.sp),
            decoration: BoxDecoration(
              color: kWhiteColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.visibility_outlined,
              color: kWhiteColor,
              size: 18.sp,
            ),
          ),
          SizedBox(width: 10.sp),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Preview Mode',
                  style: AppTypography.textSmBold.copyWith(
                    color: kWhiteColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Tap anywhere to exit or explore moves',
                  style: AppTypography.textXsRegular.copyWith(
                    color: kWhiteColor.withValues(alpha: 0.85),
                    fontSize: 11.sp,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 8.sp),
          GestureDetector(
            onTap: onExit,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 6.sp),
              decoration: BoxDecoration(
                color: kWhiteColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6.sp),
                border: Border.all(
                  color: kWhiteColor.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.close,
                    color: kWhiteColor,
                    size: 16.sp,
                  ),
                  SizedBox(width: 4.sp),
                  Text(
                    'Exit',
                    style: AppTypography.textXsMedium.copyWith(
                      color: kWhiteColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RibbonAnalysisButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final Color color;
  final bool enabled;

  const _RibbonAnalysisButton({
    required this.icon,
    required this.color,
    this.onPressed,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveOnTap = enabled ? onPressed : null;

    return GestureDetector(
      onTap: effectiveOnTap,
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 13.5.sp, vertical: 10.sp),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.35),
                color.withValues(alpha: 0.25),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(14.sp),
              bottomLeft: Radius.circular(14.sp),
              topRight: Radius.circular(6.sp),
              bottomRight: Radius.circular(6.sp),
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 0.8,
            ),
          ),
          child: Icon(icon, size: 18.sp, color: kWhiteColor),
        ),
      ),
    );
  }
}

enum _NotationTokenType {
  move,
  openParen,
  closeParen,
  ellipsis,
  variationPlaceholder,
}

class _NotationDisplayToken {
  final _NotationTokenType type;
  final String text;
  final int depth;
  final String? pointerId;
  final NotationMoveNode? node;
  final ChessMovePointer? pointer;
  final int? variationIndex;
  final bool isVariationHead;
  final ChessMovePointer? variationHeadPointer;
  final List<NotationMoveNode>? variationMoves;
  final NotationVariationNode? variation;
  final bool isCollapsed;
  final bool defaultsToCollapsed;
  final bool isForcedOpen;

  const _NotationDisplayToken({
    required this.type,
    required this.text,
    required this.depth,
    this.pointerId,
    this.node,
    this.pointer,
    this.variationIndex,
    this.isVariationHead = false,
    this.variationHeadPointer,
    this.variationMoves,
    this.variation,
    this.isCollapsed = false,
    this.defaultsToCollapsed = false,
    this.isForcedOpen = false,
  });
}

enum _MoveAction { goTo, nullMove }

enum _VariationAction { start, promote, delete, copy }

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

    // When entering preview mode with locked PV, jump to page 0
    final wasPreviewActive = oldWidget.state.isPvPreviewActive;
    final isPreviewActive = widget.state.isPvPreviewActive;
    final hasLockedPv = widget.state.lockedPvLine != null;

    if (!wasPreviewActive && isPreviewActive && hasLockedPv) {
      _currentPage = 0;
      _lastUserSelectedIndex = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      });
    }

    final lines = widget.state.principalVariations.toList(growable: false);
    final pageCount = lines.length;
    if (lines.isNotEmpty) {
      _lastNonEmptyLines = lines;
    }
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

    final oldSelectedIndex = oldWidget.state.selectedVariantIndex;
    final newSelectedIndex = widget.state.selectedVariantIndex;
    final selectedIndexChanged = oldSelectedIndex != newSelectedIndex;
    final userSelected = _lastUserSelectedIndex;

    int targetIndex;

    // CRITICAL FIX: Only jump pages when position changes or user explicitly selects a variant
    // During silent updates (depth increases), preserve the user's current scroll position
    if (positionChanged) {
      // Position changed - reset to first variant or explicitly selected one
      targetIndex = ((newSelectedIndex ?? 0).clamp(0, maxIndex)).toInt();
      _lastUserSelectedIndex = targetIndex;
    } else if (selectedIndexChanged &&
        newSelectedIndex != null &&
        newSelectedIndex <= maxIndex) {
      // User explicitly selected a variant (selectedVariantIndex changed) - honor that selection
      targetIndex = newSelectedIndex;
      _lastUserSelectedIndex = newSelectedIndex;
    } else if (userSelected != null && userSelected <= maxIndex) {
      // Silent update (e.g., depth increase) - preserve user's current position
      targetIndex = userSelected;
    } else if (_currentPage > maxIndex) {
      // Current page out of bounds - clamp to max
      targetIndex = maxIndex;
    } else {
      // Preserve current page during silent updates
      targetIndex = _currentPage;
    }

    if (targetIndex != _currentPage) {
      // Only animate when user explicitly selects a variant
      final animate =
          !positionChanged &&
          selectedIndexChanged &&
          newSelectedIndex != null &&
          newSelectedIndex == targetIndex;
      _currentPage = targetIndex;
      _jumpToPage(targetIndex, animate: animate);
    }

    if ((newSelectedIndex == null || newSelectedIndex != targetIndex) &&
        _lastUserSelectedIndex != null &&
        _lastUserSelectedIndex! <= maxIndex) {
      _scheduleVariantSelection(_lastUserSelectedIndex!);
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
    final clampedLines =
        (widget.state.principalVariations.length > multiPV)
            ? widget.state.principalVariations
                .take(multiPV)
                .toList(growable: false)
            : widget.state.principalVariations.toList(growable: false);

    final hasActivePvs = clampedLines.isNotEmpty;
    final fallbackLines =
        (!hasActivePvs && _lastNonEmptyLines.isNotEmpty)
            ? (_lastNonEmptyLines.length > multiPV
                ? _lastNonEmptyLines.take(multiPV).toList(growable: false)
                : _lastNonEmptyLines.toList(growable: false))
            : const <AnalysisLine>[];
    final displayLines = hasActivePvs ? clampedLines : fallbackLines;
    // Determine loading state for PV cards
    final showEndOfGame = isGameOver && widget.state.isAnalysisMode;
    final showSkeleton =
        !showEndOfGame &&
        !hasActivePvs &&
        _lastNonEmptyLines.isEmpty &&
        widget.state.isEvaluating;
    final showEmptyState =
        !showEndOfGame &&
        displayLines.isEmpty &&
        !widget.state.isEvaluating &&
        _lastNonEmptyLines.isEmpty;
    // Add 1 to pageCount when in preview mode for the static PV card
    final hasLockedPv =
        widget.state.isPvPreviewActive && widget.state.lockedPvLine != null;
    final basePageCount =
        (showSkeleton || showEmptyState) ? 1 : displayLines.length;
    final pageCount = hasLockedPv ? basePageCount + 1 : basePageCount;

    List<InlineSpan> buildPreviewCardSpans(List<_PvToken> tokens) {
      final spans = <InlineSpan>[];
      final baseStyle = AppTypography.textXsMedium.copyWith(
        color: kWhiteColor.withValues(alpha: 0.95),
        fontWeight: FontWeight.w600,
      );

      final currentNavIndex = widget.state.lockedPvNavigationIndex ?? -1;

      for (final token in tokens) {
        final isMove = token.moveIndex != null;
        final isSelectedMove = isMove && token.moveIndex == currentNavIndex;

        if (!isMove) {
          spans.add(
            TextSpan(
              text: '${token.text} ',
              style: baseStyle,
            ),
          );
          continue;
        }

        // Add selected state highlighting
        final moveStyle =
            isSelectedMove
                ? baseStyle.copyWith(
                  backgroundColor: kPrimaryColor.withValues(alpha: 0.4),
                  color: kWhiteColor,
                )
                : baseStyle;

        final recognizer = TapGestureRecognizer()
          ..onTap = () {
            HapticFeedback.lightImpact();
            // Navigate to this position in the preview card
            notifier.navigateToPreviewCardIndex(token.moveIndex!);
          };

        spans.add(
          TextSpan(
            text: '${token.text} ',
            style: moveStyle,
            recognizer: recognizer,
          ),
        );
      }
      return spans;
    }

    Widget buildStaticPvCard() {
      final lockedLine = widget.state.lockedPvLine;
      final mergedMoves = widget.state.lockedPvMergedMoves;

      if (lockedLine == null || mergedMoves == null) {
        return const SizedBox.shrink();
      }

      // Format the merged moves for display
      final sanMoves = _formatPv(mergedMoves, 1, true);
      final evalText = _formatEvalLabel(lockedLine);

      // Use a special color for the static PV card
      const staticColor = kPrimaryColor;
      final opacityScale = 0.7;
      final borderColor = staticColor.withValues(alpha: opacityScale);
      final backgroundColor = staticColor.withValues(alpha: 0.2);
      final badgeBackgroundColor = staticColor.withValues(alpha: 0.4);
      final badgeBorderColor = staticColor.withValues(alpha: 0.7);
      final pvTokens = _buildPvTokens(sanMoves);

      return Container(
        width: MediaQuery.of(context).size.width - 40.sp,
        margin: EdgeInsets.symmetric(horizontal: 2.sp),
        decoration: BoxDecoration(
          border: Border.all(
            color: borderColor,
            width: 2.5, // Thicker border for static card
          ),
          borderRadius: BorderRadius.circular(6.sp),
          color: backgroundColor,
        ),
        clipBehavior: Clip.hardEdge,
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 10.sp),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Evaluation badge - non-interactive for static card
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
                            evalText,
                            style: AppTypography.textXsMedium.copyWith(
                              color: kWhiteColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // Notation text - shows merged PGN + PV moves
                        Expanded(
                          child: ClipRect(
                            child: SingleChildScrollView(
                              primary: false,
                              physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                              padding: EdgeInsets.only(bottom: 4.sp),
                              child: RichText(
                                text: TextSpan(
                                  style: AppTypography.textXsMedium.copyWith(
                                    color: kWhiteColor.withValues(alpha: 0.95),
                                    fontWeight: FontWeight.w600,
                                  ),
                                  children: buildPreviewCardSpans(pvTokens),
                                ),
                                softWrap: true,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Preview badge in top-right corner
            Positioned(
              top: 6.sp,
              right: 6.sp,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 6.sp, vertical: 2.sp),
                decoration: BoxDecoration(
                  color: kPrimaryColor,
                  borderRadius: BorderRadius.circular(4.sp),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimaryColor.withValues(alpha: 0.5),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Text(
                  'PREVIEW',
                  style: AppTypography.textXsMedium.copyWith(
                    color: kWhiteColor,
                    fontSize: 9.sp,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget buildVariantCard({
      required AnalysisLine line,
      required int variantIndex,
      required bool isSelected,
    }) {
      final sanMoves = _formatPv(line.sanMoves, baseMoveNumber, isWhiteToMove);
      final evalText = _formatEvalLabel(line);
      final activeVariantColor = notifier.getVariantColor(variantIndex, true);
      final opacityScale = 0.7;
      final borderColor = activeVariantColor.withValues(alpha: opacityScale);
      final backgroundColor = activeVariantColor.withValues(
        alpha: 0.15,
      );
      final badgeBackgroundColor = activeVariantColor.withValues(alpha: 0.3);
      final badgeBorderColor = activeVariantColor.withValues(alpha: 0.6);
      final pvTokens = _buildPvTokens(sanMoves);

      // Check if any move in this variant is selected for preview
      final isPreviewingThisVariant =
          widget.state.isPvPreviewActive &&
          widget.state.pvPreviewVariantIndex == variantIndex;

      return Container(
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
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 10.sp),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Evaluation badge - tap applies move to PGN history
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        // Check if we're in preview mode with a locked PV
                        if (widget.state.lockedPvLine != null &&
                            widget.state.lockedPvMergedMoves != null) {
                          // Case 1: In preview mode - overwrite PGN history with preview card's history
                          // then insert this move and exit preview mode
                          notifier.applyPreviewHistoryAndInsertMove(line);
                        } else {
                          // Case 2: Normal mode - insert regularly
                          notifier.clearPvPreview();
                          notifier.playPrincipalVariationMove(line);
                        }
                      },
                      child: Container(
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
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            evalText,
                            key: ValueKey('$variantIndex-$evalText'),
                            style: AppTypography.textXsMedium.copyWith(
                              color: kWhiteColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Notation text - tap previews position without modifying PGN
                    Expanded(
                      child: ClipRect(
                        child: SingleChildScrollView(
                          primary: false,
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          padding: EdgeInsets.only(bottom: 4.sp),
                          child: RichText(
                            text: TextSpan(
                              style: AppTypography.textXsMedium.copyWith(
                                color: kWhiteColor.withValues(
                                  alpha: 0.95,
                                ),
                                fontWeight: FontWeight.w600,
                              ),
                              children: _buildPvSpans(
                                tokens: pvTokens,
                                notifier: notifier,
                                line: line,
                                variantIndex: variantIndex,
                                previewMoveIndex:
                                    isPreviewingThisVariant
                                        ? widget.state.pvPreviewMoveIndex
                                        : null,
                              ),
                            ),
                            softWrap: true,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20.sp, 8.sp, 20.sp, 8.sp),
      child: Column(
        // CRITICAL: No key here! Adding a key that changes with eval causes Flutter
        // to rebuild the entire widget tree, resetting PageController position.
        // State is already managed via _currentPage and _lastUserSelectedIndex.
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

                        // Static preview card at index 0
                        if (hasLockedPv && pageIndex == 0) {
                          return;
                        }

                        if (clampedLines.isEmpty) {
                          return;
                        }

                        // Adjust index for dynamic PV cards when static card is present
                        final variantIndex =
                            (hasLockedPv ? pageIndex - 1 : pageIndex)
                                .clamp(0, clampedLines.length - 1);

                        notifier.selectVariant(
                          variantIndex,
                          preservePreview: hasLockedPv,
                        );
                      },
                      itemCount: pageCount,
                      itemBuilder: (context, index) {
                        // Show static PV card at index 0 when in preview mode
                        if (hasLockedPv && index == 0) {
                          return buildStaticPvCard();
                        }

                        // Adjust index for dynamic PV cards when static card is present
                        final dynamicIndex = hasLockedPv ? index - 1 : index;

                        if (showSkeleton) {
                          final placeholderLine =
                              displayLines.isNotEmpty
                                  ? displayLines.first
                                  : _lastNonEmptyLines.isNotEmpty
                                  ? _lastNonEmptyLines.first
                                  : const AnalysisLine(
                                    sanMoves: ['...'],
                                    evaluation: 0,
                                  );
                          return Skeletonizer(
                            enabled: true,
                          child: buildVariantCard(
                            line: placeholderLine,
                            variantIndex: 0,
                            isSelected: false,
                          ),
                        );
                        }
                        if (showEmptyState) {
                          return Container(
                            width: MediaQuery.of(context).size.width - 40.sp,
                            margin: EdgeInsets.symmetric(horizontal: 2.sp),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: kWhiteColor.withValues(alpha: 0.1),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(6.sp),
                              color: Colors.black.withValues(alpha: 0.3),
                            ),
                            padding: EdgeInsets.symmetric(
                              horizontal: 12.sp,
                              vertical: 16.sp,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.max,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.horizontal_rule_rounded,
                                  color: kWhiteColor.withValues(alpha: 0.4),
                                  size: 20.sp,
                                ),
                                SizedBox(height: 6.sp),
                                Flexible(
                                  child: Text(
                                    widget.state.isEvaluating
                                        ? 'Preparing analysis...'
                                        : 'No engine lines available',
                                    textAlign: TextAlign.center,
                                    softWrap: true,
                                    maxLines: 3,
                                    overflow: TextOverflow.fade,
                                    style: AppTypography.textXsMedium.copyWith(
                                      color: kWhiteColor.withValues(alpha: 0.7),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final variantIndex = dynamicIndex;
                        final line = displayLines[dynamicIndex];
                        final isSelected =
                            hasActivePvs &&
                            widget.state.selectedVariantIndex == variantIndex;

                        return buildVariantCard(
                          line: line,
                          variantIndex: variantIndex,
                          isSelected: isSelected,
                        );
                      },
                    ),
          ),
          if (pageCount > 1) ...[
            SizedBox(height: 8.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(pageCount, (index) {
                final isLockedDot = hasLockedPv && index == 0;
                final isActive = index == _currentPage;
                final dynamicIndex = hasLockedPv ? index - 1 : index;
                final Color activeColor =
                    isLockedDot
                        ? kPrimaryColor
                        : displayLines.isNotEmpty
                            ? notifier.getVariantColor(
                              dynamicIndex.clamp(
                                0,
                                displayLines.length - 1,
                              ),
                              true,
                            )
                            : kWhiteColor.withValues(alpha: 0.7);
                final Color dotColor =
                    isActive
                        ? activeColor
                        : kWhiteColor.withValues(alpha: 0.3);
                final double size = isLockedDot ? 8.w : 6.w;
                return GestureDetector(
                  onTap: () {
                    _lastUserSelectedIndex = index;
                    _pageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: EdgeInsets.symmetric(horizontal: 4.sp),
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: dotColor,
                      border:
                          isLockedDot
                              ? Border.all(
                                color:
                                    isActive
                                        ? kWhiteColor
                                        : kPrimaryColor.withValues(
                                          alpha: 0.7,
                                        ),
                                width: isActive ? 1.5 : 1,
                              )
                              : null,
                    ),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  List<_PvToken> _buildPvTokens(List<String> formattedMoves) {
    final tokens = <_PvToken>[];
    var moveCursor = -1;
    for (final entry in formattedMoves) {
      if (entry.trim().isEmpty) continue;
      final trimmed = entry.trim();
      final isWhiteNumber =
          trimmed.endsWith('.') && !trimmed.contains('...');
      final isBlackNumber =
          trimmed.contains('...') && !trimmed.endsWith('...');
      if (isWhiteNumber || isBlackNumber) {
        tokens.add(_PvToken(text: entry));
      } else {
        moveCursor++;
        tokens.add(_PvToken(text: entry, moveIndex: moveCursor));
      }
    }
    return tokens;
  }

  List<InlineSpan> _buildPvSpans({
    required List<_PvToken> tokens,
    required ChessBoardScreenNotifierNew notifier,
    required AnalysisLine line,
    required int variantIndex,
    int? previewMoveIndex,
  }) {
    final spans = <InlineSpan>[];
    // Use consistent styling for all text in PV notation
    final baseStyle = AppTypography.textXsMedium.copyWith(
      color: kWhiteColor.withValues(alpha: 0.95),
      fontWeight: FontWeight.w600,
    );

    for (final token in tokens) {
      final isMove = token.moveIndex != null;
      final isSelectedMove = isMove && token.moveIndex == previewMoveIndex;

      if (!isMove) {
        spans.add(
          TextSpan(
            text: '${token.text} ',
            style: baseStyle, // Same style as moves
          ),
        );
        continue;
      }

      // Add selected state highlighting
      final moveStyle =
          isSelectedMove
              ? baseStyle.copyWith(
                backgroundColor: kPrimaryColor.withValues(alpha: 0.4),
                color: kWhiteColor,
              )
              : baseStyle;

      // Create unique tag for heroine transition
      // Use identityHashCode to ensure uniqueness across different line instances
      final heroineTag = 'pv_move_${identityHashCode(line)}_${variantIndex}_${token.moveIndex}';

      // Use WidgetSpan with GestureDetector to handle tap and long press
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              // Single tap: add the next best move to PGN history
              notifier.clearPvPreview();
              notifier.playPrincipalVariationMove(line);
            },
            onLongPress: () {
              HapticFeedback.mediumImpact();
              // Long press: show hero animation and preview after 1.5s
              _showMovePreviewAnimation(
                context,
                token.text,
                heroineTag,
                line,
                variantIndex,
                token.moveIndex!,
                notifier,
              );
            },
            child: Heroine(
              tag: heroineTag,
              child: Text(
                '${token.text} ',
                style: moveStyle,
              ),
            ),
          ),
        ),
      );
    }
    return spans;
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

  void _showMovePreviewAnimation(
    BuildContext context,
    String moveText,
    String heroineTag,
    AnalysisLine line,
    int variantIndex,
    int moveIndex,
    ChessBoardScreenNotifierNew notifier,
  ) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.3),
        barrierDismissible: false,
        pageBuilder: (context, animation, secondaryAnimation) =>
            _MovePreviewAnimationOverlay(
          moveText: moveText,
          heroineTag: heroineTag,
          line: line,
          variantIndex: variantIndex,
          moveIndex: moveIndex,
          notifier: notifier,
        ),
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 300),
      ),
    );
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

class _PvToken {
  final String text;
  final int? moveIndex;

  const _PvToken({required this.text, this.moveIndex});
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
    final boardSettingsAsync = ref.watch(boardSettingsProviderNew);
    final boardSettingsNew =
        boardSettingsAsync.valueOrNull ?? const BoardSettingsNew();
    final boardTheme = ref
        .read(boardSettingsRepository)
        .getBoardTheme(boardSettingsNew.boardColorValue);

    // Build board settings for the share overlay board (sized responsively inside the overlay)
    final chessboardSettings = ChessboardSettings(
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
      boardSettings: chessboardSettings,
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

/// Overlay widget that shows the move preview animation with loading bar
class _MovePreviewAnimationOverlay extends StatefulWidget {
  final String moveText;
  final String heroineTag;
  final AnalysisLine line;
  final int variantIndex;
  final int moveIndex;
  final ChessBoardScreenNotifierNew notifier;

  const _MovePreviewAnimationOverlay({
    required this.moveText,
    required this.heroineTag,
    required this.line,
    required this.variantIndex,
    required this.moveIndex,
    required this.notifier,
  });

  @override
  State<_MovePreviewAnimationOverlay> createState() =>
      _MovePreviewAnimationOverlayState();
}

class _MovePreviewAnimationOverlayState
    extends State<_MovePreviewAnimationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _smoothProgress;
  bool _completed = false;

  @override
  void initState() {
    super.initState();

    // Configure for buttery smooth 120fps on high refresh rate displays
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
      animationBehavior: AnimationBehavior.preserve, // Maintain frame rate
    );

    // Smooth cubic easing optimized for high refresh rates
    _smoothProgress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    // Start animation
    _controller.forward().then((_) {
      if (mounted && !_completed) {
        _completed = true;
        // Trigger the preview
        widget.notifier.previewPrincipalVariationMoveAt(
          widget.line,
          widget.variantIndex,
          widget.moveIndex,
        );
        // Close overlay with magical animation
        _closeWithMagicalAnimation();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _closeWithMagicalAnimation() {
    // Add magical edge animation before closing
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    // Use smooth cubic easing for silky 120fps animation
    final progress = _smoothProgress.value;

    // Create pulsing glow effect optimized for high refresh rate
    final glowOpacity = (math.sin(progress * math.pi * 4) * 0.3 + 0.7).clamp(0.0, 1.0);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Background blur/dim effect
          Positioned.fill(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: progress * 0.3,
              child: Container(
                color: Colors.black,
              ),
            ),
          ),

          // Magical light particles from screen edges
          ...List.generate(12, (index) {
            final angle = (index / 12) * 2 * math.pi;
            final startX = screenSize.width / 2 + (screenSize.width * 0.7) * math.cos(angle);
            final startY = screenSize.height / 2 + (screenSize.height * 0.7) * math.sin(angle);

            // Stagger particle animations
            final particleProgress = (progress - (index * 0.03)).clamp(0.0, 1.0);

            return Positioned(
              left: startX + (screenSize.width / 2 - startX) * particleProgress,
              top: startY + (screenSize.height / 2 - startY) * particleProgress,
              child: Opacity(
                opacity: (1 - particleProgress) * 0.8,
                child: Container(
                  width: 3.sp,
                  height: 3.sp,
                  decoration: BoxDecoration(
                    color: kPrimaryColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: kPrimaryColor.withValues(alpha: 0.8),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          // Glassic hero card with heroine transition and drag-to-dismiss
          Center(
            child: DragDismissable(
              child: Transform.scale(
                scale: 1 + (progress * 0.2),
                child: Opacity(
                  opacity: (progress * 1.5).clamp(0.0, 1.0),
                  child: Heroine(
                    tag: widget.heroineTag,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: screenSize.width * 0.75,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24.sp),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 40.sp,
                              vertical: 32.sp,
                            ),
                            decoration: BoxDecoration(
                              // Glassic gradient with transparency
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  kWhiteColor.withValues(alpha: 0.15),
                                  kWhiteColor.withValues(alpha: 0.05),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(24.sp),
                              border: Border.all(
                                color: kWhiteColor.withValues(alpha: 0.2),
                                width: 1.5,
                              ),
                              boxShadow: [
                                // Outer glow
                                BoxShadow(
                                  color: kPrimaryColor.withValues(alpha: glowOpacity * 0.5),
                                  blurRadius: 40,
                                  spreadRadius: 0,
                                ),
                                // Inner shadow for depth
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Move text with shimmer effect
                                ShaderMask(
                                  shaderCallback: (bounds) {
                                    return LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        kWhiteColor,
                                        kPrimaryColor.withValues(alpha: 0.8),
                                        kWhiteColor,
                                      ],
                                      stops: [
                                        0.0,
                                        progress.clamp(0.3, 0.7),
                                        1.0,
                                      ],
                                    ).createShader(bounds);
                                  },
                                  child: Text(
                                    widget.moveText,
                                    style: AppTypography.textXsMedium.copyWith(
                                      color: kWhiteColor,
                                      fontSize: 42.sp,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 3,
                                      height: 1.2,
                                    ),
                                  ),
                                ),

                                SizedBox(height: 24.sp),

                                // Glassic loading bar container
                                Container(
                                  width: 160.sp,
                                  height: 6.sp,
                                  decoration: BoxDecoration(
                                    color: kWhiteColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(3.sp),
                                    border: Border.all(
                                      color: kWhiteColor.withValues(alpha: 0.1),
                                      width: 0.5,
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(3.sp),
                                    child: Stack(
                                      children: [
                                        // Progress fill with gradient
                                        FractionallySizedBox(
                                          alignment: Alignment.centerLeft,
                                          widthFactor: progress,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  kPrimaryColor,
                                                  kPrimaryColor.withValues(alpha: 0.7),
                                                ],
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: kPrimaryColor.withValues(alpha: 0.6),
                                                  blurRadius: 8,
                                                  spreadRadius: 1,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        // Shimmer overlay on progress
                                        if (progress > 0 && progress < 1)
                                          Positioned(
                                            left: (160.sp * progress) - 30.sp,
                                            child: Container(
                                              width: 30.sp,
                                              height: 6.sp,
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: [
                                                    Colors.transparent,
                                                    kWhiteColor.withValues(alpha: 0.5),
                                                    Colors.transparent,
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),

                                SizedBox(height: 12.sp),

                                // Subtle hint text
                                Text(
                                  'Drag to cancel',
                                  style: AppTypography.textXsMedium.copyWith(
                                    color: kWhiteColor.withValues(alpha: 0.5),
                                    fontSize: 11.sp,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double cos(double radians) => math.cos(radians);
  double sin(double radians) => math.sin(radians);
}
