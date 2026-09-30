import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/calendar/calendar_event_detail_screen.dart';
import 'package:chessever2/screens/calendar/provider/calendar_detail_screen_provider.dart';
import 'package:chessever2/screens/calendar/provider/calendar_month_events_provider.dart';
import 'package:chessever2/screens/calendar/provider/calendar_screen_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/user_error_message.dart';
import 'package:chessever2/widgets/app_snack.dart';
import 'package:chessever2/widgets/generic_error_widget.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/simple_search_bar.dart';
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

/// Pushes the calendar as an ordinary route. It is no longer a main section;
/// the sidebar month view is its entry point.
///
/// [day] opens it on that day's events. Without it the year of months opens
/// at today. Year and month move to the target before the route builds, so
/// the year grid never fetches the wrong year first, and filters left over
/// from an earlier visit are cleared so every open starts clean.
Future<void> openCalendarScreen(
  BuildContext context, {
  DateTime? day,
  String source = 'sidebar',
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final navigator = Navigator.of(context);
  final years = container.read(availableYearsProvider);
  // The year dropdown only offers [years]; a day outside them cannot be shown.
  final focus =
      day != null && years.contains(day.year) ? DateUtils.dateOnly(day) : null;
  final target = focus ?? DateTime.now();

  container.read(selectedYearProvider.notifier).state = target.year;
  container.read(selectedMonthProvider.notifier).state = target.month;
  container.read(calendarSearchQueryProvider.notifier).state = '';
  container.read(calendarTimeControlProvider.notifier).state = null;
  container.read(calendarFilterModeProvider.notifier).state =
      CalendarFilterMode.all;

  AnalyticsService.instance.trackEventDetached(
    'Calendar Opened',
    properties: {'source': source, 'focused_day': focus != null},
  );

  return navigator.push(
    MaterialPageRoute<void>(builder: (_) => CalendarScreen(initialDate: focus)),
  );
}

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key, this.initialDate});

  /// Opens the screen on this day's events instead of the year of months.
  /// Use [openCalendarScreen], which also moves the year to match.
  final DateTime? initialDate;

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  final TextEditingController searchController = TextEditingController();
  final focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchAnalyticsTimer;

  /// The day whose events are shown in place of the month grid, or null.
  DateTime? _focusDay;

  @override
  void initState() {
    super.initState();
    // The query outlives the screen; show it rather than an empty field over
    // filtered results.
    searchController.text = ref.read(calendarSearchQueryProvider);
    final initial = widget.initialDate;
    if (initial == null) return;
    _focusDay = DateUtils.dateOnly(initial);
    // Opened directly rather than through [openCalendarScreen]: bring the
    // year along after the first frame so the grid behind the day matches.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final day = _focusDay;
      if (day == null) return;
      if (ref.read(selectedYearProvider) != day.year &&
          ref.read(availableYearsProvider).contains(day.year)) {
        ref.read(selectedYearProvider.notifier).state = day.year;
      }
    });
  }

  @override
  void dispose() {
    searchController.dispose();
    focusNode.dispose();
    _scrollController.dispose();
    _searchAnalyticsTimer?.cancel();
    super.dispose();
  }

  void _clearFocus() {
    if (_focusDay == null) return;
    setState(() => _focusDay = null);
  }

  @override
  Widget build(BuildContext context) {
    // Searching, switching to a quick filter or picking another year asks a
    // different question than "what is on this day", so the day gives way.
    ref.listen<String>(calendarSearchQueryProvider, (_, next) {
      if (next.trim().isNotEmpty) _clearFocus();
    });
    ref.listen<CalendarFilterMode>(calendarFilterModeProvider, (_, next) {
      if (next != CalendarFilterMode.all) _clearFocus();
    });
    ref.listen<int>(selectedYearProvider, (_, next) {
      if (_focusDay != null && _focusDay!.year != next) _clearFocus();
    });

    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final yearList = ref.read(availableYearsProvider);
    const timeControls = ['Standard', 'Rapid', 'Blitz'];
    final filterMode = ref.watch(calendarFilterModeProvider);
    final searchQuery = ref.watch(calendarSearchQueryProvider);
    final isListMode =
        filterMode != CalendarFilterMode.all || searchQuery.trim().isNotEmpty;

    return Scaffold(
      key: e2eKey(E2eIds.calendarRoot),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 24.h + MediaQuery.of(context).viewPadding.top),

          /// Search bar + Filters
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.sp),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (canPop) ...[
                      _CalendarBackButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      SizedBox(width: 4.w),
                    ],

                    /// Search bar
                    Expanded(
                      child: Hero(
                        tag: 'search_bar',
                        child: Material(
                          color: Colors.transparent,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            padding: EdgeInsets.symmetric(
                              horizontal: 2.sp,
                              vertical: 4.sp,
                            ),
                            decoration: BoxDecoration(
                              color: context.colors.surfaceRecessed,
                              borderRadius: BorderRadius.circular(8.br),
                              border: Border.all(
                                // Light matches the sibling search fields:
                                // an accentText ring, no raw-cyan glow.
                                color:
                                    focusNode.hasFocus
                                        ? (context.isLightTheme
                                            ? context.colors.accentText
                                            : kPrimaryColor.withValues(
                                              alpha: 0.5,
                                            ))
                                        : Colors.transparent,
                                width: 2.0,
                              ),
                              boxShadow:
                                  focusNode.hasFocus && !context.isLightTheme
                                      ? [
                                        BoxShadow(
                                          color: kPrimaryColor.withValues(
                                            alpha: 0.15,
                                          ),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                      : [],
                            ),
                            child: SimpleSearchBar(
                              key: e2eKey(E2eIds.calendarSearchField),
                              textFieldKey: e2eKey(E2eIds.calendarSearchField),
                              controller: searchController,
                              focusNode: focusNode,
                              hintText: 'Search',
                              onCloseTap: () {
                                searchController.clear();
                                focusNode.unfocus();
                                ref
                                    .read(calendarSearchQueryProvider.notifier)
                                    .state = '';
                              },
                              onChanged: (val) {
                                ref
                                    .read(calendarSearchQueryProvider.notifier)
                                    .state = val;
                                _searchAnalyticsTimer?.cancel();
                                final query = val.trim();
                                if (query.isEmpty) return;
                                _searchAnalyticsTimer = Timer(
                                  const Duration(milliseconds: 350),
                                  () {
                                    AnalyticsService.instance
                                        .trackEventDetached(
                                          'Calendar Search',
                                          properties: {
                                            'query': query,
                                            'query_length': query.length,
                                          },
                                        );
                                  },
                                );
                              },
                              onOpenFilter: null,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),

                    /// Year dropdown
                    Container(
                      height: 48.h,
                      padding: EdgeInsets.symmetric(horizontal: 12.w),
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        borderRadius: BorderRadius.circular(8.br),
                        border: Border.all(
                          color: context.colors.divider,
                          width: 1.w,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: ref.watch(selectedYearProvider),
                          onChanged: (int? newValue) {
                            if (newValue != null) {
                              ref.read(selectedYearProvider.notifier).state =
                                  newValue;
                              AnalyticsService.instance.trackEventDetached(
                                'Calendar Year Changed',
                                properties: {'year': newValue},
                              );
                            }
                          },
                          icon: Icon(
                            Icons.keyboard_arrow_down_outlined,
                            color: context.colors.iconPrimary,
                            size: 20.ic,
                          ),
                          style: AppTypography.textMdBold.copyWith(
                            color: context.colors.textPrimary,
                          ),
                          dropdownColor: context.colors.surface,
                          borderRadius: BorderRadius.circular(8.br),
                          items:
                              yearList.map((value) {
                                return DropdownMenuItem<int>(
                                  value: value,
                                  child: Text(value.toString()),
                                );
                              }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),
                Row(
                  children: [
                    /// Time Control dropdown with icons
                    Expanded(
                      child: Container(
                        height: 40.h,
                        padding: EdgeInsets.symmetric(horizontal: 12.w),
                        decoration: BoxDecoration(
                          color: context.colors.surface,
                          borderRadius: BorderRadius.circular(8.br),
                          border: Border.all(
                            color: context.colors.divider,
                            width: 1.w,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: ref.watch(calendarTimeControlProvider),
                            hint: Row(
                              children: [
                                Icon(
                                  Icons.speed_outlined,
                                  size: 16.ic,
                                  color: context.colors.textSecondary,
                                ),
                                SizedBox(width: 8.w),
                                Text(
                                  'Time Control',
                                  style: AppTypography.textSmRegular.copyWith(
                                    color: context.colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            onChanged: (String? newValue) {
                              ref
                                  .read(calendarTimeControlProvider.notifier)
                                  .state = newValue;
                              AnalyticsService.instance.trackEventDetached(
                                'Calendar Time Control Selected',
                                properties: {'time_control': newValue ?? 'All'},
                              );
                            },
                            icon: Icon(
                              Icons.keyboard_arrow_down_outlined,
                              color: context.colors.iconPrimary,
                              size: 20.ic,
                            ),
                            style: AppTypography.textMdBold.copyWith(
                              color: context.colors.textPrimary,
                            ),
                            dropdownColor: context.colors.surface,
                            borderRadius: BorderRadius.circular(8.br),
                            isExpanded: true,
                            selectedItemBuilder: (context) {
                              return [
                                _buildTimeControlRow(null, 'All Formats'),
                                _buildTimeControlRow('Standard', 'Standard'),
                                _buildTimeControlRow('Rapid', 'Rapid'),
                                _buildTimeControlRow('Blitz', 'Blitz'),
                              ];
                            },
                            items: [
                              DropdownMenuItem<String?>(
                                value: null,
                                child: _buildTimeControlDropdownItem(
                                  null,
                                  'All Formats',
                                ),
                              ),
                              ...timeControls.map((value) {
                                return DropdownMenuItem<String?>(
                                  value: value,
                                  child: _buildTimeControlDropdownItem(
                                    value,
                                    value,
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12.h),

                /// Quick Filter Buttons (Upcoming / Favorites)
                _QuickFilterButtons(),
              ],
            ),
          ),

          SizedBox(height: 16.h),

          /// A focused day, or the month grid
          if (_focusDay != null)
            Expanded(child: _buildDayFocus(_focusDay!))
          else
          Expanded(
            child: ref
                .watch(calendarScreenProvider)
                .when(
                  data: (rawData) {
                    final data = orderMonthsByRelevance(
                      rawData,
                      ref.watch(selectedYearProvider),
                    );
                    if (isListMode) {
                      return _buildEventList(data);
                    }

                    final isTablet = ResponsiveHelper.isTablet;
                    final crossAxisCount = isTablet ? 3 : 2;

                    return RefreshIndicator(
                      onRefresh: () async {
                        HapticFeedbackService.medium();
                        // Invalidate the calendar provider to refresh data
                        ref.invalidate(calendarScreenProvider);
                      },
                      color: context.colors.accentText,
                      backgroundColor: context.colors.surface,
                      displacement: 60.h,
                      strokeWidth: 3.w,
                      child: GridView.builder(
                        controller: _scrollController,
                        // Explicit padding stops the scroll view adding the
                        // home-indicator inset itself, so add it here: this
                        // is a pushed route with no bottom bar beneath it.
                        padding: EdgeInsets.fromLTRB(
                          16.sp,
                          0,
                          16.sp,
                          12.sp + MediaQuery.viewPaddingOf(context).bottom,
                        ),
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 12.sp,
                          crossAxisSpacing: 12.sp,
                          childAspectRatio: 2.2,
                        ),
                        itemCount: data.length,
                        itemBuilder: (context, index) {
                          final summary = data[index];
                          return _MonthButton(
                            monthName: summary.monthName,
                            eventCount: summary.eventCount,
                            onTap: () {
                              ref.read(selectedMonthProvider.notifier).state =
                                  summary.monthNumber;
                              AnalyticsService.instance.trackEventDetached(
                                'Calendar Month Opened',
                                properties: {
                                  'month': summary.monthNumber,
                                  'month_name': summary.monthName,
                                  'event_count': summary.eventCount,
                                  'year': ref.read(selectedYearProvider),
                                },
                              );
                              Navigator.pushNamed(
                                context,
                                '/calendar_detail_screen',
                              );
                            },
                          );
                        },
                      ),
                    );
                  },
                  error: (e, _) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Failed To Load Months!\nPlease Try Again Later',
                            style: AppTypography.textLgRegular.copyWith(
                              color: context.colors.textPrimary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  },
                  loading: () {
                    final isTablet = ResponsiveHelper.isTablet;
                    final crossAxisCount = isTablet ? 3 : 2;
                    final months = [
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
                      child: GridView.builder(
                        padding: EdgeInsets.fromLTRB(
                          16.sp,
                          0,
                          16.sp,
                          12.sp + MediaQuery.viewPaddingOf(context).bottom,
                        ),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 12.sp,
                          crossAxisSpacing: 12.sp,
                          childAspectRatio: 2.2,
                        ),
                        itemCount: 12,
                        itemBuilder: (context, index) {
                          return _MonthButton(
                            monthName: months[index],
                            eventCount: (index % 3 == 0) ? index + 1 : 0,
                            onTap: () {},
                          );
                        },
                      ),
                    );
                  },
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

    return _buildEventCollection(
      events: sortedEvents,
      onRefresh: () async {
        HapticFeedbackService.medium();
        ref.invalidate(calendarScreenProvider);
      },
      emptyText: 'No events found',
      heroPrefix: 'calendar-list',
    );
  }

  /// The day view: every event running on [day], in the calendar's usual
  /// card list, from the same month rows the sidebar marked the day with.
  Widget _buildDayFocus(DateTime day) {
    final args = CalendarFilterArgs(month: day.month, year: day.year);
    final monthAsync = ref.watch(calendarMonthEventsProvider(args));
    final liveIds =
        ref.watch(liveGroupBroadcastIdsProvider).valueOrNull ??
        const <String>[];
    final timeControl = normalizeTimeControl(
      ref.watch(calendarTimeControlProvider),
    );

    List<GroupEventCardModel> eventsOn(CalendarMonthEvents month) {
      final events = <GroupEventCardModel>[
        for (final b in month.broadcasts)
          if (calendarEventRunsOn(b.dateStart, b.dateEnd, day))
            GroupEventCardModel.fromGroupBroadcast(b, liveIds),
        for (final e in month.calendarEvents)
          if (calendarEventRunsOn(e.startDate, e.endDate, day))
            GroupEventCardModel.fromCalendarEvent(e),
      ];
      final shown =
          timeControl == null
              ? events
              : events
                  .where((e) => normalizeTimeControl(e.timeControl) == timeControl)
                  .toList();
      return ref
          .read(tournamentSortingServiceProvider)
          .sortCalendarEvents(shown, prioritizeFavorites: false);
    }

    final events = monthAsync.whenOrNull(data: eventsOn);
    final years = ref.watch(availableYearsProvider);
    final firstDay = DateTime(years.first);
    final lastDay = DateTime(years.last, 12, 31);

    final Widget body = monthAsync.when(
      data: (_) => _buildEventCollection(
        events: events!,
        onRefresh: () async {
          HapticFeedbackService.medium();
          ref.invalidate(calendarMonthEventsProvider(args));
          try {
            await ref.read(calendarMonthEventsProvider(args).future);
          } catch (_) {
            // The error branch shows the failure with a retry.
          }
        },
        emptyText: 'No events on this day',
        heroPrefix: 'calendar-day',
      ),
      loading: () => const _DayLoadingTiles(),
      error: (error, _) => GenericErrorWidget(
        message: userFacingError(
          error,
          fallback: "Couldn't load this day's events",
        ),
        onRetry: () => ref.invalidate(calendarMonthEventsProvider(args)),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DayFocusHeader(
          day: day,
          eventCount: events?.length,
          onPrevious:
              day.isAfter(firstDay) ? () => _stepDay(day, -1) : null,
          onNext: day.isBefore(lastDay) ? () => _stepDay(day, 1) : null,
          onShowMonths: () {
            HapticFeedbackService.navigation();
            _clearFocus();
          },
        ),
        Expanded(child: body),
      ],
    );
  }

  void _stepDay(DateTime from, int delta) {
    HapticFeedbackService.selection();
    final next = DateTime(from.year, from.month, from.day + delta);
    setState(() => _focusDay = next);
    // Keep the year behind the day in step; the listener sees the new focus
    // year and leaves the day in place.
    if (ref.read(selectedYearProvider) != next.year) {
      ref.read(selectedYearProvider.notifier).state = next.year;
    }
    ref.read(selectedMonthProvider.notifier).state = next.month;
  }

  /// Event cards as the calendar shows them: a grid on tablets, a list on
  /// phones, pull to refresh, and [emptyText] when there is nothing to show.
  Widget _buildEventCollection({
    required List<GroupEventCardModel> events,
    required Future<void> Function() onRefresh,
    required String emptyText,
    required String heroPrefix,
  }) {
    final isTablet = ResponsiveHelper.isTablet;
    final crossAxisCount = ResponsiveHelper.getGridCrossAxisCount(
      phoneCount: 1,
    );
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.sp,
      tablet: 24.sp,
    );
    // Explicit padding stops the scroll view adding the home-indicator inset
    // itself; this is a pushed route, so nothing else clears it.
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: context.colors.accentText,
      backgroundColor: context.colors.surface,
      displacement: 60.h,
      strokeWidth: 3.w,
      child:
          events.isEmpty
              ? ListView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  24.h,
                  horizontalPadding,
                  24.h + bottomInset,
                ),
                children: [
                  Center(
                    child: Text(
                      emptyText,
                      style: AppTypography.textLgRegular.copyWith(
                        color: context.colors.textPrimaryMuted,
                      ),
                    ),
                  ),
                ],
              )
              // Use grid layout for tablets, list for phones
              : isTablet && crossAxisCount > 1
              ? GridView.builder(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  12.h,
                  horizontalPadding,
                  12.h + bottomInset,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 16.sp,
                  mainAxisSpacing: 16.sp,
                  childAspectRatio: ResponsiveHelper.isLandscape ? 2.2 : 1.8,
                ),
                itemCount: events.length,
                itemBuilder: (context, index) {
                  final event = events[index];
                  return EventCard(
                    tourEventCardModel: event,
                    heroTagSuffix: '$heroPrefix-$index',
                    onTap: () => _onEventTap(event, events),
                  );
                },
              )
              : ListView.builder(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  12.h,
                  horizontalPadding,
                  12.h + bottomInset,
                ),
                itemCount: events.length,
                itemBuilder: (context, index) {
                  final event = events[index];
                  return Padding(
                    padding: EdgeInsets.only(bottom: 12.h),
                    child: EventCard(
                      tourEventCardModel: event,
                      heroTagSuffix: '$heroPrefix-$index',
                      onTap: () => _onEventTap(event, events),
                    ),
                  );
                },
              ),
    );
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
          for (final cal in yearEvents)
            _sanitizeCalendarEventId(cal.name): cal,
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
            showAppSnack(
              context,
              'Event details not found',
              tone: AppSnackTone.danger,
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
            builder: (_) => CalendarEventDetailScreen(
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
      showAppSnack(
        context,
        'Unable to open event',
        tone: AppSnackTone.danger,
      );
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
      assetPath = PngAsset.blitzIcon;
    } else if (lower.contains('rapid')) {
      assetPath = PngAsset.rapidIcon;
    } else if (lower.contains('standard') || lower.contains('classic')) {
      assetPath = PngAsset.classicalIcon;
    } else if (lower.contains('bullet')) {
      // Bullet has no mark of its own. Borrow the blitz coin, as the library
      // and feed cards do, and let the label beside it name the format; a
      // second, stock Material bolt read as a near-duplicate of blitz.
      assetPath = PngAsset.blitzIcon;
    }

    if (assetPath != null) {
      return TimeControlGlyph(assetPath, size: 16.sp);
    }

    return Icon(
      Icons.timer_outlined,
      size: 16.ic,
      color: context.colors.textSecondary,
    );
  }
}

/// Simple month button - just name and count
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
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8.br),
      child: InkWell(
        borderRadius: BorderRadius.circular(8.br),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(8.br),
            border: Border.all(
              color: context.colors.divider,
              width: 1,
            ),
          ),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          child: Row(
            children: [
              // Month name takes available space, aligns left
              Expanded(
                child: Text(
                  monthName,
                  style: AppTypography.textMdMedium.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              // Event count badge always on the right
              if (eventCount > 0)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 8.sp,
                    vertical: 4.sp,
                  ),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceRecessed,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    eventCount.toString(),
                    style: AppTypography.textXsBold.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickFilterButtons extends ConsumerWidget {
  const _QuickFilterButtons();

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

    return Row(
      children: [
        Expanded(
          child: _FilterButton(
            label: 'Upcoming',
            icon: Icons.schedule_rounded,
            count: upcomingCount,
            isSelected: filterMode == CalendarFilterMode.upcoming,
            isDisabled: isUpcomingDisabled,
            onTap: () {
              if (isUpcomingDisabled) return;
              final current = ref.read(calendarFilterModeProvider);
              final next =
                  current == CalendarFilterMode.upcoming
                      ? CalendarFilterMode.all
                      : CalendarFilterMode.upcoming;
              ref.read(calendarFilterModeProvider.notifier).state = next;
              AnalyticsService.instance.trackEventDetached(
                'Calendar Filter Changed',
                properties: {
                  'previous_filter': current.name,
                  'filter': next.name,
                },
              );
            },
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: _FilterButton(
            label: 'Favorites',
            icon: Icons.star_rounded,
            count: favoritesCount,
            isSelected: filterMode == CalendarFilterMode.favorites,
            onTap: () {
              final current = ref.read(calendarFilterModeProvider);
              final next =
                  current == CalendarFilterMode.favorites
                      ? CalendarFilterMode.all
                      : CalendarFilterMode.favorites;
              ref.read(calendarFilterModeProvider.notifier).state = next;
              AnalyticsService.instance.trackEventDetached(
                'Calendar Filter Changed',
                properties: {
                  'previous_filter': current.name,
                  'filter': next.name,
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    required this.label,
    required this.icon,
    required this.count,
    required this.isSelected,
    required this.onTap,
    this.isDisabled = false,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final iconColor = isDisabled
        ? context.colors.placeholder
        : isSelected
            ? context.colors.accentText
            : context.colors.textSecondary;
    final textColor = isDisabled
        ? context.colors.placeholder
        : isSelected
            ? context.colors.accentText
            : context.colors.textPrimary;
    final badgeColor = isDisabled
        ? context.colors.divider.withValues(alpha: 0.4)
        : isSelected
            // On the deeper cyan wash the count only just makes 4.5:1 on
            // paper; light seats it on the surface instead (6.8:1).
            ? (context.isLightTheme
                ? context.colors.surface
                : kPrimaryColor.withValues(alpha: 0.25))
            : context.colors.surfaceRecessed;
    final badgeTextColor = isDisabled
        ? context.colors.placeholder
        : isSelected
            ? context.colors.accentText
            : context.colors.textSecondary;
    final borderColor = isDisabled
        ? context.colors.divider
        : isSelected
            // Cyan at 0.6 is 1.7:1 on paper; light rings in the accent ink.
            ? (context.isLightTheme
                ? context.colors.accentText
                : kPrimaryColor.withValues(alpha: 0.6))
            : context.colors.divider;
    final backgroundColor = isDisabled
        ? context.colors.surface.withValues(alpha: 0.6)
        : isSelected
            ? kPrimaryColor.withValues(alpha: 0.12)
            : context.colors.surface;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10.br),
      child: InkWell(
        borderRadius: BorderRadius.circular(10.br),
        onTap: isDisabled ? null : onTap,
        child: Container(
          height: 44.h,
          padding: EdgeInsets.symmetric(horizontal: 14.w),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(10.br),
            border: Border.all(
              color: borderColor,
              width: isSelected ? 1.5.w : 1.w,
            ),
            // Subtle gradient overlay for filter buttons to differentiate from month boxes
            gradient:
                isSelected
                    ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        kPrimaryColor.withValues(alpha: 0.15),
                        kPrimaryColor.withValues(alpha: 0.05),
                      ],
                    )
                    : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon indicator - key visual differentiator
              Icon(icon, size: 16.ic, color: iconColor),
              SizedBox(width: 6.w),
              Text(
                label,
                style: AppTypography.textSmMedium.copyWith(
                  color: textColor,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              if (count > 0) ...[
                SizedBox(width: 6.w),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 6.sp,
                    vertical: 2.sp,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    count.toString(),
                    style: AppTypography.textXsBold.copyWith(
                      color: badgeTextColor,
                      fontSize: 10.sp,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Back to wherever the calendar was opened from, on a 44pt target.
class _CalendarBackButton extends StatelessWidget {
  const _CalendarBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: IconButton(
        tooltip: 'Back',
        padding: EdgeInsets.zero,
        onPressed: () {
          HapticFeedbackService.navigation();
          onPressed();
        },
        icon: Icon(
          Icons.arrow_back_ios_new_rounded,
          color: context.colors.iconPrimary,
          size: 20.ic,
        ),
      ),
    );
  }
}

/// Title row of the day view: the date with previous/next day steps, then
/// the event count and the way back to the year of months.
class _DayFocusHeader extends StatelessWidget {
  const _DayFocusHeader({
    required this.day,
    required this.eventCount,
    required this.onPrevious,
    required this.onNext,
    required this.onShowMonths,
  });

  final DateTime day;

  /// Null while the month is loading.
  final int? eventCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onShowMonths;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // Another year's date carries the year, so its weekday is shortened to
    // keep the title whole on a narrow phone.
    final pattern =
        day.year == DateTime.now().year ? 'EEEE, d MMMM' : 'EEE, d MMMM y';
    final count = eventCount;
    final countLabel = switch (count) {
      null => '',
      1 => '1 event',
      _ => '$count events',
    };

    return Padding(
      // The step buttons' 44pt boxes overhang the 16pt gutter so their
      // glyphs, not their boxes, line up with the content edge.
      padding: EdgeInsets.fromLTRB(16.sp, 0, 6.sp, 4.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    liveRegion: true,
                    child: Text(
                      DateFormat(pattern).format(day),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.textLgBold.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ),
                _DayStepButton(
                  icon: Icons.chevron_left_rounded,
                  tooltip: 'Previous day',
                  onPressed: onPrevious,
                ),
                _DayStepButton(
                  icon: Icons.chevron_right_rounded,
                  tooltip: 'Next day',
                  onPressed: onNext,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    countLabel,
                    maxLines: 1,
                    style: AppTypography.textSmRegular.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                InkWell(
                  onTap: onShowMonths,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10.sp),
                    child: Center(
                      child: Text(
                        'All months',
                        style: AppTypography.textSmMedium.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
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

class _DayStepButton extends StatelessWidget {
  const _DayStepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.iconPrimary;
    return SizedBox.square(
      dimension: 44,
      child: IconButton(
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        onPressed: onPressed,
        color: ink,
        disabledColor: ink.withValues(alpha: 0.25),
        icon: Icon(icon, size: 24.ic),
      ),
    );
  }
}

/// Plain card-shaped tiles while a day's month loads, in the same list or
/// grid the cards will take. Real event cards would look up images for ids
/// that do not exist.
class _DayLoadingTiles extends StatelessWidget {
  const _DayLoadingTiles();

  @override
  Widget build(BuildContext context) {
    final crossAxisCount = ResponsiveHelper.getGridCrossAxisCount(
      phoneCount: 1,
    );
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.sp,
      tablet: 24.sp,
    );
    final tile = DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
    );
    final padding = EdgeInsets.symmetric(
      horizontal: horizontalPadding,
      vertical: 12.h,
    );

    if (ResponsiveHelper.isTablet && crossAxisCount > 1) {
      return GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 16.sp,
          mainAxisSpacing: 16.sp,
          childAspectRatio: ResponsiveHelper.isLandscape ? 2.2 : 1.8,
        ),
        itemCount: crossAxisCount * 2,
        itemBuilder: (_, _) => tile,
      );
    }
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      itemCount: 4,
      itemBuilder:
          (_, _) => Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: SizedBox(height: 96.h, child: tile),
          ),
    );
  }
}
