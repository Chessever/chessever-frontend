import 'dart:async';
// import 'dart:io'; // UNUSED: Removed with old dialog approach
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
import 'package:chessever2/providers/gamebase_overlay_settings_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
// DISABLED: Move annotation overlay (requires move impact analysis)
// import 'package:chessever2/screens/chessboard/widgets/move_annotation_overlay.dart';
import 'package:chessever2/screens/chessboard/widgets/share_game_card_overlay.dart';
import 'package:chessever2/screens/chessboard/chess_board_settings_page.dart';
import 'package:chessever2/screens/chessboard/widgets/smooth_sheet_config.dart';
import 'package:chessever2/screens/chessboard/widgets/save_analysis_sheet.dart';
import 'package:chessever2/screens/group_event/providers/countryman_games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/utils/audio_player_service.dart';
// import 'package:chessever2/utils/keyboard_animation_builder.dart'; // UNUSED: Removed with old dialog
// import 'package:chessever2/providers/keyboard_total_height_provider.dart'; // UNUSED: Removed with old dialog
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
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
// import 'package:chessever2/widgets/smooth_dialog.dart'; // UNUSED: Removed with old dialog
import 'package:smooth_sheets/smooth_sheets.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:country_flags/country_flags.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/url_launcher_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:motor/motor.dart';
import 'package:chessever2/screens/gamebase/widgets/gamebase_explorer_view.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/library/utils/gamebase_pgn_builder.dart';
import 'package:chessever2/screens/library/utils/gamebase_game_to_games_tour_model.dart';
import 'package:chessever2/utils/chess_title_utils.dart';

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

  /// Optional saved analysis data to restore full state (variations, comments, position)
  final SavedAnalysisData? savedAnalysisData;

  /// When true, hides the event info button in the app bar.
  /// Use this when navigating from library for position analysis where event info is not relevant.
  final bool hideEventInfo;
  final bool showGamebaseButton;

  /// When true, the gamebase overlay will be disabled by default on screen init.
  /// Use this for library routes where games are typically past move 10.
  final bool disableGamebaseOverlayByDefault;
  final bool showClock;

  const ChessBoardScreenNew({
    required this.currentIndex,
    required this.games,
    this.savedAnalysisData,
    this.hideEventInfo = false,
    this.showGamebaseButton = false,
    this.disableGamebaseOverlayByDefault = false,
    this.showClock = true,
    super.key,
  });

  @override
  ConsumerState<ChessBoardScreenNew> createState() => _ChessBoardScreenState();
}

class _ChessBoardScreenState extends ConsumerState<ChessBoardScreenNew>
    with WidgetsBindingObserver {
  late PageController _pageController;
  bool analysisMode = false;
  int? _lastViewedIndex;
  int _currentPageIndex = 0;
  final Set<String> _syncedLatestPositions = <String>{};
  bool _isRevertingPage = false;
  ProviderSubscription<AsyncValue<ChessBoardStateNew>>? _boardKeepAliveSub;
  ChessBoardProviderParams? _keepAliveParams;

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

  /// Returns saved analysis data only for the initial page (currentIndex)
  /// This ensures variations and comments are only restored for the saved analysis game
  SavedAnalysisData? _getSavedAnalysisDataForIndex(int index) {
    // Only apply saved analysis data to the initial page
    if (index == widget.currentIndex) {
      return widget.savedAnalysisData;
    }
    return null;
  }

  /// Creates ChessBoardProviderParams with optional saved analysis data
  ChessBoardProviderParams _createParams(GamesTourModel game, int index) {
    return ChessBoardProviderParams(
      game: game,
      index: index,
      savedAnalysisData: _getSavedAnalysisDataForIndex(index),
    );
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

  /// Keep the active board provider alive even before build starts watching it.
  /// This prevents the autoDispose notifier from being disposed while we kick off
  /// early work (parseMoves / initial eval) from initState/didChangeDependencies.
  void _keepBoardProviderAlive(int pageIndex) {
    if (widget.games.isEmpty) return;

    final params = _createParams(_resolveGameForIndex(pageIndex), pageIndex);

    if (_keepAliveParams == params) return;

    _boardKeepAliveSub?.close();
    _keepAliveParams = params;
    _boardKeepAliveSub = ref.listenManual<AsyncValue<ChessBoardStateNew>>(
      chessBoardScreenProviderNew(params),
      (_, __) {},
      fireImmediately: false,
      onError: (err, st) {
        debugPrint('Error keeping chess board provider alive: $err');
      },
    );
  }

  @override
  void initState() {
    super.initState();
    // Defensive: Ensure currentIndex is within bounds of games list
    final safeIndex = widget.currentIndex.clamp(0, widget.games.length - 1);
    _pageController = PageController(initialPage: safeIndex);
    _currentPageIndex = safeIndex;
    _keepBoardProviderAlive(_currentPageIndex);

    // Note: We'll enable streaming in didChangeDependencies when ref is available
    WidgetsBinding.instance.addObserver(this);
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

        // Disable gamebase overlay by default for library routes (games past move 10)
        if (widget.disableGamebaseOverlayByDefault) {
          ref.read(gamebaseOverlayEnabledProvider.notifier).setEnabled(false);
        }

        // Analysis mode is already enabled by default in the provider initialization
        // No need to toggle it here
        try {
          final initialGame = _resolveGameForIndex(_currentPageIndex);
          final params = _createParams(initialGame, _currentPageIndex);
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
    final params = _createParams(game, pageIndex);
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
    _keepBoardProviderAlive(newIndex);

    // CRITICAL: Update the global provider to track which page is visible
    // This prevents off-screen games from playing audio
    ref.read(currentlyVisiblePageIndexProvider.notifier).state = newIndex;

    // Cancel active evaluations on the board that just went off-screen
    try {
      final prevGame = _resolveGameForIndex(previousIndex);
      final prevParams = _createParams(prevGame, previousIndex);
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
                _createParams(prevGame, previousIndex),
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
          final params = _createParams(newGame, newIndex);
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

  void _handleLifecycleResume() {
    if (!mounted || widget.games.isEmpty) return;
    final safeIndex = _currentPageIndex.clamp(0, widget.games.length - 1);
    final currentGame = _resolveGameForIndex(safeIndex);
    final params = _createParams(currentGame, safeIndex);
    try {
      final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
      unawaited(notifier.onBecameVisible(force: true));
    } catch (e) {
      debugPrint('Error refreshing Stockfish on resume: $e');
    }
  }

  void _handleLifecyclePaused() {
    if (!mounted || widget.games.isEmpty) return;
    final safeIndex = _currentPageIndex.clamp(0, widget.games.length - 1);
    final currentGame = _resolveGameForIndex(safeIndex);
    final params = _createParams(currentGame, safeIndex);
    try {
      final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
      unawaited(notifier.onBecameInvisible());
    } catch (e) {
      debugPrint('Error pausing Stockfish on lifecycle change: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      _handleLifecycleResume();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _handleLifecyclePaused();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _boardKeepAliveSub?.close();
    _pageController.dispose();
    super.dispose();
  }

  void _navigateToGame(int gameIndex) {
    debugPrint(
      '🎯 _navigateToGame called with gameIndex: $gameIndex, current: $_currentPageIndex',
    );
    if (gameIndex == _currentPageIndex) {
      debugPrint('🎯 Same page, returning early');
      return;
    }

    // Validate gameIndex is within bounds
    if (gameIndex < 0 || gameIndex >= widget.games.length) {
      debugPrint(
        '🎯 Invalid gameIndex: $gameIndex (games.length: ${widget.games.length})',
      );
      return;
    }

    // OPTIMIZED: Don't read provider during navigation - just pause the current game
    try {
      final currentGame = _resolveGameForIndex(_currentPageIndex);
      ref
          .read(
            chessBoardScreenProviderNew(
              _createParams(currentGame, _currentPageIndex),
            ).notifier,
          )
          .pauseGame();
    } catch (e) {
      debugPrint('Error pausing game during navigation: $e');
    }

    // Use jumpToPage for jumps > 1 page to avoid animation interference
    // animateToPage can trigger multiple onPageChanged events during animation
    final distance = (gameIndex - _currentPageIndex).abs();
    debugPrint(
      '🎯 Navigating from $_currentPageIndex to $gameIndex (distance: $distance)',
    );

    if (distance > 1) {
      // For large jumps, use jumpToPage to avoid intermediate page triggers
      _pageController.jumpToPage(gameIndex);
    } else {
      // For adjacent pages, animate smoothly
      _pageController.animateToPage(
        gameIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _toggleGamebase() {
    ref.read(gamebaseOverlayEnabledProvider.notifier).toggle();
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
        // Use a non-listening read here to avoid triggering rebuilds of the
        // tournament list/app bar while this board is building (which caused
        // setState during build exceptions). We still get the latest snapshot.
        gamesAsync = ref.read(gamesTourScreenProvider);
        break;
      case ChessboardView.countryman:
        gamesAsync = ref.watch(countrymanGamesTourScreenProvider);
        break;
    }

    // Fallback for contexts (e.g., For You tab) where gamesTourScreenProvider
    // isn't hydrated yet. We still want to open the board with the passed games.
    GamesScreenModel? gamesModel = gamesAsync.valueOrNull;
    if (gamesModel == null || gamesModel.gamesTourModels.isEmpty) {
      if (widget.games.isNotEmpty) {
        gamesModel = GamesScreenModel(
          gamesTourModels: widget.games,
          pinnedGamedIs: const [],
        );
      }
    }

    if (gamesModel == null || gamesModel.gamesTourModels.isEmpty) {
      return _LoadingScreen(
        games: widget.games.isNotEmpty ? widget.games : [widget.games.first],
        currentGameIndex: _currentPageIndex.clamp(0, widget.games.length - 1),
        onGameChanged: (index) {},
        lastViewedIndex: _lastViewedIndex,
      );
    }

    final liveGamesMap = Map.fromEntries(
      gamesModel.gamesTourModels.map((g) => MapEntry(g.gameId, g)),
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
      final params = _createParams(game, i);
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
        _createParams(currentGame, _currentPageIndex),
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
              audioService.playSound(audioService.pieceCheckmateSfx);
            } else if (moveSan.contains('+')) {
              // Check notation (but not checkmate)
              audioService.playSound(audioService.pieceCheckSfx);
            } else if (moveSan == 'O-O' || moveSan == 'O-O-O') {
              // Castling (kingside or queenside) - exact match
              audioService.playSound(audioService.pieceCastlingSfx);
            } else if (moveSan.contains('=')) {
              // Pawn promotion (e.g., e8=Q)
              audioService.playSound(audioService.piecePromotionSfx);
            } else if (moveSan.contains('x')) {
              // Capture notation
              audioService.playSound(audioService.pieceTakeoverSfx);
            } else {
              // Regular move (no special notation)
              audioService.playSound(audioService.pieceMoveSfx);
            }
          } else if (currentIndex == -1 && prevIndex >= 0) {
            // Moving back to the starting position (before first move)
            // Play a regular move sound for the "undo" action
            audioService.playSound(audioService.pieceMoveSfx);
          } else if (currentIndex == movesSan.length && movesSan.isNotEmpty) {
            // We're at the end of the game, check for game-ending conditions
            final lastMoveSan = movesSan.last;

            if (lastMoveSan.contains('#')) {
              // Game ended with checkmate
              audioService.playSound(audioService.pieceCheckmateSfx);
            } else if (state.game.gameStatus == GameStatus.draw) {
              // Game ended in a draw
              audioService.playSound(audioService.pieceDrawSfx);
            } else {
              // Other game endings (resignation, time out, etc.)
              audioService.playSound(audioService.pieceMoveSfx);
            }
          } else {
            // Fallback for edge cases (shouldn't normally happen)
            audioService.playSound(audioService.pieceMoveSfx);
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
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.black,
          systemNavigationBarColor: Colors.black,
        ),
        child: Scaffold(
          backgroundColor: Colors.black,
          resizeToAvoidBottomInset: false,
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
                  final params = _createParams(game, index);
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
                        hideEventInfo: widget.hideEventInfo,
                        onToggleGamebase: _toggleGamebase,
                        showGamebaseButton: widget.showGamebaseButton,
                        showClock: widget.showClock,
                      );
                    },
                    error: (e, _) => ErrorWidget(e),
                    loading:
                        () => _LoadingScreen(
                          games: liveGames,
                          currentGameIndex: index,
                          onGameChanged: _navigateToGame,
                          lastViewedIndex: _lastViewedIndex,
                          hideEventInfo: widget.hideEventInfo,
                        ),
                  );
                } catch (e) {
                  // Fallback for when provider isn't ready
                  return _LoadingScreen(
                    games: liveGames,
                    currentGameIndex: index,
                    onGameChanged: _navigateToGame,
                    lastViewedIndex: _lastViewedIndex,
                    hideEventInfo: widget.hideEventInfo,
                  );
                }
              } else {
                return SizedBox.shrink();
              }
            },
          ),
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
  final bool hideEventInfo;
  final VoidCallback onToggleGamebase;
  final bool showGamebaseButton;
  final bool showClock;

  const _GamePage({
    required this.game,
    required this.state,
    required this.games,
    required this.currentGameIndex,
    required this.currentPageIndex,
    required this.onGameChanged,
    required this.onToggleGamebase,
    this.lastViewedIndex,
    this.hideEventInfo = false,
    this.showGamebaseButton = false,
    this.showClock = true,
  });

  @override
  Widget build(BuildContext context) {
    final scaffold = Scaffold(
      resizeToAvoidBottomInset: false,
      bottomNavigationBar: _BottomNavBar(
        index: currentGameIndex,
        state: state,
        game: game,
        onGamebaseToggle: onToggleGamebase,
        showGamebaseButton: showGamebaseButton,
      ),
      appBar: _AppBar(
        game: game,
        games: games,
        currentGameIndex: currentGameIndex,
        onGameChanged: onGameChanged,
        lastViewedIndex: lastViewedIndex,
        hideEventInfo: hideEventInfo,
      ),
      body: _GameBody(
        index: currentGameIndex,
        currentPageIndex: currentPageIndex,
        game: game,
        state: state,
        showGamebaseButton: showGamebaseButton,
        showClock: showClock,
      ),
    );
    return MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: scaffold,
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  final List<GamesTourModel> games;
  final int currentGameIndex;
  final void Function(int) onGameChanged;
  final int? lastViewedIndex;
  final bool hideEventInfo;

  const _LoadingScreen({
    required this.games,
    required this.currentGameIndex,
    required this.onGameChanged,
    this.lastViewedIndex,
    this.hideEventInfo = false,
  });

  @override
  Widget build(BuildContext context) {
    final sideBarWidth = 20.w;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final boardSize = screenWidth - sideBarWidth - 32.w;

    final scaffold = Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: _AppBar(
        game: games[currentGameIndex],
        games: games,
        currentGameIndex: currentGameIndex,
        onGameChanged: onGameChanged,
        isLoading: true,
        lastViewedIndex: lastViewedIndex,
        hideEventInfo: hideEventInfo,
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
    return MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      child: scaffold,
    );
  }
}

class _AppBar extends ConsumerStatefulWidget implements PreferredSizeWidget {
  final GamesTourModel game;
  final List<GamesTourModel> games;
  final int currentGameIndex;
  final void Function(int) onGameChanged;
  final bool isLoading;
  final int? lastViewedIndex;
  final bool hideEventInfo;

  const _AppBar({
    required this.game,
    required this.games,
    required this.currentGameIndex,
    required this.onGameChanged,
    this.isLoading = false,
    this.lastViewedIndex,
    this.hideEventInfo = false,
  });

  @override
  ConsumerState<_AppBar> createState() => _AppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _AppBarState extends ConsumerState<_AppBar> {
  Future<void> _showSaveAnalysisDialog() async {
    final allowed = await requireFullAuthGuard(context);
    if (!allowed) return;

    final params = ChessBoardProviderParams(
      game: widget.game,
      index: widget.currentGameIndex,
    );
    final boardState = ref.read(chessBoardScreenProviderNew(params));

    if (!boardState.hasValue || boardState.value == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please wait for the game to load'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await showSaveAnalysisSheet(
      context: context,
      state: boardState.value!,
      params: params,
    );
  }

  void copyPgnBtnClicked() async {
    String? pgn;
    final params = ChessBoardProviderParams(
      game: widget.game,
      index: widget.currentGameIndex,
    );
    final boardState = ref.read(chessBoardScreenProviderNew(params));
    final analysisGame = boardState.valueOrNull?.analysisState.game;
    if (analysisGame != null) {
      pgn = exportGameToPgn(analysisGame);
    }
    pgn ??=
        (await ref
            .read(gameRepositoryProvider)
            .getGameById(widget.game.gameId)).pgn ??
        '';
    Clipboard.setData(ClipboardData(text: pgn));
  }

  void shareGameBtnClicked() async {
    // Get the board provider to access the current state
    final params = ChessBoardProviderParams(
      game: widget.game,
      index: widget.currentGameIndex,
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
        .getGameById(widget.game.gameId);
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
                  _ShareGameScreen(game: widget.game, state: state, pgn: pgn),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    }
  }

  void _showEventInfoSheet(BuildContext context, WidgetRef ref, String? pgn) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EventInfoSheet(game: widget.game, pgn: pgn),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch the board state for PGN data
    final params = ChessBoardProviderParams(
      game: widget.game,
      index: widget.currentGameIndex,
    );
    final boardState = ref.watch(chessBoardScreenProviderNew(params));
    final state = boardState.valueOrNull;
    final infoSheetPgn = state?.pgnData ?? widget.game.pgn;

    return AppBar(
      elevation: 0,
      backgroundColor: Colors.black,
      surfaceTintColor: Colors.black,
      leadingWidth: 44.sp,
      titleSpacing: 4.sp,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new, color: kWhiteColor, size: 20.sp),
        onPressed: () => Navigator.pop(context, widget.lastViewedIndex),
      ),
      title:
          widget.hideEventInfo
              ? Text(
                'Analysis Board',
                style: TextStyle(
                  color: kWhiteColor,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
              )
              : _GameSelectionDropdown(
                games: widget.games,
                currentGameIndex: widget.currentGameIndex,
                onGameChanged: widget.onGameChanged,
                isLoading: widget.isLoading,
              ),
      actions: [
        SizedBox(width: 4.sp),
        // Event info button (hidden when navigating from library for position analysis)
        if (!widget.hideEventInfo)
          IconButton(
            icon: Icon(
              Icons.info_outline_rounded,
              color: kWhiteColor,
              size: 20.sp,
            ),
            tooltip: 'Event info',
            onPressed:
                widget.isLoading
                    ? null
                    : () => _showEventInfoSheet(context, ref, infoSheetPgn),
          ),
        // Save Analysis button
        IconButton(
          icon: Icon(Icons.save_outlined, color: kWhiteColor, size: 20.sp),
          tooltip: 'Save analysis',
          onPressed: widget.isLoading ? null : _showSaveAnalysisDialog,
        ),
        // 3-dot menu
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: kWhiteColor, size: 22.sp),
          enabled: !widget.isLoading,
          onSelected: (value) async {
            if (value == 'share') {
              shareGameBtnClicked();
            } else if (value == 'board_settings') {
              final allowed = await requireFullAuthGuard(context);
              if (!allowed) return;
              if (!context.mounted) return;
              Navigator.of(context).push(ChessBoardSettingsPage.route());
            } else if (value == 'clear_analysis') {
              final params = ChessBoardProviderParams(
                game: widget.game,
                index: widget.currentGameIndex,
              );
              final boardState = ref.read(chessBoardScreenProviderNew(params));
              final analysisGame = boardState.valueOrNull?.analysisState.game;
              final hasCustomAnalysis = _gameHasCustomVariations(analysisGame);

              if (!hasCustomAnalysis) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('No custom analysis to clear'),
                    backgroundColor: Colors.orange,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }

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
              final notifier = ref.read(
                chessBoardScreenProviderNew(params).notifier,
              );
              await notifier.clearUserAnalysis();
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
                    copyPgnBtnClicked();
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
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'clear_analysis',
                  child: Row(
                    children: [
                      Icon(Icons.auto_delete_outlined, color: kRedColor),
                      SizedBox(width: 8.w),
                      const Text(
                        'Clear Analysis',
                        style: TextStyle(color: kRedColor),
                      ),
                    ],
                  ),
                ),
              ],
        ),
        SizedBox(width: 4.sp),
      ],
    );
  }
}

