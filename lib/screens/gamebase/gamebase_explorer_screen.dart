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
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';

/// Main screen for exploring the Gamebase opening database.
/// Displays a chess board, move statistics, and navigation controls.
class GamebaseExplorerScreen extends ConsumerStatefulWidget {
  const GamebaseExplorerScreen({super.key, this.initialPlayer});

  /// When non-null, the explorer opens pre-filtered to this player's games.
  final GamebasePlayer? initialPlayer;

  @override
  ConsumerState<GamebaseExplorerScreen> createState() =>
      _GamebaseExplorerScreenState();
}

class _GamebaseExplorerScreenState
    extends ConsumerState<GamebaseExplorerScreen> {
  bool _isFlipped = false;
  Timer? _backwardLongPressTimer;
  Timer? _forwardLongPressTimer;

  @override
  void initState() {
    super.initState();

    // Riverpod best practice: never modify providers synchronously in widget
    // lifecycles (can happen while the widget tree is building).
    // Defer to post-frame to keep provider updates safe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final notifier = ref.read(gamebaseExplorerProvider.notifier);

      if (widget.initialPlayer != null) {
        notifier.initializeWithPlayer(widget.initialPlayer!);
      } else {
        // Ensure we have a valid starting position and kick off the initial fetch.
        // Without this, the explorer can render with an empty FEN and never load stats.
        final state = ref.read(gamebaseExplorerProvider);

        if (state.currentFen.trim().isEmpty) {
          notifier.goToStart();
        } else if (state.moveAggregates.isEmpty) {
          notifier.refresh();
        }
      }
    });
  }

  @override
  void dispose() {
    _stopLongPressBackward();
    _stopLongPressForward();
    // Reset the full explorer state when leaving so stale moves/position
    // don't persist into the next visit or bleed into the chessboard overlay.
    ref.read(gamebaseExplorerProvider.notifier).reset();
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
    final showEngineAnalysis = ref.watch(
      engineSettingsProviderNew.select(
        (s) => s.valueOrNull?.showEngineAnalysis ?? true,
      ),
    );

    final state = ref.watch(gamebaseExplorerProvider);

    return ScreenWrapper(
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
      leading: IconButton(
        icon: Icon(Icons.arrow_back, size: 24.ic),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title:
          state.filters.selectedPlayers.isNotEmpty
              ? Column(
                mainAxisSize: MainAxisSize.min,
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
              ),
      actions: [
        if (state.hasActiveFilters)
          IconButton(
            icon: Icon(Icons.filter_alt_off, size: 24.ic),
            onPressed:
                () =>
                    ref.read(gamebaseExplorerProvider.notifier).clearFilters(),
            tooltip: 'Clear filters',
          ),
        IconButton(
          icon: Icon(Icons.tune, size: 24.ic),
          onPressed: () => _showFilterSheet(context),
          tooltip: 'Filters',
        ),
        GestureDetector(
          onTap: () => _openAnalysis(context),
          child: Container(
            margin: EdgeInsets.only(right: 12.sp),
            padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 6.sp),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: kBlack3Color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16.br)),
      ),
      constraints: ResponsiveHelper.bottomSheetConstraints,
      builder: (context) => const _FilterSheet(),
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
  void _syncEngineState({bool force = false}) {
    ref
        .read(explorerEvalProvider.notifier)
        .setEngineEnabled(
          enabled: widget.showEngineAnalysis,
          fen: widget.fen,
          force: force,
        );
  }

  bool _shouldTriggerEvaluation(ExplorerEvalState evalState) {
    if (!widget.showEngineAnalysis || widget.fen.isEmpty) return false;
    if (evalState.fen != widget.fen) return true;
    return !evalState.isEvaluating && evalState.pvLines.isEmpty;
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
    if (widget.fen != oldWidget.fen ||
        widget.showEngineAnalysis != oldWidget.showEngineAnalysis) {
      _syncEngineState(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showEngineAnalysis || widget.fen.isEmpty) {
      return SizedBox(width: widget.width, height: widget.height);
    }

    final evalState = ref.watch(explorerEvalProvider);
    if (_shouldTriggerEvaluation(evalState)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncEngineState(force: true);
      });
    }

    return EvaluationBarWidget(
      width: widget.width,
      height: widget.height,
      isFlipped: widget.isFlipped,
      evaluation: evalState.evaluation,
      mate: evalState.mate,
      isEvaluating: evalState.isEvaluating,
      positionKey: widget.fen,
    );
  }
}

