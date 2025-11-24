import 'dart:async';

import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/event_favorite_players_provider.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/screens/calendar/calendar_event_detail_screen.dart';
import 'package:chessever2/screens/calendar/provider/calendar_screen_provider.dart';
import 'package:chessever2/screens/calendar/provider/calendar_search_isolate.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';

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
  final Set<String> _primingFavoritePlayers = {};

  List<GroupBroadcast> groupBroadcast = [];
  List<CalendarEvent> calendarEvents = [];
  List<CalendarEventData> _eventsData = []; // Cached isolate-safe data

  Timer? _debounceTimer;
  int _filterVersion = 0; // For cancellation of stale queries

  void _listenToFilters() {
    ref.listen(calendarSearchQueryProvider, (_, __) => _applyFiltersDebounced());
    ref.listen(calendarTimeControlProvider, (_, __) => _applyFiltersDebounced());
    ref.listen(calendarFilterModeProvider, (_, __) => _applyFiltersDebounced());
    ref.listen(liveGroupBroadcastIdsProvider, (_, __) => _applyFiltersDebounced());
    ref.listen(favoriteEventsProvider, (_, __) => _applyFiltersDebounced());
    ref.listen(favoritePlayersNotifierProvider, (_, __) => _applyFiltersDebounced());
    ref.listen(eventFavoritePlayersCacheProvider, (_, __) => _applyFiltersDebounced());
  }

  void _applyFiltersDebounced() {
    _debounceTimer?.cancel();
    final searchQuery = ref.read(calendarSearchQueryProvider);
    // Use longer debounce when search is active to avoid hanging
    final debounceTime = searchQuery.isNotEmpty
        ? const Duration(milliseconds: 500)
        : const Duration(milliseconds: 150);
    _debounceTimer = Timer(debounceTime, _applyFilters);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
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

      // Pre-build isolate-safe data
      final liveIds = ref.read(liveBroadcastIdsProvider);
      _eventsData = [
        ...current.map((b) => _broadcastToEventData(b, liveIds)),
        ...calEvents.map(_calendarEventToEventData),
      ];

      _applyFilters();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  CalendarEventData _broadcastToEventData(GroupBroadcast b, List<String> liveIds) {
    final model = GroupEventCardModel.fromGroupBroadcast(b, liveIds);
    return CalendarEventData(
      id: model.id,
      title: model.title,
      location: model.location,
      timeControl: model.timeControl,
      startDate: model.startDate,
      endDate: model.endDate,
      searchTerms: model.searchTerms,
      dates: model.dates,
      maxAvgElo: model.maxAvgElo,
      timeUntilStart: model.timeUntilStart,
      tourEventCategory: model.tourEventCategory.name,
      eventSource: model.eventSource.name,
    );
  }

  CalendarEventData _calendarEventToEventData(CalendarEvent e) {
    final model = GroupEventCardModel.fromCalendarEvent(e);
    return CalendarEventData(
      id: model.id,
      title: model.title,
      location: model.location,
      timeControl: model.timeControl,
      startDate: model.startDate,
      endDate: model.endDate,
      searchTerms: model.searchTerms,
      dates: model.dates,
      maxAvgElo: model.maxAvgElo,
      timeUntilStart: model.timeUntilStart,
      tourEventCategory: model.tourEventCategory.name,
      eventSource: model.eventSource.name,
    );
  }

  Future<void> _applyFilters() async {
    try {
      if (_eventsData.isEmpty) {
        state = const AsyncValue.data([]);
        return;
      }

      // Increment version to cancel any in-flight filter operations
      final currentVersion = ++_filterVersion;

      final searchQuery = ref.read(calendarSearchQueryProvider).trim();
      final timeControl = ref.read(calendarTimeControlProvider);
      final filterMode = ref.read(calendarFilterModeProvider);

      // Build favorite data for isolate
      final favoriteEventIds = <String>{};
      if (filterMode == CalendarFilterMode.favorites) {
        final favoritesAsync = ref.read(favoriteEventsProvider);
        final favorites = favoritesAsync.valueOrNull ?? [];
        favoriteEventIds.addAll(favorites.map((e) => e.eventId));
      }

      final favoritePlayersCache = ref.read(eventFavoritePlayersCacheProvider);
      final favoritePlayersMap = <String, bool>{};
      for (final entry in favoritePlayersCache.entries) {
        favoritePlayersMap[entry.key] = entry.value.hasFavorites;
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Prepare params for isolate
      final params = DetailSearchParams(
        events: _eventsData,
        searchQuery: searchQuery,
        timeControl: timeControl,
        month: filterArgs.month,
        year: filterArgs.year,
        today: today,
        filterMode: filterMode.name,
        favoriteEventIds: favoriteEventIds,
        favoritePlayersMap: favoritePlayersMap,
      );

      // Run filtering in background isolate
      final result = await compute(filterDetailEventsIsolate, params);

      // Check if this result is still current (cancellation check)
      if (!mounted || _filterVersion != currentVersion) return;

      // Prime favorite players for events that need it
      for (final eventId in result.eventsToPrime) {
        _primeFavoritePlayers(eventId);
      }

      // Convert back to GroupEventCardModel for UI
      final liveIds = ref.read(liveBroadcastIdsProvider);
      final events = result.events.map((data) {
        // Try to find the original model for efficiency
        for (final broadcast in groupBroadcast) {
          if (broadcast.id == data.id) {
            return GroupEventCardModel.fromGroupBroadcast(broadcast, liveIds);
          }
        }
        for (final calEvent in calendarEvents) {
          final model = GroupEventCardModel.fromCalendarEvent(calEvent);
          if (model.id == data.id) {
            return model;
          }
        }
        // Fallback to reconstructing from data
        return _fromEventData(data);
      }).toList();

      if (!mounted) return;
      state = AsyncValue.data(events);
    } catch (e, st) {
      if (!mounted) return;
      state = AsyncValue.error(e, st);
    }
  }

  GroupEventCardModel _fromEventData(CalendarEventData data) {
    return GroupEventCardModel(
      id: data.id,
      title: data.title,
      dates: data.dates,
      maxAvgElo: data.maxAvgElo,
      timeUntilStart: data.timeUntilStart,
      tourEventCategory: TourEventCategory.values.firstWhere(
        (e) => e.name == data.tourEventCategory,
        orElse: () => TourEventCategory.completed,
      ),
      timeControl: data.timeControl ?? 'Standard',
      endDate: data.endDate,
      startDate: data.startDate,
      location: data.location,
      searchTerms: data.searchTerms,
      eventSource: EventSource.values.firstWhere(
        (e) => e.name == data.eventSource,
        orElse: () => EventSource.lichessBroadcast,
      ),
    );
  }

  void _primeFavoritePlayers(String eventId) {
    if (_primingFavoritePlayers.contains(eventId)) return;
    _primingFavoritePlayers.add(eventId);

    ref
        .read(eventFavoritePlayersProvider(eventId).future)
        .then(
          (result) => ref
              .read(eventFavoritePlayersCacheProvider.notifier)
              .updateCache(eventId, result),
        )
        .whenComplete(() => _primingFavoritePlayers.remove(eventId));
  }

  void onSelectTournament({
    required BuildContext context,
    required String id,
  }) async {
    try {
      // Check if this is a calendar event (community event)
      if (id.startsWith('cal_event_')) {
        final sanitizedName = id.replaceFirst('cal_event_', '');

        final event = calendarEvents.firstWhere((e) {
          final eventSanitized =
              e.name
                  .replaceAll(' ', '_')
                  .replaceAll(RegExp(r'[^\w\-]'), '')
                  .toLowerCase();
          return eventSanitized == sanitizedName;
        }, orElse: () => throw Exception('Event not found'));

        if (context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CalendarEventDetailScreen(event: event),
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