/// Beautiful stadium-chip style game selection dropdown with glass morphism
/// and smooth spring animations - matching CategoryDropdown design language
class _GameSelectionDropdown extends StatefulWidget {
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

  @override
  State<_GameSelectionDropdown> createState() => _GameSelectionDropdownState();
}

class _GameSelectionDropdownState extends State<_GameSelectionDropdown>
    with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  late AnimationController _animationController;
  late Animation<double> _animation;
  bool _isOpen = false;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    _animationController.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    try {
      _overlayEntry?.remove();
    } catch (_) {}
    _overlayEntry = null;
  }

  String _formatName(String fullName, {double? maxWidth}) {
    List<String> nameParts =
        fullName.trim().split(' ').where((part) => part.isNotEmpty).toList();
    if (nameParts.length <= 1) return fullName;

    String familyName = nameParts.last;
    List<String> otherNames = nameParts.sublist(0, nameParts.length - 1);
    String fullVersion = '${otherNames.join(' ')} $familyName';

    if (maxWidth == null) return fullVersion;

    double estimatedWidth = fullVersion.length * 6.0;
    if (estimatedWidth <= maxWidth) return fullVersion;

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
    return '${displayNames.join(' ')} $familyName';
  }

  String _extractLastName(String fullName) {
    final name = fullName.trim();
    if (name.isEmpty) return fullName;

    // Handle "LastName, FirstName" format (common in chess)
    if (name.contains(',')) {
      final lastName = name.split(',').first.trim();
      if (lastName.isNotEmpty) return lastName;
    }

    // Suffixes to ignore when finding last name
    const suffixes = {
      'jr',
      'jr.',
      'sr',
      'sr.',
      'ii',
      'iii',
      'iv',
      'v',
      '2nd',
      '3rd',
      '4th',
      '5th',
    };

    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return fullName;
    if (parts.length == 1) return parts.first;

    // Find the last part that isn't a suffix
    for (int i = parts.length - 1; i >= 0; i--) {
      if (!suffixes.contains(parts[i].toLowerCase())) {
        return parts[i];
      }
    }

    return parts.last;
  }

  void _openDropdown() {
    if (widget.games.length <= 1 || widget.isLoading || _isOpen) return;

    HapticFeedback.selectionClick();
    setState(() => _isOpen = true);
    _showOverlay();
    _animationController.forward();
  }

  void _closeDropdown() {
    if (!_isOpen) return;

    _animationController.reverse().then((_) {
      if (mounted) {
        setState(() => _isOpen = false);
        _removeOverlay();
      }
    });
  }

  void _showOverlay() {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final availableHeight = screenHeight - offset.dy - size.height - 32.sp;

    _overlayEntry = OverlayEntry(
      builder:
          (context) => _GameDropdownOverlay(
            layerLink: _layerLink,
            triggerSize: size,
            triggerOffset: offset,
            screenWidth: screenWidth,
            availableHeight: availableHeight,
            animation: _animation,
            games: widget.games,
            currentGameIndex: widget.currentGameIndex,
            isLoading: widget.isLoading,
            onSelect: (selectedIndex) {
              debugPrint(
                '🎯 Dropdown onSelect: selectedIndex=$selectedIndex, currentGameIndex=${widget.currentGameIndex}',
              );
              HapticFeedback.selectionClick();
              if (selectedIndex >= 0 &&
                  selectedIndex < widget.games.length &&
                  selectedIndex != widget.currentGameIndex) {
                debugPrint(
                  '🎯 Calling onGameChanged with index: $selectedIndex',
                );
                widget.onGameChanged(selectedIndex);
              } else {
                debugPrint(
                  '🎯 Skipping navigation - same game or invalid index',
                );
              }
              _closeDropdown();
            },
            onDismiss: _closeDropdown,
          ),
    );

    overlay.insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.games.isEmpty) return const SizedBox.shrink();

    final currentGame = widget.games[widget.currentGameIndex];
    final displayText =
        '${_extractLastName(currentGame.whitePlayer.displayName)} vs ${_extractLastName(currentGame.blackPlayer.displayName)}';

    return CompositedTransformTarget(
      link: _layerLink,
      child: _GameChipButton(
        label: displayText,
        gameStatus: currentGame.gameStatus,
        isOpen: _isOpen,
        isLoading: widget.isLoading,
        showChevron: widget.games.length > 1,
        onTap: () {
          if (_isOpen) {
            _closeDropdown();
          } else {
            _openDropdown();
          }
        },
      ),
    );
  }
}

/// Stadium-shaped chip button for game selection trigger
class _GameChipButton extends StatelessWidget {
  final String label;
  final GameStatus gameStatus;
  final bool isOpen;
  final bool isLoading;
  final bool showChevron;
  final VoidCallback? onTap;

  const _GameChipButton({
    required this.label,
    required this.gameStatus,
    required this.isOpen,
    this.onTap,
    this.isLoading = false,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: 10.sp, vertical: 6.sp),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100.br),
          color:
              isOpen
                  ? kPrimaryColor.withValues(alpha: 0.15)
                  : kWhiteColor.withValues(alpha: 0.06),
          border: Border.all(
            color:
                isOpen
                    ? kPrimaryColor.withValues(alpha: 0.4)
                    : kWhiteColor.withValues(alpha: 0.12),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Status indicator
            _GameStatusIndicator(status: gameStatus, isLoading: isLoading),
            SizedBox(width: 6.sp),
            // Game label - centered, flexible to allow truncation
            Flexible(
              child: Text(
                label,
                style: AppTypography.textXsMedium.copyWith(
                  color: isOpen ? kPrimaryColor : kWhiteColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            // Chevron
            if (showChevron) ...[
              SizedBox(width: 4.sp),
              AnimatedRotation(
                turns: isOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color:
                      isOpen
                          ? kPrimaryColor
                          : kWhiteColor.withValues(alpha: 0.7),
                  size: 16.ic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Game status indicator with live pulsing animation
class _GameStatusIndicator extends StatelessWidget {
  final GameStatus status;
  final bool isLoading;

  const _GameStatusIndicator({required this.status, this.isLoading = false});

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return SizedBox(
        width: 10.sp,
        height: 10.sp,
        child: CircularProgressIndicator(
          strokeWidth: 1.5,
          color: kPrimaryColor,
        ),
      );
    }

    final color = _getStatusColor();
    final isLive = status == GameStatus.ongoing;

    return Container(
      width: 8.sp,
      height: 8.sp,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        // Flat design - no glow/shadow
      ),
      child: isLive ? _LivePulsingDot(color: color) : null,
    );
  }

  Color _getStatusColor() {
    switch (status) {
      case GameStatus.ongoing:
        return kPrimaryColor;
      case GameStatus.whiteWins:
      case GameStatus.blackWins:
      case GameStatus.draw:
        return kWhiteColor70;
      case GameStatus.unknown:
        return kWhiteColor70;
    }
  }
}

/// Pulsing animation for live/ongoing games
class _LivePulsingDot extends StatefulWidget {
  final Color color;

  const _LivePulsingDot({required this.color});

  @override
  State<_LivePulsingDot> createState() => _LivePulsingDotState();
}

class _LivePulsingDotState extends State<_LivePulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 1 - _controller.value * 0.5),
          ),
        );
      },
    );
  }
}

/// The floating dropdown overlay with glass morphism
class _GameDropdownOverlay extends StatelessWidget {
  final LayerLink layerLink;
  final Size triggerSize;
  final Offset triggerOffset;
  final double screenWidth;
  final double availableHeight;
  final Animation<double> animation;
  final List<GamesTourModel> games;
  final int currentGameIndex;
  final bool isLoading;
  final ValueChanged<int> onSelect; // Provides the tapped game index directly
  final VoidCallback onDismiss;

  const _GameDropdownOverlay({
    required this.layerLink,
    required this.triggerSize,
    required this.triggerOffset,
    required this.screenWidth,
    required this.availableHeight,
    required this.animation,
    required this.games,
    required this.currentGameIndex,
    required this.isLoading,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate dropdown width - much wider for player names
    final dropdownWidth = (screenWidth - 32.w).clamp(280.w, 340.w);
    // Center the dropdown below the trigger
    final leftOffset = (screenWidth - dropdownWidth) / 2;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onDismiss,
      child: Stack(
        children: [
          Positioned.fill(child: Container(color: Colors.transparent)),
          Positioned(
            left: leftOffset,
            top: triggerOffset.dy + triggerSize.height + 8.sp,
            child: Material(
              type: MaterialType.transparency,
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  final progress = animation.value.clamp(0.0, 1.0);
                  return Transform.scale(
                    scale: 0.92 + (progress * 0.08),
                    alignment: Alignment.topCenter,
                    child: Opacity(opacity: progress, child: child),
                  );
                },
                child: Container(
                  width: dropdownWidth,
                  constraints: BoxConstraints(
                    maxHeight: availableHeight.clamp(180.0, 380.0),
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(16.br),
                    border: Border.all(
                      color: kWhiteColor.withValues(alpha: 0.08),
                      width: 1.0,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16.br),
                    child: _GameDropdownContent(
                      dropdownWidth: dropdownWidth,
                      availableHeight: availableHeight,
                      animation: animation,
                      games: games,
                      currentGameIndex: currentGameIndex,
                      isLoading: isLoading,
                      onSelect: onSelect,
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
}

/// Minimal dropdown content with round section separators
class _GameDropdownContent extends StatefulWidget {
  final double dropdownWidth;
  final double availableHeight;
  final Animation<double> animation;
  final List<GamesTourModel> games;
  final int currentGameIndex;
  final bool isLoading;
  final ValueChanged<int> onSelect;

  const _GameDropdownContent({
    required this.dropdownWidth,
    required this.availableHeight,
    required this.animation,
    required this.games,
    required this.currentGameIndex,
    required this.isLoading,
    required this.onSelect,
  });

  @override
  State<_GameDropdownContent> createState() => _GameDropdownContentState();
}

class _GameDropdownContentState extends State<_GameDropdownContent> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _listKey = GlobalKey();
  final List<GlobalKey> _itemKeys = [];

  bool _isDragging = false;
  int _currentIndex = 0;
  double _targetY = 0.0;

  // Item metrics (measured after layout)
  double _itemHeight = 36.0;
  double _itemStride = 38.0; // height + spacing between rows
  double _itemBaseTop = 6.0; // accounts for list padding/margins
  double get _totalItemHeight => _itemStride;
  static const double _indicatorInset = 2.0;

  // Track if pointer started on the selector
  bool _pointerStartedOnSelector = false;
  Offset? _lastPointerPosition;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.currentGameIndex;
    _targetY = _itemBaseTop + _currentIndex * _totalItemHeight;

    // Scroll to center the current game after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureMetrics();
      _scrollToCenter();
    });
  }

  @override
  void didUpdateWidget(covariant _GameDropdownContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.games.isEmpty) return;
    if (oldWidget.currentGameIndex != widget.currentGameIndex ||
        oldWidget.games.length != widget.games.length) {
      _currentIndex = widget.currentGameIndex.clamp(0, widget.games.length - 1);
      _targetY = _itemBaseTop + _currentIndex * _totalItemHeight;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _measureMetrics();
        _scrollToCenter();
      });
    }
  }

  /// Scrolls the list to center the current game in the visible area
  void _scrollToCenter() {
    if (!_scrollController.hasClients) return;

    final viewportHeight = _scrollController.position.viewportDimension;
    final maxScroll = _scrollController.position.maxScrollExtent;

    // Calculate the scroll offset to center the current item
    // Item's center position minus half the viewport height
    final itemCenter = _targetY + (_itemHeight / 2);
    final targetScroll = itemCenter - (viewportHeight / 2);

    // Clamp to valid scroll range
    final clampedScroll = targetScroll.clamp(0.0, maxScroll);

    _scrollController.jumpTo(clampedScroll);
  }

  void _measureMetrics() {
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null) return;

    double? itemHeight;
    double? firstTop;
    double? secondTop;

    if (_itemKeys.isNotEmpty) {
      final firstCtx = _itemKeys[0].currentContext;
      final firstBox = firstCtx?.findRenderObject() as RenderBox?;
      if (firstBox != null && firstBox.hasSize) {
        itemHeight = firstBox.size.height;
        firstTop =
            listBox.globalToLocal(firstBox.localToGlobal(Offset.zero)).dy;
      }
    }

    if (_itemKeys.length > 1) {
      final secondCtx = _itemKeys[1].currentContext;
      final secondBox = secondCtx?.findRenderObject() as RenderBox?;
      if (secondBox != null && secondBox.hasSize && firstTop != null) {
        secondTop =
            listBox.globalToLocal(secondBox.localToGlobal(Offset.zero)).dy;
      }
    }

    final resolvedHeight = itemHeight ?? _itemHeight;
    final resolvedBaseTop = firstTop ?? _itemBaseTop;
    final fallbackStride = resolvedHeight + 2.h; // margin/padding allowance

    double resolvedStride = _itemStride;
    if (secondTop != null && firstTop != null) {
      final stride = secondTop - firstTop;
      resolvedStride = stride > 0 ? stride : fallbackStride;
    } else {
      resolvedStride = fallbackStride;
    }

    if (!mounted) return;

    setState(() {
      _itemHeight = resolvedHeight;
      _itemBaseTop = resolvedBaseTop;
      _itemStride = resolvedStride;
      _targetY = _itemBaseTop + _currentIndex * _itemStride;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCenter());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Check if a global position is within the current selector bounds
  bool _isOnSelector(Offset globalPosition) {
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null) return false;

    final localPos = listBox.globalToLocal(globalPosition);
    final scrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;

    // Calculate selector's current visual position (accounting for scroll and padding)
    final indicatorInset = _indicatorInset.h;
    final selectorHeight = (_itemHeight - indicatorInset * 2).clamp(
      0.0,
      _itemHeight,
    );
    final selectorVisualTop = _targetY - scrollOffset + indicatorInset;
    final selectorVisualBottom = selectorVisualTop + selectorHeight;

    // Add some tolerance for easier grabbing
    const tolerance = 8.0;
    return localPos.dy >= (selectorVisualTop - tolerance) &&
        localPos.dy <= (selectorVisualBottom + tolerance);
  }

  void _handlePointerDown(PointerDownEvent event) {
    _lastPointerPosition = event.position;
    _pointerStartedOnSelector = _isOnSelector(event.position);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_lastPointerPosition == null) return;

    _lastPointerPosition = event.position;

    // Only start dragging if pointer started on the selector
    if (!_isDragging && _pointerStartedOnSelector) {
      HapticFeedback.heavyImpact();
      setState(() => _isDragging = true);
    }

    if (_isDragging) {
      // Update selector position based on current pointer position
      _updateIndexFromPosition(event.position);

      // Auto-scroll when near edges
      _handleEdgeScroll(event.position);
    }
  }

