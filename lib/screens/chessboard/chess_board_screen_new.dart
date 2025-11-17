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
import 'package:motor/motor.dart';

/// Spring-based curve that mimics iOS snappy motion
/// Quick, precise animation with subtle natural settling
class SnappySpringCurve extends Curve {
  const SnappySpringCurve();

  @override
  double transform(double t) {
    // Approximates CupertinoMotion.snappy() using damped spring physics
    // This creates a quick, responsive motion with minimal overshoot
    final damping = 0.85; // High damping for snappy feel
    final frequency = 3.5; // High frequency for quick response

    final omega = frequency * 2 * math.pi;
    final dampingRatio = damping;
    final dampedFreq = omega * math.sqrt(1 - dampingRatio * dampingRatio);

    final envelope = math.exp(-dampingRatio * omega * t);
    final oscillation = math.cos(dampedFreq * t);

    return 1 - envelope * oscillation;
  }
}

/// Spring-based curve that mimics iOS bouncy motion
/// Playful animation with natural bounce and overshoot
class BouncySpringCurve extends Curve {
  const BouncySpringCurve();

  @override
  double transform(double t) {
    // Approximates CupertinoMotion.bouncy() with pronounced spring effect
    // Lower damping creates visible bounce and overshoot
    final damping = 0.55; // Lower damping for bouncy feel
    final frequency = 2.8; // Medium frequency for natural bounce

    final omega = frequency * 2 * math.pi;
    final dampingRatio = damping;
    final dampedFreq = omega * math.sqrt(1 - dampingRatio * dampingRatio);

    final envelope = math.exp(-dampingRatio * omega * t);
    final oscillation = math.cos(dampedFreq * t);

    return 1 - envelope * oscillation;
  }
}

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

    final confirmed =
        await _showAnalysisConfirmationDialog(
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
    final baseCanMoveForward = state.analysisState.canMoveForward;
    final baseCanMoveBackward = state.analysisState.canMoveBackward;
    final canMoveForward =
        navigatorState != null
            ? (navigatorState.canGoForward || baseCanMoveForward)
            : baseCanMoveForward;
    final canMoveBackward =
        navigatorState != null
            ? (navigatorState.canGoBackward || baseCanMoveBackward)
            : baseCanMoveBackward;
    final previewMoves = state.lockedPvMergedMoves;
    final previewIndex = state.lockedPvNavigationIndex ?? 0;
    final isPreviewActive =
        state.isPvPreviewActive &&
        previewMoves != null &&
        previewMoves.isNotEmpty;
    final previewCanMoveForward =
        isPreviewActive ? previewIndex < previewMoves.length - 1 : false;
    // CRITICAL FIX: In preview mode, can go backward as long as we have moves
    // previewIndex >= 0 means we can go backward (even from index 0 to starting position)
    final previewCanMoveBackward =
        isPreviewActive ? previewIndex >= 0 && previewMoves.isNotEmpty : false;
    final effectiveCanMoveForward =
        isPreviewActive ? previewCanMoveForward : canMoveForward;
    final effectiveCanMoveBackward =
        isPreviewActive ? previewCanMoveBackward : canMoveBackward;

    return ChessBoardBottomNavBar(
      gameIndex: index,
      onFlip: () => notifier.flipBoard(),
      toggleEngineVisibility: () => notifier.toggleEngineVisibility(),
      onEngineSettingsLongPress: () {
        Navigator.of(context).push(ChessBoardSettingsPage.route());
      },
      onRightMove:
          effectiveCanMoveForward
              ? () {
                notifier.moveForward().then((_) {
                  final updatedState =
                      ref.read(chessBoardScreenProviderNew(params)).valueOrNull;
                  if (updatedState == null ||
                      updatedState.isPvPreviewActive ||
                      !updatedState.hasUnseenMoves) {
                    return;
                  }
                  final atLastMove =
                      updatedState.analysisState.currentMoveIndex >=
                      updatedState.allMoves.length - 1;
                  if (atLastMove) {
                    notifier.markMovesAsSeen();
                  }
                });
              }
              : null,
      onLeftMove:
          effectiveCanMoveBackward ? () => notifier.moveBackward() : null,
      onLongPressBackwardStart: () => notifier.startLongPressBackward(),
      onLongPressBackwardEnd: () => notifier.stopLongPress(),
      onLongPressForwardStart: () => notifier.startLongPressForward(),
      onLongPressForwardEnd: () => notifier.stopLongPress(),
      canMoveForward: effectiveCanMoveForward,
      canMoveBackward: effectiveCanMoveBackward,
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
        child: ExcludeSemantics(
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
          // Subtle overlay when preview is active - only covers main variant area
          if (widget.state.isPvPreviewActive)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 0, // Will be covered by PV cards naturally
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  // Tap anywhere on overlay to exit preview
                  ref
                      .read(chessBoardScreenProviderNew(params).notifier)
                      .clearPvPreview();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12.sp),
                      topRight: Radius.circular(12.sp),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(12.sp),
                      topRight: Radius.circular(12.sp),
                    ),
                    child: Stack(
                      children: [
                        BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.55),
                          ),
                        ),
                        Align(
                          alignment: Alignment.center,
                          child: TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.elasticOut,
                            tween: Tween(begin: 0.0, end: 1.0),
                            builder: (context, value, child) {
                              final clampedValue = value.clamp(0.0, 1.0);
                              return Transform.scale(
                                scale: 0.8 + (clampedValue * 0.2),
                                child: Opacity(
                                  opacity: clampedValue,
                                  child: child,
                                ),
                              );
                            },
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 18.sp,
                                vertical: 16.sp,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.visibility_outlined,
                                    color: Colors.white.withValues(alpha: 0.95),
                                    size: 20.sp,
                                  ),
                                  SizedBox(height: 8.sp),
                                  Text(
                                    'Preview mode',
                                    textAlign: TextAlign.center,
                                    style: AppTypography.textSmMedium.copyWith(
                                      color: Colors.white,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                  SizedBox(height: 4.sp),
                                  Text(
                                    'Tap anywhere to exit or swipe the hero card up to apply.',
                                    textAlign: TextAlign.center,
                                    style: AppTypography.textXsRegular.copyWith(
                                      color: Colors.white.withValues(
                                        alpha: 0.85,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: 12.sp),
                                  // Promote main variant button
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () async {
                                        // Prevent tap from propagating to parent GestureDetector
                                        HapticFeedback.mediumImpact();

                                        final lockedLine =
                                            widget.state.lockedPvLine;
                                        if (lockedLine == null) return;

                                        // Confirm before promoting
                                        final confirmed =
                                            await showDialog<bool>(
                                              context: context,
                                              builder:
                                                  (
                                                    dialogContext,
                                                  ) => AlertDialog(
                                                    backgroundColor:
                                                        kBlack2Color,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12.br,
                                                          ),
                                                    ),
                                                    title: Text(
                                                      'Promote to main variant?',
                                                      style: AppTypography
                                                          .textMdBold
                                                          .copyWith(
                                                            color: kWhiteColor,
                                                          ),
                                                    ),
                                                    content: Text(
                                                      'This will replace the main variant with this preview line.',
                                                      style: AppTypography
                                                          .textSmRegular
                                                          .copyWith(
                                                            color: kWhiteColor
                                                                .withValues(
                                                                  alpha: 0.7,
                                                                ),
                                                          ),
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed:
                                                            () => Navigator.of(
                                                              dialogContext,
                                                            ).pop(false),
                                                        child: Text(
                                                          'Cancel',
                                                          style: AppTypography
                                                              .textSmMedium
                                                              .copyWith(
                                                                color: kWhiteColor
                                                                    .withValues(
                                                                      alpha:
                                                                          0.7,
                                                                    ),
                                                              ),
                                                        ),
                                                      ),
                                                      TextButton(
                                                        onPressed:
                                                            () => Navigator.of(
                                                              dialogContext,
                                                            ).pop(true),
                                                        child: Text(
                                                          'Promote',
                                                          style: AppTypography
                                                              .textSmMedium
                                                              .copyWith(
                                                                color:
                                                                    kPrimaryColor,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                            ) ??
                                            false;

                                        if (!confirmed) return;
                                        if (!context.mounted) return;

                                        notifier.promotePreviewToMainVariant();
                                      },
                                      borderRadius: BorderRadius.circular(8.sp),
                                      splashColor: kPrimaryColor.withValues(
                                        alpha: 0.3,
                                      ),
                                      highlightColor: kPrimaryColor.withValues(
                                        alpha: 0.2,
                                      ),
                                      child: Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 20.sp,
                                          vertical: 10.sp,
                                        ),
                                        decoration: BoxDecoration(
                                          color: kPrimaryColor.withValues(
                                            alpha: 0.15,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8.sp,
                                          ),
                                          border: Border.all(
                                            color: kPrimaryColor.withValues(
                                              alpha: 0.4,
                                            ),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.upgrade_rounded,
                                              color: kWhiteColor,
                                              size: 16.sp,
                                            ),
                                            SizedBox(width: 8.sp),
                                            Text(
                                              'Promote main variant',
                                              style: AppTypography.textSmMedium
                                                  .copyWith(
                                                    color: kWhiteColor,
                                                    letterSpacing: 0.2,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 12.sp,
            right: 0,
            child: _AnalysisActionButtons(params: params),
          ),
        ],
      ),
    );
  }

  Widget _buildMoveChip(
    _NotationDisplayToken token,
    ChessBoardProviderParams params,
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
    final color = _resolveMoveColor(token, currentPly);

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
        final pointer = token.pointer;
        if (pointer == null || token.pointerId == null) return;
        _showMoveActions(
          params,
          pointer,
          token.pointerId!,
          token.text,
          token.node?.move.san == '--',
          token.node?.isMainline ?? false,
          _variantHeadPointerForToken(token),
        );
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
    final depthColor =
        token.depth > 0
            ? _colorForVariationDepth(token.depth)
            : kWhiteColor.withValues(alpha: 0.75);

    Widget child;
    if (token.type == _NotationTokenType.variationPlaceholder) {
      child = Container(
        padding: EdgeInsets.symmetric(horizontal: 6.sp, vertical: 2.sp),
        decoration: BoxDecoration(
          color: depthColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4.sp),
        ),
        child: Text(
          token.text,
          style: AppTypography.textXsMedium.copyWith(
            color: depthColor.withValues(alpha: 0.85),
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    } else {
      child = Text(
        token.text,
        style: AppTypography.textXsMedium.copyWith(
          color:
              token.type == _NotationTokenType.ellipsis
                  ? kWhiteColor70
                  : depthColor.withValues(alpha: 0.85),
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

    final heroChild = ExcludeSemantics(
      excluding: true,
      child: Heroine(
        tag: token.heroineTag ?? 'variation-${token.variation!.id}',
        child: child,
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _focusVariationHead(token.variation!);
        _toggleVariationCollapse(token);
      },
      onLongPress: () {
        _showVariationActions(token);
      },
      child: heroChild,
    );
  }

  void _focusVariationHead(NotationVariationNode variation) {
    if (variation.moves.isEmpty) {
      return;
    }
    final params = ChessBoardProviderParams(
      game: widget.game,
      index: widget.index,
    );
    final headPointer = List<Number>.of(variation.moves.first.pointer);
    ref
        .read(chessBoardScreenProviderNew(params).notifier)
        .goToMovePointer(headPointer);
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

  static const List<Color> _variationDepthPalette = [
    Color(0xFFA98BFF),
    Color(0xFFFF9EB5),
    Color(0xFFFFE28C),
    Color(0xFF8EE0C7),
    Color(0xFF8EC6FF),
  ];

  Color _colorForVariationDepth(int depth) {
    if (depth <= 0) {
      return kWhiteColor;
    }
    final paletteIndex = (depth - 1) % _variationDepthPalette.length;
    return _variationDepthPalette[paletteIndex];
  }

  Color _resolveMoveColor(_NotationDisplayToken token, int currentPly) {
    final node = token.node;
    if (node == null) {
      return kWhiteColor;
    }

    if (token.pointerId == null) {
      return kWhiteColor;
    }

    final isPast = currentPly >= 0 && node.ply <= currentPly;
    if (node.isMainline || token.depth <= 0) {
      return isPast ? kWhiteColor : kWhiteColor;
    }

    final depthColor = _colorForVariationDepth(token.depth);
    return depthColor.withValues(alpha: isPast ? 0.95 : 0.75);
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

      // CRITICAL FIX: Never suppress black move prefix for proper PGN notation
      // Variations starting with black moves MUST show ellipsis (e.g., "1... c5")
      final text = _formatMoveText(node);
      final variationMovesList = variationContext?.moves;
      final variationHeadPointer =
          (variationMovesList?.isNotEmpty ?? false)
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
        final variationHeroTagBase =
            'notation-variation-${variation.id}-${variation.depth}-${variation.variationIndex}';

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
            variationHeadPointer:
                variation.moves.isNotEmpty
                    ? List<Number>.of(variation.moves.first.pointer)
                    : null,
            heroineTag: '$variationHeroTagBase-open',
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
              variationHeadPointer:
                  variation.moves.isNotEmpty
                      ? List<Number>.of(variation.moves.first.pointer)
                      : null,
              heroineTag: '$variationHeroTagBase-placeholder',
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
            variationHeadPointer:
                variation.moves.isNotEmpty
                    ? List<Number>.of(variation.moves.first.pointer)
                    : null,
            heroineTag: '$variationHeroTagBase-close',
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
      final bool isNullMove = node.move.san == '--';
      final bool isFirstBlackInLine =
          !node.isWhiteMove && (node.showEllipsis || suppressBlackMovePrefix);
      if (isNullMove && !node.isWhiteMove) {
        buffer.write('${node.moveNumber}... ');
      } else if (isFirstBlackInLine) {
        // Still suppress for regular variation heads
      } else {
        final separator = node.isWhiteMove ? '. ' : '... ';
        buffer.write('${node.moveNumber}$separator');
      }
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

  ChessMovePointer? _variantHeadPointerForMove(ChessMovePointer pointer) {
    if (pointer.length < 3) {
      return null;
    }
    for (int i = pointer.length - 2; i >= 0; i--) {
      if (i.isOdd) {
        final head = List<Number>.of(pointer.sublist(0, i + 1));
        head.add(0);
        return head;
      }
    }
    return null;
  }

  ChessMovePointer? _variantHeadPointerForToken(_NotationDisplayToken token) {
    final variation = token.variation;
    if (variation != null) {
      final head = <Number>[
        ...variation.parentPointer,
        variation.variationIndex,
        0,
      ];
      return head;
    }
    if (token.pointer != null) {
      return _variantHeadPointerForMove(token.pointer!);
    }
    final head = token.variationHeadPointer;
    return head == null ? null : List<Number>.of(head);
  }

  Future<void> _showMoveActions(
    ChessBoardProviderParams params,
    ChessMovePointer pointer,
    String pointerId,
    String moveText,
    bool isNullMove,
    bool isMainlineMove,
    ChessMovePointer? variantHeadOverride,
  ) async {
    final hostContext = context;
    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
    final variantHeadPointer =
        variantHeadOverride ?? _variantHeadPointerForMove(pointer);
    final canModifyVariant = variantHeadPointer != null && !isMainlineMove;
    final actions = <_NotationActionItem>[
      _NotationActionItem(
        icon: Icons.delete_outline,
        label: 'Delete from here',
        color: kRedColor,
        onSelected: (overlayContext) async {
          Navigator.of(overlayContext).pop();
          await notifier.deleteContinuationFromPointer(
            List<Number>.of(pointer),
          );
        },
      ),
      _NotationActionItem(
        icon: Icons.block,
        label: 'Add null move after',
        color: kPrimaryColor,
        onSelected: (overlayContext) async {
          Navigator.of(overlayContext).pop();
          await notifier.insertNullMoveAfterPointer(List<Number>.of(pointer));
        },
      ),
      if (canModifyVariant)
        _NotationActionItem(
          icon: Icons.delete_forever,
          label: 'Delete variant',
          color: kRedColor,
          onSelected: (overlayContext) async {
            Navigator.of(overlayContext).pop();
            final snapshot = notifier.navigatorStateSnapshot();
            await notifier.deleteVariationAtPointer(
              List<Number>.of(variantHeadPointer),
            );
            if (!mounted) return;
            final currentContext = this.context;
            if (snapshot != null) {
              _showUndoSnackBar(
                currentContext,
                params,
                snapshot,
                'Variant removed',
              );
            } else {
              _showInfoSnack(currentContext, 'Variant removed');
            }
          },
        ),
      if (canModifyVariant)
        _NotationActionItem(
          icon: Icons.trending_up_rounded,
          label: 'Promote variant',
          color: kPrimaryColor,
          onSelected: (overlayContext) async {
            Navigator.of(overlayContext).pop();
            await notifier.promoteVariationAtPointer(
              List<Number>.of(variantHeadPointer),
            );
          },
        ),
      _NotationActionItem(
        icon: Icons.upgrade_rounded,
        label: 'Promote main variant',
        color: kPrimaryColor,
        onSelected: (overlayContext) async {
          Navigator.of(overlayContext).pop();
          await notifier.promoteBranchToMainVariant(List<Number>.of(pointer));
        },
      ),
    ];

    await _pushNotationActionOverlay(
      context: hostContext,
      heroineTag: 'move-action-$pointerId',
      title: isNullMove ? 'Null move' : moveText,
      subtitle: 'Move options',
      actions: actions,
    );
  }

  Future<void> _showVariationActions(_NotationDisplayToken token) async {
    final variation = token.variation;
    final headPointer = _variantHeadPointerForToken(token);
    if (variation == null || headPointer == null) {
      return;
    }
    final hostContext = context;
    final params = ChessBoardProviderParams(
      game: widget.game,
      index: widget.index,
    );
    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
    final actions = <_NotationActionItem>[
      _NotationActionItem(
        icon: Icons.trending_up_rounded,
        label: 'Promote variant',
        color: kPrimaryColor,
        onSelected: (overlayContext) async {
          Navigator.of(overlayContext).pop();
          await notifier.promoteVariationAtPointer(
            List<Number>.of(headPointer),
          );
        },
      ),
      _NotationActionItem(
        icon: Icons.delete_forever,
        label: 'Delete variant',
        color: kRedColor,
        onSelected: (overlayContext) async {
          Navigator.of(overlayContext).pop();
          final snapshot = notifier.navigatorStateSnapshot();
          await notifier.deleteVariationAtPointer(List<Number>.of(headPointer));
          if (!mounted) return;
          final currentContext = this.context;
          if (snapshot != null) {
            _showUndoSnackBar(
              currentContext,
              params,
              snapshot,
              'Variation removed',
            );
          } else {
            _showInfoSnack(currentContext, 'Variation removed');
          }
        },
      ),
      _NotationActionItem(
        icon: Icons.upgrade_rounded,
        label: 'Promote main variant',
        color: kPrimaryColor,
        onSelected: (overlayContext) async {
          Navigator.of(overlayContext).pop();
          await notifier.promoteBranchToMainVariant(
            List<Number>.of(headPointer),
          );
        },
      ),
    ];

    await _pushNotationActionOverlay(
      context: hostContext,
      heroineTag: token.heroineTag ?? 'variation-action-${variation.id}',
      title: 'Variation',
      subtitle: 'Variation options',
      actions: actions,
    );
  }

  Future<void> _pushNotationActionOverlay({
    required BuildContext context,
    required String heroineTag,
    required String title,
    String? subtitle,
    required List<_NotationActionItem> actions,
  }) {
    return Navigator.of(context).push(
      _HeroinePreviewRoute(
        child: _NotationActionOverlay(
          heroineTag: heroineTag,
          title: title,
          subtitle: subtitle,
          actions: actions,
        ),
      ),
    );
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

  void _showUndoSnackBar(
    BuildContext context,
    ChessBoardProviderParams params,
    ChessGameNavigatorState snapshot,
    String message,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: Colors.transparent,
        margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 20.h),
        padding: EdgeInsets.zero,
        content: Container(
          padding: EdgeInsets.symmetric(horizontal: 18.sp, vertical: 16.sp),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22.sp),
            gradient: LinearGradient(
              colors: [
                kPrimaryColor.withValues(alpha: 0.9),
                kPrimaryColor.withValues(alpha: 0.65),
                kBlack2Color.withValues(alpha: 0.85),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: kPrimaryColor.withValues(alpha: 0.35),
                blurRadius: 32,
                spreadRadius: 6,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(10.sp),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14.sp),
                ),
                child: Icon(
                  Icons.auto_fix_high_rounded,
                  color: kWhiteColor,
                  size: 20.ic,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message,
                      style: AppTypography.textSmBold.copyWith(
                        color: kWhiteColor,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Tap to bring the variation back.',
                      style: AppTypography.textXsRegular.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  ref
                      .read(chessBoardScreenProviderNew(params).notifier)
                      .restoreNavigatorState(snapshot);
                  messenger.hideCurrentSnackBar();
                },
                style: TextButton.styleFrom(
                  foregroundColor: kWhiteColor,
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                ),
                child: const Text('UNDO'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showInfoSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AnalysisActionButtons extends ConsumerWidget {
  final ChessBoardProviderParams params;

  const _AnalysisActionButtons({required this.params});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chessBoardScreenProviderNew(params)).valueOrNull;
    final analysisGame = state?.analysisState.game;
    final hasCustomAnalysis = _gameHasCustomVariations(analysisGame);
    final canInsertNullMove = analysisGame != null;
    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _RibbonAnalysisButton(
          icon: Icons.auto_delete_outlined,
          color: kRedColor,
          enabled: hasCustomAnalysis,
          iconAlpha: 0.7,
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
        SizedBox(height: 12.sp),
        _RibbonAnalysisButton(
          icon: Icons.control_point_duplicate_rounded,
          color: kPrimaryColor,
          alphaTop: 0.20,
          alphaBottom: 0.15,
          shadowAlpha: 0.12,
          iconAlpha: 0.7,
          enabled: canInsertNullMove,
          onPressed:
              canInsertNullMove
                  ? () {
                    HapticFeedback.mediumImpact();
                    notifier.insertNullMoveAfterCurrent();
                  }
                  : null,
        ),
      ],
    );
  }
}

class _RibbonAnalysisButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final Color color;
  final bool enabled;
  final double? alphaTop;
  final double? alphaBottom;
  final double? shadowAlpha;
  final double? iconAlpha;

  const _RibbonAnalysisButton({
    required this.icon,
    required this.color,
    this.onPressed,
    this.enabled = true,
    this.alphaTop,
    this.alphaBottom,
    this.shadowAlpha,
    this.iconAlpha,
  });

  @override
  State<_RibbonAnalysisButton> createState() => _RibbonAnalysisButtonState();
}

class _RibbonAnalysisButtonState extends State<_RibbonAnalysisButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final effectiveOnTap = widget.enabled ? widget.onPressed : null;

    // Use provided alpha or defaults
    final alphaTop = widget.alphaTop ?? 0.35;
    final alphaBottom = widget.alphaBottom ?? 0.25;
    final shadowAlpha = widget.shadowAlpha ?? 0.2;
    final iconAlpha = widget.iconAlpha ?? 0.7;

    // Brighten when pressed
    final pressMultiplier = _isPressed ? 1.5 : 1.0;

    return GestureDetector(
      onTapDown:
          effectiveOnTap != null
              ? (_) {
                setState(() => _isPressed = true);
              }
              : null,
      onTapUp:
          effectiveOnTap != null
              ? (_) {
                setState(() => _isPressed = false);
              }
              : null,
      onTapCancel:
          effectiveOnTap != null
              ? () {
                setState(() => _isPressed = false);
              }
              : null,
      onTap: effectiveOnTap,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.35,
        child: Container(
          width: 40.sp,
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 9.sp),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                widget.color.withValues(
                  alpha: (alphaTop * pressMultiplier).clamp(0.0, 1.0),
                ),
                widget.color.withValues(
                  alpha: (alphaBottom * pressMultiplier).clamp(0.0, 1.0),
                ),
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
                color: widget.color.withValues(
                  alpha: (shadowAlpha * pressMultiplier).clamp(0.0, 1.0),
                ),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(
              color: kWhiteColor.withValues(alpha: 0.25),
              width: 0.8,
            ),
          ),
          child: Icon(
            widget.icon,
            size: 18.sp,
            color: kWhiteColor.withValues(
              alpha: (iconAlpha * pressMultiplier).clamp(0.0, 1.0),
            ),
          ),
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
  final String? heroineTag;

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
    this.heroineTag,
  });
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

  // Preview card notation scroll support
  final ScrollController _previewScrollController = ScrollController();
  final Map<int, GlobalKey> _previewMoveKeys = {};
  int? _lastScrolledPreviewIndex;
  int? _pressedVariantIndex;

  void _setCardPressed(int? index) {
    if (_pressedVariantIndex == index) return;
    setState(() {
      _pressedVariantIndex = index;
    });
  }

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

    // Auto-scroll preview card notation when navigation index changes
    final oldNavIndex = oldWidget.state.lockedPvNavigationIndex;
    final newNavIndex = widget.state.lockedPvNavigationIndex;
    if (isPreviewActive &&
        hasLockedPv &&
        newNavIndex != null &&
        newNavIndex != oldNavIndex &&
        newNavIndex != _lastScrolledPreviewIndex) {
      _lastScrolledPreviewIndex = newNavIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToPreviewMove(newNavIndex);
      });
    }

    if (isPreviewActive && hasLockedPv) {
      if (_currentPage != 0) {
        _currentPage = 0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageController.hasClients) {
            _pageController.jumpToPage(0);
          }
        });
      }
      _lastPositionKey = _derivePositionKey(widget.state);
      return;
    }

    final lines = widget.state.principalVariations.toList(growable: false);
    final pageCount = lines.length;
    final positionKey = _derivePositionKey(widget.state);
    final positionChanged = positionKey != _lastPositionKey;
    _lastPositionKey = positionKey;

    // Update cached lines: clear on position change, update when new lines available
    if (positionChanged) {
      // Clear cached lines when position changes to avoid showing PV lines from wrong position
      _lastNonEmptyLines = const [];
    }
    if (lines.isNotEmpty) {
      _lastNonEmptyLines = lines;
    }

    // Preserve user selection reference when PV list temporarily empties
    if (pageCount == 0) {
      _lastUserSelectedIndex ??=
          oldWidget.state.selectedVariantIndex ?? _currentPage;
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
      // Position changed - keep the user's last viewed variant when possible
      final desiredIndex =
          _lastUserSelectedIndex ?? newSelectedIndex ?? _currentPage;
      targetIndex = desiredIndex.clamp(0, maxIndex);
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

    // Only schedule variant selection if:
    // 1. Not in preview mode (preview mode handles its own variant selection in onPageChanged)
    // 2. The provider's selectedVariantIndex doesn't match our target
    // 3. We have a valid user selection to apply
    final isInPreview = widget.state.isPvPreviewActive;
    if (!isInPreview &&
        (newSelectedIndex == null || newSelectedIndex != targetIndex) &&
        _lastUserSelectedIndex != null &&
        _lastUserSelectedIndex! <= maxIndex) {
      _scheduleVariantSelection(_lastUserSelectedIndex!);
    }
  }

  void _scrollToPreviewMove(int moveIndex) {
    if (!_previewScrollController.hasClients) return;
    if (!mounted) return;

    final key = _previewMoveKeys[moveIndex];
    final context = key?.currentContext;
    if (context == null) {
      // Context not ready yet, try again
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToPreviewMove(moveIndex);
      });
      return;
    }

    final targetContext = context;
    Future.microtask(() {
      if (!mounted) return;
      if (!targetContext.mounted) return;
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        alignment: 0.5, // Center the move in the viewport
      );
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _previewScrollController.dispose();
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
    // During preview mode, only show the static preview card (pageCount = 1)
    final pageCount = hasLockedPv ? 1 : basePageCount;

    List<InlineSpan> buildPreviewCardSpans(
      List<_PvToken> tokens,
      Color variantColor,
    ) {
      final spans = <InlineSpan>[];
      final baseStyle = AppTypography.textXsMedium.copyWith(
        color: kWhiteColor.withValues(alpha: 0.95),
        fontWeight: FontWeight.w600,
      );

      final currentNavIndex = widget.state.lockedPvNavigationIndex ?? -1;

      // Clear old keys before rebuilding
      _previewMoveKeys.clear();

      for (final token in tokens) {
        final isMove = token.moveIndex != null;
        final isSelectedMove = isMove && token.moveIndex == currentNavIndex;

        if (!isMove) {
          spans.add(TextSpan(text: '${token.text} ', style: baseStyle));
          continue;
        }

        // Add selected state highlighting - use same variant color as main variant
        final moveStyle =
            isSelectedMove
                ? baseStyle.copyWith(
                  backgroundColor: variantColor.withValues(alpha: 0.4),
                  color: kWhiteColor,
                )
                : baseStyle;

        // Create GlobalKey for this move to enable scrolling
        final key = GlobalKey();
        _previewMoveKeys[token.moveIndex!] = key;

        // Wrap move text in a widget with key for scroll targeting
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: GestureDetector(
              key: key,
              onTap: () {
                HapticFeedback.lightImpact();
                // Navigate to this position in the preview card
                notifier.navigateToPreviewCardIndex(token.moveIndex!);
              },
              child: Text('${token.text} ', style: moveStyle),
            ),
          ),
        );
      }
      return spans;
    }

    Widget buildStaticPvCard() {
      final lockedLine = widget.state.lockedPvLine;
      final mergedMoves = widget.state.lockedPvMergedMoves;
      final mergedPositions = widget.state.lockedPvMergedPositions;
      final previewVariantIndex = widget.state.pvPreviewVariantIndex ?? 0;

      if (lockedLine == null ||
          mergedMoves == null ||
          mergedPositions == null) {
        return const SizedBox.shrink();
      }

      // Format the merged moves for display
      // Use the starting position to determine the correct move number
      final startingPosition = mergedPositions.first;
      final startMoveNumber = startingPosition.fullmoves;
      final isWhiteToMove = startingPosition.turn == Side.white;
      final sanMoves = _formatPv(mergedMoves, startMoveNumber, isWhiteToMove);
      final evalText = _formatEvalLabel(lockedLine);

      // Use the same color as the originating PV card
      final variantColor = notifier.getVariantColor(previewVariantIndex, true);
      final opacityScale = 0.7;
      final borderColor = variantColor.withValues(alpha: opacityScale);
      final backgroundColor = variantColor.withValues(alpha: 0.15);
      final badgeBackgroundColor = variantColor.withValues(alpha: 0.3);
      final badgeBorderColor = variantColor.withValues(alpha: 0.6);
      final pvTokens = _buildPvTokens(sanMoves);

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () {
          HapticFeedback.heavyImpact();
          notifier.applyPreviewHistoryAndInsertMove(lockedLine);
        },
        child: Container(
          width: double.infinity,
          margin: EdgeInsets.symmetric(horizontal: 2.sp),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: 1.5),
            borderRadius: BorderRadius.circular(6.sp),
            color: backgroundColor,
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            children: [
              // Subtle left accent border for preview indication
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 3.sp,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        variantColor.withValues(alpha: 0.9),
                        variantColor.withValues(alpha: 0.6),
                      ],
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(6.sp),
                      bottomLeft: Radius.circular(6.sp),
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Evaluation badge - non-interactive for static card
                        Padding(
                          padding: EdgeInsets.fromLTRB(12.sp, 10.sp, 0, 10.sp),
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
                            child: Text(
                              evalText,
                              style: AppTypography.textXsMedium.copyWith(
                                color: kWhiteColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        // Notation text - shows merged PGN + PV moves
                        Expanded(
                          child: ClipRect(
                            child: SingleChildScrollView(
                              controller: _previewScrollController,
                              primary: false,
                              physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                              padding: EdgeInsets.fromLTRB(
                                0,
                                10.sp,
                                12.sp,
                                10.sp,
                              ),
                              child: RichText(
                                text: TextSpan(
                                  style: AppTypography.textXsMedium.copyWith(
                                    color: kWhiteColor.withValues(alpha: 0.95),
                                    fontWeight: FontWeight.w600,
                                  ),
                                  children: buildPreviewCardSpans(
                                    pvTokens,
                                    variantColor,
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
            ],
          ),
        ),
      );
    }

    Widget buildVariantCard({
      required AnalysisLine line,
      required int variantIndex,
      required bool isSelected,
      required bool hasLockedPreview,
    }) {
      final sanMoves = _formatPv(line.sanMoves, baseMoveNumber, isWhiteToMove);
      final evalText = _formatEvalLabel(line);
      final activeVariantColor = notifier.getVariantColor(variantIndex, true);
      final opacityScale = 0.7;
      final borderColor = activeVariantColor.withValues(alpha: opacityScale);
      final backgroundColor = activeVariantColor.withValues(alpha: 0.15);
      final pvTokens = _buildPvTokens(sanMoves);

      // Check if any move in this variant is selected for preview
      final isPreviewingThisVariant =
          widget.state.isPvPreviewActive &&
          widget.state.pvPreviewVariantIndex == variantIndex;

      final isPressed = _pressedVariantIndex == variantIndex;

      return GestureDetector(
        onTapDown: (_) => _setCardPressed(variantIndex),
        onTapUp: (_) => _setCardPressed(null),
        onTapCancel: () => _setCardPressed(null),
        onLongPressStart: (_) => _setCardPressed(variantIndex),
        onLongPressEnd: (_) => _setCardPressed(null),
        onTap: () {
          HapticFeedback.lightImpact();
          notifier.clearPvPreview();
          notifier.playPrincipalVariationMove(line);
        },
        onLongPress: () {
          HapticFeedback.mediumImpact();
          final lastMoveIndex = line.sanMoves.length - 1;
          if (lastMoveIndex >= 0) {
            final lastMoveText =
                pvTokens.lastWhere((t) => t.moveIndex != null).text;
            // Make tag unique by including game ID, page index, and timestamp
            final heroineTag =
                'pv_move_${widget.game.gameId}_${widget.index}_${variantIndex}_$lastMoveIndex';
            _showMovePreviewAnimation(
              context,
              lastMoveText,
              heroineTag,
              line,
              variantIndex,
              lastMoveIndex,
              notifier,
              activeVariantColor,
            );
          }
        },
        child: AnimatedScale(
          scale: isPressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          child: Container(
            width: double.infinity,
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
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Compact evaluation badge on the left
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() {
                          _lastUserSelectedIndex =
                              hasLockedPreview
                                  ? variantIndex + 1
                                  : variantIndex;
                        });
                        if (widget.state.isPvPreviewActive &&
                            widget.state.lockedPvLine != null) {
                          notifier.previewPrincipalVariationMoveAt(
                            line,
                            variantIndex,
                            0,
                          );
                        } else {
                          notifier.clearPvPreview();
                          notifier.playPrincipalVariationMove(line);
                        }
                      },
                      child: Container(
                        width: 48.sp,
                        decoration: BoxDecoration(
                          color: activeVariantColor.withValues(alpha: 0.25),
                          border: Border(
                            right: BorderSide(
                              color: activeVariantColor.withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            evalText,
                            style: AppTypography.textSmBold.copyWith(
                              color: kWhiteColor,
                              fontSize: 12.sp,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Notation text - vertically scrollable middle section
                    Expanded(
                      child: SingleChildScrollView(
                        primary: false,
                        scrollDirection: Axis.vertical,
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: 10.sp,
                          vertical: 10.sp,
                        ),
                        child: RichText(
                          text: TextSpan(
                            style: AppTypography.textXsMedium.copyWith(
                              color: kWhiteColor.withValues(alpha: 0.95),
                              fontWeight: FontWeight.w600,
                            ),
                            children: _buildPvSpans(
                              tokens: pvTokens,
                              notifier: notifier,
                              line: line,
                              variantIndex: variantIndex,
                              variantColor: activeVariantColor,
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
                    // '+' button on the right - inserts next best move
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          setState(() {
                            _lastUserSelectedIndex =
                                hasLockedPreview
                                    ? variantIndex + 1
                                    : variantIndex;
                          });
                          notifier.clearPvPreview();
                          notifier.playPrincipalVariationMove(line);
                        },
                        splashColor: activeVariantColor.withValues(alpha: 0.3),
                        highlightColor: activeVariantColor.withValues(
                          alpha: 0.2,
                        ),
                        child: Container(
                          width: 40.sp,
                          decoration: BoxDecoration(
                            color: activeVariantColor.withValues(alpha: 0.2),
                            border: Border(
                              left: BorderSide(
                                color: activeVariantColor.withValues(
                                  alpha: 0.4,
                                ),
                                width: 1,
                              ),
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.add_rounded,
                              color: kWhiteColor.withValues(alpha: 0.9),
                              size: 20.sp,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      // CRITICAL: No key here! Adding a key that changes with eval causes Flutter
      // to rebuild the entire widget tree, resetting PageController position.
      // State is already managed via _currentPage and _lastUserSelectedIndex.
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16.sp, 8.sp, 16.sp, 4.h),
          child: SizedBox(
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
                      physics:
                          hasLockedPv
                              ? const NeverScrollableScrollPhysics()
                              : const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                      padEnds: false,
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
                        final variantIndex = (hasLockedPv
                                ? pageIndex - 1
                                : pageIndex)
                            .clamp(0, clampedLines.length - 1);

                        if (!widget.state.isPvPreviewActive) {
                          notifier.selectVariant(
                            variantIndex,
                            preservePreview: hasLockedPv,
                          );
                        }
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
                              hasLockedPreview: hasLockedPv,
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
                          hasLockedPreview: hasLockedPv,
                        );
                      },
                    ),
          ),
        ),
        SizedBox(height: 4.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(pageCount > 0 ? pageCount : 1, (index) {
            if (pageCount == 0) {
              return Container(
                margin: EdgeInsets.symmetric(horizontal: 4.sp),
                width: 6.w,
                height: 6.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kWhiteColor.withValues(alpha: 0.1),
                ),
              );
            }
            final isLockedDot = hasLockedPv && index == 0;
            final isActive = index == _currentPage;
            final dynamicIndex = hasLockedPv ? index - 1 : index;

            Color dotColor;
            Border? border;

            if (isLockedDot) {
              dotColor =
                  isActive
                      ? kWhiteColor.withValues(alpha: 0.95)
                      : kWhiteColor.withValues(alpha: 0.35);
              border = Border.all(
                color: kWhiteColor.withValues(alpha: isActive ? 1.0 : 0.65),
                width: isActive ? 1.5 : 1,
              );
            } else if (displayLines.isNotEmpty) {
              final variantColor = notifier.getVariantColor(
                dynamicIndex.clamp(0, displayLines.length - 1),
                true,
              );
              dotColor =
                  isActive
                      ? variantColor
                      : variantColor.withValues(alpha: 0.35);
            } else {
              dotColor =
                  isActive
                      ? kWhiteColor.withValues(alpha: 0.85)
                      : kWhiteColor.withValues(alpha: 0.3);
            }

            final double size = isLockedDot ? 8.w : 6.w;
            return GestureDetector(
              onTap: () {
                if (!hasLockedPv ||
                    widget.state.isPvPreviewActive == false ||
                    index != 0) {
                  _lastUserSelectedIndex = index;
                }
                if (_pageController.hasClients && pageCount > 0) {
                  _pageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: EdgeInsets.symmetric(horizontal: 4.sp),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotColor,
                  border: border,
                ),
              ),
            );
          }),
        ),
        SizedBox(height: 4.h),
      ],
    );
  }

  List<_PvToken> _buildPvTokens(List<String> formattedMoves) {
    final tokens = <_PvToken>[];
    var moveCursor = -1;
    for (final entry in formattedMoves) {
      if (entry.trim().isEmpty) continue;
      final trimmed = entry.trim();
      // Check if this is a move number (white or black)
      // White: "1.", "2.", etc. (number followed by single period)
      // Black: "1...", "2...", etc. (number followed by three periods)
      final isNumber = RegExp(r'^\d+\.\.?\.?$').hasMatch(trimmed);
      if (isNumber) {
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
    required Color variantColor,
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
      final heroineTag =
          'pv_move_${identityHashCode(line)}_${variantIndex}_${token.moveIndex}';

      // Use WidgetSpan with GestureDetector to handle tap and long press
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              // Single tap: Enter preview mode and navigate to the tapped move
              notifier.previewPrincipalVariationMoveAt(
                line,
                variantIndex,
                token.moveIndex ?? 0,
              );
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
                variantColor,
              );
            },
            child: Heroine(
              tag: heroineTag,
              child: Material(
                color: Colors.transparent,
                child: Text('${token.text} ', style: moveStyle),
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

      // Add move number prefix for white moves and first black moves
      if (isWhiteMove) {
        // White move: use standard notation (e.g., "1.")
        formatted.add('$moveNumber.');
      } else {
        // Black moves follow white moves without extra prefix
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
      // Preserve preview mode when switching variants during preview
      final shouldPreserve = widget.state.isPvPreviewActive;
      ref
          .read(chessBoardScreenProviderNew(params).notifier)
          .selectVariant(index, preservePreview: shouldPreserve);
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
    Color variantColor,
  ) {
    Navigator.of(context).push(
      _HeroinePreviewRoute(
        child: _MovePreviewAnimationOverlay(
          moveText: moveText,
          heroineTag: heroineTag,
          line: line,
          variantIndex: variantIndex,
          moveIndex: moveIndex,
          notifier: notifier,
          variantColor: variantColor,
        ),
      ),
    );
  }

  int get maxPageIndex {
    final count = _lastNonEmptyLines.length;
    return count == 0 ? 0 : count - 1;
  }

  String _derivePositionKey(ChessBoardStateNew state) {
    // In preview mode, use the locked PV line's base position as the key
    // This ensures switching between PV cards doesn't trigger position change logic
    if (state.isPvPreviewActive && state.lockedPvLine != null) {
      // Use a stable key that represents "preview mode at base position"
      // This prevents the PV list from jumping pages when navigating within preview
      final basePos =
          state.isAnalysisMode ? state.analysisState.position : state.position;
      return 'preview:${state.lockedPvLine.hashCode}:${basePos?.fen ?? ''}';
    }

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

class _NotationActionOverlay extends StatefulWidget {
  final String heroineTag;
  final String title;
  final String? subtitle;
  final List<_NotationActionItem> actions;

  const _NotationActionOverlay({
    required this.heroineTag,
    required this.title,
    this.subtitle,
    required this.actions,
  });

  @override
  State<_NotationActionOverlay> createState() => _NotationActionOverlayState();
}

class _NotationActionOverlayState extends State<_NotationActionOverlay>
    with TickerProviderStateMixin {
  static const double _dragDismissThreshold = 120.0;

  bool _isEntering = true;
  double _glowIntensity = 0.0;
  bool _hasPlayedThresholdHaptic = false;
  Offset _cardOffset = Offset.zero;
  Offset _animationStart = Offset.zero;
  Offset _animationTarget = Offset.zero;
  Curve _animationCurve = Curves.easeOut;
  VoidCallback? _animationComplete;
  bool _isDragging = false;
  Offset _trackedVelocity = Offset.zero;
  Duration? _lastSampleTime;
  late final AnimationController _offsetController;

  @override
  void initState() {
    super.initState();
    _offsetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )
      ..addListener(_handleOffsetTick)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _animationComplete?.call();
          _animationComplete = null;
        }
      });

    // Initial haptic feedback
    HapticFeedback.mediumImpact();

    // Trigger entrance animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isEntering = false;
        });
      }
    });
  }

  void _dismiss() {
    Navigator.of(context).pop();
  }

  void _handleOffsetTick() {
    final progress = _animationCurve.transform(_offsetController.value);
    setState(() {
      _cardOffset = Offset.lerp(_animationStart, _animationTarget, progress)!;
      _glowIntensity = (_cardOffset.distance / (_dragDismissThreshold * 1.4))
          .clamp(0.0, 1.0);
    });
  }

  void _startDrag(DragStartDetails details) {
    _offsetController.stop();
    _isDragging = true;
    _trackedVelocity = Offset.zero;
    _lastSampleTime = details.sourceTimeStamp;
  }

  void _updateDrag(DragUpdateDetails details) {
    final timestamp = details.sourceTimeStamp;
    if (timestamp != null && _lastSampleTime != null) {
      final delta = timestamp - _lastSampleTime!;
      final seconds = delta.inMicroseconds / 1e6;
      if (seconds > 0) {
        final velocity = details.delta / seconds;
        _trackedVelocity = Offset.lerp(_trackedVelocity, velocity, 0.35)!;
      }
    }
    _lastSampleTime = timestamp;

    final proposed = _cardOffset + details.delta;
    final radius = proposed.distance;
    Offset limitedOffset = proposed;
    const maxRadius = 260.0;
    if (radius > maxRadius) {
      final excess = radius - maxRadius;
      final rubberBand = maxRadius + excess * 0.25;
      limitedOffset = proposed / radius * rubberBand;
    }

    setState(() {
      _cardOffset = limitedOffset;
      _glowIntensity =
          (_cardOffset.distance / (_dragDismissThreshold * 1.4)).clamp(
        0.0,
        1.0,
      );
    });

    if (_glowIntensity > 0.85 && !_hasPlayedThresholdHaptic) {
      HapticFeedback.selectionClick();
      _hasPlayedThresholdHaptic = true;
    } else if (_glowIntensity <= 0.75 && _hasPlayedThresholdHaptic) {
      _hasPlayedThresholdHaptic = false;
    }
  }

  void _endDrag(DragEndDetails details) {
    _isDragging = false;
    final releaseVelocity =
        details.velocity.pixelsPerSecond + (_trackedVelocity * 0.2);
    final distance = _cardOffset.distance;
    final shouldDismiss =
        distance > _dragDismissThreshold || releaseVelocity.distance > 1200;

    if (shouldDismiss) {
      HapticFeedback.mediumImpact();
      final directionVector =
          (_cardOffset + releaseVelocity * 0.2).distance == 0
              ? const Offset(0, 1)
              : (_cardOffset + releaseVelocity * 0.2);
      final normalized = directionVector / directionVector.distance;
      final screen = MediaQuery.of(context).size;
      final travelDistance =
          math.max(screen.width, screen.height) * 0.9 * normalized.distance;
      final target = _cardOffset + normalized * travelDistance;
      _animateOffsetTo(
        target,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
        onComplete: () => Navigator.of(context).pop(),
      );
    } else {
      _animateOffsetTo(
        Offset.zero,
        duration: const Duration(milliseconds: 650),
        curve: Curves.elasticOut,
      );
      _hasPlayedThresholdHaptic = false;
    }
  }

  void _animateOffsetTo(
    Offset target, {
    required Duration duration,
    Curve curve = Curves.easeOut,
    VoidCallback? onComplete,
  }) {
    _animationStart = _cardOffset;
    _animationTarget = target;
    _animationCurve = curve;
    _animationComplete = onComplete;
    _offsetController.duration = duration;
    _offsetController.forward(from: 0.0);
  }

  @override
  void dispose() {
    _offsetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background with blur that reacts to heroine dismiss
        ReactToHeroineDismiss(
          builder: (context, dismissProgress, offset, child) {
            final progress = 1.0 - dismissProgress;
            final blurAmount = 4.0 * progress;
            final backgroundOpacity = 0.3 * progress;

            return GestureDetector(
              onTap: _dismiss,
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: blurAmount,
                  sigmaY: blurAmount,
                ),
                child: Container(
                  color: Colors.black.withValues(alpha: backgroundOpacity),
                ),
              ),
            );
          },
        ),

        // Main card with drag-to-dismiss
        Center(
          child: SingleMotionBuilder(
            motion: CupertinoMotion.bouncy(),
            value: _isEntering ? 0.0 : 1.0,
            builder: (context, value, child) {
              final cardOpacity = value.clamp(0.0, 1.0);
              final scale = lerpDouble(0.88, 1.0, value) ?? 1.0;
              return Opacity(
                opacity: cardOpacity,
                child: Transform.scale(
                  scale: scale,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    dragStartBehavior: DragStartBehavior.down,
                    onPanStart: _startDrag,
                    onPanUpdate: _updateDrag,
                    onPanEnd: _endDrag,
                    child: _LiquidHeroSurface(
                      heroineTag: widget.heroineTag,
                      motion: const CupertinoMotion.interactive(),
                      offset: _cardOffset,
                      glowStrength: _glowIntensity,
                      entryProgress: value,
                      accentColor: kPrimaryColor,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (_glowIntensity > 0.0)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24.sp),
                                  boxShadow: [
                                    BoxShadow(
                                      color: kPrimaryColor.withValues(
                                        alpha: _glowIntensity * 0.35,
                                      ),
                                      blurRadius: 35 * _glowIntensity,
                                      spreadRadius: 10 * _glowIntensity,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Material(
                            color: Colors.transparent,
                            child: Container(
                              width: double.infinity,
                              margin: EdgeInsets.symmetric(horizontal: 20.sp),
                              padding: EdgeInsets.all(22.sp),
                              decoration: BoxDecoration(
                                color: kBlack2Color.withValues(alpha: 0.96),
                                borderRadius: BorderRadius.circular(24.sp),
                                border: Border.all(
                                  color: kPrimaryColor.withValues(
                                    alpha: 0.3 + (_glowIntensity * 0.4),
                                  ),
                                  width: 1.6 + (_glowIntensity * 0.7),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: 0.55,
                                    ),
                                    blurRadius: 40 + (_glowIntensity * 12),
                                    offset: Offset(
                                      0,
                                      18 + (_glowIntensity * 10),
                                    ),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _ActionOverlayHeader(
                                    title: widget.title,
                                    subtitle: widget.subtitle,
                                  ),
                                  SizedBox(height: 20.h),
                                  ...List.generate(widget.actions.length,
                                      (index) {
                                    final action = widget.actions[index];
                                    final staggerDelay = index * 0.12;
                                    final buttonEntranceValue =
                                        _isEntering ? 0.0 : 1.0;
                                    return IgnorePointer(
                                      ignoring: _isDragging,
                                      child: SingleMotionBuilder(
                                        motion: CupertinoMotion.bouncy(),
                                        value: buttonEntranceValue,
                                        builder: (context, value, child) {
                                          final delayed = (value - staggerDelay)
                                              .clamp(0.0, 1.0);
                                          final normalized =
                                              (staggerDelay >= 1.0
                                                      ? 0.0
                                                      : delayed /
                                                          (1.0 - staggerDelay))
                                                  .clamp(0.0, 1.0);
                                          return Transform.translate(
                                            offset: Offset(
                                              0,
                                              (1.0 - normalized) * 28,
                                            ),
                                            child: Opacity(
                                              opacity: normalized,
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: Padding(
                                          padding:
                                              EdgeInsets.only(bottom: 12.h),
                                          child: _ActionButton(
                                            action: action,
                                            onPressed: () =>
                                                action.onSelected(context),
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                  SizedBox(height: 4.h),
                                  Center(
                                    child: AnimatedOpacity(
                                      duration:
                                          const Duration(milliseconds: 180),
                                      opacity: 0.4 + (_glowIntensity * 0.35),
                                      child: Text(
                                        'Flick away to dismiss',
                                        style:
                                            AppTypography.textXsRegular.copyWith(
                                          color: kWhiteColor.withValues(
                                            alpha: 0.55,
                                          ),
                                          fontStyle: FontStyle.italic,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Beautiful action button with hover and press states
class _ActionButton extends StatefulWidget {
  final _NotationActionItem action;
  final VoidCallback onPressed;

  const _ActionButton({required this.action, required this.onPressed});

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
        HapticFeedback.lightImpact();
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onPressed();
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
      },
      child: SingleMotionBuilder(
        motion: CupertinoMotion.snappy(),
        value: _isPressed ? 0.95 : 1.0,
        builder: (context, scale, child) {
          return Transform.scale(
            scale: scale,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 18.sp, vertical: 14.sp),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    widget.action.color.withValues(
                      alpha: _isPressed ? 0.28 : 0.18,
                    ),
                    widget.action.color.withValues(
                      alpha: _isPressed ? 0.18 : 0.12,
                    ),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14.sp),
                border: Border.all(
                  color: widget.action.color.withValues(
                    alpha: _isPressed ? 0.6 : 0.45,
                  ),
                  width: 1.5,
                ),
                boxShadow:
                    _isPressed
                        ? []
                        : [
                          BoxShadow(
                            color: widget.action.color.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
              ),
              child: Row(
                children: [
                  Icon(widget.action.icon, color: kWhiteColor, size: 20.ic),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      widget.action.label,
                      style: AppTypography.textSmMedium.copyWith(
                        color: kWhiteColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: kWhiteColor.withValues(alpha: 0.4),
                    size: 14.ic,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ActionOverlayHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _ActionOverlayHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(10.sp),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                kPrimaryColor.withValues(alpha: 0.4),
                kPrimaryColor.withValues(alpha: 0.15),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14.sp),
            boxShadow: [
              BoxShadow(
                color: kPrimaryColor.withValues(alpha: 0.25),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            Icons.auto_awesome_rounded,
            color: kWhiteColor,
            size: 20.ic,
          ),
        ),
        SizedBox(width: 14.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.textLgBold.copyWith(
                  color: kWhiteColor,
                  letterSpacing: 0.3,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: AppTypography.textXsRegular.copyWith(
                    color: kWhiteColor.withValues(alpha: 0.65),
                    letterSpacing: 0.2,
                  ),
                ),
            ],
          ),
        ),
        Container(
          height: 32.h,
          padding: EdgeInsets.symmetric(horizontal: 10.sp),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: kWhiteColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: kWhiteColor.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.drag_handle_rounded,
                color: kWhiteColor.withValues(alpha: 0.55),
                size: 16.ic,
              ),
              SizedBox(width: 4.w),
              Text(
                'Drag',
                style: AppTypography.textXsRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LiquidHeroSurface extends StatelessWidget {
  final String heroineTag;
  final Motion motion;
  final Offset offset;
  final double glowStrength;
  final double entryProgress;
  final Color accentColor;
  final Widget child;

  const _LiquidHeroSurface({
    required this.heroineTag,
    required this.motion,
    required this.offset,
    required this.glowStrength,
    required this.entryProgress,
    required this.accentColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final dragFactor = (offset.distance / 260).clamp(0.0, 1.0);
    final depthScale = (1 - dragFactor * 0.05) *
        (0.9 + (entryProgress.clamp(0.0, 1.0) * 0.1));
    final tiltX = (offset.dy / 1200).clamp(-0.35, 0.35);
    final tiltY = (offset.dx / 1200).clamp(-0.35, 0.35);

    final matrix = Matrix4.identity()
      ..translate(offset.dx, offset.dy)
      ..setEntry(3, 2, 0.0015)
      ..rotateX(tiltX)
      ..rotateY(-tiltY)
      ..scale(depthScale);

    final aura = BoxShadow(
      color: accentColor.withValues(alpha: 0.25 + glowStrength * 0.4),
      blurRadius: 40 + glowStrength * 20,
      spreadRadius: 8 + glowStrength * 6,
      offset: Offset(0, 18),
    );

    return Transform(
      transform: matrix,
      alignment: Alignment.center,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        decoration: BoxDecoration(boxShadow: [aura]),
        child: Heroine(tag: heroineTag, motion: motion, child: child),
      ),
    );
  }
}

class _NotationActionItem {
  final IconData icon;
  final String label;
  final Color color;
  final FutureOr<void> Function(BuildContext context) onSelected;

  const _NotationActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onSelected,
  });
}

/// Custom route with Heroine support for smooth hero transitions
class _HeroinePreviewRoute<T> extends PageRoute<T> with HeroinePageRouteMixin {
  final Widget child;

  _HeroinePreviewRoute({required this.child});

  @override
  Color? get barrierColor => Colors.transparent;

  @override
  String? get barrierLabel => null;

  @override
  bool get opaque => false;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 450);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 320);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return child;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Fade transition for the overlay
    return FadeTransition(opacity: animation, child: child);
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
  final Color variantColor;

  const _MovePreviewAnimationOverlay({
    required this.moveText,
    required this.heroineTag,
    required this.line,
    required this.variantIndex,
    required this.moveIndex,
    required this.notifier,
    required this.variantColor,
  });

  @override
  State<_MovePreviewAnimationOverlay> createState() =>
      _MovePreviewAnimationOverlayState();
}

class _MovePreviewAnimationOverlayState
    extends State<_MovePreviewAnimationOverlay> {
  static const double _dragDismissThreshold = 140.0;
  static const double _maxDragRadius = 280.0;

  // Animation state
  bool _isEntering = true;
  bool _isDismissing = false;
  Offset _dragOffset = Offset.zero;
  Offset _dragReturnTarget = Offset.zero;
  bool _isReturning = false;

  // Interaction state
  bool _isDraggingCard = false;
  Offset _currentDragVelocity = Offset.zero;
  Duration? _lastDragSampleTime;
  bool _hasTriggeredInstantApply = false;
  bool _pendingReject = false;
  Offset? _rejectDirection;
  bool _completed = false;
  double _magicBurst = 0.0;
  bool _showExpandedMoveText = false;

  @override
  void initState() {
    super.initState();

    // Initial haptic feedback on long press start
    HapticFeedback.mediumImpact();

    // Trigger entrance animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isEntering = false;
        });
      }
    });

    // Delay the large move-text reveal until the hero flight settles
    Future.delayed(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      setState(() {
        _showExpandedMoveText = true;
      });
    });
  }

  void _startDrag() {
    _lastDragSampleTime = null;
    _currentDragVelocity = Offset.zero;
    setState(() {
      _isDraggingCard = true;
      _isReturning = false;
    });
  }

  void _updateDrag(DragUpdateDetails details) {
    final timestamp = details.sourceTimeStamp;
    if (timestamp != null) {
      if (_lastDragSampleTime != null) {
        final deltaMicros =
            (timestamp - _lastDragSampleTime!).inMicroseconds.toDouble();
        if (deltaMicros > 0) {
          final seconds = deltaMicros / 1e6;
          final velocity = details.delta / seconds;
          // More responsive velocity tracking with less smoothing
          _currentDragVelocity = _currentDragVelocity * 0.3 + velocity * 0.7;
        }
      }
      _lastDragSampleTime = timestamp;
    }

    // Direct drag response without lerping for instant finger tracking
    final proposed = _dragOffset + details.delta;
    final radius = proposed.distance;
    Offset limitedOffset;
    if (radius > _maxDragRadius) {
      // Apply rubber-band effect at the edge
      final excess = radius - _maxDragRadius;
      final rubberBand = _maxDragRadius + excess * 0.3;
      limitedOffset = proposed / radius * rubberBand;
    } else {
      limitedOffset = proposed;
    }

    setState(() {
      _dragOffset = limitedOffset; // Direct assignment - no lerp!
    });

    final upward = -_dragOffset.dy;
    final sideways = _dragOffset.dx.abs();
    // Provide haptic feedback when reaching threshold
    if (!_hasTriggeredInstantApply &&
        upward > _dragDismissThreshold * 0.9 &&
        sideways < _dragDismissThreshold * 0.6) {
      _hasTriggeredInstantApply = true;
      HapticFeedback.heavyImpact();
      _sparkMagicBurst();
    }
  }

  void _endDrag(DragEndDetails details) {
    final upward = -_dragOffset.dy;
    final sideways = _dragOffset.dx.abs();
    final releaseVelocity = details.velocity.pixelsPerSecond;
    final velocityY = -releaseVelocity.dy; // Negative = upward

    // More fluid gesture detection - focus on intent, not perfect path
    // Use velocity direction as primary indicator of intent
    final hasUpwardVelocity = velocityY > 400; // More lenient threshold
    final hasStrongUpwardVelocity = velocityY > 800;
    final hasUpwardDistance = upward > _dragDismissThreshold * 0.6; // More lenient

    // Check vertical-to-horizontal ratio instead of absolute values
    // This allows diagonal swipes if the upward component is dominant
    final verticalRatio = sideways > 0 ? upward / sideways : double.infinity;
    final isUpwardDominant = verticalRatio > 0.8; // Allows ~51° angle or steeper

    // Accept if:
    // 1. Strong upward velocity (user clearly flicked up), OR
    // 2. Good upward velocity with reasonable angle, OR
    // 3. Sufficient upward distance with upward-dominant direction
    final shouldActivate = hasStrongUpwardVelocity ||
        (hasUpwardVelocity && isUpwardDominant) ||
        (hasUpwardDistance && verticalRatio > 1.2); // Even more lenient for distance

    if (shouldActivate) {
      // Magical upward swipe - activate preview!
      HapticFeedback.heavyImpact();
      _activatePreviewWithMagic();
      return;
    }

    final releaseSpeed = releaseVelocity.distance;
    final shouldFlingAway =
        releaseSpeed > 450 || _dragOffset.distance > _dragDismissThreshold * 0.75;
    if (shouldFlingAway) {
      HapticFeedback.mediumImpact();
      _flingAway(releaseVelocity);
      return;
    }

    // Snap back to center after dragging
    _isDraggingCard = false;
    _animateDragBack();
  }

  void _animateDragBack() {
    setState(() {
      _dragReturnTarget = Offset.zero;
      _isReturning = true;
    });

    // Reset drag state after animation completes (bouncy motion is ~600ms)
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted && !_isDraggingCard) {
        final shouldDismiss = _pendingReject;
        _pendingReject = false;

        setState(() {
          _dragOffset = Offset.zero;
          _currentDragVelocity = Offset.zero;
          _lastDragSampleTime = null;
          _hasTriggeredInstantApply = false;
          _isReturning = false;
        });

        if (shouldDismiss) {
          _dismissEarly(triggerHaptic: false);
        }
      }
    });
  }

  void _sparkMagicBurst() {
    setState(() => _magicBurst = 1.0);
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() => _magicBurst = 0.0);
      }
    });
  }

  void _flingAway(Offset releaseVelocity) {
    if (_isDismissing) return;

    // Calculate direction with velocity for natural continuation
    final releaseVector =
        (_dragOffset * 0.7) + ((_currentDragVelocity + releaseVelocity) * 0.003);
    Offset direction =
        releaseVector == Offset.zero ? const Offset(0, 1) : releaseVector;
    final normalized = direction / direction.distance;

    final screenSize = MediaQuery.of(context).size;

    // Follow the natural fling direction - don't snap to axes!
    // Calculate how far to go in the fling direction to exit screen
    final scale = math.max(screenSize.width, screenSize.height) * 1.5;
    final target = _dragOffset + (normalized * scale);

    setState(() {
      _isDraggingCard = false;
      _pendingReject = true;
      _rejectDirection = normalized;
      _dragReturnTarget = target;
      _isReturning = true;
    });

    // Dismiss after animation completes
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted && _pendingReject) {
        _dismissEarly(triggerHaptic: false);
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  String _formatPreviewMoves() {
    // Get the moves from the PV line that will be added
    final moves = widget.line.sanMoves;
    if (moves.isEmpty) return '';

    // Show moves starting from the selected move index
    final remainingMoves = moves.skip(widget.moveIndex).take(4).toList();
    if (remainingMoves.isEmpty) return '';

    final moveList = remainingMoves.join(' ');
    final hasMore = moves.length > widget.moveIndex + 4;
    return moveList + (hasMore ? ' ...' : '');
  }

  String _formatEvalChange() {
    final eval = widget.line.evaluation;
    if (eval == null && !widget.line.isMate) return '';

    if (widget.line.isMate) {
      final mate = widget.line.mate ?? 0;
      final absMate = mate.abs();
      final prefix = mate >= 0 ? '#+' : '#-';
      return '$prefix$absMate';
    }

    final formatted = eval!.abs().toStringAsFixed(1);
    final sign = eval >= 0 ? '+' : '-';
    return '$sign$formatted';
  }

  void _activatePreviewWithMagic() {
    if (_completed) return;
    _completed = true;

    // Magical burst effect
    _sparkMagicBurst();

    // Activate preview mode
    widget.notifier.previewPrincipalVariationMoveAt(
      widget.line,
      widget.variantIndex,
      widget.moveIndex,
    );

    // Follow the natural fling direction instead of snapping to center
    final screenSize = MediaQuery.of(context).size;

    // Calculate direction based on current drag offset and velocity
    final releaseVector = _dragOffset + (_currentDragVelocity * 0.003);
    final direction = releaseVector == Offset.zero
        ? const Offset(0, -1) // Default upward if no velocity
        : releaseVector;
    final normalized = direction / direction.distance;

    // Calculate target point off-screen in the fling direction
    // Scale by screen dimensions to ensure it goes far enough
    final scale = math.max(screenSize.width, screenSize.height) * 1.2;
    final target = _dragOffset + (normalized * scale);

    setState(() {
      _isDraggingCard = false;
      _dragReturnTarget = target;
      _isReturning = true;
    });

    // Pop after ascension completes
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  void _onPreview() {
    if (_completed) return;
    _completed = true;
    HapticFeedback.heavyImpact();
    widget.notifier.previewPrincipalVariationMoveAt(
      widget.line,
      widget.variantIndex,
      widget.moveIndex,
    );
    _closeWithMagicalAnimation();
  }

  void _onInsertAllMoves() {
    if (_completed) return;
    _completed = true;
    HapticFeedback.heavyImpact();
    // Insert all moves from this PV line
    widget.notifier.clearPvPreview();
    widget.notifier.insertPvMoves(widget.line);
    _closeWithMagicalAnimation();
  }

  void _onPromoteMainVariant() async {
    if (_completed) return;
    HapticFeedback.mediumImpact();

    // Show confirmation dialog
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder:
              (dialogContext) => AlertDialog(
                backgroundColor: kBlack2Color,
                title: const Text('Promote to main variant?'),
                content: const Text(
                  'This will replace the main variant with this line from the current position.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    style: TextButton.styleFrom(foregroundColor: kPrimaryColor),
                    child: const Text('Promote'),
                  ),
                ],
              ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    _completed = true;
    HapticFeedback.heavyImpact();

    // Enter preview mode first
    widget.notifier.previewPrincipalVariationMoveAt(
      widget.line,
      widget.variantIndex,
      widget.moveIndex,
    );

    // Wait a frame then promote using the line we just previewed
    await Future.delayed(const Duration(milliseconds: 50));
    if (mounted) {
      widget.notifier.promotePreviewToMainVariant();
    }

    _closeWithMagicalAnimation();
  }

  void _closeWithMagicalAnimation() {
    if (_isDismissing) return;
    setState(() {
      _isDismissing = true;
      _isDraggingCard = false;
      _isReturning = false;
      _dragOffset = Offset.zero;
      _currentDragVelocity = Offset.zero;
      _lastDragSampleTime = null;
      _hasTriggeredInstantApply = false;
      _pendingReject = false;
      _rejectDirection = null;
      _magicBurst = 0.0;
    });

    // Pop with hero transition after brief delay for dismiss animation
    Future.delayed(const Duration(milliseconds: 280), () {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  void _dismissEarly({bool triggerHaptic = true}) {
    if (!_completed && triggerHaptic) {
      HapticFeedback.lightImpact();
    }
    setState(() {
      _dragOffset = Offset.zero;
      _isDraggingCard = false;
      _isReturning = false;
    });
    _closeWithMagicalAnimation();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final variantColor = widget.variantColor;
    const particleCount = 45; // More particles for magical effect

    return Material(
      color: Colors.transparent,
      child: SingleMotionBuilder(
        motion: CupertinoMotion.bouncy(),
        value: _isEntering ? 0.0 : 1.0,
        builder: (context, entranceValue, child) {
          return SingleMotionBuilder(
            motion: CupertinoMotion.snappy(),
            value: _isDismissing ? 1.0 : 0.0,
            builder: (context, dismissValue, child) {
              return MotionBuilder(
                motion:
                    _isReturning
                        ? CupertinoMotion.bouncy()
                        : CupertinoMotion.snappy(),
                value: _isReturning ? _dragReturnTarget : _dragOffset,
                converter: OffsetMotionConverter(),
                builder: (context, currentOffset, child) {
                  // Smooth progress with natural spring motion
                  final progress = entranceValue.clamp(0.0, 1.0);
                  final particleProgress = progress;

                  // Card scale with bouncy spring - allows overshoot up to 1.15
                  final cardScaleValue = (0.7 + (progress * 0.4)).clamp(
                    0.0,
                    1.15,
                  );

                  // Dismiss scale (shrink to 0.2)
                  final dismissScaleValue = (1.0 - dismissValue * 0.8).clamp(
                    0.0,
                    1.0,
                  );

                  final baseScale =
                      _isDismissing ? dismissScaleValue : cardScaleValue;
                  final backgroundOpacityValue =
                      _isDismissing
                          ? ((1 - dismissValue).clamp(0.0, 1.0) * 0.5)
                          : (progress * 0.5);
                  final glowOpacity = (math.sin(progress * math.pi * 3) * 0.2 +
                          0.8)
                      .clamp(0.0, 1.0);

                  // Use animated offset for smooth drag return
                  final interactiveOffset =
                      _isDraggingCard ? _dragOffset : currentOffset;
                  final dragProgress = (-interactiveOffset.dy /
                          _dragDismissThreshold)
                      .clamp(0.0, 1.0);
                  final interactiveScaleFactor = 1 + (dragProgress * 0.2);

                  // Card opacity with dismiss fade
                  final cardOpacityValue =
                      (_isDismissing
                          ? (1 - dismissValue).clamp(0.0, 1.0)
                          : 1.0) *
                      (_pendingReject
                          ? (1 -
                                  (currentOffset.distance /
                                      screenSize.width *
                                      0.5))
                              .clamp(0.0, 1.0)
                          : 1.0);

                  // Enhanced rotation with more dynamic response
                  final rotationAngle = (interactiveOffset.dx / 180).clamp(
                    -0.35,
                    0.35,
                  );

                  // Add 3D perspective flip based on vertical drag
                  final flipAngleX =
                      (dragProgress * 0.15) *
                      math.pi; // Flip backward as dragging up
                  final flipAngleY =
                      ((interactiveOffset.dx / _maxDragRadius) * 0.2).clamp(
                        -0.25,
                        0.25,
                      ) *
                      math.pi;

                  // Calculate rejection progress for smooth animation
                  final totalDistance = _dragReturnTarget.distance;
                  final currentDistance = currentOffset.distance;
                  final rejectionPhase =
                      _pendingReject && totalDistance > 0
                          ? (1 -
                              (currentDistance / totalDistance).clamp(0.0, 1.0))
                          : 0.0;
                  final rejectionTwist =
                      _rejectDirection == null
                          ? 0.0
                          : _rejectDirection!.dx.sign * rejectionPhase * 0.45;
                  final rejectionScale =
                      _pendingReject ? (1 - rejectionPhase * 0.25) : 1.0;
                  final combinedScale =
                      baseScale * interactiveScaleFactor * rejectionScale;
                  final combinedRotation = rotationAngle + rejectionTwist;

                  // Enhanced magic pulse with more intensity
                  final magicPulse = (dragProgress * 0.8 + _magicBurst * 1.2)
                      .clamp(0.0, 1.0);

                  final spiralParticles = List.generate(particleCount, (index) {
                    final angle = (index / particleCount) * 2 * math.pi;
                    final spiralOffset = (index / particleCount) * 0.25;
                    final particleValue = (particleProgress - spiralOffset)
                        .clamp(0.0, 1.0);

                    // More dynamic spiral with varying speeds
                    final particleRotation =
                        angle + (particleValue * math.pi * 4);
                    final distance =
                        screenSize.width * 0.55 * (1 - particleValue);

                    final x =
                        screenSize.width / 2 + distance * cos(particleRotation);
                    final y =
                        screenSize.height / 2 +
                        distance * sin(particleRotation);

                    // Varying particle sizes for depth
                    final size = (4 + (index % 5) * 2.5).sp;
                    final dismissOpacity = (1 - dismissValue).clamp(0.0, 1.0);
                    final particleOpacity =
                        _isDismissing
                            ? dismissOpacity
                            : particleValue * (1 - particleValue * 0.4) * 1.0;

                    // Pulsating effect
                    final pulsate =
                        0.8 +
                        0.2 * math.sin(particleProgress * math.pi * 6 + index);

                    return Positioned(
                      left: x,
                      top: y,
                      child: Opacity(
                        opacity: particleOpacity.clamp(0.0, 1.0),
                        child: Container(
                          width: size * pulsate,
                          height: size * pulsate,
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              colors: [
                                variantColor.withValues(alpha: 1.0),
                                variantColor.withValues(alpha: 0.3),
                              ],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: variantColor.withValues(alpha: 0.9),
                                blurRadius: 25,
                                spreadRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  });

                  final milestoneRings = <Widget>[];
                  if (!_isDismissing) {
                    if (progress >= 0.25 && progress < 0.35) {
                      final ringProgress = ((progress - 0.25) / 0.10).clamp(
                        0.0,
                        1.0,
                      );
                      milestoneRings.add(
                        Center(
                          child: Container(
                            width:
                                screenSize.width *
                                0.3 *
                                (1 + ringProgress * 0.5),
                            height:
                                screenSize.width *
                                0.3 *
                                (1 + ringProgress * 0.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: variantColor.withValues(
                                  alpha: (1 - ringProgress) * 0.6,
                                ),
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    if (progress >= 0.50 && progress < 0.60) {
                      final ringProgress = ((progress - 0.50) / 0.10).clamp(
                        0.0,
                        1.0,
                      );
                      milestoneRings.add(
                        Center(
                          child: Container(
                            width:
                                screenSize.width *
                                0.35 *
                                (1 + ringProgress * 0.5),
                            height:
                                screenSize.width *
                                0.35 *
                                (1 + ringProgress * 0.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: variantColor.withValues(
                                  alpha: (1 - ringProgress) * 0.7,
                                ),
                                width: 3.5,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    if (progress >= 0.75 && progress < 0.85) {
                      final ringProgress = ((progress - 0.75) / 0.10).clamp(
                        0.0,
                        1.0,
                      );
                      milestoneRings.add(
                        Center(
                          child: Container(
                            width:
                                screenSize.width *
                                0.4 *
                                (1 + ringProgress * 0.5),
                            height:
                                screenSize.width *
                                0.4 *
                                (1 + ringProgress * 0.5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: variantColor.withValues(
                                  alpha: (1 - ringProgress) * 0.8,
                                ),
                                width: 4,
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                  }

                  // Ascending "lifting" particles when dragging upward
                  final ascendingParticles = <Widget>[];
                  if (dragProgress > 0.1 || _isDraggingCard) {
                    const int liftCount = 20;
                    for (int i = 0; i < liftCount; i++) {
                      final stagger = (i / liftCount);
                      final liftHeight = dragProgress * screenSize.height * 0.6;
                      final horizontalSpread = (i - liftCount / 2) * 15.sp;
                      final yPosition =
                          screenSize.height / 2 - liftHeight * (1 - stagger);
                      final xPosition =
                          screenSize.width / 2 +
                          horizontalSpread +
                          interactiveOffset.dx * 0.5;

                      final particleOpacity =
                          (dragProgress * (1 - stagger * 0.7)).clamp(0.0, 1.0);
                      final size = (3 + stagger * 8).sp;

                      // Wavy motion as particles rise
                      final wavyX =
                          math.sin(progress * math.pi * 4 + i * 0.5) *
                          8.sp *
                          dragProgress;

                      ascendingParticles.add(
                        Positioned(
                          left: xPosition + wavyX,
                          top: yPosition,
                          child: Opacity(
                            opacity: particleOpacity,
                            child: Container(
                              width: size,
                              height: size,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    variantColor.withValues(alpha: 0.9),
                                    variantColor.withValues(alpha: 0.0),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: variantColor.withValues(
                                      alpha: particleOpacity * 0.6,
                                    ),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                  }

                  // Subtle orbiting particles (reduced count for elegance)
                  final centerBase = Offset(
                    screenSize.width / 2 + interactiveOffset.dx,
                    screenSize.height / 2 + interactiveOffset.dy,
                  );
                  final orbitingParticles = <Widget>[];
                  if (!_isDraggingCard || dragProgress < 0.3) {
                    for (int i = 0; i < 6; i++) {
                      final angle =
                          (particleProgress * math.pi * 2) +
                          i * (math.pi / 3.0);
                      final orbitRadius =
                          70 +
                          math.sin(particleProgress * math.pi * 2 + i) * 15;
                      final x = centerBase.dx + orbitRadius * math.cos(angle);
                      final y = centerBase.dy + orbitRadius * math.sin(angle);
                      final size = (4 + (i % 2) * 2).sp;
                      final particleGlow =
                          (0.3 +
                              0.3 * math.sin(angle + progress * math.pi * 2)) *
                          (1 - dragProgress);
                      orbitingParticles.add(
                        Positioned(
                          left: x - size / 2,
                          top: y - size / 2,
                          child: Opacity(
                            opacity: particleGlow.clamp(0.0, 1.0),
                            child: Container(
                              width: size,
                              height: size,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    variantColor.withValues(alpha: 0.9),
                                    variantColor.withValues(alpha: 0.0),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: variantColor.withValues(alpha: 0.5),
                                    blurRadius: 14,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                  }

                  final dragTrail = <Widget>[];
                  if (dragProgress > 0.05 || _isDraggingCard) {
                    const int trailCount = 6;
                    for (int i = 0; i < trailCount; i++) {
                      final fraction = (i + 1) / trailCount;
                      final dx = interactiveOffset.dx * fraction;
                      final dy = interactiveOffset.dy * fraction;
                      final size = (6 + i * 4).sp;
                      final opacity = (dragProgress * (1 - fraction)).clamp(
                        0.0,
                        1.0,
                      );
                      dragTrail.add(
                        Positioned(
                          left: (screenSize.width / 2) + dx - size / 2,
                          top: (screenSize.height / 2) + dy - size / 2,
                          child: Opacity(
                            opacity: opacity,
                            child: Container(
                              width: size,
                              height: size,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    variantColor.withValues(alpha: 0.8),
                                    variantColor.withValues(alpha: 0.0),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: variantColor.withValues(
                                      alpha: opacity * 0.8,
                                    ),
                                    blurRadius: 16,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                  }

                  return GestureDetector(
                    onTap: _dismissEarly,
                    behavior: HitTestBehavior.opaque,
                    child: ReactToHeroineDismiss(
                      builder: (context, dismissProgress, offset, child) {
                        final overlayFade = (1 - dismissProgress).clamp(
                          0.0,
                          1.0,
                        );
                        return Opacity(opacity: overlayFade, child: child!);
                      },
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Opacity(
                              opacity: backgroundOpacityValue,
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                          ),
                          ...spiralParticles,
                          ...milestoneRings,
                          ...orbitingParticles,
                          ...ascendingParticles,
                          if (magicPulse > 0)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: Opacity(
                                  opacity: magicPulse * 0.75,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: RadialGradient(
                                        center: const Alignment(0, -0.3),
                                        radius: 1.0,
                                        colors: [
                                          variantColor.withValues(alpha: 0.5),
                                          variantColor.withValues(alpha: 0.2),
                                          Colors.transparent,
                                        ],
                                        stops: const [0.0, 0.5, 1.0],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Center(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              dragStartBehavior: DragStartBehavior.down,
                              onTap: () {},
                              onPanStart: (_) => _startDrag(),
                              onPanUpdate: _updateDrag,
                              onPanEnd: _endDrag,
                              child: Transform.translate(
                                offset: interactiveOffset,
                                child: Transform.scale(
                                  scale: combinedScale,
                                  child: Transform(
                                    transform:
                                        Matrix4.identity()
                                          ..setEntry(
                                            3,
                                            2,
                                            0.001,
                                          ) // Add perspective
                                          ..rotateX(
                                            flipAngleX,
                                          ) // 3D flip on X axis
                                          ..rotateY(
                                            flipAngleY,
                                          ) // 3D flip on Y axis
                                          ..rotateZ(
                                            combinedRotation,
                                          ), // Regular Z rotation
                                    alignment: Alignment.center,
                                    child: Opacity(
                                      opacity: cardOpacityValue,
                                      child: Container(
                                        constraints: BoxConstraints(
                                          maxWidth: screenSize.width * 0.8,
                                        ),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            16.sp,
                                          ),
                                          child: BackdropFilter(
                                            filter: ImageFilter.blur(
                                              sigmaX: 40,
                                              sigmaY: 40,
                                            ),
                                            child: Container(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 32.sp,
                                                vertical: 28.sp,
                                              ),
                                              decoration: BoxDecoration(
                                                color: variantColor.withValues(
                                                  alpha: 0.25,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                      16.sp,
                                                    ),
                                                border: Border.all(
                                                  color: variantColor
                                                      .withValues(alpha: 0.8),
                                                  width: 2.0,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: variantColor
                                                        .withValues(
                                                          alpha:
                                                              glowOpacity * 0.8,
                                                        ),
                                                    blurRadius: 60,
                                                    spreadRadius: 12,
                                                  ),
                                                  BoxShadow(
                                                    color: variantColor
                                                        .withValues(alpha: 0.4),
                                                    blurRadius: 80,
                                                    spreadRadius: 20,
                                                  ),
                                                  BoxShadow(
                                                    color: Colors.black
                                                        .withValues(alpha: 0.4),
                                                    blurRadius: 20,
                                                    offset: const Offset(0, 10),
                                                  ),
                                                ],
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  // Evaluation badge at top
                                                  if (_formatEvalChange()
                                                      .isNotEmpty)
                                                    Container(
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                            horizontal: 12.sp,
                                                            vertical: 6.sp,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: variantColor
                                                            .withValues(
                                                              alpha: 0.3,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              20.sp,
                                                            ),
                                                        border: Border.all(
                                                          color: variantColor
                                                              .withValues(
                                                                alpha: 0.6,
                                                              ),
                                                          width: 1.5,
                                                        ),
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: variantColor
                                                                .withValues(
                                                                  alpha: 0.4,
                                                                ),
                                                            blurRadius: 12,
                                                            spreadRadius: 2,
                                                          ),
                                                        ],
                                                      ),
                                                      child: Text(
                                                        _formatEvalChange(),
                                                        style: AppTypography
                                                            .textXsMedium
                                                            .copyWith(
                                                              color:
                                                                  kWhiteColor,
                                                              fontSize: 16.sp,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              letterSpacing: 1,
                                                            ),
                                                      ),
                                                    ),
                                                  SizedBox(height: 12.sp),
                                                  // Main move text with hero animation
                                                  Builder(
                                                    builder: (context) {
                                                      final baseStyle =
                                                          AppTypography
                                                              .textXsMedium
                                                              .copyWith(
                                                                color:
                                                                    kWhiteColor,
                                                                fontSize: 16.sp,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                letterSpacing:
                                                                    -0.2,
                                                                height: 1.1,
                                                              );
                                                      final expandedStyle = AppTypography
                                                          .textXsMedium
                                                          .copyWith(
                                                            color: kWhiteColor,
                                                            fontSize: 52.sp,
                                                            fontWeight:
                                                                FontWeight.w900,
                                                            letterSpacing: 5,
                                                            height: 1.1,
                                                            shadows: [
                                                              Shadow(
                                                                color: variantColor
                                                                    .withValues(
                                                                      alpha:
                                                                          0.9,
                                                                    ),
                                                                blurRadius: 24,
                                                              ),
                                                              Shadow(
                                                                color: Colors
                                                                    .black
                                                                    .withValues(
                                                                      alpha:
                                                                          0.6,
                                                                    ),
                                                                blurRadius: 6,
                                                                offset:
                                                                    const Offset(
                                                                      0,
                                                                      3,
                                                                    ),
                                                              ),
                                                            ],
                                                          );
                                                      final targetStyle =
                                                          _showExpandedMoveText
                                                              ? expandedStyle
                                                              : baseStyle;

                                                      final heroChild = Material(
                                                        color:
                                                            Colors.transparent,
                                                        child: AnimatedDefaultTextStyle(
                                                          duration:
                                                              const Duration(
                                                                milliseconds:
                                                                    260,
                                                              ),
                                                          curve:
                                                              Curves.easeInOut,
                                                          style: targetStyle,
                                                          child: Text(
                                                            widget.moveText,
                                                            textAlign:
                                                                TextAlign
                                                                    .center,
                                                          ),
                                                        ),
                                                      );
                                                      // Always use Heroine for magical hero transition
                                                      return HeroineVelocity(
                                                        velocity: Velocity(
                                                          pixelsPerSecond:
                                                              _currentDragVelocity,
                                                        ),
                                                        child: Heroine(
                                                          tag:
                                                              widget.heroineTag,
                                                          child: heroChild,
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                  SizedBox(height: 18.sp),
                                                  // Continuation preview
                                                  if (_formatPreviewMoves()
                                                      .isNotEmpty)
                                                    Container(
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                            horizontal: 18.sp,
                                                            vertical: 10.sp,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.black
                                                            .withValues(
                                                              alpha: 0.5,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              10.sp,
                                                            ),
                                                        border: Border.all(
                                                          color: variantColor
                                                              .withValues(
                                                                alpha: 0.4,
                                                              ),
                                                          width: 1,
                                                        ),
                                                      ),
                                                      child: Opacity(
                                                        opacity: (progress *
                                                                1.3)
                                                            .clamp(0.0, 1.0),
                                                        child: Text(
                                                          _formatPreviewMoves(),
                                                          textAlign:
                                                              TextAlign.center,
                                                          style: AppTypography
                                                              .textXsMedium
                                                              .copyWith(
                                                                color: kWhiteColor
                                                                    .withValues(
                                                                      alpha:
                                                                          0.95,
                                                                    ),
                                                                fontSize: 15.sp,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                letterSpacing:
                                                                    1.2,
                                                                height: 1.5,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  SizedBox(height: 24.sp),
                                                  // Action buttons - ignore pointer when dragging
                                                  IgnorePointer(
                                                    ignoring: _isDraggingCard,
                                                    child: Column(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        // Promote Main Variant button
                                                        SizedBox(
                                                          width:
                                                              double.infinity,
                                                          child: Material(
                                                            color:
                                                                Colors
                                                                    .transparent,
                                                            child: InkWell(
                                                              onTap:
                                                                  _onPromoteMainVariant,
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    10.sp,
                                                                  ),
                                                              child: Container(
                                                                padding:
                                                                    EdgeInsets.symmetric(
                                                                      vertical:
                                                                          14.sp,
                                                                    ),
                                                                decoration: BoxDecoration(
                                                                  gradient: LinearGradient(
                                                                    colors: [
                                                                      variantColor.withValues(
                                                                        alpha:
                                                                            0.4,
                                                                      ),
                                                                      variantColor.withValues(
                                                                        alpha:
                                                                            0.3,
                                                                      ),
                                                                    ],
                                                                  ),
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        10.sp,
                                                                      ),
                                                                  border: Border.all(
                                                                    color: variantColor
                                                                        .withValues(
                                                                          alpha:
                                                                              0.6,
                                                                        ),
                                                                    width: 1.5,
                                                                  ),
                                                                ),
                                                                child: Row(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .center,
                                                                  children: [
                                                                    Icon(
                                                                      Icons
                                                                          .upgrade_rounded,
                                                                      color:
                                                                          kWhiteColor,
                                                                      size:
                                                                          18.sp,
                                                                    ),
                                                                    SizedBox(
                                                                      width:
                                                                          8.sp,
                                                                    ),
                                                                    Text(
                                                                      'Promote Main Variant',
                                                                      style: AppTypography.textSmBold.copyWith(
                                                                        color:
                                                                            kWhiteColor,
                                                                        fontSize:
                                                                            14.sp,
                                                                        fontWeight:
                                                                            FontWeight.w700,
                                                                        letterSpacing:
                                                                            0.3,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        SizedBox(height: 10.sp),
                                                        // Insert All Moves button
                                                        SizedBox(
                                                          width:
                                                              double.infinity,
                                                          child: Material(
                                                            color:
                                                                Colors
                                                                    .transparent,
                                                            child: InkWell(
                                                              onTap:
                                                                  _onInsertAllMoves,
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    10.sp,
                                                                  ),
                                                              child: Container(
                                                                padding:
                                                                    EdgeInsets.symmetric(
                                                                      vertical:
                                                                          14.sp,
                                                                    ),
                                                                decoration: BoxDecoration(
                                                                  color: Colors
                                                                      .black
                                                                      .withValues(
                                                                        alpha:
                                                                            0.3,
                                                                      ),
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        10.sp,
                                                                      ),
                                                                  border: Border.all(
                                                                    color: variantColor
                                                                        .withValues(
                                                                          alpha:
                                                                              0.4,
                                                                        ),
                                                                    width: 1,
                                                                  ),
                                                                ),
                                                                child: Row(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .center,
                                                                  children: [
                                                                    Icon(
                                                                      Icons
                                                                          .add_circle_outline_rounded,
                                                                      color: kWhiteColor.withValues(
                                                                        alpha:
                                                                            0.9,
                                                                      ),
                                                                      size:
                                                                          18.sp,
                                                                    ),
                                                                    SizedBox(
                                                                      width:
                                                                          8.sp,
                                                                    ),
                                                                    Text(
                                                                      'Insert All Moves',
                                                                      style: AppTypography.textSmBold.copyWith(
                                                                        color: kWhiteColor.withValues(
                                                                          alpha:
                                                                              0.9,
                                                                        ),
                                                                        fontSize:
                                                                            14.sp,
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                        letterSpacing:
                                                                            0.3,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        SizedBox(height: 10.sp),
                                                        // Preview button
                                                        SizedBox(
                                                          width:
                                                              double.infinity,
                                                          child: Material(
                                                            color:
                                                                Colors
                                                                    .transparent,
                                                            child: InkWell(
                                                              onTap: _onPreview,
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    10.sp,
                                                                  ),
                                                              child: Container(
                                                                padding:
                                                                    EdgeInsets.symmetric(
                                                                      vertical:
                                                                          14.sp,
                                                                    ),
                                                                decoration: BoxDecoration(
                                                                  color: Colors
                                                                      .black
                                                                      .withValues(
                                                                        alpha:
                                                                            0.3,
                                                                      ),
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        10.sp,
                                                                      ),
                                                                  border: Border.all(
                                                                    color: variantColor
                                                                        .withValues(
                                                                          alpha:
                                                                              0.4,
                                                                        ),
                                                                    width: 1,
                                                                  ),
                                                                ),
                                                                child: Row(
                                                                  mainAxisAlignment:
                                                                      MainAxisAlignment
                                                                          .center,
                                                                  children: [
                                                                    Icon(
                                                                      Icons
                                                                          .visibility_outlined,
                                                                      color: kWhiteColor.withValues(
                                                                        alpha:
                                                                            0.9,
                                                                      ),
                                                                      size:
                                                                          18.sp,
                                                                    ),
                                                                    SizedBox(
                                                                      width:
                                                                          8.sp,
                                                                    ),
                                                                    Text(
                                                                      'Preview',
                                                                      style: AppTypography.textSmBold.copyWith(
                                                                        color: kWhiteColor.withValues(
                                                                          alpha:
                                                                              0.9,
                                                                        ),
                                                                        fontSize:
                                                                            14.sp,
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                        letterSpacing:
                                                                            0.3,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        // Swipe up hint with animated arrow
                                                        SizedBox(height: 16.sp),
                                                        TweenAnimationBuilder<
                                                          double
                                                        >(
                                                          duration:
                                                              const Duration(
                                                                milliseconds:
                                                                    1500,
                                                              ),
                                                          tween: Tween(
                                                            begin: 0.0,
                                                            end: 1.0,
                                                          ),
                                                          curve:
                                                              Curves.easeInOut,
                                                          builder: (
                                                            context,
                                                            value,
                                                            child,
                                                          ) {
                                                            final bounce =
                                                                math.sin(
                                                                  value *
                                                                      math.pi *
                                                                      2,
                                                                ) *
                                                                4;
                                                            final opacity =
                                                                0.4 +
                                                                (math.sin(
                                                                      value *
                                                                          math.pi *
                                                                          2,
                                                                    ) *
                                                                    0.3);
                                                            return Transform.translate(
                                                              offset: Offset(
                                                                0,
                                                                bounce,
                                                              ),
                                                              child: Opacity(
                                                                opacity:
                                                                    opacity,
                                                                child: Column(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    Icon(
                                                                      Icons
                                                                          .keyboard_arrow_up_rounded,
                                                                      color:
                                                                          variantColor,
                                                                      size:
                                                                          32.sp,
                                                                    ),
                                                                    Text(
                                                                      'Swipe up to preview',
                                                                      style: AppTypography.textXsRegular.copyWith(
                                                                        color: kWhiteColor.withValues(
                                                                          alpha:
                                                                              0.6,
                                                                        ),
                                                                        fontSize:
                                                                            11.sp,
                                                                        fontWeight:
                                                                            FontWeight.w500,
                                                                        letterSpacing:
                                                                            0.5,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              ),
                                                            );
                                                          },
                                                          onEnd: () {
                                                            // Loop the animation
                                                            if (mounted) {
                                                              setState(() {});
                                                            }
                                                          },
                                                        ),
                                                      ],
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
                          ),
                          ...dragTrail,
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  double cos(double radians) => math.cos(radians);
  double sin(double radians) => math.sin(radians);
}
