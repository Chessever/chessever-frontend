import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/screens/calendar/provider/calendar_screen_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final calendarDetailScreenProvider = AutoDisposeStateNotifierProvider.family<
  _CalendarDetailScreenController,
  AsyncValue<List<GroupEventCardModel>>,
  CalendarFilterArgs
>((ref, filterArgs) {
  return _CalendarDetailScreenController(ref: ref, filterArgs: filterArgs);
});

class _CalendarDetailScreenController
    extends StateNotifier<AsyncValue<List<GroupEventCardModel>>> {
  _CalendarDetailScreenController({required this.ref, required this.filterArgs})
    : super(const AsyncValue.loading()) {
    _init();
    _listenToFilters();
  }

  final Ref ref;
  final CalendarFilterArgs filterArgs;

  List<GroupBroadcast> groupBroadcast = [];
  List<CalendarEvent> calendarEvents = [];

  void _listenToFilters() {
    ref.listen(calendarSearchQueryProvider, (_, __) => _applyFilters());
    ref.listen(calendarTimeControlProvider, (_, __) => _applyFilters());
    ref.listen(calendarFilterModeProvider, (_, __) => _applyFilters());
    ref.listen(liveGroupBroadcastIdsProvider, (_, __) => _applyFilters());
  }

  Future<void> _init() async {
    try {
      // Fetch both group broadcasts and calendar events
      final current = await ref
          .read(groupBroadcastRepositoryProvider)
          .getCurrentMonthGroupBroadcasts(
            selectedMonth: filterArgs.month,
            selectedYear: filterArgs.year,
          );

      final calEvents = await ref
          .read(calendarEventRepositoryProvider)
          .getCalendarEventsForMonth(
            selectedMonth: filterArgs.month,
            selectedYear: filterArgs.year,
          );

      groupBroadcast = current;
      calendarEvents = calEvents;

      _applyFilters();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void _applyFilters() {
    final searchQuery = ref.read(calendarSearchQueryProvider).toLowerCase();
    final timeControl = ref.read(calendarTimeControlProvider);
    final filterMode = ref.read(calendarFilterModeProvider);
    final liveIds = ref.read(liveBroadcastIdsProvider);

    // Get favorite event IDs if filtering by favorites
    final favoriteEventIds = <String>{};
    if (filterMode == CalendarFilterMode.favorites) {
      final favoritesAsync = ref.read(favoriteEventsProvider);
      final favorites = favoritesAsync.valueOrNull ?? [];
      favoriteEventIds.addAll(favorites.map((e) => e.eventId));
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final monthStart = DateTime(filterArgs.year, filterArgs.month, 1);
    final monthEnd = DateTime(filterArgs.year, filterArgs.month + 1, 0, 23, 59, 59);

    // Filter group broadcasts
    final filteredBroadcasts = groupBroadcast.where((t) {
      final range = resolveCalendarDateRange(t.dateStart, t.dateEnd);
      if (range == null) return false;

      if (!_overlapsMonth(range, monthStart, monthEnd)) return false;

      if (!_matchesFilters(
        t.name,
        null,
        t.timeControl,
        searchQuery,
        timeControl,
      )) return false;

      // Apply filter mode
      if (filterMode == CalendarFilterMode.upcoming) {
        final startDate = t.dateStart ?? t.dateEnd;
        if (startDate == null || startDate.isBefore(today)) {
          return false;
        }
      } else if (filterMode == CalendarFilterMode.favorites) {
        if (!favoriteEventIds.contains(t.id)) {
          return false;
        }
      }

      return true;
    }).toList();

    // Filter calendar events
    final filteredCalEvents = calendarEvents.where((e) {
      final range = resolveCalendarDateRange(e.startDate, e.endDate);
      if (range == null) return false;

      if (!_overlapsMonth(range, monthStart, monthEnd)) return false;

      if (!_matchesFilters(
        e.name,
        e.location,
        e.timeControl,
        searchQuery,
        timeControl,
      )) return false;

      // Apply filter mode
      if (filterMode == CalendarFilterMode.upcoming) {
        final startDate = e.startDate ?? e.endDate;
        if (startDate == null || startDate.isBefore(today)) {
          return false;
        }
      } else if (filterMode == CalendarFilterMode.favorites) {
        // Calendar events use generated ID format
        final eventId = 'cal_event_${e.name.replaceAll(' ', '_').replaceAll(RegExp(r'[^\w\-]'), '').toLowerCase()}';
        if (!favoriteEventIds.contains(eventId)) {
          return false;
        }
      }

      return true;
    }).toList();

    // Convert to card models
    final broadcastCards = filteredBroadcasts
        .map((t) => GroupEventCardModel.fromGroupBroadcast(t, liveIds))
        .toList();

    final calendarCards = filteredCalEvents
        .map((e) => GroupEventCardModel.fromCalendarEvent(e))
        .toList();

    // Combine both lists
    final allCards = [...broadcastCards, ...calendarCards];

    if (allCards.isEmpty) {
      state = const AsyncValue.data([]);
      return;
    }

    final sortedEvents = ref
        .read(tournamentSortingServiceProvider)
        .sortCalendarEvents(allCards);

    state = AsyncValue.data(sortedEvents);
  }

  bool _matchesFilters(
    String name,
    String? location,
    String? timeControl,
    String searchQuery,
    String? filterTimeControl,
  ) {
    final normalizedFilter = normalizeTimeControl(filterTimeControl);
    if (normalizedFilter != null) {
      final eventTime = normalizeTimeControl(timeControl);
      if (eventTime != normalizedFilter) {
        return false;
      }
    }

    return CalendarSearchHelper.matches(
      title: name,
      location: location,
      searchQuery: searchQuery,
    );
  }

  bool _overlapsMonth(
    DateTimeRange range,
    DateTime monthStart,
    DateTime monthEnd,
  ) {
    return !range.start.isAfter(monthEnd) && !range.end.isBefore(monthStart);
  }

  void onSelectTournament({
    required BuildContext context,
    required String id,
  }) async {
    try {
      // Check if this is a calendar event (community event)
      if (id.startsWith('cal_event_')) {
        final sanitizedName = id.replaceFirst('cal_event_', '');

        final event = calendarEvents.firstWhere(
          (e) {
            final eventSanitized = e.name
                .replaceAll(' ', '_')
                .replaceAll(RegExp(r'[^\w\-]'), '')
                .toLowerCase();
            return eventSanitized == sanitizedName;
          },
          orElse: () => throw Exception('Event not found'),
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${event.name}\n${event.location ?? 'Location TBA'}',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Regular group broadcast handling
      GroupBroadcast? selectedBroadcast;
      for (final broadcast in groupBroadcast) {
        if (broadcast.id == id) {
          selectedBroadcast = broadcast;
          break;
        }
      }

      selectedBroadcast ??= await ref
          .read(groupBroadcastRepositoryProvider)
          .getGroupBroadcastById(id);

      ref.read(selectedBroadcastModelProvider.notifier).state =
          selectedBroadcast;

      if (context.mounted && ref.read(selectedBroadcastModelProvider) != null) {
        Navigator.pushNamed(context, '/tournament_detail_screen');
      }
    } catch (e, st) {
      debugPrint('Failed to open calendar event: $e');
      debugPrintStack(stackTrace: st);
    }
  }

  Future<void> refresh() async {
    await _init();
  }
}

class CalendarFilterArgs {
  final int month;
  final int year;

  const CalendarFilterArgs({required this.month, required this.year});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CalendarFilterArgs &&
          runtimeType == other.runtimeType &&
          month == other.month &&
          year == other.year;

  @override
  int get hashCode => month.hashCode ^ year.hashCode;
}
