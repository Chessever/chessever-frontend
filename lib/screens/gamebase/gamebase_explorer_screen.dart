import 'dart:async';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/chess_board_settings_page.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_bottom_nav_bar.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/screens/gamebase/providers/explorer_eval_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/figurine_notation.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_explorer_state.dart';
import 'package:chessever2/screens/gamebase/widgets/widgets.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';

/// Main screen for exploring the Gamebase opening database.
/// Displays a chess board, move statistics, and navigation controls.
class GamebaseExplorerScreen extends ConsumerStatefulWidget {
  const GamebaseExplorerScreen({super.key, this.initialPlayer});

  /// Creates an isolated explorer scope so other mounted routes (for example
  /// hidden player-profile/game-card widgets) cannot mutate this explorer's
  /// provider state and continuously restart engine analysis.
  static Widget scoped({Key? key, GamebasePlayer? initialPlayer}) {
    return ProviderScope(
      overrides: [
        gamebaseExplorerProvider.overrideWith(
          (ref) => GamebaseExplorerNotifier(ref),
        ),
        explorerEvalProvider.overrideWith((ref) => ExplorerEvalNotifier(ref)),
      ],
      child: GamebaseExplorerScreen(key: key, initialPlayer: initialPlayer),
    );
  }

  /// When non-null, the explorer opens pre-filtered to this player's games.
  final GamebasePlayer? initialPlayer;

  @override
  ConsumerState<GamebaseExplorerScreen> createState() =>
      _GamebaseExplorerScreenState();
}

