import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/calendar/calendar_event_detail_screen.dart';
import 'package:chessever2/screens/calendar/provider/calendar_screen_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/liquid_glass/glass_kit.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';

/// Filter mode for the calendar view
enum CalendarFilterMode { all, upcoming, favorites }

final availableYearsProvider = AutoDisposeProvider<List<int>>((ref) {
  final currentYear = DateTime.now().year;
  return [currentYear - 1, currentYear, currentYear + 1];
});

final selectedYearProvider = StateProvider<int>((ref) {
  return DateTime.now().year;
});

final selectedMonthProvider = StateProvider<int>((ref) {
  return DateTime.now().month;
});

final calendarFilterModeProvider = StateProvider<CalendarFilterMode>((ref) {
  return CalendarFilterMode.all;
});

/// Orders months so the current month leads when viewing the current year,
/// letting users jump straight to what's relevant now. Earlier months wrap to
/// the end (e.g. June → ... → Dec, Jan → ... → May). Past/future years stay in
/// plain chronological order since no month is "current" in them.
List<MonthEventsSummary> orderMonthsByRelevance(
  List<MonthEventsSummary> months,
  int selectedYear,
) {
  final now = DateTime.now();
  if (selectedYear != now.year) return months;
  final pivot = months.indexWhere((m) => m.monthNumber == now.month);
  if (pivot <= 0) return months;
  return [...months.sublist(pivot), ...months.sublist(0, pivot)];
}

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  final TextEditingController searchController = TextEditingController();
  final focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchAnalyticsTimer;
  bool _searchExpanded = false;

  @override
  void dispose() {
    searchController.dispose();
    focusNode.dispose();
    _scrollController.dispose();
    _searchAnalyticsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final yearList = ref.read(availableYearsProvider);
    final filterMode = ref.watch(calendarFilterModeProvider);
    final searchQuery = ref.watch(calendarSearchQueryProvider);
    final selectedYear = ref.watch(selectedYearProvider);
    final calendarState = ref.watch(calendarScreenProvider);
    final isListMode =
        filterMode != CalendarFilterMode.all || searchQuery.trim().isNotEmpty;
    final scaledLabelHeight = MediaQuery.textScalerOf(context).scale(14) * 1.2;
    final controlHeight = (scaledLabelHeight + 20).clamp(48.0, 96.0);

    return GlassFullScreenPage(
      key: e2eKey(E2eIds.calendarRoot),
      backgroundColor: context.colors.background,
      contentPadding: EdgeInsets.only(top: controlHeight * 2 + 28, bottom: 12),
      topOverlayPadding: const EdgeInsets.only(top: 4),
      topOverlay: GlassIslandStack(
        key: const ValueKey<String>('calendar-floating-controls'),
        includeStatusBar: false,
        gap: 6,
        children: [
          GlassIslandTopBar(
            topPadding: 0,
            height: controlHeight,
            title:
                _searchExpanded
                    ? null
                    : GlassTitleChip(
                      label: 'Calendar',
                      maxWidth: 132,
                      height: controlHeight,
                    ),
            center: Semantics(
              label:
                  _searchExpanded ? 'Search calendar field' : 'Search calendar',
              button: !_searchExpanded,
              textField: _searchExpanded,
              child: GlassIslandSearch(
                controller: searchController,
                focusNode: focusNode,
                expanded: _searchExpanded,
                textFieldKey: e2eKey(E2eIds.calendarSearchField),
                hintText: 'Search events',
                collapsedSize: controlHeight,
                expandedHeight: controlHeight,
                onExpandedChanged:
                    (expanded) => setState(() => _searchExpanded = expanded),
                onChanged: _onSearchChanged,
                onClear: _clearSearch,
              ),
            ),
            trailing:
                _searchExpanded
                    ? const []
                    : [
                      _buildYearPicker(
                        yearList: yearList,
                        selectedYear: selectedYear,
                        controlHeight: controlHeight,
                      ),
                    ],
          ),
          _buildControlRail(controlHeight),
        ],
      ),
      content: AnimatedSwitcher(
        key: const ValueKey<String>('calendar-state-switcher'),
        duration: GlassMotion.resolveDuration(
          context,
          const Duration(milliseconds: 180),
        ),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        child: _buildCalendarBody(
          state: calendarState,
          selectedYear: selectedYear,
          isListMode: isListMode,
          controlHeight: controlHeight,
        ),
      ),
    );
  }

  void _onSearchChanged(String value) {
    ref.read(calendarSearchQueryProvider.notifier).state = value;
    _searchAnalyticsTimer?.cancel();
    final query = value.trim();
    if (query.isEmpty) return;
    _searchAnalyticsTimer = Timer(const Duration(milliseconds: 350), () {
      AnalyticsService.instance.trackEventDetached(
        'Calendar Search',
        properties: {'query': query, 'query_length': query.length},
      );
    });
  }

  void _clearSearch() {
    ref.read(calendarSearchQueryProvider.notifier).state = '';
  }

  Widget _buildYearPicker({
    required List<int> yearList,
    required int selectedYear,
    required double controlHeight,
  }) {
    return Semantics(
      key: const ValueKey<String>('calendar-year-picker'),
      container: true,
      label: 'Calendar year',
      value: '$selectedYear',
      child: GlassContainer(
        useOwnLayer: true,
        height: controlHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: LiquidRoundedSuperellipse(borderRadius: controlHeight / 2),
        quality: GlassQuality.standard,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: selectedYear,
            onChanged: (newValue) {
              if (newValue == null || newValue == selectedYear) return;
              ref.read(selectedYearProvider.notifier).state = newValue;
              AnalyticsService.instance.trackEventDetached(
                'Calendar Year Changed',
                properties: {'year': newValue},
              );
            },
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: context.colors.iconPrimary,
              size: 20.ic,
            ),
            style: AppTypography.textMdBold.copyWith(
              color: context.colors.textPrimary,
            ),
            dropdownColor: context.colors.surfaceElevated,
            borderRadius: BorderRadius.circular(12.br),
            items: yearList
                .map(
                  (year) =>
                      DropdownMenuItem<int>(value: year, child: Text('$year')),
                )
                .toList(growable: false),
          ),
        ),
      ),
    );
  }

  Widget _buildControlRail(double controlHeight) {
    return SingleChildScrollView(
      key: const ValueKey<String>('calendar-floating-filter-rail'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTimeControlPicker(controlHeight),
          const SizedBox(width: 8),
          _QuickFilterButtons(controlHeight: controlHeight),
        ],
      ),
    );
  }

  Widget _buildTimeControlPicker(double controlHeight) {
    const timeControls = ['Standard', 'Rapid', 'Blitz'];
    final selected = ref.watch(calendarTimeControlProvider);
    return Semantics(
      key: const ValueKey<String>('calendar-time-control-picker'),
      container: true,
      label: 'Time control filter',
      value: selected ?? 'All formats',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 156),
        child: GlassContainer(
          useOwnLayer: true,
          height: controlHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: LiquidRoundedSuperellipse(borderRadius: controlHeight / 2),
          quality: GlassQuality.standard,
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: selected,
              onChanged: (newValue) {
                ref.read(calendarTimeControlProvider.notifier).state = newValue;
                AnalyticsService.instance.trackEventDetached(
                  'Calendar Time Control Selected',
                  properties: {'time_control': newValue ?? 'All'},
                );
              },
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: context.colors.iconPrimary,
                size: 20.ic,
              ),
              style: AppTypography.textMdBold.copyWith(
                color: context.colors.textPrimary,
              ),
              dropdownColor: context.colors.surfaceElevated,
              borderRadius: BorderRadius.circular(12.br),
              selectedItemBuilder:
                  (_) => [
                    _buildTimeControlRow(null, 'All Formats'),
                    _buildTimeControlRow('Standard', 'Standard'),
                    _buildTimeControlRow('Rapid', 'Rapid'),
                    _buildTimeControlRow('Blitz', 'Blitz'),
                  ],
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: _buildTimeControlDropdownItem(null, 'All Formats'),
                ),
                ...timeControls.map(
                  (value) => DropdownMenuItem<String?>(
                    value: value,
                    child: _buildTimeControlDropdownItem(value, value),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarBody({
    required AsyncValue<List<MonthEventsSummary>> state,
    required int selectedYear,
    required bool isListMode,
    required double controlHeight,
  }) {
    return state.when(
      data: (rawData) {
        final data = orderMonthsByRelevance(rawData, selectedYear);
        return KeyedSubtree(
          key: const ValueKey<String>('calendar-data-state'),
          child:
              isListMode
                  ? _buildEventList(data)
                  : _buildMonthCanvas(data, controlHeight),
        );
      },
      error:
          (_, _) => KeyedSubtree(
            key: const ValueKey<String>('calendar-error-state'),
            child: _buildErrorCanvas(),
          ),
      loading:
          () => KeyedSubtree(
            key: const ValueKey<String>('calendar-loading-state'),
            child: _buildLoadingCanvas(controlHeight),
          ),
    );
  }

  Widget _buildMonthCanvas(
    List<MonthEventsSummary> data,
    double controlHeight,
  ) {
    return RefreshIndicator(
      onRefresh: _refreshCalendar,
      color: kPrimaryColor,
      backgroundColor: context.colors.surfaceElevated,
      child: CustomScrollView(
        key: const PageStorageKey<String>('calendar-month-canvas'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            sliver: _buildResponsiveMonthGrid(
              itemCount: data.length,
              controlHeight: controlHeight,
              itemBuilder: (context, index) {
                final summary = data[index];
                return _MonthButton(
                  monthName: summary.monthName,
                  eventCount: summary.eventCount,
                  onTap: () => _openMonth(summary),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingCanvas(double controlHeight) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return SkeletonWidget(
      child: CustomScrollView(
        key: const ValueKey<String>('calendar-loading-canvas'),
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            sliver: _buildResponsiveMonthGrid(
              itemCount: months.length,
              controlHeight: controlHeight,
              itemBuilder:
                  (_, index) => _MonthButton(
                    monthName: months[index],
                    eventCount: 0,
                    onTap: () {},
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveMonthGrid({
    required int itemCount,
    required double controlHeight,
    required NullableIndexedWidgetBuilder itemBuilder,
  }) {
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columns =
            width >= 840 && textScale <= 1.5
                ? 3
                : width >= 340 && textScale <= 1.4
                ? 2
                : 1;
        return SliverGrid(
          delegate: SliverChildBuilderDelegate(
            itemBuilder,
            childCount: itemCount,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: controlHeight + 20,
          ),
        );
      },
    );
  }

  Widget _buildErrorCanvas() {
    return RefreshIndicator(
      onRefresh: _refreshCalendar,
      color: kPrimaryColor,
      backgroundColor: context.colors.surfaceElevated,
      child: CustomScrollView(
        key: const ValueKey<String>('calendar-error-canvas'),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _CalendarStatePanel(
              icon: Icons.calendar_month_outlined,
              title: 'Calendar unavailable',
              message:
                  'We could not load the events. Check your connection and try again.',
              actionLabel: 'Retry calendar',
              onAction: () => ref.invalidate(calendarScreenProvider),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventList(List<MonthEventsSummary> summaries) {
    final filterMode = ref.watch(calendarFilterModeProvider);
    final eventsById = <String, GroupEventCardModel>{};

    for (final summary in summaries) {
      for (final event in summary.events) {
        final existing = eventsById[event.id];
        if (existing == null) {
          eventsById[event.id] = event;
        } else {
          final existingDate = existing.startDate ?? existing.endDate;
          final currentDate = event.startDate ?? event.endDate;
          if (existingDate != null &&
              currentDate != null &&
              currentDate.isBefore(existingDate)) {
            eventsById[event.id] = event;
          }
        }
      }
    }

    final flattenedEvents = eventsById.values.toList();
    List<GroupEventCardModel> sortedEvents;

    if (filterMode == CalendarFilterMode.favorites) {
      // Sort by start date descending (most recent first)
      flattenedEvents.sort((a, b) {
        final dateA = a.startDate ?? a.endDate;
        final dateB = b.startDate ?? b.endDate;

        if (dateA != null && dateB != null) {
          return dateB.compareTo(dateA); // Newest events first
        }
        if (dateA != null) return 1;
        if (dateB != null) return -1;
        return 0;
      });
      sortedEvents = flattenedEvents;
    } else {
      sortedEvents = ref
          .read(tournamentSortingServiceProvider)
          .sortCalendarEvents(flattenedEvents, prioritizeFavorites: false);
    }

    final isTablet = ResponsiveHelper.isTablet;
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.sp,
      tablet: 24.sp,
    );

    return RefreshIndicator(
      onRefresh: _refreshCalendar,
      color: kPrimaryColor,
      backgroundColor: context.colors.surfaceElevated,
      child: CustomScrollView(
        key: const PageStorageKey<String>('calendar-event-canvas'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          if (sortedEvents.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _CalendarStatePanel(
                icon: Icons.event_busy_outlined,
                title: 'No events found',
                message: 'Try another search, format, or calendar filter.',
                actionLabel: 'Show all months',
                actionIcon: Icons.calendar_view_month_rounded,
                onAction: _clearCalendarFilters,
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                12,
                horizontalPadding,
                32,
              ),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final textScale =
                      MediaQuery.textScalerOf(context).scale(14) / 14;
                  final useGrid =
                      isTablet &&
                      constraints.crossAxisExtent >= 700 &&
                      textScale <= 1.35;
                  if (useGrid) {
                    final columns = ResponsiveHelper.getGridCrossAxisCount(
                      phoneCount: 1,
                    );
                    return SliverGrid(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final event = sortedEvents[index];
                        return EventCard(
                          tourEventCardModel: event,
                          heroTagSuffix: 'calendar-list-$index',
                          onTap: () => _onEventTap(event, sortedEvents),
                        );
                      }, childCount: sortedEvents.length),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: 16.sp,
                        mainAxisSpacing: 16.sp,
                        childAspectRatio:
                            ResponsiveHelper.isLandscape ? 2.2 : 1.8,
                      ),
                    );
                  }
                  return SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final event = sortedEvents[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: EventCard(
                          tourEventCardModel: event,
                          heroTagSuffix: 'calendar-list-$index',
                          forceCompactLayout: true,
                          onTap: () => _onEventTap(event, sortedEvents),
                        ),
                      );
                    }, childCount: sortedEvents.length),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _refreshCalendar() async {
    HapticFeedbackService.medium();
    ref.invalidate(calendarScreenProvider);
  }

  void _openMonth(MonthEventsSummary summary) {
    ref.read(selectedMonthProvider.notifier).state = summary.monthNumber;
    AnalyticsService.instance.trackEventDetached(
      'Calendar Month Opened',
      properties: {
        'month': summary.monthNumber,
        'month_name': summary.monthName,
        'event_count': summary.eventCount,
        'year': ref.read(selectedYearProvider),
      },
    );
    Navigator.pushNamed(context, '/calendar_detail_screen');
  }

  void _clearCalendarFilters() {
    _searchAnalyticsTimer?.cancel();
    searchController.clear();
    focusNode.unfocus();
    setState(() => _searchExpanded = false);
    ref.read(calendarSearchQueryProvider.notifier).state = '';
    ref.read(calendarTimeControlProvider.notifier).state = null;
    ref.read(calendarFilterModeProvider.notifier).state =
        CalendarFilterMode.all;
  }

  Future<void> _onEventTap(
    GroupEventCardModel event,
    List<GroupEventCardModel> visibleEvents,
  ) async {
    try {
      if (event.eventSource == EventSource.communityEvent) {
        final repo = ref.read(calendarEventRepositoryProvider);
        final selectedYear = ref.read(selectedYearProvider);

        // Visible community events in display order — defines swipe sequence.
        final visibleCommunity = visibleEvents
            .where((e) => e.eventSource == EventSource.communityEvent)
            .toList(growable: false);

        // Fetch full CalendarEvent rows for current year, then map to the
        // visible community subset by sanitized id. Falls back to title-search
        // if year fetch returns nothing useful.
        final yearEvents = await repo.getCalendarEventsForYear(
          year: selectedYear,
        );

        final byId = <String, CalendarEvent>{
          for (final cal in yearEvents) _sanitizeCalendarEventId(cal.name): cal,
        };

        final ordered = <CalendarEvent>[];
        var initialIndex = 0;
        for (final visible in visibleCommunity) {
          final match = byId[visible.id];
          if (match == null) continue;
          if (visible.id == event.id) {
            initialIndex = ordered.length;
          }
          ordered.add(match);
        }

        // Fallback: tapped event not in year set (defensive) — try title search.
        if (ordered.isEmpty || byId[event.id] == null) {
          final results = await repo.searchCalendarEvents(event.title);
          CalendarEvent? match;
          for (final cal in results) {
            if (_sanitizeCalendarEventId(cal.name) == event.id) {
              match = cal;
              break;
            }
          }
          match ??= results.isNotEmpty ? results.first : null;

          if (!mounted) return;

          if (match == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Event details not found')),
            );
            return;
          }
          if (ordered.isEmpty) {
            ordered.add(match);
            initialIndex = 0;
          }
        }

        if (!mounted) return;

        Navigator.of(context).push(
          MaterialPageRoute(
            builder:
                (_) => CalendarEventDetailScreen(
                  events: ordered,
                  initialIndex: initialIndex,
                ),
          ),
        );
        return;
      }

      final broadcast = await ref
          .read(groupBroadcastRepositoryProvider)
          .getGroupBroadcastById(event.id);
      ref.read(selectedBroadcastModelProvider.notifier).state = broadcast;

      if (!mounted) return;
      if (ref.read(selectedBroadcastModelProvider) != null) {
        Navigator.pushNamed(context, '/tournament_detail_screen');
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open event')));
    }
  }

  String _sanitizeCalendarEventId(String name) {
    final sanitizedName =
        name
            .replaceAll(' ', '_')
            .replaceAll(RegExp(r'[^\w\-]'), '')
            .toLowerCase();
    return 'cal_event_$sanitizedName';
  }

  /// Build time control row for selected item display
  Widget _buildTimeControlRow(String? timeControl, String label) {
    return Row(
      children: [
        _getTimeControlIcon(timeControl),
        SizedBox(width: 8.w),
        Text(
          label,
          style: AppTypography.textSmMedium.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
      ],
    );
  }

  /// Build time control dropdown item with icon
  Widget _buildTimeControlDropdownItem(String? timeControl, String label) {
    return Row(
      children: [
        _getTimeControlIcon(timeControl),
        SizedBox(width: 10.w),
        Text(
          label,
          style: AppTypography.textSmMedium.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
      ],
    );
  }

  /// Get the appropriate icon for a time control
  Widget _getTimeControlIcon(String? timeControl) {
    if (timeControl == null) {
      return Icon(
        Icons.grid_view_rounded,
        size: 16.ic,
        color: context.colors.textSecondary,
      );
    }

    final lower = timeControl.toLowerCase();
    String? assetPath;

    if (lower.contains('blitz')) {
      assetPath = 'assets/pngs/blitz.png';
    } else if (lower.contains('rapid')) {
      assetPath = 'assets/pngs/rapid.png';
    } else if (lower.contains('standard') || lower.contains('classic')) {
      assetPath = 'assets/pngs/classical.png';
    } else if (lower.contains('bullet')) {
      // No bullet asset, use a lightning icon
      return Icon(
        Icons.flash_on_rounded,
        size: 16.ic,
        color: const Color(0xFFFFD700), // Gold color for bullet
      );
    }

    if (assetPath != null) {
      return Image.asset(
        assetPath,
        width: 16.sp,
        height: 16.sp,
        fit: BoxFit.contain,
      );
    }

    return Icon(
      Icons.timer_outlined,
      size: 16.ic,
      color: context.colors.textSecondary,
    );
  }
}

class _CalendarStatePanel extends StatelessWidget {
  const _CalendarStatePanel({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.actionIcon = Icons.refresh_rounded,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 32, color: context.colors.iconSecondary),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTypography.textLgBold.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textPrimaryMuted,
                  ),
                ),
                const SizedBox(height: 18),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: FilledButton.icon(
                    onPressed: onAction,
                    icon: Icon(actionIcon),
                    label: Text(actionLabel),
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

/// Opaque month content card. Calendar management controls remain glass.
class _MonthButton extends StatelessWidget {
  const _MonthButton({
    required this.monthName,
    required this.eventCount,
    required this.onTap,
  });

  final String monthName;
  final int eventCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final eventLabel =
        eventCount == 0
            ? 'No events'
            : '$eventCount ${eventCount == 1 ? 'event' : 'events'}';
    return Semantics(
      button: true,
      label: '$monthName, $eventLabel',
      onTap: onTap,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Material(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(14.br),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: context.colors.divider),
                  borderRadius: BorderRadius.circular(14.br),
                ),
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        monthName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.textMdMedium.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                    if (eventCount > 0) ...[
                      SizedBox(width: 8.w),
                      Container(
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        alignment: Alignment.center,
                        padding: EdgeInsets.symmetric(horizontal: 8.sp),
                        decoration: BoxDecoration(
                          color: context.colors.surfaceRecessed,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$eventCount',
                          style: AppTypography.textXsBold.copyWith(
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickFilterButtons extends ConsumerWidget {
  const _QuickFilterButtons({required this.controlHeight});

  final double controlHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filterMode = ref.watch(calendarFilterModeProvider);
    final calendarData = ref.watch(calendarScreenProvider);
    final selectedYear = ref.watch(selectedYearProvider);
    final currentYear = DateTime.now().year;
    final isUpcomingDisabled = selectedYear > currentYear;

    // Calculate upcoming count (events starting today or in future)
    // This should show the count of upcoming events that match the current search
    final upcomingCount = calendarData.maybeWhen(
      data: (summaries) {
        // If we're already in upcoming filter mode, show the actual filtered count
        if (filterMode == CalendarFilterMode.upcoming) {
          int count = 0;
          for (final summary in summaries) {
            count += summary.events.length;
          }
          return count;
        }

        // Otherwise, calculate potential upcoming events from current filtered data
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        int count = 0;
        for (final summary in summaries) {
          for (final event in summary.events) {
            final startDate = event.startDate ?? event.endDate;
            if (startDate == null || startDate.isBefore(today)) continue;
            // Mirror the Upcoming filter: only curated FIDE major-calendar
            // events + Lichess broadcasts count toward the Upcoming badge.
            if (event.eventSource == EventSource.communityEvent &&
                !event.isMajorUpcoming) {
              continue;
            }
            count++;
          }
        }
        return count;
      },
      orElse: () => 0,
    );

    // Calculate favorites count from starred events.
    final favoriteEventIdsAsync = ref.watch(calendarFavoriteEventIdsProvider);

    final favoritesCount = calendarData.maybeWhen(
      data: (summaries) {
        // If we're already in favorites filter mode, show the actual filtered count
        if (filterMode == CalendarFilterMode.favorites) {
          // Deduplicate events across months
          final uniqueIds = <String>{};
          for (final summary in summaries) {
            for (final event in summary.events) {
              uniqueIds.add(event.id);
            }
          }
          return uniqueIds.length;
        }

        // Otherwise, calculate potential favorite events from current year data
        final favoriteEventIds =
            favoriteEventIdsAsync.valueOrNull ?? <String>{};

        // Count unique events in the current data that are in our favorites set
        final matchingEventIds = <String>{};
        for (final summary in summaries) {
          for (final event in summary.events) {
            if (matchingEventIds.contains(event.id)) continue;

            if (favoriteEventIds.contains(event.id)) {
              matchingEventIds.add(event.id);
            }
          }
        }
        return matchingEventIds.length;
      },
      orElse: () => 0,
    );

    void changeFilter(CalendarFilterMode next) {
      final current = ref.read(calendarFilterModeProvider);
      if (next == current) return;
      ref.read(calendarFilterModeProvider.notifier).state = next;
      AnalyticsService.instance.trackEventDetached(
        'Calendar Filter Changed',
        properties: {'previous_filter': current.name, 'filter': next.name},
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FilterButton(
          key: const ValueKey<String>('calendar-filter-months'),
          label: 'Months',
          icon: Icons.calendar_view_month_rounded,
          count: 0,
          controlHeight: controlHeight,
          isSelected: filterMode == CalendarFilterMode.all,
          onTap: () => changeFilter(CalendarFilterMode.all),
        ),
        const SizedBox(width: 8),
        _FilterButton(
          key: const ValueKey<String>('calendar-filter-upcoming'),
          label: 'Upcoming',
          icon: Icons.schedule_rounded,
          count: upcomingCount,
          controlHeight: controlHeight,
          isSelected: filterMode == CalendarFilterMode.upcoming,
          isDisabled: isUpcomingDisabled,
          onTap: () {
            if (isUpcomingDisabled) return;
            changeFilter(
              filterMode == CalendarFilterMode.upcoming
                  ? CalendarFilterMode.all
                  : CalendarFilterMode.upcoming,
            );
          },
        ),
        const SizedBox(width: 8),
        _FilterButton(
          key: const ValueKey<String>('calendar-filter-favorites'),
          label: 'Favorites',
          icon: Icons.star_rounded,
          count: favoritesCount,
          controlHeight: controlHeight,
          isSelected: filterMode == CalendarFilterMode.favorites,
          onTap: () {
            changeFilter(
              filterMode == CalendarFilterMode.favorites
                  ? CalendarFilterMode.all
                  : CalendarFilterMode.favorites,
            );
          },
        ),
      ],
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    super.key,
    required this.label,
    required this.icon,
    required this.count,
    required this.controlHeight,
    required this.isSelected,
    required this.onTap,
    this.isDisabled = false,
  });

  final String label;
  final IconData icon;
  final int count;
  final double controlHeight;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final iconColor =
        isDisabled
            ? context.colors.placeholder
            : isSelected
            ? kPrimaryColor
            : context.colors.textSecondary;
    final textColor =
        isDisabled
            ? context.colors.placeholder
            : isSelected
            ? kPrimaryColor
            : context.colors.textPrimary;
    final visibleLabel = count > 0 ? '$label · $count' : label;
    final semanticsLabel = count > 0 ? '$label, $count events' : label;
    final reduceMotion = GlassMotion.reduceMotion(context);

    return Semantics(
      button: true,
      selected: isSelected,
      enabled: !isDisabled,
      label: semanticsLabel,
      onTap: isDisabled ? null : onTap,
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: controlHeight),
          child: GlassChip(
            label: visibleLabel,
            icon: Icon(icon, size: 17.ic, color: iconColor),
            selected: isSelected,
            selectedColor: kPrimaryColor.withValues(
              alpha: context.isLightTheme ? 0.18 : 0.28,
            ),
            useOwnLayer: true,
            quality: GlassQuality.standard,
            labelStyle: AppTypography.textSmMedium.copyWith(color: textColor),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            interactionScale: reduceMotion ? 1 : 1.03,
            stretch: reduceMotion ? 0 : 0.3,
            onTap: isDisabled ? null : onTap,
          ),
        ),
      ),
    );
  }
}
