import 'dart:ui' show ImageFilter;
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/figurine_notation.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart' hide ShimmerEffect;
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:intl/intl.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/responsive_helper.dart';
import '../models/models.dart';
import '../providers/explorer_game_focus_provider.dart';
import '../providers/gamebase_explorer_state.dart';
import '../providers/gamebase_providers.dart';
import '../utils/explorer_move_sort.dart';
import 'explorer_game_card.dart';
import 'position_games_sheet.dart';

const double _kMoveColumnWidth = 74;
const double _kGamesColumnWidth = 84;
const double _kLastColumnWidth = 56;
const double _kColumnGap = 6;

/// Free users see explorer aggregates up to and including the 10th full move
/// (ply 20). `currentMoveNumber` is `ply + 1`, so anything above 20 means the
/// current position is *past* move 10 and premium is required.
const int kFreeExplorerMoveNumberLimit = 20;

/// When this many games (or fewer) remain in the explored position, the panel
/// appends an inline games section under the move table (Trello #984).
const int kExplorerInlineGamesLimit = 10;

/// Empty state for the move table.
///
/// Mirrors the desktop explorer's `_ExplorerEmpty`: an icon, a title that
/// states the outcome, and a line explaining what it means, so a deep or rare
/// position does not read as a broken lookup. Collapses to just the text when
/// the panel is short (the swipe panel can be very short in landscape).
class _ExplorerEmpty extends StatelessWidget {
  const _ExplorerEmpty({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight;
        final compact = maxHeight.isFinite && maxHeight < 132;
        final ultraCompact = maxHeight.isFinite && maxHeight < 76;

        return Center(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: (compact ? 16 : 24).sp,
              vertical: (ultraCompact ? 6 : (compact ? 10 : 24)).sp,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 360.w),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!ultraCompact) ...[
                    Icon(
                      Icons.menu_book_outlined,
                      size: (compact ? 18 : 24).ic,
                      color: context.colors.textSecondary,
                    ),
                    SizedBox(height: (compact ? 6 : 10).sp),
                  ],
                  Text(
                    title,
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.colors.textPrimary,
                      fontSize: (compact ? 12 : 13).f,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: (compact ? 2 : 4).sp),
                  Text(
                    message,
                    maxLines: compact ? 1 : 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: (compact ? 10.5 : 11).f,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tappable column header. Cycles ascending -> descending -> unsorted, the
/// same three states the desktop header cycles through. Touch has no hover,
/// so the idle affordance is a permanently dimmed sort glyph rather than the
/// desktop's hover-revealed one.
class _SortHeader extends StatelessWidget {
  const _SortHeader({
    required this.label,
    required this.field,
    required this.align,
    required this.sort,
    required this.onSort,
    this.color,
  });

  final String label;
  final ExplorerMoveSortField field;
  final TextAlign align;
  final ExplorerMoveSort? sort;
  final ValueChanged<ExplorerMoveSortField> onSort;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final active = sort?.field == field;
    final ascending = sort?.ascending ?? true;
    final rightAligned = align == TextAlign.right;

    final children = <Widget>[
      Flexible(
        child: Text(
          label,
          textAlign: align,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color:
                active
                    ? context.colors.textPrimary
                    : (color ?? context.colors.textSecondary),
            fontSize: 11.f,
            fontWeight: active ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
      SizedBox(width: 2.sp),
      Icon(
        active
            ? (ascending
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded)
            : Icons.unfold_more_rounded,
        size: 11.ic,
        color:
            active
                ? kPrimaryColor
                : context.colors.textSecondary.withValues(alpha: 0.45),
      ),
    ];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSort(field),
      child: Row(
        mainAxisAlignment:
            rightAligned ? MainAxisAlignment.end : MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: rightAligned ? children.reversed.toList() : children,
      ),
    );
  }
}

/// Panel displaying move statistics for the current position.
/// Shows each possible move with game count and win/draw/loss bar.
class MoveStatisticsPanel extends HookConsumerWidget {
  const MoveStatisticsPanel({super.key, this.onMove});

  /// Optional handler for move taps. When supplied, taps invoke this callback
  /// instead of advancing the gamebase explorer's internal state — used when
  /// embedding the panel in the chess board screen so taps play on the user's
  /// game rather than diverging into the explorer's standalone exploration.
  final void Function(String uci)? onMove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gamebaseExplorerProvider);
    final hasStaleData = state.moveAggregates.isNotEmpty;

    // Column ordering is view state: it survives navigation between positions
    // (like desktop) but never leaves this panel.
    final sort = useState<ExplorerMoveSort?>(null);
    void cycleSort(ExplorerMoveSortField field) {
      sort.value = ExplorerMoveSort.cycle(sort.value, field);
    }

    final sortedAggregates = applyExplorerMoveSort(
      state.moveAggregates,
      sort.value,
      state.currentFen,
    );

    final isSubscribed = ref.watch(
      subscriptionProvider.select((s) => s.isSubscribed),
    );
    // Mirror `requirePremiumGuard`: bypass in debug so engineers can exercise
    // deep positions without a live RevenueCat subscription.
    final pastFreeLimit =
        state.currentMoveNumber > kFreeExplorerMoveNumberLimit;
    final showGate = pastFreeLimit && !isSubscribed && !kDebugMode;
    // True when the current position is the last free step — the next ply
    // would land past move 10. Used to paywall *before* navigating into the
    // gated zone, rather than letting the user advance and then blurring the
    // panel behind them.
    final nextStepCrossesLimit =
        !isSubscribed &&
        !kDebugMode &&
        state.currentMoveNumber >= kFreeExplorerMoveNumberLimit;

    // First load (or a position change that cleared the table) shows the same
    // header+rows scaffold with shimmering skeleton rows instead of a centered
    // spinner — keeps the layout stable and matches the app's shimmer style.
    final showSkeleton = state.isLoading && !hasStaleData && !showGate;

    if (state.error != null && !showGate) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(16.sp),
          child: Text(
            state.error!,
            style: TextStyle(color: kRedColor, fontSize: 14.f),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (state.moveAggregates.isEmpty && !showGate && !state.isLoading) {
      // Match the desktop explorer's wording. "No games found" reads like a
      // failure; the position simply has no indexed games, which is the
      // normal outcome once a line runs past what the database covers.
      return const _ExplorerEmpty(
        title: 'No games match this position',
        message:
            'No master/online games are indexed for the position on the board.',
      );
    }

    final Widget mainContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.isLoading)
          LinearProgressIndicator(
            minHeight: 2,
            color: context.colors.textPrimary,
            backgroundColor: Colors.transparent,
          ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 6.sp),
          child: Row(
            children: [
              SizedBox(
                width: _kMoveColumnWidth.w,
                child: _SortHeader(
                  label: 'Move',
                  field: ExplorerMoveSortField.move,
                  align: TextAlign.left,
                  sort: sort.value,
                  onSort: cycleSort,
                ),
              ),
              SizedBox(width: _kColumnGap.sp),
              Expanded(
                child: _SortHeader(
                  label: 'Score',
                  field: ExplorerMoveSortField.score,
                  align: TextAlign.center,
                  sort: sort.value,
                  onSort: cycleSort,
                ),
              ),
              SizedBox(width: _kColumnGap.sp),
              SizedBox(
                width: _kGamesColumnWidth.w,
                child: _SortHeader(
                  label: 'Games',
                  field: ExplorerMoveSortField.games,
                  align: TextAlign.right,
                  sort: sort.value,
                  onSort: cycleSort,
                  color: kPrimaryColor,
                ),
              ),
              SizedBox(width: _kColumnGap.sp),
              SizedBox(
                width: _kLastColumnWidth.w,
                child: _SortHeader(
                  label: 'Last',
                  field: ExplorerMoveSortField.last,
                  align: TextAlign.right,
                  sort: sort.value,
                  onSort: cycleSort,
                ),
              ),
            ],
          ),
        ),
        Divider(color: context.colors.divider, height: 1),
        // Move list
        Expanded(
          child:
              showSkeleton
                  ? Skeletonizer(
                    enabled: true,
                    // Match the app-wide loading shimmer: a low-alpha, inactive
                    // grey sweep (see `chess_board_screen_new.dart` variant cards).
                    effect: ShimmerEffect(
                      baseColor: context.colors.textPrimary.withValues(
                        alpha: 0.05,
                      ),
                      highlightColor: context.colors.textPrimary.withValues(
                        alpha: 0.1,
                      ),
                      duration: const Duration(milliseconds: 1500),
                    ),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: 7,
                      separatorBuilder:
                          (_, __) => Divider(
                            color: context.colors.divider,
                            height: 1,
                            indent: 12.sp,
                          ),
                      itemBuilder:
                          (_, index) => _MoveStatisticsSkeletonRow(seed: index),
                    ),
                  )
                  : ListView(
                    padding: EdgeInsets.zero,
                    children: _buildListChildren(
                      context,
                      ref,
                      state,
                      aggregates: sortedAggregates,
                      showGate: showGate,
                      nextStepCrossesLimit: nextStepCrossesLimit,
                    ),
                  ),
        ),
      ],
    );

    if (showGate) {
      return Stack(
        children: [
          mainContent,
          Positioned.fill(
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.4),
                  child: GestureDetector(
                    onTap: () => requirePremiumGuard(context, ref),
                    behavior: HitTestBehavior.opaque,
                    child: const _ExplorerPremiumGate(),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return mainContent;
  }

  List<Widget> _buildListChildren(
    BuildContext context,
    WidgetRef ref,
    GamebaseExplorerState state, {
    required List<MoveAggregate> aggregates,
    required bool showGate,
    required bool nextStepCrossesLimit,
  }) {
    Widget divider() =>
        Divider(color: context.colors.divider, height: 1, indent: 12.sp);

    final children = <Widget>[];

    if (aggregates.isEmpty && showGate) {
      for (var i = 0; i < 5; i++) {
        if (i > 0) children.add(divider());
        children.add(const _MoveStatisticsPlaceholderRow());
      }
      return children;
    }

    for (var i = 0; i < aggregates.length; i++) {
      final aggregate = aggregates[i];
      if (i > 0) children.add(divider());
      children.add(
        _MoveStatisticsRow(
          aggregate: aggregate,
          currentFen: state.currentFen,
          exploredMoves: state.exploredMoves,
          filters: state.filters,
          onTap: () async {
            // A move-row tap always releases a focused game card so the
            // arrows return to the main board instantly (Trello #984).
            ref.read(explorerFocusedGameProvider.notifier).clear();
            if (showGate) {
              await requirePremiumGuard(context, ref);
              return;
            }
            if (nextStepCrossesLimit) {
              final unlocked = await requirePremiumGuard(context, ref);
              if (!unlocked) return;
            }
            if (onMove != null) {
              onMove!(aggregate.uci);
            } else {
              ref
                  .read(gamebaseExplorerProvider.notifier)
                  .makeMove(aggregate.uci);
            }
          },
        ),
      );
    }

    // Lichess-style '∑' totals row — hidden when only one move remains.
    if (aggregates.length > 1) {
      children.add(divider());
      children.add(_MoveStatisticsSummaryRow(aggregates: aggregates));
    }

    // Inline games section once few enough games remain in this position.
    // The blur gate already covers the whole panel past the free limit, so
    // no extra gating is needed here.
    final totalGames = state.totalGames;
    if (!showGate &&
        !state.isLoading &&
        aggregates.isNotEmpty &&
        totalGames > 0 &&
        totalGames <= kExplorerInlineGamesLimit) {
      children.add(divider());
      children.add(
        ExplorerGamesSection(
          fen: state.currentFen,
          moves: state.exploredMoves,
          filters: state.filters,
        ),
      );
    }

    return children;
  }
}

/// Totals row summing every move row above it ('∑'): weighted W/D/L bar,
/// aggregate game count, and the most recent last-played date. Mirrors the
/// per-row column geometry so it reads as part of the table.
class _MoveStatisticsSummaryRow extends StatelessWidget {
  const _MoveStatisticsSummaryRow({required this.aggregates});

  final List<MoveAggregate> aggregates;

  @override
  Widget build(BuildContext context) {
    final summary = MoveAggregatesSummary.fromAggregates(aggregates);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 10.sp),
      child: Row(
        children: [
          SizedBox(
            width: _kMoveColumnWidth.w,
            child: Text(
              '∑',
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 14.f,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(width: _kColumnGap.sp),
          Expanded(
            child: _StatisticsBar(
              whiteRate: summary.whiteRate,
              drawRate: summary.drawRate,
              blackRate: summary.blackRate,
            ),
          ),
          SizedBox(width: _kColumnGap.sp),
          SizedBox(
            width: _kGamesColumnWidth.w,
            child: Text(
              summary.formattedTotal,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: kPrimaryColor,
                fontSize: 12.f,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(width: _kColumnGap.sp),
          SizedBox(
            width: _kLastColumnWidth.w,
            child: Text(
              _formatLastPlayed(summary.lastPlayed),
              textAlign: TextAlign.right,
              style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12.f,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Placeholder row for blurred stats teaser.
class _MoveStatisticsPlaceholderRow extends StatelessWidget {
  const _MoveStatisticsPlaceholderRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 10.sp),
      child: Row(
        children: [
          SizedBox(
            width: _kMoveColumnWidth.w,
            child: Row(
              children: [
                Container(
                  width: 20.w,
                  height: 12.h,
                  decoration: BoxDecoration(
                    color: context.colors.textSecondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2.br),
                  ),
                ),
                SizedBox(width: 4.w),
                Container(
                  width: 30.w,
                  height: 14.h,
                  decoration: BoxDecoration(
                    color: context.colors.textSecondary.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2.br),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: _kColumnGap.sp),
          Expanded(
            child: Container(
              height: 14.h,
              decoration: BoxDecoration(
                color: context.colors.textSecondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16.br),
              ),
            ),
          ),
          SizedBox(width: _kColumnGap.sp),
          Container(
            width: _kGamesColumnWidth.w,
            height: 12.h,
            decoration: BoxDecoration(
              color: context.colors.textSecondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2.br),
            ),
          ),
          SizedBox(width: _kColumnGap.sp),
          Container(
            width: _kLastColumnWidth.w,
            height: 12.h,
            decoration: BoxDecoration(
              color: context.colors.textSecondary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2.br),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shimmering skeleton row shown during first load / position change. Mirrors
/// the real [_MoveStatisticsRow] column geometry so swapping in live data
/// causes no layout shift; the wrapping [Skeletonizer] paints the grey shimmer
/// over these leaves.
class _MoveStatisticsSkeletonRow extends StatelessWidget {
  const _MoveStatisticsSkeletonRow({required this.seed});

  final int seed;

  @override
  Widget build(BuildContext context) {
    const sans = ['Nf3', 'e4', 'Bb5', 'd4', 'c4', 'Nc3', 'Bc4'];
    const counts = ['1.2M', '430k', '88k', '21k', '9.4k', '3.1k', '740'];

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 10.sp),
      child: Row(
        children: [
          SizedBox(
            width: _kMoveColumnWidth.w,
            child: Row(
              children: [
                Text(
                  '12.',
                  style: TextStyle(fontSize: 12.f, fontWeight: FontWeight.w500),
                ),
                SizedBox(width: 4.w),
                Text(
                  sans[seed % sans.length],
                  style: TextStyle(fontSize: 14.f, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          SizedBox(width: _kColumnGap.sp),
          Expanded(
            child: Container(
              height: 14.h,
              decoration: BoxDecoration(
                color: context.colors.textPrimary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16.br),
              ),
            ),
          ),
          SizedBox(width: _kColumnGap.sp),
          SizedBox(
            width: _kGamesColumnWidth.w,
            child: Text(
              counts[seed % counts.length],
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12.f, fontWeight: FontWeight.w700),
            ),
          ),
          SizedBox(width: _kColumnGap.sp),
          SizedBox(
            width: _kLastColumnWidth.w,
            child: Text(
              '2024',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12.f),
            ),
          ),
        ],
      ),
    );
  }
}

/// Individual row showing move statistics.
class _MoveStatisticsRow extends ConsumerWidget {
  const _MoveStatisticsRow({
    required this.aggregate,
    required this.currentFen,
    required this.exploredMoves,
    required this.filters,
    required this.onTap,
  });

  final MoveAggregate aggregate;
  final String currentFen;
  final List<String> exploredMoves;
  final GamebaseFilters filters;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (sanMove, _) = uciToSanAndFen(aggregate.uci, currentFen);
    final moveNumberLabel =
        currentFen.split(' ')[1] == 'w'
            ? '${_fullMoveNumberFromFen(currentFen)}.'
            : '${_fullMoveNumberFromFen(currentFen)}...';

    final useFigurine = ref.watch(
      boardSettingsProviderNew.select(
        (s) =>
            s.valueOrNull?.useFigurine ?? const BoardSettingsNew().useFigurine,
      ),
    );
    final pieceAssets = ref.watch(
      boardSettingsProviderNew.select(
        (s) =>
            s.valueOrNull?.pieceAssets ?? const BoardSettingsNew().pieceAssets,
      ),
    );

    final moveStyle = TextStyle(
      color: context.colors.textPrimary,
      fontSize: 14.f,
      fontWeight: FontWeight.w500,
    );

    void openGames() {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        builder:
            (_) => PositionGamesSheet(
              fen: currentFen,
              moves: exploredMoves,
              uci: aggregate.uci,
              filters: filters,
              title: 'Games for $moveNumberLabel$sanMove',
            ),
      );
    }

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 10.sp),
        child: Row(
          children: [
            // Move name
            SizedBox(
              width: _kMoveColumnWidth.w,
              child: Row(
                children: [
                  Text(
                    moveNumberLabel,
                    style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 12.f,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(width: 4.w),
                  Expanded(
                    child:
                        useFigurine
                            ? RichText(
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              text: TextSpan(
                                children: buildFigurineSpans(
                                  text: sanMove,
                                  pieceAssets: pieceAssets,
                                  style: moveStyle,
                                  pieceSize: 16.f,
                                ),
                              ),
                            )
                            : Text(
                              sanMove,
                              style: moveStyle,
                              overflow: TextOverflow.ellipsis,
                            ),
                  ),
                ],
              ),
            ),
            SizedBox(width: _kColumnGap.sp),
            // Statistics bar
            Expanded(
              child: _StatisticsBar(
                whiteRate: aggregate.whiteWinRate,
                drawRate: aggregate.drawRate,
                blackRate: aggregate.blackWinRate,
              ),
            ),
            SizedBox(width: _kColumnGap.sp),
            SizedBox(
              width: _kGamesColumnWidth.w,
              child: Align(
                alignment: Alignment.centerRight,
                child: Tooltip(
                      message: 'Games',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: openGames,
                          borderRadius: BorderRadius.circular(20.br),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8.w,
                              vertical: 4.h,
                            ),
                            decoration: BoxDecoration(
                              color: kPrimaryColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(20.br),
                              border: Border.all(
                                color: kPrimaryColor.withValues(alpha: 0.45),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: Text(
                                    aggregate.formattedTotal,
                                    textAlign: TextAlign.right,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: kPrimaryColor,
                                      fontSize: 12.f,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 4.w),
                                Icon(
                                  Icons.list_alt_rounded,
                                  color: kPrimaryColor,
                                  size: 15.ic,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scaleXY(
                      begin: 1.0,
                      end: 1.04,
                      duration: 1200.ms,
                      curve: Curves.easeInOut,
                    ),
              ),
            ),
            SizedBox(width: _kColumnGap.sp),
            SizedBox(
              width: _kLastColumnWidth.w,
              child: Text(
                _formatLastPlayed(aggregate.lastPlayed),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 12.f,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatLastPlayed(DateTime? date) {
  if (date == null) return '—';
  return DateFormat('MMM yyyy').format(date);
}

/// Convert UCI move notation to SAN (Standard Algebraic Notation) for display.
String uciToSan(String uci, String fen) {
  try {
    final position = Chess.fromSetup(Setup.parseFen(fen));

    final from = Square.fromName(uci.substring(0, 2));
    final to = Square.fromName(uci.substring(2, 4));
    Role? promotion;
    if (uci.length > 4) {
      promotion = Role.fromChar(uci[4]);
    }

    final move = NormalMove(from: from, to: to, promotion: promotion);
    final result = position.makeSan(move);
    return result.$2;
  } catch (_) {
    return uci;
  }
}

int _fullMoveNumberFromFen(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  if (parts.length < 6) return 1;
  return int.tryParse(parts[5]) ?? 1;
}

/// Like [uciToSan] but also returns the resulting FEN after the move.
/// Returns `(san, resultingFen)`. `resultingFen` is null on parse failure.
(String san, String? resultingFen) uciToSanAndFen(String uci, String fen) {
  try {
    final position = Chess.fromSetup(Setup.parseFen(fen));

    final from = Square.fromName(uci.substring(0, 2));
    final to = Square.fromName(uci.substring(2, 4));
    Role? promotion;
    if (uci.length > 4) {
      promotion = Role.fromChar(uci[4]);
    }

    final move = NormalMove(from: from, to: to, promotion: promotion);
    final result = position.makeSan(move);
    // result.$1 is the new Position, result.$2 is the SAN string
    return (result.$2, result.$1.fen);
  } catch (_) {
    return (uci, null);
  }
}

/// Horizontal bar showing win/draw/loss distribution.
class _StatisticsBar extends StatelessWidget {
  const _StatisticsBar({
    required this.whiteRate,
    required this.drawRate,
    required this.blackRate,
  });

  final double whiteRate;
  final double drawRate;
  final double blackRate;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16.br),
      child: SizedBox(
        height: 16.h,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final segments = _scoreSegments();
            if (segments.isEmpty || constraints.maxWidth <= 0) {
              return const SizedBox.shrink();
            }

            final widths = _scoreSegmentWidths(
              segments,
              constraints.maxWidth,
              minimumLabelWidth: 28.w,
            );

            return Row(
              children: [
                for (var i = 0; i < segments.length; i++)
                  SizedBox(
                    width: widths[i],
                    child: _ScoreSegment(segment: segments[i]),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  List<_ScoreSegmentData> _scoreSegments() {
    return [
      if (whiteRate > 0)
        _ScoreSegmentData(
          rate: whiteRate,
          label: _formatScorePercent(whiteRate),
          backgroundColor: kMoveStatWhiteColor,
          textColor: kMoveStatBlackColor,
        ),
      if (drawRate > 0)
        _ScoreSegmentData(
          rate: drawRate,
          label: _formatScorePercent(drawRate),
          backgroundColor: kMoveStatDrawColor,
          textColor: kMoveStatWhiteColor,
        ),
      if (blackRate > 0)
        _ScoreSegmentData(
          rate: blackRate,
          label: _formatScorePercent(blackRate),
          backgroundColor: kMoveStatBlackColor,
          textColor: kMoveStatWhiteColor,
        ),
    ];
  }
}

class _ScoreSegment extends StatelessWidget {
  const _ScoreSegment({required this.segment});

  final _ScoreSegmentData segment;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: segment.backgroundColor,
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: 1.w),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          segment.label,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: segment.textColor,
            fontSize: 10.f,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ScoreSegmentData {
  const _ScoreSegmentData({
    required this.rate,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });

  final double rate;
  final String label;
  final Color backgroundColor;
  final Color textColor;
}

String _formatScorePercent(double rate) =>
    '${(rate * 100).toStringAsFixed(0)}%';

List<double> _scoreSegmentWidths(
  List<_ScoreSegmentData> segments,
  double availableWidth, {
  required double minimumLabelWidth,
}) {
  if (segments.isEmpty || availableWidth <= 0) return const [];

  final safeMinimum = minimumLabelWidth.clamp(
    0.0,
    availableWidth / segments.length,
  );
  final totalRate = segments.fold<double>(
    0,
    (sum, segment) => sum + segment.rate,
  );
  final remainingWidth = availableWidth - (safeMinimum * segments.length);

  if (remainingWidth <= 0 || totalRate <= 0) {
    return List<double>.filled(
      segments.length,
      availableWidth / segments.length,
    );
  }

  final widths = <double>[
    for (final segment in segments)
      safeMinimum + (remainingWidth * (segment.rate / totalRate)),
  ];

  // Remove any sub-pixel drift so the row fills the clipped bar exactly.
  final drift =
      availableWidth - widths.fold<double>(0, (sum, width) => sum + width);
  widths[widths.length - 1] += drift;
  return widths;
}

/// CTA shown in place of the move-aggregate table when the current position
/// is past the 10th full move and the user is not subscribed.
class _ExplorerPremiumGate extends ConsumerWidget {
  const _ExplorerPremiumGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.sp, vertical: 24.sp),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56.w,
              height: 56.h,
              decoration: BoxDecoration(
                color: kPrimaryColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_stories_rounded,
                color: kPrimaryColor,
                size: 28.ic,
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'Theory ends here. Prep doesn’t.',
              textAlign: TextAlign.center,
              style: AppTypography.textLgBold.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Games are won past book. Unlock Premium to keep mining master '
              'data deep into the middlegame — score trends, sideline '
              'frequency, novelties, and the exact paths titled players take '
              'beyond move 10.',
              textAlign: TextAlign.center,
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textSecondary,
                height: 1.35,
              ),
            ),
            SizedBox(height: 20.h),
            GestureDetector(
              onTap: () => requirePremiumGuard(context, ref),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12.br),
                  gradient: LinearGradient(
                    colors: [kPrimaryColor, kDarkBlue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Text(
                  'Unlock deeper prep',
                  style: AppTypography.textMdBold.copyWith(
                    color: kBlackColor,
                    letterSpacing: 0.2,
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
