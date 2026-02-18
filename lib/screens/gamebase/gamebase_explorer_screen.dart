import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
import 'package:chessever2/screens/gamebase/providers/gamebase_providers.dart';
import 'package:chessever2/screens/gamebase/widgets/widgets.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';

/// Main screen for exploring the Gamebase opening database.
/// Displays a chess board, move statistics, and navigation controls.
class GamebaseExplorerScreen extends ConsumerStatefulWidget {
  const GamebaseExplorerScreen({super.key});

  @override
  ConsumerState<GamebaseExplorerScreen> createState() =>
      _GamebaseExplorerScreenState();
}

class _GamebaseExplorerScreenState
    extends ConsumerState<GamebaseExplorerScreen> {
  @override
  void initState() {
    super.initState();

    // Riverpod best practice: never modify providers synchronously in widget
    // lifecycles (can happen while the widget tree is building).
    // Defer to post-frame to keep provider updates safe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Ensure we have a valid starting position and kick off the initial fetch.
      // Without this, the explorer can render with an empty FEN and never load stats.
      final state = ref.read(gamebaseExplorerProvider);
      final notifier = ref.read(gamebaseExplorerProvider.notifier);

      if (state.currentFen.trim().isEmpty) {
        notifier.goToStart();
      } else if (state.moveAggregates.isEmpty) {
        // If we ever add an "open explorer at FEN" entrypoint, make sure it loads.
        notifier.refresh();
      }
    });
  }

  static final double _evalBarWidth = 20.sp;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gamebaseExplorerProvider);
    final screenWidth = MediaQuery.of(context).size.width;
    final boardSize =
        screenWidth - 48.sp - _evalBarWidth - 4.sp; // padding + eval bar + gap

    return ScreenWrapper(
      child: Scaffold(
        backgroundColor: kBlack2Color,
        appBar: _buildAppBar(context),
        body: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: Column(
              children: [
                // Chess board section with eval bar
                Padding(
                  padding: EdgeInsets.all(24.sp),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ExplorerEvalBar(
                        fen: state.currentFen,
                        height: boardSize,
                        width: _evalBarWidth,
                      ),
                      SizedBox(width: 4.sp),
                      _GamebaseChessBoard(
                        fen: state.currentFen,
                        boardSize: boardSize,
                      ),
                    ],
                  ),
                ),

                // Navigation controls
                _NavigationControls(
                  canGoBack: state.canGoBack,
                  canGoForward: state.canGoForward,
                  onGoToStart:
                      () =>
                          ref
                              .read(gamebaseExplorerProvider.notifier)
                              .goToStart(),
                  onGoBack:
                      () =>
                          ref.read(gamebaseExplorerProvider.notifier).goBack(),
                  onGoForward:
                      () =>
                          ref
                              .read(gamebaseExplorerProvider.notifier)
                              .goForward(),
                  onGoToEnd:
                      () =>
                          ref.read(gamebaseExplorerProvider.notifier).goToEnd(),
                  onReset:
                      () => ref.read(gamebaseExplorerProvider.notifier).reset(),
                ),

                SizedBox(height: 8.sp),

                // Move statistics panel
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: kBlack3Color,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(16.br),
                      ),
                    ),
                    child: const MoveStatisticsPanel(),
                  ),
                ),
              ],
            ),
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
      title: Text(
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
              'Analyze',
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
  const _GamebaseChessBoard({required this.fen, required this.boardSize});

  final String fen;
  final double boardSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardSettingsAsync = ref.watch(boardSettingsProviderNew);
    final boardSettings =
        boardSettingsAsync.valueOrNull ?? const BoardSettingsNew();

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
        child: AbsorbPointer(
          child: Chessboard.fixed(
            size: boardSize,
            settings: ChessboardSettings(
              enableCoordinates: true,
              // Use theme colors from settings with our custom app colors
              colorScheme: boardSettings.colorScheme,
              // Use piece set from settings
              pieceAssets: boardSettings.pieceAssets,
            ),
            orientation: Side.white,
            fen: fen,
          ),
        ),
      ),
    );
  }
}

/// Eval bar for the standalone gamebase explorer, powered by
/// [gameCardEvalWithStockfishFallbackProvider] (local → Supabase → Stockfish depth 8).
class _ExplorerEvalBar extends ConsumerWidget {
  const _ExplorerEvalBar({
    required this.fen,
    required this.height,
    required this.width,
  });

