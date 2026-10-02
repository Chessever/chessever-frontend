import 'package:chessever2/widgets/paywall/game_report_access.dart';
import 'dart:async';

import 'package:chessever2/screens/collections/event_view_shell.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/providers/reports_provider.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/report_type_chips.dart';
import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/game_date_header.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// Saved reports, progressively loaded on the existing game-card design.
/// A single page, so the tab strip is a search row with the usual layout
/// toggle instead of a one-word "Games" tab.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  static Future<void> open(BuildContext context) async {
    if (!await ensureGameReportAccess(context) || !context.mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ReportsScreen()));
  }

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EventViewShell(
    title: 'Reports',
    titleIcon: Icon(Icons.assessment_rounded),
    tabs: const ['Reports'],
    tabStripPadding: EdgeInsets.zero,
    tabStripOverride: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: HomeTopBarMetrics.horizontalPadding,
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 44.h,
                  decoration: BoxDecoration(
                    color: context.colors.background,
                    borderRadius: BorderRadius.circular(12.br),
                    border: Border.all(color: context.colors.surfaceRecessed),
                  ),
                  child: Row(
                    children: [
                      SizedBox(width: 12.w),
                      Icon(
                        Icons.search,
                        size: 20.sp,
                        color: context.colors.textSecondary,
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          style: AppTypography.textSmRegular.copyWith(
                            color: context.colors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search players',
                            hintStyle: AppTypography.textSmRegular.copyWith(
                              color: context.colors.textSecondary,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (value) =>
                              setState(() => _query = value.trim()),
                        ),
                      ),
                      if (_query.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          child: Padding(
                            padding: EdgeInsets.all(8.w),
                            child: Icon(
                              Icons.close,
                              size: 18.sp,
                              color: context.colors.textSecondary,
                            ),
                          ),
                        )
                      else
                        SizedBox(width: 12.w),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              Semantics(
                label: 'Toggle chessboard view',
                child: AppBarIcons(
                  image: SvgAsset.chase_grid,
                  onTap: () {
                    HapticFeedbackService.cardTap();
                    ref.read(gamesListViewModeSwitcher).toggleViewMode();
                  },
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 8.h),
        ReportTypeChips(
          selected: ref.watch(reportsGameTypeProvider),
          onSelected: (type) {
            if (type == ref.read(reportsGameTypeProvider)) return;
            HapticFeedbackService.selection();
            ref.read(reportsGameTypeProvider.notifier).state = type;
          },
        ),
      ],
    ),
    pageBuilder: (context, _) => _ReportsGames(query: _query),
  );
}

class _ReportsGames extends ConsumerStatefulWidget {
  const _ReportsGames({required this.query});

  final String query;

  @override
  ConsumerState<_ReportsGames> createState() => _ReportsGamesState();
}

class _ReportsGamesState extends ConsumerState<_ReportsGames> {
  bool _checkScheduled = false;
  final Set<DateTime?> _collapsedDates = {};

  List<GamesTourModel> _visibleItems(List<GamesTourModel> items) {
    final query = widget.query.toLowerCase();
    if (query.isEmpty) return items;
    return [
      for (final game in items)
        if ('${game.whitePlayer.name} ${game.blackPlayer.name}'
            .toLowerCase()
            .contains(query))
          game,
    ];
  }

  DateTime? _dayOf(GamesTourModel game) {
    final date = game.lastMoveTime?.toUtc();
    return date == null ? null : DateTime.utc(date.year, date.month, date.day);
  }

  String _dateLabel(DateTime? day) {
    if (day == null) return 'Unknown date';
    final now = DateTime.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    final daysAgo = today.difference(day).inDays;
    if (daysAgo == 0) return 'Today';
    if (daysAgo == 1) return 'Yesterday';
    return DateFormat('EEEE, MMM d, y').format(day);
  }

  void _toggleDay(DateTime? day) {
    setState(() {
      if (!_collapsedDates.remove(day)) _collapsedDates.add(day);
    });
    _checkAfterLayout();
  }

  List<_ReportRow> _rows(List<GamesTourModel> games, int columns) {
    final rows = <_ReportRow>[];
    // Keep the server's order, including undated/fallback dates. Grouping must
    // never move a later page above cards already visible to the reader.
    for (var start = 0; start < games.length;) {
      final day = _dayOf(games[start]);
      var end = start + 1;
      while (end < games.length && _dayOf(games[end]) == day) {
        end++;
      }
      rows.add(_ReportDay(day, games[start].gameId));
      if (!_collapsedDates.contains(day)) {
        for (var index = start; index < end; index += columns) {
          rows.add(
            _ReportGamesRow(
              index,
              (end - index).clamp(0, columns),
              index + columns >= end,
            ),
          );
        }
      }
      start = end;
    }
    return rows;
  }

  Widget _buildRow(_ReportRow row, List<GamesTourModel> games, int columns) =>
      switch (row) {
        _ReportDay(:final day, :final firstGameId) => Padding(
          key: ValueKey('reports_day_$firstGameId'),
          padding: EdgeInsets.only(bottom: 12.h),
          child: GameDateHeader(
            dateLabel: _dateLabel(day),
            isExpanded: !_collapsedDates.contains(day),
            onToggle: () => _toggleDay(day),
          ),
        ),
        _ReportGamesRow(:final start, :final count, :final isLast) => Padding(
          key: ValueKey('reports_row_${games[start].gameId}'),
          padding: EdgeInsets.only(bottom: isLast ? 16.h : 12.h),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) SizedBox(width: 12.sp),
                Expanded(
                  child: column < count
                      ? DiscoveryGameCard(
                          games: games,
                          index: start + column,
                          streamEnabled: false,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      };

  void _checkAfterLayout() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!mounted) return;
      final reports = ref.read(reportsPaginationProvider);
      if (reports.isLoading || !reports.hasMore || reports.error != null) {
        return;
      }
      final scroll = PrimaryScrollController.maybeOf(context);
      if (scroll == null || !scroll.hasClients) return;
      // An entirely filtered page must keep advancing, even if the loading
      // placeholder happens to be taller than the viewport in board mode.
      if (reports.items.isEmpty || scroll.position.extentAfter <= 600) {
        unawaited(ref.read(reportsPaginationProvider.notifier).loadNextPage());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(reportsGameTypeProvider, (previous, next) {
      _collapsedDates.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final scroll = PrimaryScrollController.maybeOf(context);
        if (scroll != null && scroll.hasClients) scroll.jumpTo(0);
      });
    });
    final gameType = ref.watch(reportsGameTypeProvider);
    final reports = ref.watch(reportsPaginationProvider);
    final mode = ref.watch(gamesListViewModeProvider);
    final perRow = mode == GamesListViewMode.chessBoardGrid
        ? (ResponsiveHelper.isTablet && ResponsiveHelper.isLandscape ? 4 : 2)
        : 1;
    final items = _visibleItems(reports.items);
    final rows = _rows(items, perRow);
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );
    final notifier = ref.read(reportsPaginationProvider.notifier);
    _checkAfterLayout();

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) {
        if (notification.depth == 0 &&
            notification.metrics.axis == Axis.vertical) {
          _checkAfterLayout();
        }
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth == 0 &&
              notification.metrics.axis == Axis.vertical) {
            _checkAfterLayout();
          }
          return false;
        },
        child: RefreshIndicator(
          color: context.colors.textPrimary,
          backgroundColor: context.colors.surface,
          onRefresh: () async {
            HapticFeedbackService.medium();
            ref.invalidate(discoveryAnalyzedGamesProvider);
            ref.invalidate(discoveryReviewCurveProvider);
            await notifier.refresh();
          },
          child: CustomScrollView(
            key: const PageStorageKey('reports_scroll'),
            primary: true,
            scrollCacheExtent: kListScrollCacheExtent,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(child: SizedBox(height: 12.h)),
              if (items.isNotEmpty)
                SliverPadding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: 8.h,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildRow(rows[index], items, perRow),
                      childCount: rows.length,
                      addAutomaticKeepAlives: false,
                    ),
                  ),
                )
              else if (reports.error == null &&
                  (reports.isLoading || reports.hasMore))
                SliverPadding(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
                    vertical: 8.h,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: DiscoveryGameListSkeleton(
                      count: mode == GamesListViewMode.gamesCard
                          ? 6
                          : perRow * 2,
                      gridColumns: perRow,
                      padded: false,
                      viewMode: mode,
                    ),
                  ),
                )
              else if (reports.error == null)
                SliverToBoxAdapter(
                  child: DiscoveryNotice(
                    text: widget.query.isEmpty
                        ? gameType == null
                              ? 'Analyzed games will appear here when a report is available.'
                              : 'No ${gameType.label} reports yet.'
                        : 'No reports match "${widget.query}".',
                  ),
                ),
              if (reports.error != null)
                SliverToBoxAdapter(
                  child: DiscoveryNotice(
                    text: reports.error!,
                    actionLabel: 'Retry',
                    onAction: () => unawaited(notifier.retry()),
                  ),
                )
              else if (items.isNotEmpty &&
                  reports.isLoading &&
                  !reports.isRefreshing)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24.h),
                    child: Center(
                      child: SizedBox(
                        width: 24.w,
                        height: 24.h,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: context.colors.textPrimary,
                          semanticsLabel: 'Loading more reports',
                        ),
                      ),
                    ),
                  ),
                )
              else if (items.isNotEmpty && !reports.hasMore)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.h),
                    child: Center(
                      child: Text(
                        'No more reports',
                        style: AppTypography.textXsRegular.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 24.h + MediaQuery.viewPaddingOf(context).bottom,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

sealed class _ReportRow {
  const _ReportRow();
}

class _ReportDay extends _ReportRow {
  const _ReportDay(this.day, this.firstGameId);
  final DateTime? day;
  final String firstGameId;
}

class _ReportGamesRow extends _ReportRow {
  const _ReportGamesRow(this.start, this.count, this.isLast);
  final int start;
  final int count;
  final bool isLast;
}