class _GamebaseExplorerScreenState
    extends ConsumerState<GamebaseExplorerScreen> with RouteAware {
  bool _isFlipped = false;
  bool _routeActive = true;
  Timer? _backwardLongPressTimer;
  Timer? _forwardLongPressTimer;

  void _resetExplorerState({bool fetch = false, bool preserveScope = true}) {
    final notifier = ref.read(gamebaseExplorerProvider.notifier);
    final scopedPlayer = preserveScope ? widget.initialPlayer : null;

    if (fetch && scopedPlayer != null) {
      // Player-scoped explorer reset: keep the original player filter.
      notifier.initializeWithPlayer(scopedPlayer);
    } else {
      notifier.reset(fetch: fetch);
    }

    // On teardown (fetch=false), explicitly stop the engine.
    // On init (fetch=true), let _ExplorerEvalBar handle engine lifecycle
    // via its initState/didUpdateWidget to avoid double-start conflicts
    // that cause depth jitter and perpetual "..." states.
    if (!fetch) {
      ref
          .read(explorerEvalProvider.notifier)
          .setEngineEnabled(
            enabled: false,
            fen: ref.read(gamebaseExplorerProvider).currentFen,
          );
    }
  }

  bool _shouldShowClearFilters(GamebaseExplorerState state) {
    final scopedPlayer = widget.initialPlayer;
    if (scopedPlayer == null) return state.hasActiveFilters;

    final hasRatingOrTimeFilters =
        state.filters.timeControls.isNotEmpty ||
        state.filters.minRating != null ||
        state.filters.maxRating != null;

    final hasDifferentPlayerScope =
        state.filters.playerIds.length != 1 ||
        state.filters.playerIds.first != scopedPlayer.id ||
        state.filters.selectedPlayers.length != 1 ||
        state.filters.selectedPlayers.first.id != scopedPlayer.id;

    return hasRatingOrTimeFilters || hasDifferentPlayerScope;
  }

  void _clearFiltersForCurrentScope() {
    final notifier = ref.read(gamebaseExplorerProvider.notifier);
    final scopedPlayer = widget.initialPlayer;

    if (scopedPlayer != null) {
      // In player-scoped explorer, "clear filters" should keep player scope.
      notifier.initializeWithPlayer(scopedPlayer);
      return;
    }

    notifier.clearFilters();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void didPushNext() {
    // Another route was pushed on top — this explorer is now in the background.
    // Disable its engine to prevent Stockfish contention with the foreground
    // explorer (which also uses isCurrentPosition: true). Multiple background
    // explorers retrying after cancellation cause an infinite preemption cycle.
    setState(() => _routeActive = false);
    super.didPushNext();
  }

  @override
  void didPopNext() {
    // The route on top was popped — this explorer is visible again.
    // Re-enable its engine so the eval restarts.
    setState(() => _routeActive = true);
    super.didPopNext();
  }

  @override
  void initState() {
    super.initState();

    // Riverpod best practice: never modify providers synchronously in widget
    // lifecycles (can happen while the widget tree is building).
    // Defer to post-frame to keep provider updates safe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Always start fresh; preserve player scope when present.
      _resetExplorerState(fetch: true);
    });
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _stopLongPressBackward();
    _stopLongPressForward();
    super.dispose();
  }

  static final double _evalBarWidth = 20.sp;

  Future<void> _toggleEngineAnalysis() async {
    final current = ref.read(engineSettingsProviderNew).valueOrNull;
    final nextValue = !(current?.showEngineAnalysis ?? true);
    await ref
        .read(engineSettingsProviderNew.notifier)
        .toggleEngineAnalysis(nextValue);
  }

  void _startLongPressBackward() {
    _backwardLongPressTimer?.cancel();
    _backwardLongPressTimer = Timer.periodic(
      const Duration(milliseconds: 130),
      (_) {
        final currentState = ref.read(gamebaseExplorerProvider);
        if (!currentState.canGoBack) {
          _stopLongPressBackward();
          return;
        }
        ref.read(gamebaseExplorerProvider.notifier).goBack();
      },
    );
  }

  void _stopLongPressBackward() {
    _backwardLongPressTimer?.cancel();
    _backwardLongPressTimer = null;
  }

  void _startLongPressForward() {
    _forwardLongPressTimer?.cancel();
    _forwardLongPressTimer = Timer.periodic(const Duration(milliseconds: 130), (
      _,
    ) {
      final currentState = ref.read(gamebaseExplorerProvider);
      if (!currentState.canGoForward) {
        _stopLongPressForward();
        return;
      }
      ref.read(gamebaseExplorerProvider.notifier).goForward();
    });
  }

  void _stopLongPressForward() {
    _forwardLongPressTimer?.cancel();
    _forwardLongPressTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final showEngineAnalysis = _routeActive &&
        ref.watch(
          engineSettingsProviderNew.select(
            (s) => s.valueOrNull?.showEngineAnalysis ?? true,
          ),
        );

    final state = ref.watch(gamebaseExplorerProvider);

    return ScreenWrapper(
      child: PopScope(
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) return;
          _resetExplorerState();
        },
        child: Scaffold(
          backgroundColor: kBlack2Color,
          appBar: _buildAppBar(context),
          bottomNavigationBar: ChessBoardBottomNavBar(
            gameIndex: 0,
            onFlip: () => setState(() => _isFlipped = !_isFlipped),
            toggleEngineVisibility: _toggleEngineAnalysis,
            onEngineSettingsLongPress: () {
              requireFullAuthGuard(context).then((allowed) {
                if (!allowed || !context.mounted) return;
                Navigator.of(context).push(ChessBoardSettingsPage.route());
              });
            },
            onRightMove:
                state.canGoForward
                    ? () =>
                        ref.read(gamebaseExplorerProvider.notifier).goForward()
                    : null,
            onLeftMove:
                state.canGoBack
                    ? () => ref.read(gamebaseExplorerProvider.notifier).goBack()
                    : null,
            onLongPressBackwardStart:
                state.canGoBack ? _startLongPressBackward : null,
            onLongPressBackwardEnd: _stopLongPressBackward,
            onLongPressForwardStart:
                state.canGoForward ? _startLongPressForward : null,
            onLongPressForwardEnd: _stopLongPressForward,
            canMoveForward: state.canGoForward,
            canMoveBackward: state.canGoBack,
            showEngineAnalysis: showEngineAnalysis,
            showUnseenMoveBadge: false,
            showGamebaseButton: false,
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isTablet = ResponsiveHelper.isTablet;
              final isLandscape = ResponsiveHelper.isLandscape;

              if (isTablet && isLandscape) {
                return _buildTabletLandscapeLayout(
                  constraints,
                  showEngineAnalysis: showEngineAnalysis,
                );
              } else if (isTablet) {
                return _buildTabletPortraitLayout(
                  constraints,
                  showEngineAnalysis: showEngineAnalysis,
                );
              } else {
                return _buildPhoneLayout(
                  constraints,
                  showEngineAnalysis: showEngineAnalysis,
                );
              }
            },
          ),
        ),
      ),
    );
  }

  /// Phone layout — identical to the original layout.
  Widget _buildPhoneLayout(
    BoxConstraints constraints, {
    required bool showEngineAnalysis,
  }) {
    final state = ref.watch(gamebaseExplorerProvider);
    final boardSize = constraints.maxWidth - 48.sp - _evalBarWidth - 4.sp;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ResponsiveHelper.contentMaxWidth),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(24.sp),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ExplorerEvalBar(
                    fen: state.currentFen,
                    height: boardSize,
                    width: _evalBarWidth,
                    isFlipped: _isFlipped,
                    showEngineAnalysis: showEngineAnalysis,
                  ),
                  SizedBox(width: 4.sp),
                  _GamebaseChessBoard(
                    fen: state.currentFen,
                    boardSize: boardSize,
                    isFlipped: _isFlipped,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: kBlack3Color,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(16.br),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    if (showEngineAnalysis) const _ExplorerEngineLines(),
                    const Expanded(child: MoveStatisticsPanel()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tablet landscape — side-by-side: board on left, stats panel on right.
  Widget _buildTabletLandscapeLayout(
    BoxConstraints constraints, {
    required bool showEngineAnalysis,
  }) {
    final state = ref.watch(gamebaseExplorerProvider);
    final availableHeight = constraints.maxHeight;
    final verticalPadding = 8.sp * 2; // top + bottom
    final boardSize = (availableHeight - verticalPadding).clamp(
      200.0,
      double.infinity,
    );
    final leftWidth = boardSize + _evalBarWidth + 4.sp + 24.sp;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 8.sp),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left column: board + nav controls
          SizedBox(
            width: leftWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ExplorerEvalBar(
                      fen: state.currentFen,
                      height: boardSize,
                      width: _evalBarWidth,
                      isFlipped: _isFlipped,
                      showEngineAnalysis: showEngineAnalysis,
                    ),
                    SizedBox(width: 4.sp),
                    _GamebaseChessBoard(
                      fen: state.currentFen,
                      boardSize: boardSize,
                      isFlipped: _isFlipped,
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: 12.sp),
          // Right column: stats panel
          Expanded(
            child: Container(
              height: availableHeight - verticalPadding,
              decoration: BoxDecoration(
                color: kBlack3Color,
                borderRadius: BorderRadius.circular(12.sp),
                border: Border.all(color: kDividerColor),
              ),
              clipBehavior: Clip.antiAlias,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12.sp),
                child: Column(
                  children: [
                    if (showEngineAnalysis) const _ExplorerEngineLines(),
                    const Expanded(child: MoveStatisticsPanel()),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tablet portrait — centered column with constrained width.
  Widget _buildTabletPortraitLayout(
    BoxConstraints constraints, {
    required bool showEngineAnalysis,
  }) {
    final state = ref.watch(gamebaseExplorerProvider);
    final contentMaxWidth = (constraints.maxWidth * 0.85).clamp(0.0, 720.0);
    final boardSize = contentMaxWidth - 48.sp - _evalBarWidth - 4.sp;

    return SizedBox.expand(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.all(24.sp),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ExplorerEvalBar(
                      fen: state.currentFen,
                      height: boardSize,
                      width: _evalBarWidth,
                      isFlipped: _isFlipped,
                      showEngineAnalysis: showEngineAnalysis,
                    ),
                    SizedBox(width: 4.sp),
                    _GamebaseChessBoard(
                      fen: state.currentFen,
                      boardSize: boardSize,
                      isFlipped: _isFlipped,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: kBlack3Color,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16.br),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      if (showEngineAnalysis) const _ExplorerEngineLines(),
                      const Expanded(child: MoveStatisticsPanel()),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final state = ref.watch(gamebaseExplorerProvider);

    return AppBar(
      backgroundColor: kBlack2Color,
      elevation: 0,
      centerTitle: false,
      titleSpacing: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, size: 24.ic),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title:
          state.filters.selectedPlayers.isNotEmpty
              ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.filters.selectedPlayers.first.titleAndName,
                    style: TextStyle(
                      color: kWhiteColor,
                      fontSize: 16.f,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Opening Explorer',
                    style: TextStyle(
                      color: kSecondaryTextColor,
                      fontSize: 12.f,
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              )
              : Text(
                'Opening Explorer',
                style: TextStyle(
                  color: kWhiteColor,
                  fontSize: 18.f,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
      actions: [
        if (_shouldShowClearFilters(state))
          IconButton(
            icon: Icon(Icons.filter_alt_off, size: 24.ic),
            onPressed: _clearFiltersForCurrentScope,
            tooltip: 'Clear filters',
          ),
        IconButton(
          icon: Icon(Icons.restart_alt, size: 24.ic),
          onPressed:
              () => _resetExplorerState(fetch: true, preserveScope: true),
          tooltip: 'Reset explorer',
        ),
        IconButton(
          icon: Icon(Icons.tune, size: 24.ic),
          onPressed: () => _showFilterSheet(context),
          tooltip: 'Filters',
        ),
        GestureDetector(
          onTap: () => _openAnalysis(context),
          child: Container(
            margin: EdgeInsets.only(right: 8.sp),
            padding: EdgeInsets.symmetric(horizontal: 8.sp, vertical: 6.sp),
            decoration: BoxDecoration(
              color: kWhiteColor,
              borderRadius: BorderRadius.circular(8.br),
            ),
            child: Text(
              'Done',
              style: AppTypography.textSmMedium.copyWith(
                color: kBackgroundColor,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openAnalysis(BuildContext context) {
    final state = ref.read(gamebaseExplorerProvider);
    final exploredMoves = state.exploredMoves;
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    // Convert UCI moves to SAN by replaying from the start.
    //
    // NOTE: `package:chess`'s `move()` returns a `bool` in our current version,
    // so we can't rely on verbose move maps (`move['san']`). Use `dartchess`
    // instead (same helper we use in the move list) to produce SAN + advance FEN.
    final sanMoves = <String>[];
    var currentFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
    for (final uci in exploredMoves) {
      final (san, nextFen) = uciToSanAndFen(uci, currentFen);
      sanMoves.add(san);
      if (nextFen == null) break;
      currentFen = nextFen;
    }

    // Build PGN move text.
    final moveText = StringBuffer();
    for (var i = 0; i < sanMoves.length; i++) {
      if (i % 2 == 0) moveText.write('${(i ~/ 2) + 1}. ');
      moveText.write(sanMoves[i]);
      if (i < sanMoves.length - 1) moveText.write(' ');
    }

    final pgn =
        '[Event "Opening Explorer"]\n'
        '[Site "ChessEver"]\n'
        '[Date "${DateTime.now().toIso8601String().split('T')[0]}"]\n'
        '[White "White"]\n'
        '[Black "Black"]\n'
        '[Result "*"]\n'
        '\n${moveText.isEmpty ? '*' : '$moveText *'}';

    final whitePlayer = PlayerCard(
      name: 'White',
      federation: '',
      title: '',
      rating: 0,
      countryCode: '',
      team: null,
      fideId: null,
    );

    final blackPlayer = PlayerCard(
      name: 'Black',
      federation: '',
      title: '',
      rating: 0,
      countryCode: '',
      team: null,
      fideId: null,
    );

    final game = GamesTourModel(
      gameId: 'explorer_$timestamp',
      whitePlayer: whitePlayer,
      blackPlayer: blackPlayer,
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.unknown,
      roundId: 'opening_explorer',
      tourId: 'opening_explorer',
      pgn: pgn,
    );

    _resetExplorerState();

    ref.read(chessboardViewFromProviderNew.notifier).state =
        ChessboardView.tour;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => ChessBoardScreenNew(
              currentIndex: 0,
              games: [game],
              hideEventInfo: true,
              showGamebaseButton: false,
              disableGamebaseOverlayByDefault: true,
              startAtLastMove: true,
            ),
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    final container = ProviderScope.containerOf(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kBlack3Color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.br)),
      ),
      constraints: ResponsiveHelper.bottomSheetConstraints,
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: _FilterSheet(scopedPlayer: widget.initialPlayer),
      ),
    );
  }
}

/// Chess board widget for displaying the current position.
class _GamebaseChessBoard extends ConsumerWidget {
  const _GamebaseChessBoard({
    required this.fen,
    required this.boardSize,
    this.isFlipped = false,
  });

  final String fen;
  final double boardSize;
  final bool isFlipped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardSettingsAsync = ref.watch(boardSettingsProviderNew);
    final boardSettings =
        boardSettingsAsync.valueOrNull ?? const BoardSettingsNew();
    final notifier = ref.read(gamebaseExplorerProvider.notifier);

    Chess? position;
    try {
      position = Chess.fromSetup(Setup.parseFen(fen));
    } catch (_) {
      position = null;
    }

    return Container(
      height: boardSize,
      width: boardSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4.br),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4.br),
        child:
            position == null
                ? Chessboard.fixed(
                  size: boardSize,
                  settings: ChessboardSettings(
                    enableCoordinates: true,
                    colorScheme: boardSettings.colorScheme,
                    pieceAssets: boardSettings.pieceAssets,
                  ),
                  orientation: isFlipped ? Side.black : Side.white,
                  fen: fen,
                )
                : Chessboard(
                  size: boardSize,
                  settings: ChessboardSettings(
                    enableCoordinates: true,
                    colorScheme: boardSettings.colorScheme,
                    pieceAssets: boardSettings.pieceAssets,
                    pieceShiftMethod: PieceShiftMethod.tapTwoSquares,
                    autoQueenPromotionOnPremove: false,
                  ),
                  orientation: isFlipped ? Side.black : Side.white,
                  fen: fen,
                  game: GameData(
                    playerSide:
                        position.turn == Side.white
                            ? PlayerSide.white
                            : PlayerSide.black,
                    validMoves: makeLegalMoves(position),
                    sideToMove: position.turn,
                    isCheck: position.isCheck,
                    promotionMove: null,
                    onMove: (NormalMove move, {bool? isDrop, bool? isPremove}) {
                      notifier.makeMove(move.uci);
                    },
                    onPromotionSelection: (_) {},
                  ),
                ),
      ),
    );
  }
}

/// Eval bar for the standalone gamebase explorer, powered by local Stockfish
/// with progressive depth updates via [explorerEvalProvider].
class _ExplorerEvalBar extends ConsumerStatefulWidget {
  const _ExplorerEvalBar({
    required this.fen,
    required this.height,
    required this.width,
    required this.showEngineAnalysis,
    this.isFlipped = false,
  });

  final String fen;
  final double height;
  final double width;
  final bool showEngineAnalysis;
  final bool isFlipped;

  @override
  ConsumerState<_ExplorerEvalBar> createState() => _ExplorerEvalBarState();
}

class _ExplorerEvalBarState extends ConsumerState<_ExplorerEvalBar> {
  String _positionKey(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    if (parts.length < 4) return fen.trim();
    return parts.take(4).join(' ');
  }

  bool _samePosition(String a, String b) => _positionKey(a) == _positionKey(b);

  void _syncEngineState({bool force = false}) {
    ref
        .read(explorerEvalProvider.notifier)
        .setEngineEnabled(
          enabled: widget.showEngineAnalysis,
          fen: widget.fen,
          force: force,
        );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncEngineState(force: true);
    });
  }

  @override
  void didUpdateWidget(covariant _ExplorerEvalBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_samePosition(widget.fen, oldWidget.fen)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncEngineState(force: true);
      });
    } else if (widget.showEngineAnalysis != oldWidget.showEngineAnalysis) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncEngineState();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showEngineAnalysis || widget.fen.isEmpty) {
      return SizedBox(width: widget.width, height: widget.height);
    }

    final evalState = ref.watch(explorerEvalProvider);
    return EvaluationBarWidget(
      width: widget.width,
      height: widget.height,
      isFlipped: widget.isFlipped,
      evaluation: evalState.evaluation,
      mate: evalState.mate,
      isEvaluating: evalState.isEvaluating,
      positionKey: _positionKey(widget.fen),
    );
  }
}

/// Filter sheet for time controls and ratings.
///
/// Uses local draft state and only applies changes when the user taps "Apply".
/// This prevents multiple expensive aggregate requests while toggling controls.
class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({this.scopedPlayer});

  final GamebasePlayer? scopedPlayer;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late GamebaseFilters _draftFilters;
  final TextEditingController _playerSearchController = TextEditingController();
  final FocusNode _playerSearchFocusNode = FocusNode();
  String _playerSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _draftFilters = ref.read(gamebaseExplorerProvider).filters;
    final scopedPlayer = widget.scopedPlayer;
    if (scopedPlayer != null) {
      _draftFilters = _draftFilters.copyWith(
        playerIds: [scopedPlayer.id],
        selectedPlayers: [scopedPlayer],
      );
    }
  }

  @override
  void dispose() {
    _playerSearchController.dispose();
    _playerSearchFocusNode.dispose();
    super.dispose();
  }

  void _toggleTimeControl(TimeControl timeControl) {
    final current = _draftFilters.timeControls;
    if (current.contains(timeControl)) {
      setState(() {
        _draftFilters = _draftFilters.copyWith(timeControls: const []);
      });
      return;
    }
    setState(() {
      _draftFilters = _draftFilters.copyWith(timeControls: [timeControl]);
    });
  }

  void _setRatingRange({int? minRating, int? maxRating}) {
    setState(() {
      _draftFilters = _draftFilters.copyWith(
        minRating: minRating,
        maxRating: maxRating,
      );
    });
  }

  void _setPlayer(GamebasePlayer player) {
    setState(() {
      // Backend currently supports a single player filter.
      _draftFilters = _draftFilters.copyWith(
        playerIds: [player.id],
        selectedPlayers: [player],
      );
      _playerSearchQuery = '';
      _playerSearchController.clear();
    });
    _playerSearchFocusNode.unfocus();
  }

  void _removePlayer(String playerId) {
    final currentIds = List<String>.from(_draftFilters.playerIds);
    final currentPlayers = List<GamebasePlayer>.from(
      _draftFilters.selectedPlayers,
    );
    currentIds.remove(playerId);
    currentPlayers.removeWhere((p) => p.id == playerId);
    setState(() {
      _draftFilters = _draftFilters.copyWith(
        playerIds: currentIds,
        selectedPlayers: currentPlayers,
      );
    });
  }

  void _apply() {
    ref.read(gamebaseExplorerProvider.notifier).updateFilters(_draftFilters);
    Navigator.pop(context);
  }

  bool _isScopedPlayerDraft(GamebaseFilters filters) {
    final scopedPlayer = widget.scopedPlayer;
    if (scopedPlayer == null) return false;
    return filters.playerIds.length == 1 &&
        filters.playerIds.first == scopedPlayer.id &&
        filters.selectedPlayers.length == 1 &&
        filters.selectedPlayers.first.id == scopedPlayer.id;
  }

  bool _hasActiveDraft(GamebaseFilters filters) {
    final hasTimeOrRating =
        filters.timeControls.isNotEmpty ||
        filters.minRating != null ||
        filters.maxRating != null;
    if (widget.scopedPlayer == null) {
      return hasTimeOrRating || filters.playerIds.isNotEmpty;
    }
    return hasTimeOrRating || !_isScopedPlayerDraft(filters);
  }

  void _clearAll() {
    final notifier = ref.read(gamebaseExplorerProvider.notifier);
    final scopedPlayer = widget.scopedPlayer;
    if (scopedPlayer != null) {
      notifier.updateFilters(
        GamebaseFilters(
          playerIds: [scopedPlayer.id],
          selectedPlayers: [scopedPlayer],
        ),
      );
    } else {
      notifier.clearFilters();
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final filters = _draftFilters;
    final hasActiveDraft = _hasActiveDraft(filters);

    return SafeArea(
      top: false,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Padding(
            padding: EdgeInsets.all(16.sp),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Filters',
                      style: TextStyle(
                        color: kWhiteColor,
                        fontSize: 18.f,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (hasActiveDraft)
                      TextButton(
                        onPressed: _clearAll,
                        child: Text(
                          'Clear all',
                          style: TextStyle(
                            color: kPrimaryColor,
                            fontSize: 14.f,
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 16.sp),

                // Time control filters
                Text(
                  'Time Control',
                  style: TextStyle(
                    color: kSecondaryTextColor,
                    fontSize: 12.f,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 8.sp),
                Wrap(
                  spacing: 8.sp,
                  children:
                      TimeControl.values.map((tc) {
                        final isSelected = filters.timeControls.contains(tc);
                        return FilterChip(
                          label: Text(tc.displayName),
                          selected: isSelected,
                          onSelected: (_) => _toggleTimeControl(tc),
                          selectedColor: kPrimaryColor.withValues(alpha: 0.2),
                          checkmarkColor: kPrimaryColor,
                          labelStyle: TextStyle(
                            color: isSelected ? kPrimaryColor : kWhiteColor,
                            fontSize: 12.f,
                          ),
                          backgroundColor: kBlack2Color,
                          side: BorderSide(
                            color: isSelected ? kPrimaryColor : kDividerColor,
                          ),
                        );
                      }).toList(),
                ),
                SizedBox(height: 16.sp),

                // Rating range
                Text(
                  'Rating Range',
                  style: TextStyle(
                    color: kSecondaryTextColor,
                    fontSize: 12.f,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 8.sp),
                Row(
                  children: [
                    Expanded(
                      child: _RatingDropdown(
                        value: filters.minRating,
                        hint: 'Min',
                        onChanged:
                            (value) => _setRatingRange(
                              minRating: value,
                              maxRating: filters.maxRating,
                            ),
                      ),
                    ),
                    SizedBox(width: 16.sp),
                    Text(
                      'to',
                      style: TextStyle(
                        color: kSecondaryTextColor,
                        fontSize: 14.f,
                      ),
                    ),
                    SizedBox(width: 16.sp),
                    Expanded(
                      child: _RatingDropdown(
                        value: filters.maxRating,
                        hint: 'Max',
                        onChanged:
                            (value) => _setRatingRange(
                              minRating: filters.minRating,
                              maxRating: value,
                            ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 24.sp),

                if (widget.scopedPlayer == null) ...[
                  // Player search (hidden in player-scoped explorer)
                  Text(
                    'Player',
                    style: TextStyle(
                      color: kSecondaryTextColor,
                      fontSize: 12.f,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 8.sp),
                  TextField(
                    controller: _playerSearchController,
                    focusNode: _playerSearchFocusNode,
                    style: TextStyle(color: kWhiteColor, fontSize: 13.f),
                    decoration: InputDecoration(
                      hintText: 'Search player',
                      hintStyle: TextStyle(
                        color: kSecondaryTextColor.withValues(alpha: 0.65),
                        fontSize: 13.f,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 18.sp,
                        color: kSecondaryTextColor,
                      ),
                      filled: true,
                      fillColor: kBlack2Color,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.br),
                        borderSide: BorderSide(color: kDividerColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.br),
                        borderSide: BorderSide(color: kDividerColor),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.br),
                        borderSide: BorderSide(color: kPrimaryColor),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12.sp,
                        vertical: 10.sp,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _playerSearchQuery = value.trim();
                      });
                    },
                  ),
                  if (_playerSearchQuery.length >= 2) ...[
                    SizedBox(height: 8.sp),
                    _PlayerSearchResults(
                      query: _playerSearchQuery,
                      onPlayerSelected: _setPlayer,
                    ),
                  ],
                ],
                if (widget.scopedPlayer == null &&
                    filters.selectedPlayers.isNotEmpty) ...[
                  SizedBox(height: 10.sp),
                  Wrap(
                    spacing: 8.sp,
                    runSpacing: 8.sp,
                    children: [
                      for (final player in filters.selectedPlayers)
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10.sp,
                            vertical: 6.sp,
                          ),
                          decoration: BoxDecoration(
                            color: kPrimaryColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(24.br),
                            border: Border.all(
                              color: kPrimaryColor.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                player.titleAndName,
                                style: TextStyle(
                                  color: kWhiteColor,
                                  fontSize: 12.f,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(width: 6.sp),
                              GestureDetector(
                                onTap: () => _removePlayer(player.id),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 14.sp,
                                  color: kWhiteColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ] else ...[
                  SizedBox(height: 4.sp),
                ],
                SizedBox(height: 24.sp),

                // Apply button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _apply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      padding: EdgeInsets.symmetric(vertical: 12.sp),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.br),
                      ),
                    ),
                    child: Text(
                      'Apply',
                      style: TextStyle(
                        color: kWhiteColor,
                        fontSize: 14.f,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerSearchResults extends ConsumerWidget {
  const _PlayerSearchResults({
    required this.query,
    required this.onPlayerSelected,
  });

  final String query;
  final ValueChanged<GamebasePlayer> onPlayerSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(playerSearchProvider(query));

    return Container(
      constraints: BoxConstraints(maxHeight: 200.h),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(8.br),
        border: Border.all(color: kDividerColor),
      ),
      child: results.when(
        data: (players) {
          if (players.isEmpty) {
            return Padding(
              padding: EdgeInsets.all(12.sp),
              child: Text(
                'No players found',
                style: TextStyle(color: kSecondaryTextColor, fontSize: 12.f),
              ),
            );
          }
          return ListView.separated(
            shrinkWrap: true,
            itemCount: players.length,
            separatorBuilder:
                (_, __) => Divider(height: 1, color: kDividerColor),
            itemBuilder: (context, index) {
              final player = players[index];
              return ListTile(
                dense: true,
                onTap: () => onPlayerSelected(player),
                title: Text(
                  player.titleAndName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: kWhiteColor, fontSize: 13.f),
                ),
                subtitle: Text(
                  '${player.fed}${player.highestRating != null ? ' • ${player.highestRating}' : ''}',
                  style: TextStyle(color: kSecondaryTextColor, fontSize: 11.f),
                ),
                trailing: Icon(
                  Icons.add_rounded,
                  size: 18.sp,
                  color: kPrimaryColor,
                ),
              );
            },
          );
        },
        loading:
            () => Padding(
              padding: EdgeInsets.all(12.sp),
              child: Row(
                children: [
                  SizedBox(
                    width: 16.sp,
                    height: 16.sp,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: kPrimaryColor,
                    ),
                  ),
                  SizedBox(width: 10.sp),
                  Text(
                    'Searching...',
                    style: TextStyle(
                      color: kSecondaryTextColor,
                      fontSize: 12.f,
                    ),
                  ),
                ],
              ),
            ),
        error:
            (_, __) => Padding(
              padding: EdgeInsets.all(12.sp),
              child: Text(
                'Search failed',
                style: TextStyle(color: kRedColor, fontSize: 12.f),
              ),
            ),
      ),
    );
  }
}

/// Dropdown for rating selection.
class _RatingDropdown extends StatelessWidget {
  const _RatingDropdown({
    required this.value,
    required this.hint,
    required this.onChanged,
  });

  final int? value;
  final String hint;
  final ValueChanged<int?> onChanged;

  static const List<int?> _ratings = [
    null,
    1000,
    1200,
    1400,
    1600,
    1800,
    2000,
    2200,
    2400,
    2600,
    2800,
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.sp),
      decoration: BoxDecoration(
        color: kBlack2Color,
        borderRadius: BorderRadius.circular(8.br),
        border: Border.all(color: kDividerColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: value,
          hint: Text(
            hint,
            style: TextStyle(color: kSecondaryTextColor, fontSize: 14.f),
          ),
          dropdownColor: kBlack2Color,
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: kSecondaryTextColor),
          items:
              _ratings.map((rating) {
                return DropdownMenuItem<int?>(
                  value: rating,
                  child: Text(
                    rating?.toString() ?? 'Any',
                    style: TextStyle(color: kWhiteColor, fontSize: 14.f),
                  ),
                );
              }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

/// Compact engine analysis lines displayed above the move statistics.
/// Shows up to 3 Stockfish PV lines, each as a single horizontal row
/// with an eval badge and SAN moves.
class _ExplorerEngineLines extends ConsumerWidget {
  const _ExplorerEngineLines();
  static const int _kMaxRows = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final evalState = ref.watch(explorerEvalProvider);
    final pvLines = evalState.pvLines;

    final useFigurine = ref.watch(
      boardSettingsProviderNew.select(
        (s) => s.valueOrNull?.useFigurine ?? false,
      ),
    );
    final pieceAssets = ref.watch(
      boardSettingsProviderNew.select(
        (s) =>
            s.valueOrNull?.pieceAssets ?? const BoardSettingsNew().pieceAssets,
      ),
    );

    final baseFen = ref.watch(
      gamebaseExplorerProvider.select((s) => s.currentFen),
    );
    final fenParts = baseFen.split(' ');
    final isWhiteToMove = fenParts.length > 1 ? fenParts[1] == 'w' : true;
    final startMoveNumber =
        fenParts.length > 5 ? (int.tryParse(fenParts[5]) ?? 1) : 1;

    final lines = pvLines.take(_kMaxRows).toList();
    final notifier = ref.read(gamebaseExplorerProvider.notifier);
    final uciRegex = RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _kMaxRows; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              color: kDividerColor.withValues(alpha: 0.3),
              indent: 12.sp,
              endIndent: 12.sp,
            ),
          if (i < lines.length)
            _EngineLine(
              line: lines[i],
              lineIndex: i,
              isWhiteToMove: isWhiteToMove,
              startMoveNumber: startMoveNumber,
              useFigurine: useFigurine,
              pieceAssets: pieceAssets,
              onTap: () {
                if (lines[i].uciMoves.isEmpty) return;
                final firstUci = lines[i].uciMoves.first.trim().toLowerCase();
                if (!uciRegex.hasMatch(firstUci)) return;
                notifier.makeMove(firstUci);
              },
            )
          else
            _EngineLinePlaceholder(
              isPrimary: i == 0,
              isEvaluating: evalState.isEvaluating,
            ),
        ],
        Divider(color: kDividerColor, height: 1),
      ],
    );
  }
}

class _EngineLinePlaceholder extends StatelessWidget {
  const _EngineLinePlaceholder({
    required this.isPrimary,
    required this.isEvaluating,
  });

  final bool isPrimary;
  final bool isEvaluating;

  @override
  Widget build(BuildContext context) {
    final label = ' ';
    final badgeText = isEvaluating ? '...' : '-';

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5.sp, horizontal: 12.sp),
      child: Row(
        children: [
          Container(
            width: 44.w,
            padding: EdgeInsets.symmetric(vertical: 2.sp),
            decoration: BoxDecoration(
              color: kSecondaryTextColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3.br),
            ),
            child: Text(
              badgeText,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: kWhiteColor.withValues(
                  alpha: isEvaluating ? 0.35 : 0.18,
                ),
                fontSize: 11.f,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(width: 8.sp),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: kWhiteColor.withValues(alpha: isPrimary ? 0.65 : 0.18),
                fontSize: 12.f,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single engine line row: eval badge + SAN move text.
class _EngineLine extends StatelessWidget {
  const _EngineLine({
    required this.line,
    required this.lineIndex,
    required this.isWhiteToMove,
    required this.startMoveNumber,
    required this.useFigurine,
    required this.pieceAssets,
    this.onTap,
  });

  final ExplorerPvLine line;
  final int lineIndex;
  final bool isWhiteToMove;
  final int startMoveNumber;
  final bool useFigurine;
  final PieceAssets pieceAssets;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final evalText = line.displayEval;

    // Eval badge: white bg for white advantage, dark for black, neutral for 0.0.
    final bool isWhiteWinning =
        (line.mate != null && line.mate! > 0) ||
        (line.evaluation != null && line.evaluation! > 0);
    final bool isBlackWinning =
        (line.mate != null && line.mate! < 0) ||
        (line.evaluation != null && line.evaluation! < 0);

    Color evalBgColor;
    Color evalTextColor;
    if (isWhiteWinning) {
      evalBgColor = kWhiteColor;
      evalTextColor = kBlack2Color;
    } else if (isBlackWinning) {
      evalBgColor = kDividerColor;
      evalTextColor = kWhiteColor;
    } else {
      evalBgColor = kSecondaryTextColor.withValues(alpha: 0.3);
      evalTextColor = kWhiteColor;
    }

    final moveText = _formatMoveText();
    final moveStyle = TextStyle(
      color: kWhiteColor.withValues(alpha: lineIndex == 0 ? 0.9 : 0.6),
      fontSize: 12.f,
      fontWeight: lineIndex == 0 ? FontWeight.w500 : FontWeight.w400,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 5.sp, horizontal: 12.sp),
          child: Row(
            children: [
              // Eval badge
              Container(
                width: 44.w,
                padding: EdgeInsets.symmetric(vertical: 2.sp),
                decoration: BoxDecoration(
                  color: evalBgColor,
                  borderRadius: BorderRadius.circular(3.br),
                ),
                child: Text(
                  evalText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: evalTextColor,
                    fontSize: 11.f,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              SizedBox(width: 8.sp),
              // Moves
              Expanded(
                child:
                    useFigurine
                        ? RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            children: buildFigurineSpans(
                              text: moveText,
                              pieceAssets: pieceAssets,
                              style: moveStyle,
                              pieceSize: 14.f,
                            ),
                          ),
                        )
                        : Text(
                          moveText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: moveStyle,
                        ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatMoveText() {
    if (line.sanMoves.isEmpty) return '';
    final buffer = StringBuffer();
    var moveNum = startMoveNumber;
    var isWhite = isWhiteToMove;

    for (var i = 0; i < line.sanMoves.length; i++) {
      if (isWhite) {
        if (i > 0) buffer.write(' ');
        buffer.write('$moveNum.');
      } else if (i == 0) {
        buffer.write('$moveNum...');
      } else {
        buffer.write(' ');
      }
      buffer.write(line.sanMoves[i]);

      if (!isWhite) moveNum++;
      isWhite = !isWhite;
    }
    return buffer.toString();
  }
}
