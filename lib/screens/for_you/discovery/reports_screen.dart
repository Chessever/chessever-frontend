import 'package:chessever2/screens/for_you/discovery/reports_share.dart';
import 'package:chessever2/widgets/paywall/game_report_access.dart';
import 'dart:async';

import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/collections/event_view_shell.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:chessever2/screens/for_you/discovery/providers/reports_provider.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_common.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/discovery_game_cards.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/report_type_chips.dart';
import 'package:chessever2/screens/group_event/widget/appbar_icons_widget.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_list_view_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_search_bar.dart'
    show EventSearchBarFrame;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/scroll_cache.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/ink_fab.dart' show InkFabSize;
import 'package:chessever2/widgets/simple_search_bar.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// Saved reports, progressively loaded on the existing game-card design.
/// A single page: the report types stand where tabs would, the layout
/// toggle sits in the header, and the search floats over the list.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  static Future<void> open(BuildContext context) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ReportsScreen()));
  }

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Empties the field and the list's filter.
  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) => EventViewShell(
    title: 'Reports',
    titleIcon: Icon(Icons.assessment_rounded),
    tabs: const ['Reports'],
    actions: [
      // The list's layout, in the header as on an event's Games tab: the
      // list's top is the list's own. Its slot is the back button's width,
      // so the title keeps the centre of the screen. A button node of its
      // own, or a screen reader folds it into the title.
      SizedBox(
        width: kMinInteractiveDimension,
        child: Center(
          child: Semantics(
            container: true,
            button: true,
            label: 'Toggle chessboard view',
            child: AppBarIcons(
              image: SvgAsset.chase_grid,
              boxed: false,
              onTap: () {
                HapticFeedbackService.cardTap();
                ref.read(gamesListViewModeSwitcher).toggleViewMode();
              },
            ),
          ),
        ),
      ),
    ],
    // The chips scroll edge to edge and pad themselves.
    tabStripPadding: EdgeInsets.zero,
    tabStripOverride: ReportTypeChips(
      onLongPress: (context, type) => showReportsShareMenu(context, type),
      selected: ref.watch(reportsGameTypeProvider),
      onSelected: (type) {
        if (type == ref.read(reportsGameTypeProvider)) return;
        HapticFeedbackService.selection();
        ref.read(reportsGameTypeProvider.notifier).state = type;
      },
    ),
    // Names are searched in place: the floating button opens the field in
    // the header's place, over this list filtered as the reader types,
    // within the report type chosen before it opened.
    search: EventViewSearch(
      label: 'Search reports',
      focusNode: _searchFocus,
      onClose: _clearSearch,
      field: EventSearchBarFrame(
        compact: true,
        child: SimpleSearchBar(
          controller: _searchController,
          focusNode: _searchFocus,
          hintText: 'Search players',
          textFieldKey: const ValueKey('reports_search'),
          onChanged: (value) => setState(() => _query = value.trim()),
          onCloseTap: () {
            _clearSearch();
            _searchFocus.unfocus();
          },
          onOpenFilter: null,
        ),
      ),
    ),
    // Every card here is a saved report, so its eval bar shows what the
    // report recorded for the final position rather than waiting on caches
    // that rarely hold it.
    pageBuilder: (context, _) => ProviderScope(
      overrides: [gameCardRecordedEvalProvider.overrideWithValue(true)],
      child: _ReportsGames(query: _query),
    ),
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
  bool _opening = false;

  Future<void> _openReport(List<GamesTourModel> games, int index) async {
    if (_opening) return;
    _opening = true;
    try {
      if (!await ensureGameReportAccess(context) || !mounted) return;
      openDiscoveryGame(
        context,
        ref,
        games,
        index,
        initialMoveIndexByGameId:
            ref.read(reportsGameTypeProvider) == ReportGameType.missedChance
            ? missedChanceBoardMoves(
                ref.read(reportsPaginationProvider).storyPlies,
              )
            : null,
      );
    } finally {
      _opening = false;
    }
  }

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
    // The presentation provider keeps each day together in rating order.
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
          child: ReportsDateShareHeader(
            type: ref.read(reportsGameTypeProvider),
            date: day?.toIso8601String().split('T').first,
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
                          onOpen: (games, index) =>
                              unawaited(_openReport(games, index)),
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
    final items = _visibleItems(ref.watch(reportsGamesProvider));
    return LayoutBuilder(
      builder: (context, constraints) => _buildContent(
        context,
        constraints.maxWidth,
        gameType: gameType,
        reports: reports,
        mode: mode,
        items: items,
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    double availableWidth, {
    required ReportGameType? gameType,
    required ReportsPaginationState reports,
    required GamesListViewMode mode,
    required List<GamesTourModel> items,
  }) {
    final perRow = mode == GamesListViewMode.chessBoardGrid
        ? ResponsiveHelper.columnsForWidth(
            availableWidth -
                2 * ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w),
            minItemWidth: 220,
            spacing: 16.w,
            minColumns: 2,
            maxColumns: 4,
          )
        : 1;
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
                    // The chips give way to the search field, so a miss
                    // names the type it was searched in.
                    text: widget.query.isEmpty
                        ? gameType == null
                              ? 'Analyzed games will appear here when a report is available.'
                              : 'No ${gameType.label} reports yet.'
                        : gameType == null
                        ? 'No reports match "${widget.query}".'
                        : 'No ${gameType.label} reports match "${widget.query}".',
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
              // The list ends clear of the floating search button.
              SliverToBoxAdapter(
                child: SizedBox(
                  height:
                      24.h +
                      InkFabSize.regular.side +
                      kFloatingActionButtonMargin +
                      MediaQuery.viewPaddingOf(context).bottom,
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