  void _handleEdgeScroll(Offset globalPosition) {
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null || !_scrollController.hasClients) return;

    final localPos = listBox.globalToLocal(globalPosition);
    final listHeight = listBox.size.height;
    final maxScroll = _scrollController.position.maxScrollExtent;

    const edgeThreshold = 60.0;
    const scrollSpeed = 8.0;

    if (localPos.dy < edgeThreshold && _scrollController.offset > 0) {
      // Near top edge - scroll up
      final intensity = 1.0 - (localPos.dy / edgeThreshold);
      final scrollAmount = scrollSpeed * intensity;
      final newScroll = (_scrollController.offset - scrollAmount).clamp(
        0.0,
        maxScroll,
      );
      _scrollController.jumpTo(newScroll);
      // Update index after scroll
      _updateIndexFromPosition(globalPosition);
    } else if (localPos.dy > listHeight - edgeThreshold &&
        _scrollController.offset < maxScroll) {
      // Near bottom edge - scroll down
      final intensity = 1.0 - ((listHeight - localPos.dy) / edgeThreshold);
      final scrollAmount = scrollSpeed * intensity;
      final newScroll = (_scrollController.offset + scrollAmount).clamp(
        0.0,
        maxScroll,
      );
      _scrollController.jumpTo(newScroll);
      // Update index after scroll
      _updateIndexFromPosition(globalPosition);
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_isDragging &&
        _currentIndex >= 0 &&
        _currentIndex < widget.games.length) {
      HapticFeedback.mediumImpact();
      widget.onSelect(_currentIndex);
    }
    setState(() => _isDragging = false);
    _lastPointerPosition = null;
    _pointerStartedOnSelector = false;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    setState(() => _isDragging = false);
    _lastPointerPosition = null;
    _pointerStartedOnSelector = false;
  }

  void _updateIndexFromPosition(Offset globalPosition) {
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null) return;

    final localPos = listBox.globalToLocal(globalPosition);
    final scrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    final stride =
        _totalItemHeight <= 0 ? (_itemHeight + 2.h) : _totalItemHeight;
    final adjustedY = localPos.dy + scrollOffset - _itemBaseTop;
    final newIndex = (adjustedY / stride).floor().clamp(
      0,
      widget.games.length - 1,
    );

    if (newIndex != _currentIndex) {
      HapticFeedback.selectionClick();
      _animateToIndex(newIndex);
    }
  }

  void _animateToIndex(int index) {
    setState(() {
      _currentIndex = index;
      _targetY = _itemBaseTop + index * _totalItemHeight;
    });
  }

  /// Format round slug/id into a readable label
  String _formatRoundLabel(String slug) {
    return slug
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (word) =>
              word.isEmpty
                  ? ''
                  : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: widget.dropdownWidth,
      constraints: BoxConstraints(
        maxHeight: widget.availableHeight.clamp(180.h, 380.h),
      ),
      child: Listener(
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        child: Stack(
          children: [
            // List of games - physics disabled only when dragging selector
            ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: ListView.builder(
                key: _listKey,
                controller: _scrollController,
                physics:
                    _isDragging ? const NeverScrollableScrollPhysics() : null,
                padding: EdgeInsets.symmetric(vertical: 6.h),
                itemCount: widget.games.length,
                itemBuilder: (context, index) {
                  final game = widget.games[index];
                  final isSelected = index == _currentIndex;

                  while (_itemKeys.length <= index) {
                    _itemKeys.add(GlobalKey());
                  }

                  // Determine if we should show round separator
                  final currentRound = game.roundSlug ?? game.roundId;
                  final previousRound =
                      index > 0
                          ? (widget.games[index - 1].roundSlug ??
                              widget.games[index - 1].roundId)
                          : null;
                  final showRoundSeparator =
                      previousRound != null && currentRound != previousRound;
                  final roundLabel =
                      showRoundSeparator
                          ? _formatRoundLabel(currentRound)
                          : null;

                  return KeyedSubtree(
                    key: _itemKeys[index],
                    child: _GameItemSimple(
                      index: index,
                      animation: widget.animation,
                      game: game,
                      isSelected: isSelected,
                      isDragging: _isDragging,
                      showRoundSeparator: showRoundSeparator,
                      roundLabel: roundLabel,
                      onTap: () {
                        _animateToIndex(index);
                        widget.onSelect(index);
                      },
                    ),
                  );
                },
              ),
            ),
            // Floating water droplet selector - clipped to stay within bounds
            Positioned.fill(
              child: ClipRect(
                child: IgnorePointer(
                  child: ListenableBuilder(
                    listenable: _scrollController,
                    builder: (context, _) {
                      final scrollOffset =
                          _scrollController.hasClients
                              ? _scrollController.offset
                              : 0.0;
                      final indicatorInset = _indicatorInset.h;
                      final indicatorHeight = (_itemHeight - indicatorInset * 2)
                          .clamp(0.0, _itemHeight);

                      return SingleMotionBuilder(
                        motion:
                            _isDragging
                                ? CupertinoMotion.snappy()
                                : CupertinoMotion.bouncy(),
                        value: _targetY - scrollOffset + indicatorInset,
                        builder: (context, animatedY, _) {
                          return CustomPaint(
                            painter: _GameSelectorPainter(
                              y: animatedY,
                              height: indicatorHeight,
                              isDragging: _isDragging,
                              baseColor: kPrimaryColor,
                              horizontalMargin: 6.w,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple game item - tap handled here, drag handled at list level
class _GameItemSimple extends StatelessWidget {
  final int index;
  final Animation<double> animation;
  final GamesTourModel game;
  final bool isSelected;
  final bool isDragging;
  final VoidCallback onTap;
  final bool showRoundSeparator;
  final String? roundLabel;

  const _GameItemSimple({
    required this.index,
    required this.animation,
    required this.game,
    required this.isSelected,
    required this.isDragging,
    required this.onTap,
    this.showRoundSeparator = false,
    this.roundLabel,
  });

  String _extractLastName(String fullName) {
    final name = fullName.trim();
    if (name.isEmpty) return fullName;
    if (name.contains(',')) {
      final lastName = name.split(',').first.trim();
      if (lastName.isNotEmpty) return lastName;
    }
    const suffixes = {
      'jr',
      'jr.',
      'sr',
      'sr.',
      'ii',
      'iii',
      'iv',
      'v',
      '2nd',
      '3rd',
      '4th',
      '5th',
    };
    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return fullName;
    if (parts.length == 1) return parts.first;
    for (int i = parts.length - 1; i >= 0; i--) {
      if (!suffixes.contains(parts[i].toLowerCase())) return parts[i];
    }
    return parts.last;
  }

  String _getResultText() {
    switch (game.gameStatus) {
      case GameStatus.whiteWins:
        return '1–0';
      case GameStatus.blackWins:
        return '0–1';
      case GameStatus.draw:
        return '½–½';
      case GameStatus.ongoing:
        return '';
      case GameStatus.unknown:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemDelay = index * 0.05;
    final itemAnimation = CurvedAnimation(
      parent: animation,
      curve: Interval(
        itemDelay.clamp(0.0, 0.4),
        (itemDelay + 0.5).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    final isLive = game.gameStatus == GameStatus.ongoing;
    final resultText = _getResultText();
    final whiteName = _extractLastName(game.whitePlayer.displayName);
    final blackName = _extractLastName(game.blackPlayer.displayName);

    return AnimatedBuilder(
      animation: itemAnimation,
      builder: (context, child) {
        final clampedValue = itemAnimation.value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, 10 * (1 - clampedValue)),
          child: Opacity(opacity: clampedValue, child: child),
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Round separator - subtle divider between different rounds
            if (showRoundSeparator && roundLabel != null)
              Container(
                padding: EdgeInsets.only(
                  left: 14.w,
                  right: 14.w,
                  top: index == 0 ? 2.h : 6.h,
                  bottom: 4.h,
                ),
                child: Row(
                  children: [
                    Text(
                      roundLabel!,
                      style: AppTypography.textXxsMedium.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.35),
                        letterSpacing: 0.5,
                        fontSize: 9.sp,
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Container(
                        height: 0.5,
                        color: kWhiteColor.withValues(alpha: 0.06),
                      ),
                    ),
                  ],
                ),
              ),
            // Game row
            Container(
              height: 36.0,
              margin: EdgeInsets.symmetric(horizontal: 6.w, vertical: 1.h),
              padding: EdgeInsets.symmetric(horizontal: 10.w),
              child: Row(
                children: [
                  // Live indicator
                  SizedBox(
                    width: 14.w,
                    child:
                        isLive
                            ? Container(
                              width: 6.w,
                              height: 6.h,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: kPrimaryColor,
                              ),
                            )
                            : null,
                  ),
                  // White player
                  Expanded(
                    child: Text(
                      whiteName,
                      style: AppTypography.textXsMedium.copyWith(
                        color:
                            isSelected
                                ? kPrimaryColor
                                : kWhiteColor.withValues(alpha: 0.9),
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Result
                  Container(
                    width: 36.w,
                    alignment: Alignment.center,
                    child:
                        resultText.isNotEmpty
                            ? Text(
                              resultText,
                              style: AppTypography.textXxsMedium.copyWith(
                                color: kWhiteColor.withValues(alpha: 0.5),
                                fontWeight: FontWeight.w500,
                              ),
                            )
                            : Text(
                              'vs',
                              style: AppTypography.textXxsRegular.copyWith(
                                color: kWhiteColor.withValues(alpha: 0.35),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                  ),
                  // Black player
                  Expanded(
                    child: Text(
                      blackName,
                      style: AppTypography.textXsMedium.copyWith(
                        color:
                            isSelected
                                ? kPrimaryColor
                                : kWhiteColor.withValues(alpha: 0.9),
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                      ),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
}

/// Painter for the floating game selector
class _GameSelectorPainter extends CustomPainter {
  final double y;
  final double height;
  final bool isDragging;
  final Color baseColor;
  final double horizontalMargin;

  _GameSelectorPainter({
    required this.y,
    required this.height,
    required this.isDragging,
    required this.baseColor,
    required this.horizontalMargin,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        horizontalMargin,
        y,
        size.width - horizontalMargin * 2,
        height,
      ),
      const Radius.circular(8),
    );

    // Fill
    final fillPaint =
        Paint()
          ..color = baseColor.withValues(alpha: isDragging ? 0.15 : 0.1)
          ..style = PaintingStyle.fill;
    canvas.drawRRect(rect, fillPaint);

    // Border
    final borderPaint =
        Paint()
          ..color = baseColor.withValues(alpha: isDragging ? 0.4 : 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;
    canvas.drawRRect(rect, borderPaint);
  }

  @override
  bool shouldRepaint(_GameSelectorPainter oldDelegate) {
    return y != oldDelegate.y ||
        height != oldDelegate.height ||
        isDragging != oldDelegate.isDragging;
  }
}

/// Subtle round separator - appears between game groups
class _RoundSeparator extends StatelessWidget {
  final String roundSlug;
  final bool isFirst;
  final int animationIndex;
  final Animation<double> animation;

  const _RoundSeparator({
    required this.roundSlug,
    required this.isFirst,
    required this.animationIndex,
    required this.animation,
  });

  String _formatRoundName(String slug) {
    // Convert slug like "round-1" to "Round 1" or "finals" to "Finals"
    return slug
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .split(' ')
        .map(
          (word) =>
              word.isEmpty
                  ? ''
                  : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final itemDelay = animationIndex * 0.05;
    final itemAnimation = CurvedAnimation(
      parent: animation,
      curve: Interval(
        itemDelay.clamp(0.0, 0.4),
        (itemDelay + 0.5).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    return AnimatedBuilder(
      animation: itemAnimation,
      builder: (context, child) {
        final clampedValue = itemAnimation.value.clamp(0.0, 1.0);
        return Opacity(opacity: clampedValue, child: child);
      },
      child: Container(
        padding: EdgeInsets.only(
          left: 14.w,
          right: 14.w,
          top: isFirst ? 4.h : 12.h,
          bottom: 6.h,
        ),
        child: Row(
          children: [
            Text(
              _formatRoundName(roundSlug),
              style: AppTypography.textXxsMedium.copyWith(
                color: kWhiteColor.withValues(alpha: 0.4),
                letterSpacing: 0.8,
                fontSize: 9.sp,
              ),
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: Container(
                height: 0.5,
                color: kWhiteColor.withValues(alpha: 0.06),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Staggered animated game item wrapper
class _AnimatedGameItem extends StatelessWidget {
  final int index;
  final Animation<double> animation;
  final GamesTourModel game;
  final int gameIndex;
  final bool isSelected;
  final bool isLoading;
  final VoidCallback onTap;

  const _AnimatedGameItem({
    required this.index,
    required this.animation,
    required this.game,
    required this.gameIndex,
    required this.isSelected,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final itemDelay = index * 0.06;
    final itemAnimation = CurvedAnimation(
      parent: animation,
      curve: Interval(
        itemDelay.clamp(0.0, 0.4),
        (itemDelay + 0.6).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );

    return AnimatedBuilder(
      animation: itemAnimation,
      builder: (context, child) {
        final clampedValue = itemAnimation.value.clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, 12 * (1 - clampedValue)),
          child: Opacity(opacity: clampedValue, child: child),
        );
      },
      child: _GameItem(
        game: game,
        gameIndex: gameIndex,
        isSelected: isSelected,
        isLoading: isLoading,
        onTap: onTap,
      ),
    );
  }
}

/// Compact minimal game item
class _GameItem extends StatefulWidget {
  final GamesTourModel game;
  final int gameIndex;
  final bool isSelected;
  final bool isLoading;
  final VoidCallback onTap;

  const _GameItem({
    required this.game,
    required this.gameIndex,
    required this.isSelected,
    required this.isLoading,
    required this.onTap,
  });

  @override
  State<_GameItem> createState() => _GameItemState();
}

class _GameItemState extends State<_GameItem> {
  bool _isPressed = false;

  String _extractLastName(String fullName) {
    final name = fullName.trim();
    if (name.isEmpty) return fullName;

    // Handle "LastName, FirstName" format (common in chess)
    if (name.contains(',')) {
      final lastName = name.split(',').first.trim();
      if (lastName.isNotEmpty) return lastName;
    }

    // Suffixes to ignore when finding last name
    const suffixes = {
      'jr',
      'jr.',
      'sr',
      'sr.',
      'ii',
      'iii',
      'iv',
      'v',
      '2nd',
      '3rd',
      '4th',
      '5th',
    };

    final parts = name.split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return fullName;
    if (parts.length == 1) return parts.first;

    // Find the last part that isn't a suffix
    for (int i = parts.length - 1; i >= 0; i--) {
      if (!suffixes.contains(parts[i].toLowerCase())) {
        return parts[i];
      }
    }

    return parts.last;
  }

  String _getResultText() {
    switch (widget.game.gameStatus) {
      case GameStatus.whiteWins:
        return '1–0';
      case GameStatus.blackWins:
        return '0–1';
      case GameStatus.draw:
        return '½–½';
      case GameStatus.ongoing:
        return '';
      case GameStatus.unknown:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLive = widget.game.gameStatus == GameStatus.ongoing;
    final resultText = _getResultText();
    final whiteName = _extractLastName(widget.game.whitePlayer.displayName);
    final blackName = _extractLastName(widget.game.blackPlayer.displayName);

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        margin: EdgeInsets.symmetric(horizontal: 6.w, vertical: 1.h),
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8.br),
          color:
              widget.isSelected
                  ? kPrimaryColor.withValues(alpha: 0.1)
                  : _isPressed
                  ? kWhiteColor.withValues(alpha: 0.03)
                  : Colors.transparent,
        ),
        child: Row(
          children: [
            // Live indicator - fixed width
            SizedBox(
              width: 14.w,
              child:
                  isLive
                      ? Container(
                        width: 6.w,
                        height: 6.h,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: kPrimaryColor,
                          boxShadow: [
                            BoxShadow(
                              color: kPrimaryColor.withValues(alpha: 0.4),
                              blurRadius: 4,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      )
                      : null,
            ),
            // White player
            Expanded(
              child: Text(
                whiteName,
                style: AppTypography.textXsMedium.copyWith(
                  color:
                      widget.isSelected
                          ? kPrimaryColor
                          : kWhiteColor.withValues(alpha: 0.9),
                  fontWeight:
                      widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Center: vs or result
            Container(
              width: 36.w,
              alignment: Alignment.center,
              child:
                  resultText.isNotEmpty
                      ? Text(
                        resultText,
                        style: AppTypography.textXxsMedium.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.5),
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                        ),
                      )
                      : Text(
                        'vs',
                        style: AppTypography.textXxsRegular.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.35),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
            ),
            // Black player
            Expanded(
              child: Text(
                blackName,
                style: AppTypography.textXsMedium.copyWith(
                  color:
                      widget.isSelected
                          ? kPrimaryColor
                          : kWhiteColor.withValues(alpha: 0.9),
                  fontWeight:
                      widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Selection indicator
            SizedBox(
              width: 20.w,
              child:
                  widget.isLoading
                      ? SizedBox(
                        width: 12.sp,
                        height: 12.sp,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: kPrimaryColor,
                        ),
                      )
                      : widget.isSelected
                      ? Icon(
                        Icons.check_rounded,
                        color: kPrimaryColor,
                        size: 14.ic,
                      )
                      : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNavBar extends ConsumerWidget {
  final int index;
  final ChessBoardStateNew state;
  final GamesTourModel game;
  final VoidCallback onGamebaseToggle;
  final bool showGamebaseButton;

  const _BottomNavBar({
    required this.index,
    required this.state,
    required this.game,
    required this.onGamebaseToggle,
    this.showGamebaseButton = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the provider directly to ensure rebuilds when gamebase toggle changes
    final gamebaseEnabled =
        ref.watch(gamebaseOverlayEnabledProvider).valueOrNull ?? true;
    final isGamebaseActive = showGamebaseButton ? gamebaseEnabled : false;

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
    final previewMoveCount = state.lockedPvLine?.moves.length ?? 0;
    final previewIndex = state.lockedPvNavigationIndex ?? -1;
    final isPreviewActive = state.isPvPreviewActive && previewMoveCount > 0;
    final previewCanMoveForward =
        isPreviewActive ? previewIndex < previewMoveCount - 1 : false;
    final previewCanMoveBackward = isPreviewActive ? previewIndex > 0 : false;
    final effectiveCanMoveForward =
        isPreviewActive ? previewCanMoveForward : canMoveForward;
    final effectiveCanMoveBackward =
        isPreviewActive ? previewCanMoveBackward : canMoveBackward;

    return ChessBoardBottomNavBar(
      key: ValueKey('bottom_nav_gamebase_$isGamebaseActive'),
      gameIndex: index,
      showGamebaseButton: showGamebaseButton,
      onFlip: () => notifier.flipBoard(),
      toggleEngineVisibility: () => notifier.toggleEngineVisibility(),
      onEngineSettingsLongPress: () {
        requireFullAuthGuard(context).then((allowed) {
          if (!allowed) return;
          if (!context.mounted) return;
          Navigator.of(context).push(ChessBoardSettingsPage.route());
        });
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
      onGamebaseToggle: onGamebaseToggle,
      isGamebaseActive: isGamebaseActive,
    );
  }
}

class _GameBody extends StatelessWidget {
  final int index;
  final int currentPageIndex;
  final GamesTourModel game;
  final ChessBoardStateNew state;
  final bool showGamebaseButton;
  final bool showClock;

  const _GameBody({
    required this.index,
    required this.currentPageIndex,
    required this.game,
    required this.state,
    this.showGamebaseButton = false,
    this.showClock = true,
  });

  @override
  Widget build(BuildContext context) {
    // Analysis mode is always active, use analysis game body
    return _AnalysisGameBody(
      index: index,
      currentPageIndex: currentPageIndex,
      game: game,
      state: state,
      showGamebaseButton: showGamebaseButton,
      showClock: showClock,
    );
  }
}

class _AnalysisGameBody extends ConsumerWidget {
  final int index;
  final int currentPageIndex;
  final GamesTourModel game;
  final ChessBoardStateNew state;
  final bool showGamebaseButton;
  final bool showClock;

  const _AnalysisGameBody({
    required this.index,
    required this.currentPageIndex,
    required this.game,
    required this.state,
    this.showGamebaseButton = false,
    this.showClock = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the provider directly to ensure rebuilds when gamebase toggle changes
    final gamebaseEnabled =
        ref.watch(gamebaseOverlayEnabledProvider).valueOrNull ?? true;
    final isGamebaseActive = showGamebaseButton ? gamebaseEnabled : false;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isVisiblePage = index == currentPageIndex;
        final isGamebaseActiveForPage = isGamebaseActive && isVisiblePage;
        final availableHeight =
            constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : MediaQuery.sizeOf(context).height;
        final compactThreshold = 620.h;
        final useCompactLayout = availableHeight < compactThreshold;

        final pvSection = <Widget>[];
        // Hide standard PV section if Gamebase is active (it has its own)
        if (!isGamebaseActiveForPage &&
            state.isAnalysisMode &&
            state.showEngineAnalysis &&
            state.showPrincipalVariations) {
          pvSection.add(SizedBox(height: 2.h));
          final pvList = _PrincipalVariationList(
            index: index,
            state: state,
            game: game,
          );
          if (useCompactLayout) {
            pvSection.add(pvList);
          } else {
            pvSection.add(Flexible(flex: 0, child: pvList));
          }
        }

        final headerChildren = <Widget>[
          _PlayerWidget(
            game: game,
            isFlipped: state.isBoardFlipped,
            blackPlayer: false,
            state: state,
            showClock: showClock,
          ),
          SizedBox(height: 1.h),
          _BoardWithSidebar(
            index: index,
            currentPageIndex: currentPageIndex,
            state: state,
            game: game,
          ),
          SizedBox(height: 1.h),
          _PlayerWidget(
            game: game,
            isFlipped: state.isBoardFlipped,
            blackPlayer: true,
            state: state,
            showClock: showClock,
          ),
          ...pvSection,
        ];

        Widget buildAnalysisView() {
          final movesDisplay = _MovesDisplay(
            index: index,
            currentPageIndex: currentPageIndex,
            state: state,
            game: game,
          );

          // Avoid mounting the (global) Gamebase provider for offscreen pages.
          // This prevents multiple PageView children from racing to set the
          // Gamebase FEN, which breaks lookups for real game positions.
          if (!isVisiblePage) {
            return movesDisplay;
          }

          final gamebaseDisplay = GamebaseExplorerView(
            state: state,
            onMoveSelected: (uci) {
              final params = ChessBoardProviderParams(
                game: game,
                index: index,
              );
              final notifier = ref.read(
                chessBoardScreenProviderNew(params).notifier,
              );
              try {
                if (uci.length < 4) return;
                final from = Square.fromName(uci.substring(0, 2));
                final to = Square.fromName(uci.substring(2, 4));
                Role? promotion;
                if (uci.length > 4) {
                  promotion = Role.fromChar(uci[4]);
                }
                final move = NormalMove(
                  from: from,
                  to: to,
                  promotion: promotion,
                );
                notifier.onAnalysisMove(move);
              } catch (e) {
                debugPrint('Error making move from UCI: $e');
              }
            },
            onGameSelected: (gameId) {
              unawaited(() async {
                try {
                  final preview = await ref.read(
                    gamePreviewByIdProvider(gameId).future,
                  );
                  if (preview == null) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Game not found in Gamebase.'),
                      ),
                    );
                    return;
                  }

                  final repo = ref.read(gamebaseRepositoryProvider);

                  final whitePlayerId =
                      preview['whitePlayerId']?.toString().trim();
                  final blackPlayerId =
                      preview['blackPlayerId']?.toString().trim();

                  final players = await Future.wait([
                    if (whitePlayerId != null && whitePlayerId.isNotEmpty)
                      repo.getPlayerById(whitePlayerId)
                    else
                      Future<GamebasePlayer?>.value(null),
                    if (blackPlayerId != null && blackPlayerId.isNotEmpty)
                      repo.getPlayerById(blackPlayerId)
                    else
                      Future<GamebasePlayer?>.value(null),
                  ]);

                  final whitePlayer = players[0];
                  final blackPlayer = players[1];

                  int ratingFor(GamebasePlayer? p, String? timeControl) {
                    if (p == null) return 0;
                    final tc = (timeControl ?? '').toUpperCase();
                    switch (tc) {
                      case 'RAPID':
                        return p.ratingRapid ?? p.highestRating ?? 0;
                      case 'BLITZ':
                        return p.ratingBlitz ?? p.highestRating ?? 0;
                      case 'CLASSICAL':
                      default:
                        return p.ratingClassical ?? p.highestRating ?? 0;
                    }
                  }

                  DateTime? parseDate(Object? raw) {
                    if (raw == null) return null;
                    return DateTime.tryParse(raw.toString());
                  }

                  String coalesce(
                    Map<String, dynamic> row,
                    String primary,
                    String fallback,
                    String defaultValue,
                  ) {
                    final a = (row[primary]?.toString() ?? '').trim();
                    if (a.isNotEmpty) return a;
                    final b = (row[fallback]?.toString() ?? '').trim();
                    return b.isNotEmpty ? b : defaultValue;
                  }

                  final timeControl = preview['timeControl']?.toString();
                  final date = parseDate(preview['date']);
                  final result = (preview['result']?.toString() ?? '*').trim();

                  final whiteName = coalesce(
                    preview,
                    'white',
                    'whiteName',
                    'White',
                  );
                  final blackName = coalesce(
                    preview,
                    'black',
                    'blackName',
                    'Black',
                  );

                  final event = (preview['event']?.toString() ?? 'Gamebase').trim();
                  final site = preview['site']?.toString();
                  final eco = (preview['eco']?.toString() ?? '').trim();
                  final opening = (preview['opening']?.toString() ?? '').trim();
                  final variation =
                      (preview['variation']?.toString() ?? '').trim();

                  final pgn = buildHeaderOnlyPgn(
                    whiteName: whiteName,
                    blackName: blackName,
                    result: result,
                    event: event.isNotEmpty ? event : 'Gamebase',
                    site: site,
                    date: date,
                    eco: eco,
                    opening: opening,
                    variation: variation,
                  );

                  final resolvedId =
                      (preview['id']?.toString() ?? gameId).trim();

                  final whiteTitle = ChessTitleUtils.normalize(
                    preview['whiteTitle']?.toString() ?? whitePlayer?.title,
                  );
                  final blackTitle = ChessTitleUtils.normalize(
                    preview['blackTitle']?.toString() ?? blackPlayer?.title,
                  );

                  final resolvedGame = GamesTourModel(
                    gameId: resolvedId.isNotEmpty ? resolvedId : gameId,
                    whitePlayer: PlayerCard(
                      name: whiteName,
                      federation: '',
                      title: whiteTitle,
                      rating: ratingFor(whitePlayer, timeControl),
                      countryCode: whitePlayer?.fed ?? '',
                      team: null,
                      fideId: int.tryParse(whitePlayer?.fideId ?? ''),
                    ),
                    blackPlayer: PlayerCard(
                      name: blackName,
                      federation: '',
                      title: blackTitle,
                      rating: ratingFor(blackPlayer, timeControl),
                      countryCode: blackPlayer?.fed ?? '',
                      team: null,
                      fideId: int.tryParse(blackPlayer?.fideId ?? ''),
                    ),
                    whiteTimeDisplay: '--:--',
                    blackTimeDisplay: '--:--',
                    whiteClockCentiseconds: 0,
                    blackClockCentiseconds: 0,
                    gameStatus: GameStatus.fromString(result),
                    roundId: 'gamebase_overlay',
                    roundSlug: eco.isNotEmpty ? eco : timeControl,
                    tourId: event.isNotEmpty ? event : 'Gamebase',
                    pgn: pgn,
                    lastMoveTime: date,
                  );

                  // Best-effort: fetch the full game payload (moves + PGN headers)
                  // and show it if available; fall back to preview-only if the
                  // backend errors or returns an incomplete record.
                  final full =
                      await repo
                          .getGameById(gameId)
                          .timeout(
                            const Duration(seconds: 2),
                            onTimeout: () => null,
                          );

                  GamesTourModel resolvedForOpen = resolvedGame;
                  if (full != null) {
                    final mapped = mapGamebaseGameToGamesTourModel(full);
                    final merged = mapped.copyWith(
                      whitePlayer: mapped.whitePlayer.copyWith(
                        title:
                            whiteTitle.isNotEmpty
                                ? whiteTitle
                                : mapped.whitePlayer.title,
                        rating:
                            whitePlayer != null
                                ? ratingFor(whitePlayer, timeControl)
                                : mapped.whitePlayer.rating,
                        countryCode:
                            whitePlayer?.fed.isNotEmpty == true
                                ? whitePlayer!.fed
                                : mapped.whitePlayer.countryCode,
                      ),
                      blackPlayer: mapped.blackPlayer.copyWith(
                        title:
                            blackTitle.isNotEmpty
                                ? blackTitle
                                : mapped.blackPlayer.title,
                        rating:
                            blackPlayer != null
                                ? ratingFor(blackPlayer, timeControl)
                                : mapped.blackPlayer.rating,
                        countryCode:
                            blackPlayer?.fed.isNotEmpty == true
                                ? blackPlayer!.fed
                                : mapped.blackPlayer.countryCode,
                      ),
                    );
                    resolvedForOpen = merged;
                  }

                  if (!context.mounted) return;
                  ref.read(chessboardViewFromProviderNew.notifier).state =
                      ChessboardView.tour;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder:
                          (_) => ChessBoardScreenNew(
                            games: [resolvedForOpen],
                            currentIndex: 0,
                            hideEventInfo: true,
                            showGamebaseButton: true,
                            disableGamebaseOverlayByDefault: true,
                            showClock: false,
                          ),
                    ),
                  );
                } catch (e) {
                  debugPrint('[Gamebase] Failed to open game: $e');
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not open game: $e')),
                  );
                }
              }());
            },
          );

          // Animate switching between move list and Gamebase explorer.
          // Only build Gamebase while visible/animating to avoid background fetches.
          return SingleMotionBuilder(
            motion: const CupertinoMotion.smooth(),
            value: isGamebaseActiveForPage ? 1.0 : 0.0,
            builder: (context, t, _) {
              final showGamebase = isGamebaseActiveForPage || t > 0.01;
              final showMoves = !isGamebaseActiveForPage || t < 0.99;

              return Stack(
                children: [
                  if (showMoves)
                    IgnorePointer(
                      ignoring: t > 0.05,
                      child: Opacity(
                        opacity: (1.0 - t).clamp(0.0, 1.0),
                        child: movesDisplay,
                      ),
                    ),
                  if (showGamebase)
                    IgnorePointer(
                      ignoring: t < 0.95,
                      child: Opacity(
                        opacity: t.clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(0, (1.0 - t) * 8.h),
                          child: gamebaseDisplay,
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        }

        if (useCompactLayout) {
          final movesPanelHeight = math.max(220.h, availableHeight * 0.55);
          return SingleChildScrollView(
            padding: EdgeInsets.only(bottom: 12.h),
            physics: const ClampingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...headerChildren,
                SizedBox(height: 12.h),
                SizedBox(height: movesPanelHeight, child: buildAnalysisView()),
              ],
            ),
          );
        }

        return Column(
          children: [...headerChildren, Expanded(child: buildAnalysisView())],
        );
      },
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
  final bool showClock;

  const _PlayerWidget({
    required this.game,
    required this.isFlipped,
    required this.blackPlayer,
    required this.state,
    this.showClock = true,
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
      showClock: showClock,
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
        final screenWidth = MediaQuery.sizeOf(context).width;
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
      // Only show shapes (arrows) when ALL conditions are met:
      // 1. Engine analysis is enabled (master toggle)
      // 2. Principal variations are enabled in board state
      // 3. PV arrows are enabled in engine settings
      shapes:
          (chessBoardState.showEngineAnalysis &&
                  chessBoardState.showPrincipalVariations &&
                  showPvArrows)
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
  final Set<String> _expandedCommentIds = <String>{};
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
      // Reset cached variation collapse state when the notation tree changes
      _collapsedVariationIds.clear();
      _expandedVariationIds.clear();
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
      variationComments: widget.state.variationComments,
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
                    case _NotationTokenType.comment:
                      return _buildVariationCommentChip(token, params);
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
        if (pointer == null) return;
        _showMoveActions(
          params,
          pointer,
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
        token.type != _NotationTokenType.ellipsis &&
        (token.variation != null || token.variationColorKey != null);
    Color depthColor;
    if (isVariationToken) {
      depthColor = _accentColorForToken(token);
    } else if (token.depth > 0) {
      depthColor = _colorForVariationDepth(token.depth);
    } else {
      depthColor = kWhiteColor.withValues(alpha: 0.75);
    }

    Widget child;
    if (token.type == _NotationTokenType.variationPlaceholder) {
      // Collapsed variation placeholder - tappable to expand
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          _toggleVariationCollapse(token);
        },
        onLongPress: () {
          _showVariationActions(token);
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 4.sp),
          decoration: BoxDecoration(
            color: depthColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6.sp),
            border: Border.all(
              color: depthColor.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Expand icon
              Icon(
                Icons.unfold_more_rounded,
                size: 12.sp,
                color: depthColor.withValues(alpha: 0.7),
              ),
              SizedBox(width: 4.sp),
              Text(
                token.text,
                style: AppTypography.textXsMedium.copyWith(
                  color: depthColor.withValues(alpha: 0.85),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      );
      // Return early - already has gesture handling
      return child;
    } else if (token.type == _NotationTokenType.openParen &&
        token.variation != null) {
      // Opening paren with +/- toggle button
      final isCollapsed = token.isCollapsed;
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          _toggleVariationCollapse(token);
        },
        onLongPress: () {
          _showVariationActions(token);
        },
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 4.sp, vertical: 2.sp),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Toggle button with clear visual affordance
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                width: 16.sp,
                height: 16.sp,
                margin: EdgeInsets.only(right: 3.sp),
                decoration: BoxDecoration(
                  color:
                      isCollapsed
                          ? depthColor.withValues(alpha: 0.2)
                          : depthColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4.sp),
                  border: Border.all(
                    color: depthColor.withValues(
                      alpha: isCollapsed ? 0.4 : 0.25,
                    ),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: Icon(
                      isCollapsed ? Icons.add_rounded : Icons.remove_rounded,
                      key: ValueKey(isCollapsed),
                      size: 12.sp,
                      color: depthColor.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ),
              Text(
                token.text,
                style: AppTypography.textXsMedium.copyWith(
                  color: depthColor.withValues(alpha: 0.85),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      );
      // Return early - already has gesture handling
      return child;
    } else if (token.type == _NotationTokenType.closeParen &&
        token.variation != null) {
      // Closing paren - tappable to collapse
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          _toggleVariationCollapse(token);
        },
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 2.sp, vertical: 2.sp),
          child: Text(
            token.text,
            style: AppTypography.textXsMedium.copyWith(
              color: depthColor.withValues(alpha: 0.85),
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
      return child;
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

    final decoratedChild = ExcludeSemantics(excluding: true, child: child);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _focusVariationHead(token.variation!);
        _toggleVariationCollapse(token);
      },
      onLongPress: () {
        _showVariationActions(token);
      },
      child: decoratedChild,
    );
  }

  /// Compact inline comment display - italic text with accent color
  Widget _buildVariationCommentChip(
    _NotationDisplayToken token,
    ChessBoardProviderParams params,
  ) {
    final fullText = token.commentText?.trim() ?? token.text.trim();
    if (fullText.isEmpty) {
      return const SizedBox.shrink();
    }

    final id = token.pointerId ?? token.variation?.id;
    if (id == null) return const SizedBox.shrink();

    final isExpanded = _expandedCommentIds.contains(id);
    final isLong = fullText.length > _variationCommentPreviewChars;

    final displayText =
        (isLong && !isExpanded)
            ? '${fullText.substring(0, _variationCommentPreviewChars).trimRight()}…'
            : fullText;

    final depth = token.depth;
    final accentColor = _colorForVariationAccent(
      math.max(1, depth),
      seed: token.variationColorKey ?? token.variation?.id,
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.sp, vertical: 2.sp),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          if (isLong) {
            _toggleCommentExpansion(id, isExpanded);
          } else {
            _editNotationComment(token, params, fullText);
          }
        },
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _editNotationComment(token, params, fullText);
        },
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: displayText,
                style: AppTypography.textSmRegular.copyWith(
                  color: accentColor.withValues(alpha: 0.7),
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
              if (isLong)
                TextSpan(
                  text: isExpanded ? ' ▲' : ' ▼',
                  style: AppTypography.textXsRegular.copyWith(
                    color: accentColor.withValues(alpha: 0.5),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleCommentExpansion(String id, bool isExpanded) {
    setState(() {
      if (isExpanded) {
        _expandedCommentIds.remove(id);
      } else {
        _expandedCommentIds.add(id);
      }
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _editNotationComment(
    _NotationDisplayToken token,
    ChessBoardProviderParams params,
    String fallbackText,
  ) async {
    final pointerId = token.pointerId ?? token.variation?.id;
    if (pointerId == null) {
      return;
    }

    HapticFeedback.selectionClick();

    final notifier = ref.read(chessBoardScreenProviderNew(params).notifier);
    final currentComment =
        widget.state.variationComments[pointerId] ?? fallbackText;
    final hostContext = context;

    final commentConfig = _VariationCommentSheetConfig(
      initialValue: currentComment,
      onSubmit: (ctx, value) async {
        final trimmed = value.trim();
        final normalizedInitial = currentComment.trim();
        if (trimmed == normalizedInitial) {
          return;
        }
        final limited =
            trimmed.length > _variationCommentMaxChars
                ? trimmed.substring(0, _variationCommentMaxChars)
                : trimmed;
        notifier.updateVariationComment(
          variationId: pointerId,
          comment: limited,
        );
      },
    );

    final route = ChessSheetRoutes.commentEditor(
      context: context,
      builder:
          (_) => _DirectCommentSheet(
            config: commentConfig,
            hostContext: hostContext,
          ),
    );

    await Navigator.of(context).push(route);
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
    if (variation == null) {
      HapticFeedback.lightImpact();
      return;
    }

    final variationId = variation.id;
    final defaultCollapsed = token.defaultsToCollapsed;
    final isCurrentlyCollapsed = token.isCollapsed;

    // If we're trying to collapse a forced-open variation (user is inside it),
    // first navigate to the parent move, then collapse
    if (token.isForcedOpen && !isCurrentlyCollapsed) {
      // Navigate to the parent move (the move that has this variation)
      final parentPointer = variation.parentPointer;
      if (parentPointer.isNotEmpty) {
        final params = ChessBoardProviderParams(
          game: widget.game,
          index: widget.index,
        );
        ref
            .read(chessBoardScreenProviderNew(params).notifier)
            .goToMovePointer(parentPointer);
      }
    }

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
    Color(0xFFE9EDCC),
    Color(0xFFD6E3BC),
    Color(0xFFBFD3CB),
    Color(0xFFA6C2DA),
    Color(0xFF8EB2CB),
  ];

  Color _accentColorForToken(_NotationDisplayToken token) {
    final depth = math.max(1, token.depth);
    final seed = token.variationColorKey ?? token.variation?.id;
    return _colorForVariationAccent(depth, seed: seed);
  }

  Color _colorForVariationAccent(int depth, {String? seed}) {
    if (seed == null || seed.isEmpty) {
      return _colorForVariationDepth(depth);
    }
    return _colorFromSeed(seed);
  }

  Color _colorFromSeed(String seed) {
    final normalizedSeed = seed.hashCode & 0x7fffffff;
    final random = math.Random(normalizedSeed);
    final hue = random.nextDouble() * 360.0;
    final saturation = 0.45 + random.nextDouble() * 0.35;
    final lightness = 0.45 + random.nextDouble() * 0.25;
    final hslColor = HSLColor.fromAHSL(1.0, hue, saturation, lightness);
    return hslColor.toColor();
  }

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

    final depthColor = _colorForVariationAccent(
      token.depth,
      seed: token.variationColorKey ?? token.variation?.id,
    );
    return depthColor.withValues(alpha: isPast ? 0.95 : 0.75);
  }

  List<_NotationDisplayToken> _buildTokens(
    List<NotationMoveNode> moves, {
    required int depth,
    NotationVariationNode? variationContext,
    required Map<String, NotationMoveNode> pointerMap,
    required Set<String> forcedOpenIds,
    required Map<String, String> variationComments,
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
          variationColorKey: variationContext?.id,
        ),
      );

      final moveComment = variationComments[pointerId];
      if (moveComment != null && moveComment.isNotEmpty) {
        tokens.add(
          _NotationDisplayToken(
            type: _NotationTokenType.comment,
            text: moveComment,
            depth: depth,
            pointerId: pointerId,
            variation: variationContext,
            variationIndex: variationContext?.variationIndex,
            variationColorKey: variationContext?.id,
          ),
        );
      }

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
            variationColorKey: variation.id,
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
              variationColorKey: variation.id,
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
              variationComments: variationComments,
            ),
          );
        }

        final variationComment = variationComments[variation.id];
        if (variationComment != null && variationComment.isNotEmpty) {
          tokens.add(
            _NotationDisplayToken(
              type: _NotationTokenType.comment,
              text: variationComment,
              depth: variation.depth,
              variationIndex: variation.variationIndex,
              variation: variation,
              variationHeadPointer:
                  variation.moves.isNotEmpty
                      ? List<Number>.of(variation.moves.first.pointer)
                      : null,
              commentText: variationComment,
              variationColorKey: variation.id,
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
            variationColorKey: variation.id,
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

  Duration? _parseClockLabel(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty || cleaned.contains('-')) return null;

    final parts = cleaned.split(':');
    if (parts.length == 2) {
      final minutes = int.tryParse(parts[0]);
      final seconds = int.tryParse(parts[1]);
      if (minutes == null || seconds == null) return null;
      return Duration(minutes: minutes, seconds: seconds);
    }
    if (parts.length == 3) {
      final hours = int.tryParse(parts[0]);
      final minutes = int.tryParse(parts[1]);
      final seconds = int.tryParse(parts[2]);
      if (hours == null || minutes == null || seconds == null) return null;
      return Duration(hours: hours, minutes: minutes, seconds: seconds);
    }
    return null;
  }

  Duration? _parseDurationFromTcToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty || trimmed == '-') return null;
    final parts = trimmed.split(':');
    if (parts.length == 1) {
      final seconds = int.tryParse(parts[0]);
      return seconds != null ? Duration(seconds: seconds) : null;
    }
    if (parts.length == 2) {
      final minutes = int.tryParse(parts[0]);
      final seconds = int.tryParse(parts[1]);
      if (minutes == null || seconds == null) return null;
      return Duration(minutes: minutes, seconds: seconds);
    }
    if (parts.length == 3) {
      final hours = int.tryParse(parts[0]);
      final minutes = int.tryParse(parts[1]);
      final seconds = int.tryParse(parts[2]);
      if (hours == null || minutes == null || seconds == null) return null;
      return Duration(hours: hours, minutes: minutes, seconds: seconds);
    }
    return null;
  }

  _TimeControlSnapshot _parseTimeControlSnapshot() {
    final pgn = widget.state.pgnData ?? widget.game.pgn;
    Duration? base;
    Duration increment = Duration.zero;

    if (pgn != null && pgn.isNotEmpty) {
      final tcMatch = RegExp(
        r'\[TimeControl "([^"]+)"\]',
        multiLine: true,
      ).firstMatch(pgn);
      final raw = tcMatch?.group(1);
      if (raw != null && raw.isNotEmpty && raw != '-') {
        // Only examine the primary phase (before any commas)
        final primaryPhase = raw.split(',').first.trim();

        // Extract increment (after '+') if present
        String baseToken = primaryPhase;
        final plusIndex = primaryPhase.lastIndexOf('+');
        if (plusIndex != -1 && plusIndex < primaryPhase.length - 1) {
          final incToken = primaryPhase.substring(plusIndex + 1);
          increment = _parseDurationFromTcToken(incToken) ?? Duration.zero;
          baseToken = primaryPhase.substring(0, plusIndex);
        }

        // Remove move-count prefix (e.g., "40/7200") to isolate time value
        if (baseToken.contains('/')) {
          final segments = baseToken.split('/');
          baseToken = segments.isNotEmpty ? segments.last : baseToken;
        }

        base = _parseDurationFromTcToken(baseToken);
      }
    }

    return _TimeControlSnapshot(base: base, increment: increment);
  }

  String _formatDurationLabel(Duration duration) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      return '${duration.inHours}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}';
    }
    return '${duration.inMinutes}:${twoDigits(duration.inSeconds.remainder(60))}';
  }

  String? _buildTimeSpentLabel(ChessMovePointer pointer, bool isMainlineMove) {
    if (!isMainlineMove || pointer.isEmpty) return null;

    final moveIndex = pointer.first.toInt();
    if (moveIndex < 0 || moveIndex >= widget.state.moveTimes.length) {
      return null;
    }

    final currentClock = _parseClockLabel(widget.state.moveTimes[moveIndex]);
    if (currentClock == null) return null;

    Duration? previousClock;
    for (int i = moveIndex - 2; i >= 0; i -= 2) {
      previousClock = _parseClockLabel(widget.state.moveTimes[i]);
      if (previousClock != null) break;
    }

    final timeControl = _parseTimeControlSnapshot();
    final startingClock = previousClock ?? timeControl.base;
    if (startingClock == null) return null;

    final spentSeconds =
        startingClock.inSeconds +
        timeControl.increment.inSeconds -
        currentClock.inSeconds;
    final safeSeconds = spentSeconds < 0 ? 0 : spentSeconds;

    return _formatDurationLabel(Duration(seconds: safeSeconds));
  }

  Future<void> _showMoveActions(
    ChessBoardProviderParams params,
    ChessMovePointer pointer,
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
    final pointerId = NotationPointer.encode(pointer);
    final currentComment = widget.state.variationComments[pointerId] ?? '';
    final timeSpentLabel = _buildTimeSpentLabel(pointer, isMainlineMove);

    final commentConfig = _VariationCommentSheetConfig(
      initialValue: currentComment,
      onSubmit: (ctx, value) async {
        if (!mounted) return;
        final trimmed = value.trim();
        final normalizedInitial = currentComment.trim();
        if (trimmed == normalizedInitial) {
          _showInfoSnack(hostContext, 'No changes');
          return;
        }
        final limited =
            trimmed.length > _variationCommentMaxChars
                ? trimmed.substring(0, _variationCommentMaxChars)
                : trimmed;
        notifier.updateVariationComment(
          variationId: pointerId,
          comment: limited,
        );
        if (limited.isEmpty) {
          _showInfoSnack(hostContext, 'Comment removed');
        } else {
          _showInfoSnack(hostContext, 'Comment added');
        }
      },
    );

    final actions = <_NotationActionItem>[
      _NotationActionItem(
        icon: Icons.delete_outline,
        label: 'Delete from here',
        color: kRedColor,
        onSelected: (_) async {
          await notifier.deleteContinuationFromPointer(
            List<Number>.of(pointer),
          );
        },
      ),
      _NotationActionItem(
        icon: Icons.block,
        label: 'Add null move after',
        color: kPrimaryColor,
        onSelected: (_) async {
          await notifier.insertNullMoveAfterPointer(List<Number>.of(pointer));
        },
      ),
      _NotationActionItem(
        icon: Icons.add_comment_outlined,
        label: 'Add comment',
        color: kWhiteColor,
        triggersCommentEditor: true,
        onSelected: (_) async {},
      ),
      if (canModifyVariant)
        _NotationActionItem(
          icon: Icons.delete_forever,
          label: 'Delete variant',
          color: kRedColor,
          onSelected: (_) async {
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
      // if (canModifyVariant)
      //   _NotationActionItem(
      //     icon: Icons.trending_up_rounded,
      //     label: 'Promote variant',
      //     color: kPrimaryColor,
      //     onSelected: (_) async {
      //       await notifier.promoteVariationAtPointer(
      //         List<Number>.of(variantHeadPointer),
      //       );
      //     },
      //   ),
      if (!isMainlineMove)
        _NotationActionItem(
          icon: Icons.upgrade_rounded,
          label: 'Promote main variant',
          color: kPrimaryColor,
          onSelected: (_) async {
            await notifier.promoteBranchToMainVariant(List<Number>.of(pointer));
          },
        ),
    ];

    final hasExpandedOptions = actions.length > 3;
    final initialSheetFraction =
        hasExpandedOptions
            ? _variantActionSheetInitialFraction
            : _mainlineActionSheetInitialFraction;

    await _showNotationActionSheet(
      context: hostContext,
      title: isNullMove ? 'Null move' : moveText,
      subtitle: 'Move options',
      actions: actions,
      commentConfig: commentConfig,
      timeSpentLabel: timeSpentLabel,
      initialSheetFraction: initialSheetFraction,
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
    final commentConfig = _buildVariationCommentConfig(
      variation: variation,
      notifier: notifier,
      hostContext: hostContext,
    );
    final actions = <_NotationActionItem>[
      _NotationActionItem(
        icon: Icons.add_comment_outlined,
        label: 'Add comment',
        color: kWhiteColor,
        onSelected: (_) async {},
        triggersCommentEditor: true,
      ),
      _NotationActionItem(
        icon: Icons.delete_forever,
        label: 'Delete variant',
        color: kRedColor,
        onSelected: (_) async {
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
        onSelected: (_) async {
          await notifier.promoteBranchToMainVariant(
            List<Number>.of(headPointer),
          );
        },
      ),
    ];

    final hasExpandedOptions = actions.length > 3;
    final initialSheetFraction =
        hasExpandedOptions
            ? _variantActionSheetInitialFraction
            : _mainlineActionSheetInitialFraction;

    await _showNotationActionSheet(
      context: hostContext,
      title: 'Variation',
      subtitle: 'Variation options',
      actions: actions,
      commentConfig: commentConfig,
      initialSheetFraction: initialSheetFraction,
    );
  }

  _VariationCommentSheetConfig _buildVariationCommentConfig({
    required NotationVariationNode variation,
    required ChessBoardScreenNotifierNew notifier,
    required BuildContext hostContext,
  }) {
    final initialComment = widget.state.variationComments[variation.id] ?? '';
    return _VariationCommentSheetConfig(
      initialValue: initialComment,
      onSubmit: (ctx, value) async {
        if (!mounted) return;
        final trimmed = value.trim();
        final normalizedInitial = initialComment.trim();
        if (trimmed == normalizedInitial) {
          _showInfoSnack(hostContext, 'No changes');
          return;
        }
        final limited =
            trimmed.length > _variationCommentMaxChars
                ? trimmed.substring(0, _variationCommentMaxChars)
                : trimmed;
        notifier.updateVariationComment(
          variationId: variation.id,
          comment: limited,
        );
        if (limited.isEmpty) {
          _showInfoSnack(hostContext, 'Comment removed');
        } else {
          _showInfoSnack(hostContext, 'Comment added');
        }
      },
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
        backgroundColor: kBlack2Color.withValues(alpha: 0.95),
        elevation: 2,
        margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 20.h),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.sp),
          side: BorderSide(color: kWhiteColor.withValues(alpha: 0.1), width: 1),
        ),
        content: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8.sp),
              decoration: BoxDecoration(
                color: kRedColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8.sp),
              ),
              child: Icon(Icons.delete_outline, color: kRedColor, size: 18.ic),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                message,
                style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
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
                foregroundColor: kPrimaryColor,
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'UNDO',
                style: AppTypography.textSmBold.copyWith(color: kPrimaryColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInfoSnack(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: kBlack2Color.withValues(alpha: 0.95),
        elevation: 0,
        duration: const Duration(seconds: 2),
        margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18.sp),
          side: BorderSide(color: kWhiteColor.withValues(alpha: 0.08)),
        ),
        content: Row(
          children: [
            Container(
              padding: EdgeInsets.all(6.sp),
              decoration: BoxDecoration(
                color: kPrimaryColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10.sp),
              ),
              child: Icon(
                Icons.info_outline,
                size: 16.ic,
                color: kPrimaryColor,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                message,
                style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DirectCommentSheet extends ConsumerWidget {
  final _VariationCommentSheetConfig config;
  final BuildContext hostContext;

  const _DirectCommentSheet({required this.config, required this.hostContext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigator = Navigator(
      onGenerateInitialRoutes:
          (_, __) => [
            SpringPagedSheetRoute(
              scrollConfiguration: const SheetScrollConfiguration(),
              dragConfiguration: ChessSheetConfigs.commentEditor,
              initialOffset: const SheetOffset.proportionalToViewport(0.8),
              snapGrid: ChessSheetConfigs.commentEditorSnaps(
                minFlingSpeed: 650.0,
              ),
              builder:
                  (context) => _NotationCommentPage(
                    config: config,
                    hostContext: hostContext,
                  ),
            ),
          ],
    );

    return SheetKeyboardDismissible(
      dismissBehavior: const DragDownSheetKeyboardDismissBehavior(
        isContentScrollAware: true,
      ),
      child: PagedSheet(
        decoration: ChessSheetDecoration.dark(alpha: 0.97, borderRadius: 28.sp),
        shrinkChildToAvoidDynamicOverlap: true,
        navigator: navigator,
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
  comment,
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
  final String? commentText;
  final String? variationColorKey;

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
    this.commentText,
    this.variationColorKey,
  });
}

const int _variationCommentPreviewChars = 80;
const int _variationCommentMaxChars = 280;

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
    final ignoreSelectedChangeAfterPosition =
        positionChanged && userSelected != null;

    int targetIndex;

    // CRITICAL FIX: Only jump pages when position changes or user explicitly selects a variant
    // During silent updates (depth increases), preserve the user's current scroll position
    if (positionChanged) {
      // Position changed - keep the user's last viewed variant when possible
      final desiredIndex =
          _lastUserSelectedIndex ?? newSelectedIndex ?? _currentPage;
      targetIndex = desiredIndex.clamp(0, maxIndex);
      _lastUserSelectedIndex ??= desiredIndex;
    } else if (selectedIndexChanged &&
        newSelectedIndex != null &&
        newSelectedIndex <= maxIndex) {
      // If position just changed, prefer the user's last selection to avoid flicker
      if (ignoreSelectedChangeAfterPosition && userSelected != null) {
        targetIndex = userSelected;
      } else {
        // User explicitly selected a variant (selectedVariantIndex changed) - honor that selection
        targetIndex = newSelectedIndex;
        _lastUserSelectedIndex = newSelectedIndex;
      }
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
      final mergedPositions = widget.state.lockedPvMergedPositions;
      final baseMoveCount = widget.state.lockedPvBaseMoveCount ?? 0;
      final previewVariantIndex = widget.state.pvPreviewVariantIndex ?? 0;

      if (lockedLine == null ||
          mergedPositions == null ||
          mergedPositions.isEmpty) {
        return const SizedBox.shrink();
      }

      // Format only the PV moves for display using the position where the
      // preview started (moves before the PV are hidden from the notation).
      final pvStartIndex =
          baseMoveCount.clamp(0, mergedPositions.length - 1).toInt();
      final startingPosition = mergedPositions[pvStartIndex];
      final startMoveNumber = startingPosition.fullmoves;
      final isWhiteToMove = startingPosition.turn == Side.white;
      final sanMoves = _formatPv(
        lockedLine.sanMoves,
        startMoveNumber,
        isWhiteToMove,
      );
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
          _PvToken? focusToken;
          for (final token in pvTokens.reversed) {
            if (token.moveIndex != null) {
              focusToken = token;
              break;
            }
          }
          if (focusToken == null || focusToken.moveIndex == null) {
            return;
          }
          _showPvMoveActionSheet(
            context,
            focusToken.text,
            line,
            variantIndex,
            focusToken.moveIndex!,
            notifier,
            activeVariantColor,
          );
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
                        width: MediaQuery.sizeOf(context).width - 40.sp,
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
                          final placeholderLine = const AnalysisLine(
                            sanMoves: ['e4', 'e5', 'Nf3', 'Nc6', 'Bb5'],
                            evaluation: 35,
                          );
                          return Skeletonizer(
                            enabled: true,
                            effect: ShimmerEffect(
                              baseColor: kWhiteColor.withValues(alpha: 0.05),
                              highlightColor: kWhiteColor.withValues(
                                alpha: 0.1,
                              ),
                              duration: const Duration(milliseconds: 1500),
                            ),
                            child: buildVariantCard(
                              line: placeholderLine,
                              variantIndex: 0,
                              isSelected: false,
                              hasLockedPreview: false,
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
              _showPvMoveActionSheet(
                context,
                token.text,
                line,
                variantIndex,
                token.moveIndex!,
                notifier,
                variantColor,
              );
            },
            child: Material(
              color: Colors.transparent,
              child: Text('${token.text} ', style: moveStyle),
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

  Future<void> _showPvMoveActionSheet(
    BuildContext context,
    String moveLabel,
    AnalysisLine line,
    int variantIndex,
    int moveIndex,
    ChessBoardScreenNotifierNew notifier,
    Color accentColor,
  ) async {
    final hostContext = context;
    final isThreatsMode = widget.state.isThreatsMode;
    final actions = <_NotationActionItem>[
      _NotationActionItem(
        icon: Icons.visibility_rounded,
        label: 'Preview from here',
        color: accentColor,
        onSelected: (_) async {
          notifier.previewPrincipalVariationMoveAt(
            line,
            variantIndex,
            moveIndex,
          );
        },
      ),
      _NotationActionItem(
        icon: Icons.playlist_add_check_circle_rounded,
        label: 'Insert entire line',
        color: kPrimaryColor,
        onSelected: (_) async {
          notifier.clearPvPreview();
          notifier.insertPvMoves(line);
        },
      ),
      _NotationActionItem(
        icon: isThreatsMode ? Icons.gps_off : Icons.gps_fixed,
        label: isThreatsMode ? 'Hide Threats' : 'Show Threats',
        color: Colors.red,
        onSelected: (_) async {
          notifier.toggleThreatsMode();
        },
      ),
    ];

    await _showNotationActionSheet(
      context: hostContext,
      title: moveLabel,
      subtitle: 'Engine line options',
      actions: actions,
    );
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

const double _mainlineActionSheetInitialFraction = 0.45;
const double _variantActionSheetInitialFraction = 0.55;

class _TimeControlSnapshot {
  final Duration? base;
  final Duration increment;

  const _TimeControlSnapshot({required this.base, required this.increment});
}

class _NotationActionItem {
  final IconData icon;
  final String label;
  final Color color;
  final FutureOr<void> Function(BuildContext hostContext) onSelected;
  final bool triggersCommentEditor;

  const _NotationActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onSelected,
    this.triggersCommentEditor = false,
  });
}

Future<void> _showNotationActionSheet({
  required BuildContext context,
  required String title,
  String? subtitle,
  required List<_NotationActionItem> actions,
  _VariationCommentSheetConfig? commentConfig,
  String? timeSpentLabel,
  double initialSheetFraction = _mainlineActionSheetInitialFraction,
}) async {
  final hostContext = context;
  final route = ChessSheetRoutes.actionMenu(
    context: context,
    builder:
        (_) => _NotationActionSheet(
          title: title,
          subtitle: subtitle,
          actions: actions,
          hostContext: hostContext,
          commentConfig: commentConfig,
          timeSpentLabel: timeSpentLabel,
          initialSheetFraction: initialSheetFraction,
        ),
  );

  await Navigator.of(context).push(route);
}

class _VariationCommentSheetConfig {
  final String? initialValue;
  final FutureOr<void> Function(BuildContext context, String value) onSubmit;

  const _VariationCommentSheetConfig({
    this.initialValue,
    required this.onSubmit,
  });
}

class _NotationActionSheet extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final List<_NotationActionItem> actions;
  final BuildContext hostContext;
  final _VariationCommentSheetConfig? commentConfig;
  final String? timeSpentLabel;
  final double initialSheetFraction;

  const _NotationActionSheet({
    required this.title,
    this.subtitle,
    required this.actions,
    required this.hostContext,
    this.commentConfig,
    this.timeSpentLabel,
    required this.initialSheetFraction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clampedInitial = initialSheetFraction.clamp(0.25, 0.9).toDouble();
    final snapFractions = <double>{0.35, 0.75, clampedInitial}.toList()..sort();
    final snapGrid = SheetSnapGrid(
      snaps:
          snapFractions
              .map((value) => SheetOffset.proportionalToViewport(value))
              .toList(),
      minFlingSpeed: 850.0,
    );

    final navigator = Navigator(
      onGenerateInitialRoutes:
          (_, __) => [
            SpringPagedSheetRoute(
              scrollConfiguration: const SheetScrollConfiguration(),
              dragConfiguration: ChessSheetConfigs.actionMenu,
              initialOffset: SheetOffset.proportionalToViewport(clampedInitial),
              snapGrid: snapGrid,
              builder:
                  (context) => _NotationActionListPage(
                    title: title,
                    subtitle: subtitle,
                    actions: actions,
                    commentConfig: commentConfig,
                    hostContext: hostContext,
                    timeSpentLabel: timeSpentLabel,
                  ),
            ),
          ],
    );

    return SheetKeyboardDismissible(
      dismissBehavior: const DragDownSheetKeyboardDismissBehavior(
        isContentScrollAware: true,
      ),
      child: PagedSheet(
        decoration: ChessSheetDecoration.dark(alpha: 0.97, borderRadius: 28.sp),
        shrinkChildToAvoidDynamicOverlap: true,
        navigator: navigator,
      ),
    );
  }
}

class _NotationActionListPage extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final List<_NotationActionItem> actions;
  final _VariationCommentSheetConfig? commentConfig;
  final BuildContext hostContext;
  final String? timeSpentLabel;

  const _NotationActionListPage({
    required this.title,
    required this.actions,
    required this.hostContext,
    this.subtitle,
    this.commentConfig,
    this.timeSpentLabel,
  });

  Future<void> _handleActionTap(
    BuildContext context,
    _NotationActionItem action,
  ) async {
    HapticFeedback.selectionClick();

    if (action.triggersCommentEditor && commentConfig != null) {
      await Navigator.of(context).push(
        SpringPagedSheetRoute(
          scrollConfiguration: const SheetScrollConfiguration(),
          dragConfiguration: ChessSheetConfigs.commentEditor,
          initialOffset: const SheetOffset.proportionalToViewport(0.8),
          snapGrid: ChessSheetConfigs.commentEditorSnaps(minFlingSpeed: 650.0),
          builder:
              (context) => _NotationCommentPage(
                config: commentConfig!,
                hostContext: hostContext,
              ),
        ),
      );
      return;
    }

    Navigator.of(hostContext).pop();
    await Future.sync(() => action.onSelected(hostContext));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;

    // When keyboard is visible, add its height to bottom padding so sheet rides with keyboard
    final bottomPadding =
        viewInsets.bottom > 0
            ? viewInsets.bottom + 12.sp
            : math.max(20.sp, safeBottom + 8.sp);

    return Padding(
      padding: EdgeInsets.fromLTRB(20.sp, 12.sp, 20.sp, bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: kWhiteColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTypography.textLgBold.copyWith(
                        color: kWhiteColor,
                        letterSpacing: 0.25,
                      ),
                    ),
                    if (subtitle != null) ...[
                      SizedBox(height: 4.h),
                      Text(
                        subtitle!,
                        style: AppTypography.textSmRegular.copyWith(
                          color: kWhiteColor70,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (timeSpentLabel != null) ...[
                SizedBox(width: 12.w),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Time spent',
                      style: AppTypography.textXsMedium.copyWith(
                        color: kWhiteColor70,
                        letterSpacing: 0.2,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      timeSpentLabel!,
                      style: AppTypography.textSmMedium.copyWith(
                        color: kWhiteColor,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          if (actions.isNotEmpty) ...[
            SizedBox(height: 12.h),
            for (var i = 0; i < actions.length; i++) ...[
              _NotationActionTile(
                action: actions[i],
                onTap: () => _handleActionTap(context, actions[i]),
              ),
              if (i != actions.length - 1) SizedBox(height: 8.h),
            ],
          ],
        ],
      ),
    );
  }
}

class _NotationActionTile extends StatefulWidget {
  final _NotationActionItem action;
  final VoidCallback onTap;

  const _NotationActionTile({required this.action, required this.onTap});

  @override
  State<_NotationActionTile> createState() => _NotationActionTileState();
}

class _NotationActionTileState extends State<_NotationActionTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    // Use spring curve for natural bouncy feel
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: ChessSheetCurves.bouncy),
    );

    _glowAnimation = Tween<double>(
      begin: 0.02,
      end: 0.08,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14.sp),
              onTapDown: _onTapDown,
              onTapUp: _onTapUp,
              onTapCancel: _onTapCancel,
              onTap: widget.onTap,
              splashColor: widget.action.color.withValues(alpha: 0.1),
              highlightColor: widget.action.color.withValues(alpha: 0.05),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: 12.sp,
                  vertical: 14.sp,
                ),
                decoration: BoxDecoration(
                  color: kWhiteColor.withValues(alpha: _glowAnimation.value),
                  borderRadius: BorderRadius.circular(14.sp),
                  border: Border.all(
                    color: kWhiteColor.withValues(
                      alpha: 0.05 + (_controller.value * 0.05),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: widget.action.color.withValues(
                          alpha: 0.15 + (_controller.value * 0.05),
                        ),
                        borderRadius: BorderRadius.circular(10.sp),
                      ),
                      padding: EdgeInsets.all(8.sp),
                      child: Icon(
                        widget.action.icon,
                        color: widget.action.color,
                        size: 18.ic,
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Text(
                        widget.action.label,
                        style: AppTypography.textMdMedium.copyWith(
                          color: kWhiteColor,
                        ),
                      ),
                    ),
                    Icon(
                      widget.action.triggersCommentEditor
                          ? Icons.drive_file_rename_outline
                          : Icons.arrow_forward_ios_rounded,
                      color: kWhiteColor.withValues(alpha: 0.35),
                      size: 14.ic,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NotationCommentPage extends ConsumerStatefulWidget {
  final _VariationCommentSheetConfig config;
  final BuildContext hostContext;

  const _NotationCommentPage({required this.config, required this.hostContext});

  @override
  ConsumerState<_NotationCommentPage> createState() =>
      _NotationCommentPageState();
}

class _NotationCommentPageState extends ConsumerState<_NotationCommentPage> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isSaving = false;
  bool _hasEdited = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.config.initialValue ?? '')
      ..addListener(_onChanged);

    _focusNode = FocusNode();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    final baseValue = widget.config.initialValue ?? '';
    final edited = _controller.text != baseValue;
    if (edited != _hasEdited) {
      setState(() => _hasEdited = edited);
    }
  }

  Future<void> _handleSave() async {
    if (_isSaving || !_hasEdited) return;
    setState(() => _isSaving = true);
    try {
      await Future.sync(
        () => widget.config.onSubmit(widget.hostContext, _controller.text),
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
    } catch (error, stackTrace) {
      setState(() => _isSaving = false);
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          context: ErrorDescription('Saving notation comment'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;

    // When keyboard appears, push content up so TextField stays visible above keyboard
    // Extra padding ensures buttons are well above keyboard on all devices
    final bottomPadding =
        viewInsets.bottom > 0
            ? viewInsets.bottom + 52.sp
            : math.max(20.sp, safeBottom + 8.sp);

    return Padding(
      padding: EdgeInsets.fromLTRB(20.sp, 16.sp, 20.sp, bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with back button and title
          Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: kWhiteColor,
                  size: 18.ic,
                ),
                onPressed: () {
                  // Try to pop from current navigator first (for paged sheets)
                  // If that fails, pop from root navigator (for direct sheets)
                  if (!Navigator.of(context).canPop()) {
                    Navigator.of(context, rootNavigator: true).pop();
                  } else {
                    Navigator.of(context).pop();
                  }
                },
                splashRadius: 20.sp,
              ),
              SizedBox(width: 4.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Variant comment',
                      style: AppTypography.textLgBold.copyWith(
                        color: kWhiteColor,
                        letterSpacing: 0.3,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      'Leave a note for this branch.',
                      style: AppTypography.textSmRegular.copyWith(
                        color: kWhiteColor70,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Divider(color: kWhiteColor.withValues(alpha: 0.08)),
          SizedBox(height: 12.h),

          // Text field - flexible height but not taking all space
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: 120.h, maxHeight: 280.h),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              maxLines: null,
              minLines: 4,
              maxLength: _variationCommentMaxChars,
              style: AppTypography.textSmRegular.copyWith(color: kWhiteColor),
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                filled: true,
                fillColor: kBlack2Color.withValues(alpha: 0.6),
                hintText: 'Add a quick thought…',
                hintStyle: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor70,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.sp),
                  borderSide: BorderSide(
                    color: kWhiteColor.withValues(alpha: 0.1),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.sp),
                  borderSide: BorderSide(
                    color: kPrimaryColor.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: 12.h),

          // Action buttons
          Row(
            children: [
              // Clear button - clears the text field
              TextButton(
                onPressed:
                    _controller.text.isEmpty
                        ? null
                        : () {
                          HapticFeedback.selectionClick();
                          _controller.clear();
                        },
                child: const Text('Clear'),
              ),
              const Spacer(),
              // Delete button - directly removes the comment (only shown if there's an existing comment)
              if (widget.config.initialValue != null &&
                  widget.config.initialValue!.trim().isNotEmpty) ...[
                IconButton(
                  onPressed:
                      _isSaving
                          ? null
                          : () async {
                            HapticFeedback.mediumImpact();
                            setState(() => _isSaving = true);
                            try {
                              // Submit empty string to remove the comment
                              await Future.sync(
                                () => widget.config.onSubmit(
                                  widget.hostContext,
                                  '',
                                ),
                              );
                              if (!mounted) return;
                              Navigator.of(context, rootNavigator: true).pop();
                            } catch (error, stackTrace) {
                              setState(() => _isSaving = false);
                              FlutterError.reportError(
                                FlutterErrorDetails(
                                  exception: error,
                                  stack: stackTrace,
                                  context: ErrorDescription(
                                    'Removing notation comment',
                                  ),
                                ),
                              );
                            }
                          },
                  icon: Icon(
                    Icons.delete_outline,
                    color: kRedColor.withValues(alpha: 0.8),
                  ),
                  tooltip: 'Remove comment',
                ),
                SizedBox(width: 8.w),
              ],
              FilledButton(
                onPressed: _isSaving || !_hasEdited ? null : _handleSave,
                style: FilledButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  foregroundColor: kWhiteColor,
                  padding: EdgeInsets.symmetric(
                    horizontal: 18.w,
                    vertical: 10.h,
                  ),
                ),
                child:
                    _isSaving
                        ? SizedBox(
                          height: 14.h,
                          width: 14.h,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kWhiteColor,
                          ),
                        )
                        : const Text('Save comment'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// DEPRECATED: Old dialog-based comment approach replaced with smooth bottom sheet
// Keeping for reference - can be removed in future cleanup
/*
class _CommentDialog extends ConsumerStatefulWidget {
  final String initialComment;
  final ValueChanged<String> onSave;
  final FocusNode focusNode;

  const _CommentDialog({
    required this.initialComment,
    required this.onSave,
    required this.focusNode,
  });

  @override
  ConsumerState<_CommentDialog> createState() => _CommentDialogState();
}

class _CommentDialogState extends ConsumerState<_CommentDialog>
    with SingleTickerProviderStateMixin {
  late TextEditingController _controller;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialComment);
    _controller.addListener(_onTextChanged);

    // Setup entrance animation
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: const SnappySpringCurve(),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );

    // Start animation and focus field
    _animationController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.focusNode.requestFocus();
    });
  }

  void _onTextChanged() {
    final hasChanges = _controller.text != widget.initialComment;
    if (_hasChanges != hasChanges) {
      setState(() {
        _hasChanges = hasChanges;
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_hasChanges) {
      Navigator.of(context).pop();
      return;
    }

    HapticFeedback.mediumImpact();
    await _animationController.reverse();
    if (!mounted) return;

    widget.onSave(_controller.text);
    Navigator.of(context).pop();
  }

  Future<void> _handleCancel() async {
    HapticFeedback.lightImpact();
    await _animationController.reverse();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Get platform-specific keyboard height default
    final keyboardTotalHeight = ref.watch(keyboardTotalHeightProvider);

    return MediaQuery.removeViewInsets(
      context: context,
      removeBottom: true,
      removeTop: true,
      child: GestureDetector(
        onTap: _handleCancel,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: [
            FadeTransition(
              opacity: _fadeAnimation,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(color: Colors.black.withValues(alpha: 0.6)),
              ),
            ),
            Positioned.fill(
            child: KeyboardAnimationBuilder(
              focusNode: _focusNode,
              keyboardTotalHeight: keyboardTotalHeight,
              interpolateLastPart: Platform.isIOS,
              interpolationConfig: InterpolationConfig.fidelity,
              warmUpFrame: true,
              onChange: (height) {
                if (height > 0) {
                  ref
                      .read(keyboardTotalHeightProvider.notifier)
                      .update(height);
                }
              },
                builder: (context, keyboardHeight) {
                final safePadding = MediaQuery.paddingOf(context);
                final screenSize = MediaQuery.sizeOf(context);
                final effectiveKeyboardHeight =
                    keyboardHeight.clamp(0.0, keyboardTotalHeight);

                // Calculate lift to center in available space
                // Available space center is (screenHeight - keyboardHeight) / 2
                // Current center is screenHeight / 2
                // Lift = Current - Available = keyboardHeight / 2
                final double liftDistance = effectiveKeyboardHeight / 2;

                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    20.sp,
                    safePadding.top + 24.h,
                    20.sp,
                    safePadding.bottom + 24.h,
                  ),
                  child: Align(
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth:
                            math.min(520.w, screenSize.width - 32.w),
                        maxHeight: screenSize.height * 0.65,
                      ),
                      child: GestureDetector(
                        onTap: () {},
                        child: ScaleTransition(
                          scale: _scaleAnimation,
                          alignment: Alignment.center,
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: Transform.translate(
                              offset: Offset(0, -liftDistance),
                              child: _buildCommentDialogCard(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentDialogCard(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(24.sp),
        border: Border.all(
          color: kPrimaryColor.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 40,
            offset: const Offset(0, -10),
            spreadRadius: 5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: EdgeInsets.only(top: 12.sp, bottom: 8.sp),
              width: 36.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: kWhiteColor.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2.sp),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20.sp, 8.sp, 20.sp, 12.sp),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10.sp),
                  decoration: BoxDecoration(
                    color: kPrimaryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12.sp),
                  ),
                  child: Icon(
                    Icons.comment_outlined,
                    color: kPrimaryColor,
                    size: 20.sp,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add Comment',
                        style: AppTypography.textLgBold.copyWith(
                          color: kWhiteColor,
                          letterSpacing: 0.2,
                        ),
                      ),
                      Text(
                        'Share your thoughts on this position',
                        style: AppTypography.textXsRegular.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 1,
            margin: EdgeInsets.symmetric(horizontal: 20.sp),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  kWhiteColor.withValues(alpha: 0.1),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20.sp),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: AppTypography.textMdRegular.copyWith(
                  color: kWhiteColor,
                  height: 1.5,
                ),
                maxLines: null,
                minLines: 3,
                maxLength: _variationCommentMaxChars,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'What do you think about this position?',
                  hintStyle: AppTypography.textMdRegular.copyWith(
                    color: kWhiteColor.withValues(alpha: 0.4),
                  ),
                  filled: true,
                  fillColor: kWhiteColor.withValues(alpha: 0.03),
                  contentPadding: EdgeInsets.all(16.sp),
                  counterStyle: AppTypography.textXsRegular.copyWith(
                    color: kWhiteColor.withValues(alpha: 0.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16.sp),
                    borderSide: BorderSide(
                      color: kWhiteColor.withValues(alpha: 0.1),
                      width: 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16.sp),
                    borderSide: BorderSide(
                      color: kPrimaryColor.withValues(alpha: 0.6),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              20.sp,
              12.sp,
              20.sp,
              20.sp + MediaQuery.paddingOf(context).bottom,
            ),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: kWhiteColor.withValues(alpha: 0.05),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                if (_controller.text.isNotEmpty)
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        _controller.clear();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: kWhiteColor.withValues(alpha: 0.7),
                        padding: EdgeInsets.symmetric(vertical: 14.sp),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.sp),
                        ),
                      ),
                      icon: Icon(Icons.clear, size: 18.sp),
                      label: Text(
                        'Clear',
                        style: AppTypography.textSmMedium,
                      ),
                    ),
                  ),
                if (_controller.text.isNotEmpty) SizedBox(width: 12.w),
                Expanded(
                  child: TextButton(
                    onPressed: _handleCancel,
                    style: TextButton.styleFrom(
                      foregroundColor: kWhiteColor.withValues(alpha: 0.8),
                      padding: EdgeInsets.symmetric(vertical: 14.sp),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.sp),
                        side: BorderSide(
                          color: kWhiteColor.withValues(alpha: 0.15),
                        ),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: AppTypography.textSmMedium,
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _handleSave,
                    style: FilledButton.styleFrom(
                      backgroundColor: _hasChanges
                          ? kPrimaryColor
                          : kWhiteColor.withValues(alpha: 0.1),
                      foregroundColor: _hasChanges
                          ? kWhiteColor
                          : kWhiteColor.withValues(alpha: 0.4),
                      padding: EdgeInsets.symmetric(vertical: 14.sp),
                      elevation: _hasChanges ? 4 : 0,
                      shadowColor: _hasChanges
                          ? kPrimaryColor.withValues(alpha: 0.5)
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.sp),
                      ),
                    ),
                    icon: Icon(Icons.check_circle_outline, size: 20.sp),
                    label: Text(
                      _hasChanges ? 'Save Comment' : 'No Changes',
                      style: AppTypography.textSmBold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
*/
// End of deprecated _CommentDialog class

/// Provider to fetch tour info by tour ID - used by the event info sheet
final _tourInfoByIdProvider = FutureProvider.autoDispose
    .family<AboutTourModel?, String>((ref, tourId) async {
      if (tourId.isEmpty) return null;

      try {
        final tours = await ref.read(tourRepositoryProvider).getToursByIds([
          tourId,
        ]);
        if (tours.isNotEmpty) {
          return AboutTourModel.fromTour(tours.first);
        }
      } catch (e) {
        debugPrint('Failed to fetch tour info for $tourId: $e');
      }
      return null;
    });

/// Event info sheet - displays tournament/event details
class _EventInfoSheet extends ConsumerWidget {
  final GamesTourModel game;
  final String? pgn;

  const _EventInfoSheet({required this.game, this.pgn});

  /// Parse opening info (ECO code and Opening name) from PGN headers
  ({String? eco, String? opening}) _parseOpeningFromPgn() {
    final pgnString = pgn ?? game.pgn;
    if (pgnString == null || pgnString.isEmpty) {
      return (eco: null, opening: null);
    }

    try {
      final pgnGame = PgnGame.parsePgn(pgnString);
      final eco = pgnGame.headers['ECO'];
      final opening = pgnGame.headers['Opening'];
      return (eco: eco, opening: opening);
    } catch (e) {
      // Fallback to regex parsing if dartchess fails
      String? eco;
      String? opening;

      final ecoMatch = RegExp(r'\[ECO\s+"([^"]+)"\]').firstMatch(pgnString);
      if (ecoMatch != null) {
        eco = ecoMatch.group(1);
      }

      final openingMatch = RegExp(
        r'\[Opening\s+"([^"]+)"\]',
      ).firstMatch(pgnString);
      if (openingMatch != null) {
        opening = openingMatch.group(1);
      }

      return (eco: eco, opening: opening);
    }
  }

  /// Navigate to the tournament detail screen
  Future<void> _navigateToTournament(
    BuildContext context,
    WidgetRef ref,
    AboutTourModel aboutModel,
  ) async {
    final navigator = Navigator.of(context);

    final targetId =
        aboutModel.groupBroadcastId?.isNotEmpty == true
            ? aboutModel.groupBroadcastId!
            : (aboutModel.id.isNotEmpty ? aboutModel.id : game.tourId);

    if (targetId.isEmpty) {
      return;
    }

    GroupBroadcast groupBroadcast;
    try {
      groupBroadcast = await ref
          .read(groupBroadcastRepositoryProvider)
          .getGroupBroadcastById(targetId);
    } catch (e) {
      debugPrint('Failed to fetch group broadcast for $targetId: $e');
      groupBroadcast = GroupBroadcast(
        id: targetId,
        createdAt: DateTime.now(),
        name: aboutModel.name,
        search: [aboutModel.name],
        timeControl:
            aboutModel.timeControl.isNotEmpty ? aboutModel.timeControl : null,
        maxAvgElo: null,
        dateStart: null,
        dateEnd: null,
      );
    }

    if (!context.mounted) return;

    ref.read(selectedBroadcastModelProvider.notifier).state = groupBroadcast;

    navigator.pop(); // Close the sheet
    if (ref.read(selectedBroadcastModelProvider) != null) {
      navigator.pushNamed('/tournament_detail_screen');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // First try tourDetailScreenProvider (works when navigating from tour detail)
    final tourDetail = ref.watch(tourDetailScreenProvider);
    final tourDetailAboutModel = tourDetail.valueOrNull?.aboutTourModel;

    // If tourDetailScreenProvider doesn't have data, fetch independently by tourId
    final tourInfoAsync = ref.watch(_tourInfoByIdProvider(game.tourId));

    // Use tourDetailAboutModel only if it matches the current game's tourId
    final matchesCachedTour =
        tourDetailAboutModel?.id.isNotEmpty == true &&
        tourDetailAboutModel?.id == game.tourId;
    final aboutModel =
        matchesCachedTour ? tourDetailAboutModel : tourInfoAsync.valueOrNull;

    // Check if we're still loading
    final isLoading = !matchesCachedTour && tourInfoAsync.isLoading;

    final locationService = ref.read(locationServiceProvider);
    final urlLauncher = ref.read(urlLauncherProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      builder:
          (context, scrollController) => Container(
            decoration: BoxDecoration(
              color: kBlack2Color,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16.sp)),
            ),
            child: Column(
              children: [
                // Drag handle
                Container(
                  width: 40.sp,
                  height: 4.sp,
                  margin: EdgeInsets.symmetric(vertical: 12.sp),
                  decoration: BoxDecoration(
                    color: kWhiteColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2.sp),
                  ),
                ),
                // Content
                Expanded(
                  child:
                      isLoading
                          ? Center(
                            child: CircularProgressIndicator(
                              color: kPrimaryColor,
                              strokeWidth: 2,
                            ),
                          )
                          : aboutModel == null
                          ? _buildFallbackContent(
                            context,
                            scrollController,
                            locationService,
                          )
                          : _buildTourContent(
                            context,
                            ref,
                            scrollController,
                            aboutModel,
                            locationService,
                            urlLauncher,
                          ),
                ),
              ],
            ),
          ),
    );
  }

  /// Fallback content when tour info is not available - shows game info from GamesTourModel
  Widget _buildFallbackContent(
    BuildContext context,
    ScrollController scrollController,
    LocationService locationService,
  ) {
    return ListView(
      controller: scrollController,
      padding: EdgeInsets.symmetric(horizontal: 20.sp),
      children: [
        // Game header
        Text(
          'Game Info',
          style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
        ),
        SizedBox(height: 16.h),
        // Round info
        _EventInfoRow(
          icon: Icons.format_list_numbered_rounded,
          label: 'Round',
          value:
              game.roundSlug != null
                  ? StringUtils.formatRoundLabel(game.roundSlug)
                  : game.roundDisplayName,
        ),
        SizedBox(height: 12.h),
        // Board number
        if (game.boardNr != null) ...[
          _EventInfoRow(
            icon: Icons.grid_on_rounded,
            label: 'Board',
            value: 'Board ${game.boardNr}',
          ),
          SizedBox(height: 12.h),
        ],
        // Opening info from PGN
        ..._buildOpeningInfoRows(),
        // Players section
        SizedBox(height: 8.h),
        Text(
          'Players',
          style: AppTypography.textSmMedium.copyWith(
            color: kWhiteColor.withValues(alpha: 0.6),
          ),
        ),
        SizedBox(height: 12.h),
        // White player
        _buildPlayerRow(game.whitePlayer, 'White', locationService),
        SizedBox(height: 8.h),
        // Black player
        _buildPlayerRow(game.blackPlayer, 'Black', locationService),
        SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 16.h),
      ],
    );
  }

  /// Build opening info rows if available in PGN
  List<Widget> _buildOpeningInfoRows() {
    final openingInfo = _parseOpeningFromPgn();
    final List<Widget> rows = [];

    if (openingInfo.eco != null || openingInfo.opening != null) {
      // Combine ECO and Opening name
      String openingDisplay = '';
      if (openingInfo.eco != null && openingInfo.opening != null) {
        openingDisplay = '${openingInfo.eco}: ${openingInfo.opening}';
      } else if (openingInfo.opening != null) {
        openingDisplay = openingInfo.opening!;
      } else if (openingInfo.eco != null) {
        openingDisplay = openingInfo.eco!;
      }

      if (openingDisplay.isNotEmpty) {
        rows.add(
          _EventInfoRow(
            icon: Icons.menu_book_rounded,
            label: 'Opening',
            value: openingDisplay,
          ),
        );
        rows.add(SizedBox(height: 12.h));
      }
    }

    return rows;
  }

  Widget _buildPlayerRow(
    PlayerCard player,
    String side,
    LocationService locationService,
  ) {
    // Use the same validation as PlayerFirstRowDetailWidget
    final validCountryCode = locationService.getValidCountryCode(
      player.countryCode,
    );

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 10.sp),
      decoration: BoxDecoration(
        color: kLightBlack.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8.sp),
      ),
      child: Row(
        children: [
          // Side indicator
          Container(
            width: 8.sp,
            height: 8.sp,
            decoration: BoxDecoration(
              color: side == 'White' ? kWhiteColor : kBlack2Color,
              border: Border.all(color: kWhiteColor.withValues(alpha: 0.3)),
              borderRadius: BorderRadius.circular(2.sp),
            ),
          ),
          SizedBox(width: 10.w),
          // Country flag - handle FID (FIDE) specially like PlayerFirstRowDetailWidget
          if (player.countryCode.toUpperCase() == 'FID') ...[
            Image.asset(
              PngAsset.fideLogo,
              height: 14.h,
              width: 20.w,
              fit: BoxFit.cover,
              cacheWidth: 48,
              cacheHeight: 36,
            ),
            SizedBox(width: 8.w),
          ] else if (validCountryCode.isNotEmpty) ...[
            CountryFlag.fromCountryCode(
              validCountryCode,
              width: 20.w,
              height: 14.h,
            ),
            SizedBox(width: 8.w),
          ],
          // Title
          if (player.title.isNotEmpty) ...[
            Text(
              player.title,
              style: AppTypography.textSmMedium.copyWith(color: kPrimaryColor),
            ),
            SizedBox(width: 6.w),
          ],
          // Name
          Expanded(
            child: Text(
              player.name,
              style: AppTypography.textSmMedium.copyWith(color: kWhiteColor),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Rating
          Text(
            player.displayRating,
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTourContent(
    BuildContext context,
    WidgetRef ref,
    ScrollController scrollController,
    AboutTourModel aboutModel,
    dynamic locationService,
    dynamic urlLauncher,
  ) {
    return ListView(
      controller: scrollController,
      padding: EdgeInsets.symmetric(horizontal: 20.sp),
      children: [
        // Event image
        if (aboutModel.imageUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(12.sp),
            child: SizedBox(
              height: 140.h,
              width: double.infinity,
              child: CachedNetworkImage(
                imageUrl: aboutModel.imageUrl,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                placeholder:
                    (_, __) => Container(
                      color: kLightBlack,
                      child: Center(
                        child: Icon(
                          Icons.image,
                          color: kWhiteColor.withValues(alpha: 0.3),
                          size: 40.sp,
                        ),
                      ),
                    ),
                errorWidget:
                    (_, __, ___) => Container(
                      color: kLightBlack,
                      child: Center(
                        child: Icon(
                          Icons.image_not_supported,
                          color: kWhiteColor.withValues(alpha: 0.3),
                          size: 40.sp,
                        ),
                      ),
                    ),
              ),
            ),
          ),
        SizedBox(height: 16.h),
        // Event name - clickable to navigate to tournament
        GestureDetector(
          onTap: () => _navigateToTournament(context, ref, aboutModel),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  aboutModel.name,
                  style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: kWhiteColor.withValues(alpha: 0.5),
                size: 20.sp,
              ),
            ],
          ),
        ),
        SizedBox(height: 12.h),
        // Round info from game
        _EventInfoRow(
          icon: Icons.format_list_numbered_rounded,
          label: 'Round',
          value:
              game.roundSlug != null
                  ? StringUtils.formatRoundLabel(game.roundSlug)
                  : game.roundDisplayName,
        ),
        SizedBox(height: 12.h),
        // Board number
        if (game.boardNr != null) ...[
          _EventInfoRow(
            icon: Icons.grid_on_rounded,
            label: 'Board',
            value: 'Board ${game.boardNr}',
          ),
          SizedBox(height: 12.h),
        ],
        // Opening info from PGN
        ..._buildOpeningInfoRows(),
        // Description
        if (aboutModel.description.isNotEmpty) ...[
          Text(
            aboutModel.description,
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor.withValues(alpha: 0.7),
            ),
          ),
          SizedBox(height: 16.h),
        ],
        // Info rows
        if (aboutModel.timeControl.isNotEmpty) ...[
          _EventInfoRow(
            icon: Icons.access_time_rounded,
            label: 'Time Control',
            value: StringUtils.capitalizeWords(aboutModel.timeControl),
          ),
          SizedBox(height: 12.h),
        ],
        if (aboutModel.date.isNotEmpty) ...[
          _EventInfoRow(
            icon: Icons.calendar_today_rounded,
            label: 'Date',
            value: aboutModel.date,
          ),
          SizedBox(height: 12.h),
        ],
        if (aboutModel.location.isNotEmpty)
          _EventInfoRow(
            icon: Icons.location_on_rounded,
            label: 'Location',
            value: aboutModel.location,
            trailing: _buildCountryFlag(
              locationService.getCountryCode(aboutModel.location),
            ),
          ),
        // Players section with game players highlighted
        SizedBox(height: 16.h),
        Text(
          'Players',
          style: AppTypography.textSmMedium.copyWith(
            color: kWhiteColor.withValues(alpha: 0.6),
          ),
        ),
        SizedBox(height: 8.h),
        // White player
        _buildPlayerRow(game.whitePlayer, 'White', locationService),
        SizedBox(height: 8.h),
        // Black player
        _buildPlayerRow(game.blackPlayer, 'Black', locationService),
        // Top players from tournament
        if (aboutModel.players.isNotEmpty) ...[
          SizedBox(height: 16.h),
          Text(
            'Top Players in Event',
            style: AppTypography.textSmMedium.copyWith(
              color: kWhiteColor.withValues(alpha: 0.6),
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            aboutModel.players
                .where((p) => p.rating != null)
                .take(4)
                .map((p) => p.displayName)
                .join(', '),
            style: AppTypography.textSmRegular.copyWith(color: kWhiteColor),
          ),
        ],
        // Website button
        if (aboutModel.websiteUrl.isNotEmpty) ...[
          SizedBox(height: 20.h),
          GestureDetector(
            onTap: () => urlLauncher.launchCustomUrl(aboutModel.websiteUrl),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16.sp, vertical: 12.sp),
              decoration: BoxDecoration(
                color: kPrimaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8.sp),
                border: Border.all(color: kPrimaryColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.language_rounded,
                    color: kPrimaryColor,
                    size: 18.sp,
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    aboutModel.extractDomain(),
                    style: AppTypography.textSmMedium.copyWith(
                      color: kPrimaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 16.h),
      ],
    );
  }

  Widget? _buildCountryFlag(String countryCode) {
    if (countryCode.isEmpty) return null;
    return CountryFlag.fromCountryCode(countryCode, width: 20.w, height: 14.h);
  }
}

class _EventInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  const _EventInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: kWhiteColor.withValues(alpha: 0.5), size: 18.sp),
        SizedBox(width: 10.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppTypography.textXsRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.5),
                ),
              ),
              SizedBox(height: 2.h),
              Row(
                children: [
                  if (trailing != null) ...[trailing!, SizedBox(width: 6.w)],
                  Expanded(
                    child: Text(
                      value,
                      style: AppTypography.textSmMedium.copyWith(
                        color: kWhiteColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
