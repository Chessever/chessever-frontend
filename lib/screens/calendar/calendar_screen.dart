import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/calendar/calendar_event_detail_screen.dart';
import 'package:chessever2/screens/calendar/provider/calendar_screen_provider.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/liquid_glass/home_search_providers.dart';
import 'package:chessever2/widgets/liquid_glass/glass_profile_header.dart';
import 'package:chessever2/widgets/liquid_glass/chrome_scroll_collapse.dart';
import 'package:chessever2/widgets/liquid_glass/liquid_tab_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';
import 'package:chessever2/widgets/screen_wrapper.dart';
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

/// Tab order for the calendar mode chips (mirrors the home header tabs).
const _calendarModes = <CalendarFilterMode>[
  CalendarFilterMode.all,
  CalendarFilterMode.upcoming,
  CalendarFilterMode.favorites,
];

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  final ScrollController _scrollController = ScrollController();
  final ChromeScrollCollapse _chromeCollapse = ChromeScrollCollapse();
  Timer? _searchAnalyticsTimer;

  /// Top mode tabs unite at the top of the list, separate on scroll-down —
  /// identical to the home header tabs.
  bool _controlsSeparated = false;

  @override
  void dispose() {
    _scrollController.dispose();
    _searchAnalyticsTimer?.cancel();
    super.dispose();
  }

  /// Floating calendar controls on a single horizontal line, mirroring the
  /// home header: avatar/name fills the leftover width, the All / Upcoming /
  /// Favorites tabs hug the right. The Format+Year filter is NOT a header
  /// button — it opens from the bottom-nav search bar's Filter action (only
  /// visible while search is active), same as the home page.
  Widget _buildFloatingControls() {
    final filterMode = ref.watch(calendarFilterModeProvider);
    final selectedIndex = _calendarModes
        .indexOf(filterMode)
        .clamp(0, _calendarModes.length - 1);

    // Matches the Tournaments/Library headers so the avatar sits at the same x.
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 12.sp,
      tablet: 24.sp,
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            // Header takes ALL leftover width so the name fills the gap up to
            // the tabs; the tabs keep their natural width on the right.
            Expanded(
              child: GlassProfileHeader(collapsed: _controlsSeparated),
            ),
            const SizedBox(width: 8),
            // Glued at the top of the list, loosening into gapped icon chips on
            // scroll-down.
            LiquidTabBar(
              options: const ['All', 'Upcoming', 'Favorites'],
              icons: const [
                CupertinoIcons.square_grid_2x2,
                CupertinoIcons.clock,
                CupertinoIcons.heart,
              ],
              selectedIndex: selectedIndex,
              onSelected: (i) {
                HapticFeedbackService.light();
                ref.read(calendarFilterModeProvider.notifier).state =
                    _calendarModes[i];
              },
              separated: _controlsSeparated,
            ),
          ],
        ),
      ),
    );
  }

  /// Liquid-glass dropdown sheet to pick Format + Year.
  void _openCalendarFilter() {
    HapticFeedbackService.light();
    final years = ref.read(availableYearsProvider);
    const formats = <String?>[null, 'Standard', 'Rapid', 'Blitz'];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Consumer(
          builder: (ctx, sheetRef, _) {
            final colors = context.colors;
            final tc = sheetRef.watch(calendarTimeControlProvider);
            final year = sheetRef.watch(selectedYearProvider);

            Widget pill(String label, bool selected, VoidCallback onTap) {
              return GestureDetector(
                onTap: () {
                  HapticFeedbackService.light();
                  onTap();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color:
                        selected
                            ? colors.brand.withValues(alpha: 0.22)
                            : colors.surfaceRecessed,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color:
                          selected
                              ? colors.brand.withValues(alpha: 0.7)
                              : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    label,
                    style: AppTypography.textSmMedium.copyWith(
                      color: selected ? colors.brand : colors.textPrimary,
                    ),
                  ),
                ),
              );
            }

            return GlassContainer(
              useOwnLayer: true,
              shape: const LiquidRoundedSuperellipse(borderRadius: 26),
              settings: const LiquidGlassSettings(
                glassColor: Color(0xE6141821),
                thickness: 20,
                blur: 22,
                lightIntensity: 0,
                ambientStrength: 0,
                glowIntensity: 0,
                ambientRim: 0,
                chromaticAberration: 0,
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colors.divider,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text('Format', style: AppTypography.textMdBold),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final f in formats)
                            pill(
                              f ?? 'All',
                              tc == f,
                              () =>
                                  sheetRef
                                      .read(
                                        calendarTimeControlProvider.notifier,
                                      )
                                      .state = f,
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text('Year', style: AppTypography.textMdBold),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final y in years)
                            pill(
                              '$y',
                              y == year,
                              () =>
                                  sheetRef
                                      .read(selectedYearProvider.notifier)
                                      .state = y,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<BottomNavBarReTapRequest>(bottomNavBarReTapRequestProvider, (
      previous,
      next,
    ) {
      if (next.item == BottomNavBarItem.calendar) {
        _scrollToTop();
      }
    });

    // Search is driven from the single bottom-nav search field — it filters this
    // page in place, no dedicated search screen and no per-page search bar.
    // The bottom-nav search bar's Filter action (shown only while search is
    // active) opens the calendar's Format+Year sheet — matches the home page.
    ref.listen<int>(homeBottomSearchFilterRequestProvider, (previous, next) {
      if (previous == next) return;
      _openCalendarFilter();
    });

    ref.listen<String>(homeBottomSearchTextProvider, (previous, next) {
      if (previous == next) return;
      ref.read(calendarSearchQueryProvider.notifier).state = next;
      _searchAnalyticsTimer?.cancel();
      final query = next.trim();
      if (query.isEmpty) return;
      _searchAnalyticsTimer = Timer(const Duration(milliseconds: 350), () {
        AnalyticsService.instance.trackEventDetached(
          'Calendar Search',
          properties: {'query': query, 'query_length': query.length},
        );
      });
    });

    final filterMode = ref.watch(calendarFilterModeProvider);
    final searchQuery = ref.watch(calendarSearchQueryProvider);
    final isListMode =
        filterMode != CalendarFilterMode.all || searchQuery.trim().isNotEmpty;

    return ScreenWrapper(
      child: Scaffold(
        key: e2eKey(E2eIds.calendarRoot),
        backgroundColor: Colors.transparent,
        // Content fills the screen; the year island floats over it (like
        // Events) instead of a sticky app bar row that steals height.
        body: Stack(
          children: [
            Positioned.fill(
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollUpdateNotification &&
                      _chromeCollapse.onScrollUpdate(notification)) {
                    setState(
                      () => _controlsSeparated = !_chromeCollapse.expanded,
                    );
                  }
                  return false;
                },
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
                      color: kPrimaryColor,
                      backgroundColor: context.colors.surface,
                      displacement: 60.h,
                      strokeWidth: 3.w,
                      child: GridView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.fromLTRB(
                          16.sp,
                          MediaQuery.viewPaddingOf(context).top + 128,
                          16.sp,
                          140.h,
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
                          MediaQuery.viewPaddingOf(context).top + 128,
                          16.sp,
                          140.h,
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
            ),
            Positioned(
              top: MediaQuery.viewPaddingOf(context).top + 18,
              left: 0,
              right: 0,
              child: _buildFloatingControls(),
            ),
          ],
        ),
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
    final crossAxisCount = ResponsiveHelper.getGridCrossAxisCount(
      phoneCount: 1,
    );
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.sp,
      tablet: 24.sp,
    );

    return RefreshIndicator(
      onRefresh: () async {
        HapticFeedbackService.medium();
        ref.invalidate(calendarScreenProvider);
      },
      color: kPrimaryColor,
      backgroundColor: context.colors.surface,
      displacement: 60.h,
      strokeWidth: 3.w,
      child:
          sortedEvents.isEmpty
              ? LayoutBuilder(
                builder: (context, constraints) {
                  // Clear the floating profile header + tab row so the empty
                  // message sits in the visible content area, not behind the
                  // status bar / glass controls.
                  final topInset =
                      MediaQuery.viewPaddingOf(context).top + 128;
                  return ListView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(
                      parent: BouncingScrollPhysics(),
                    ),
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      topInset,
                      horizontalPadding,
                      140.h,
                    ),
                    children: [
                      SizedBox(
                        height: (constraints.maxHeight - topInset - 140.h)
                            .clamp(0.0, double.infinity),
                        child: Center(
                          child: Text(
                            'No events found',
                            style: AppTypography.textLgRegular.copyWith(
                              color: context.colors.textPrimaryMuted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
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
                  MediaQuery.viewPaddingOf(context).top + 128,
                  horizontalPadding,
                  140.h,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 16.sp,
                  mainAxisSpacing: 16.sp,
                  childAspectRatio: ResponsiveHelper.isLandscape ? 2.2 : 1.8,
                ),
                itemCount: sortedEvents.length,
                itemBuilder: (context, index) {
                  final event = sortedEvents[index];
                  return EventCard(
                    tourEventCardModel: event,
                    heroTagSuffix: 'calendar-list-$index',
                    onTap: () => _onEventTap(event, sortedEvents),
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
                  MediaQuery.viewPaddingOf(context).top + 128,
                  horizontalPadding,
                  140.h,
                ),
                itemCount: sortedEvents.length,
                itemBuilder: (context, index) {
                  final event = sortedEvents[index];
                  return Padding(
                    padding: EdgeInsets.only(bottom: 12.h),
                    child: EventCard(
                      tourEventCardModel: event,
                      heroTagSuffix: 'calendar-list-$index',
                      onTap: () => _onEventTap(event, sortedEvents),
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
  /// Build time control dropdown item with icon
  /// Get the appropriate icon for a time control
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