  final String fen;
  final double height;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (fen.isEmpty) {
      return SizedBox(width: width, height: height);
    }

    final evalAsync = ref.watch(gameCardEvalWithStockfishFallbackProvider(fen));

    return evalAsync.when(
      data: (cloud) {
        final pv = cloud.pvs.firstOrNull;
        if (pv == null) {
          return EvaluationBarWidget(
            width: width,
            height: height,
            isFlipped: false,
            evaluation: null,
            mate: null,
            isEvaluating: true,
          );
        }

        final normalized = _normalizePvToWhitePerspective(pv);
        final eval = normalized.eval;
        final mate =
            (normalized.isMate && normalized.mate != 0)
                ? normalized.mate
                : null;

        return EvaluationBarWidget(
          width: width,
          height: height,
          isFlipped: false,
          evaluation: eval,
          mate: mate,
          isEvaluating: false,
          positionKey: fen,
        );
      },
      loading:
          () => EvaluationBarWidget(
            width: width,
            height: height,
            isFlipped: false,
            evaluation: null,
            mate: null,
            isEvaluating: true,
          ),
      error: (_, __) => SizedBox(width: width, height: height),
    );
  }
}

({double eval, bool isMate, int mate}) _normalizePvToWhitePerspective(Pv pv) {
  final sign = pv.whitePerspective ? 1 : -1;
  final isMate = pv.isMate && pv.mate != null;
  final normalizedMate = (pv.mate ?? 0) * sign;
  final normalizedEval = (pv.cp * sign) / 100.0;
  return (eval: normalizedEval, isMate: isMate, mate: normalizedMate);
}

/// Navigation controls for move history.
class _NavigationControls extends StatelessWidget {
  const _NavigationControls({
    required this.canGoBack,
    required this.canGoForward,
    required this.onGoToStart,
    required this.onGoBack,
    required this.onGoForward,
    required this.onGoToEnd,
    required this.onReset,
  });

  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onGoToStart;
  final VoidCallback onGoBack;
  final VoidCallback onGoForward;
  final VoidCallback onGoToEnd;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.sp),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _NavButton(
            icon: Icons.keyboard_double_arrow_left,
            onPressed: canGoBack ? onGoToStart : null,
            tooltip: 'Go to start',
          ),
          SizedBox(width: 8.sp),
          _NavButton(
            icon: Icons.chevron_left,
            onPressed: canGoBack ? onGoBack : null,
            tooltip: 'Previous move',
          ),
          SizedBox(width: 8.sp),
          _NavButton(icon: Icons.refresh, onPressed: onReset, tooltip: 'Reset'),
          SizedBox(width: 8.sp),
          _NavButton(
            icon: Icons.chevron_right,
            onPressed: canGoForward ? onGoForward : null,
            tooltip: 'Next move',
          ),
          SizedBox(width: 8.sp),
          _NavButton(
            icon: Icons.keyboard_double_arrow_right,
            onPressed: canGoForward ? onGoToEnd : null,
            tooltip: 'Go to end',
          ),
        ],
      ),
    );
  }
}

/// Individual navigation button.
class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8.br),
          child: Container(
            width: 44.w,
            height: 44.h,
            decoration: BoxDecoration(
              color:
                  isEnabled
                      ? kPrimaryColor.withValues(alpha: 0.1)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(8.br),
              border: Border.all(
                color:
                    isEnabled
                        ? kPrimaryColor.withValues(alpha: 0.3)
                        : kDividerColor,
              ),
            ),
            child: Icon(
              icon,
              size: 24.ic,
              color: isEnabled ? kPrimaryColor : kSecondaryTextColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Filter sheet for time controls, ratings, and players.
class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gamebaseExplorerProvider);
    final filters = state.filters;

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
                if (state.hasActiveFilters)
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
                      onSelected: (_) {
                        ref
                            .read(gamebaseExplorerProvider.notifier)
                            .toggleTimeControl(tc);
                      },
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
                    onChanged: (value) {
                      ref
                          .read(gamebaseExplorerProvider.notifier)
                          .setRatingRange(value, filters.maxRating);
                    },
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
                    onChanged: (value) {
                      ref
                          .read(gamebaseExplorerProvider.notifier)
                          .setRatingRange(filters.minRating, value);
                    },
                  ),
                ),
              ],
            ),
            SizedBox(height: 24.sp),

            // Apply button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
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