/// Filter sheet for time controls and ratings.
///
/// Uses local draft state and only applies changes when the user taps "Apply".
/// This prevents multiple expensive aggregate requests while toggling controls.
class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet();

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late GamebaseFilters _draftFilters;

  @override
  void initState() {
    super.initState();
    _draftFilters = ref.read(gamebaseExplorerProvider).filters;
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

  void _apply() {
    ref.read(gamebaseExplorerProvider.notifier).updateFilters(_draftFilters);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final filters = _draftFilters;
    final hasActiveDraft =
        filters.timeControls.isNotEmpty ||
        filters.minRating != null ||
        filters.maxRating != null ||
        filters.playerIds.isNotEmpty;

    return SafeArea(
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
                    onPressed: () {
                      ref
                          .read(gamebaseExplorerProvider.notifier)
                          .clearFilters();
                      Navigator.pop(context);
                    },
                    child: Text(
                      'Clear all',
                      style: TextStyle(color: kPrimaryColor, fontSize: 14.f),
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
                  style: TextStyle(color: kSecondaryTextColor, fontSize: 14.f),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final evalState = ref.watch(explorerEvalProvider);
    final pvLines = evalState.pvLines;

    if (pvLines.isEmpty) {
      if (!evalState.isEvaluating) return const SizedBox.shrink();
      final depthLabel =
          evalState.depth > 0
              ? 'D:${evalState.depth.toString().padLeft(2, '0')}'
              : '...';
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(vertical: 5.sp, horizontal: 12.sp),
            child: Row(
              children: [
                Container(
                  width: 44.w,
                  padding: EdgeInsets.symmetric(vertical: 2.sp),
                  decoration: BoxDecoration(
                    color: kSecondaryTextColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(3.br),
                  ),
                  child: Text(
                    '...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: kWhiteColor,
                      fontSize: 11.f,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                SizedBox(width: 8.sp),
                Expanded(
                  child: Text(
                    'Analyzing engine line ($depthLabel)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: kWhiteColor.withValues(alpha: 0.65),
                      fontSize: 12.f,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(color: kDividerColor, height: 1),
        ],
      );
    }

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

    final explorerState = ref.watch(gamebaseExplorerProvider);
    final baseFen = explorerState.currentFen;
    final fenParts = baseFen.split(' ');
    final isWhiteToMove = fenParts.length > 1 ? fenParts[1] == 'w' : true;
    final startMoveNumber =
        fenParts.length > 5 ? (int.tryParse(fenParts[5]) ?? 1) : 1;

    final lines = pvLines.take(3).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              color: kDividerColor.withValues(alpha: 0.3),
              indent: 12.sp,
              endIndent: 12.sp,
            ),
          _EngineLine(
            line: lines[i],
            lineIndex: i,
            isWhiteToMove: isWhiteToMove,
            startMoveNumber: startMoveNumber,
            useFigurine: useFigurine,
            pieceAssets: pieceAssets,
          ),
        ],
        Divider(color: kDividerColor, height: 1),
      ],
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
  });

  final ExplorerPvLine line;
  final int lineIndex;
  final bool isWhiteToMove;
  final int startMoveNumber;
  final bool useFigurine;
  final PieceAssets pieceAssets;

  @override
  Widget build(BuildContext context) {
    final evalText = line.displayEval;

    // Eval badge: white bg for white advantage, dark for black, muted for equal.
    final bool isWhiteWinning =
        (line.mate != null && line.mate! > 0) ||
        (line.evaluation != null && line.evaluation! > 0.2);
    final bool isBlackWinning =
        (line.mate != null && line.mate! < 0) ||
        (line.evaluation != null && line.evaluation! < -0.2);

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

    return Padding(
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
