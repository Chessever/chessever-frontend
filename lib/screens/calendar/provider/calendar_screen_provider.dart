import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/sorting_all_event_provider.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/month_provider.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final calendarSearchQueryProvider = StateProvider<String>((ref) => '');
final calendarTimeControlProvider = StateProvider<String?>((ref) => null);

class MonthEventsSummary {
  final String monthName;
  final int monthNumber;
  final List<GroupEventCardModel> events;

  int get eventCount => events.length;

  MonthEventsSummary({
    required this.monthName,
    required this.monthNumber,
    required this.events,
  });
}

final calendarScreenProvider = AutoDisposeStateNotifierProvider<
  _CalendarScreenNotifier,
  AsyncValue<List<MonthEventsSummary>>
>((ref) => _CalendarScreenNotifier(ref));

class _CalendarScreenNotifier
    extends StateNotifier<AsyncValue<List<MonthEventsSummary>>> {
  _CalendarScreenNotifier(this.ref) : super(const AsyncValue.loading()) {
    _init();
  }

  final Ref ref;

  List<GroupEventCardModel> _yearEvents = [];

  Future<void> _init() async {
    try {
      // Listen to filter changes
      ref.listen(calendarSearchQueryProvider, (_, __) => _applyFilters());
      ref.listen(calendarTimeControlProvider, (_, __) => _applyFilters());
      ref.listen(calendarFilterModeProvider, (_, __) => _applyFilters());
      ref.listen(selectedYearProvider, (_, __) => _fetchYearEvents());

      await _fetchYearEvents();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> _fetchYearEvents() async {
    try {
      state = const AsyncValue.loading();

      final selectedYear = ref.read(selectedYearProvider);

      final yearBroadcasts = await ref
          .read(groupBroadcastRepositoryProvider)
          .getGroupBroadcastsForYear(year: selectedYear);

      final yearCalendarEvents = await ref
          .read(calendarEventRepositoryProvider)
          .getCalendarEventsForYear(year: selectedYear);

      _yearEvents = [
        ...yearBroadcasts.map(
          (b) => GroupEventCardModel.fromGroupBroadcast(
            b,
            ref.read(liveBroadcastIdsProvider),
          ),
        ),
        ...yearCalendarEvents.map(GroupEventCardModel.fromCalendarEvent),
      ];

      await _applyFilters();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> _applyFilters() async {
    try {
      if (_yearEvents.isEmpty) {
        _setEmptyMonths();
        return;
      }

      final selectedYear = ref.read(selectedYearProvider);
      final searchQuery = ref.read(calendarSearchQueryProvider).toLowerCase();
      final timeControl = ref.read(calendarTimeControlProvider);
      final filterMode = ref.read(calendarFilterModeProvider);
      final monthConverter = ref.read(monthProvider);

      // Get favorite event IDs if filtering by favorites
      final favoriteEventIds = <String>{};
      if (filterMode == CalendarFilterMode.favorites) {
        final favoritesAsync = ref.read(favoriteEventsProvider);
        final favorites = favoritesAsync.valueOrNull ?? [];
        favoriteEventIds.addAll(favorites.map((e) => e.eventId));
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final List<MonthEventsSummary> summaries = [];
      final Map<int, List<GroupEventCardModel>> monthEvents = {};

      // Seed months
      for (int i = 1; i <= 12; i++) {
        monthEvents[i] = [];
      }

      for (final event in _yearEvents) {
        if (!_matchesFilters(event, searchQuery, timeControl)) {
          continue;
        }

        // Apply filter mode
        if (filterMode == CalendarFilterMode.upcoming) {
          final startDate = event.startDate ?? event.endDate;
          if (startDate == null || startDate.isBefore(today)) {
            continue;
          }
        } else if (filterMode == CalendarFilterMode.favorites) {
          if (!favoriteEventIds.contains(event.id)) {
            continue;
          }
        }

        final range = resolveCalendarDateRange(event.startDate, event.endDate);
        if (range == null) continue;
        final firstDate = range.start;
        final lastDate = range.end;

        if (firstDate.year > selectedYear || lastDate.year < selectedYear) {
          continue;
        }

        DateTime current = DateTime(firstDate.year, firstDate.month);
        final endMonth = DateTime(lastDate.year, lastDate.month);

        while (!current.isAfter(endMonth)) {
          if (current.year == selectedYear) {
            monthEvents[current.month]!.add(event);
          }
          current = DateTime(current.year, current.month + 1);
        }
      }

      for (int i = 1; i <= 12; i++) {
        final sortedEvents = ref
            .read(tournamentSortingServiceProvider)
            .sortCalendarEvents(monthEvents[i]!);

        summaries.add(
          MonthEventsSummary(
            monthName: monthConverter.monthNumberToName(i),
            monthNumber: i,
            events: sortedEvents,
          ),
        );
      }

      state = AsyncValue.data(summaries);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  bool _matchesFilters(
    GroupEventCardModel event,
    String searchQuery,
    String? timeControl,
  ) {
    final normalizedFilterTimeControl = normalizeTimeControl(timeControl);

    if (normalizedFilterTimeControl != null) {
      final eventTime = normalizeTimeControl(event.timeControl);
      if (eventTime != normalizedFilterTimeControl) {
        return false;
      }
    }

    if (searchQuery.isEmpty) return true;

    return CalendarSearchHelper.matches(
      title: event.title,
      location: event.location,
      searchQuery: searchQuery,
    );
  }

  void _setEmptyMonths() {
    final monthConverter = ref.read(monthProvider);
    final summaries = List.generate(
      12,
      (index) => MonthEventsSummary(
        monthName: monthConverter.monthNumberToName(index + 1),
        monthNumber: index + 1,
        events: const [],
      ),
    );

    state = AsyncValue.data(summaries);
  }

  void reset() {
    ref.read(calendarSearchQueryProvider.notifier).state = '';
    ref.read(calendarTimeControlProvider.notifier).state = null;
    _applyFilters();
  }
}

DateTimeRange? resolveCalendarDateRange(DateTime? start, DateTime? end) {
  if (start == null && end == null) return null;

  if (start != null && end != null) {
    if (end.isBefore(start)) {
      return DateTimeRange(start: end, end: start);
    }
    return DateTimeRange(start: start, end: end);
  }

  final singleDate = start ?? end!;
  return DateTimeRange(start: singleDate, end: singleDate);
}

String? normalizeTimeControl(String? timeControl) {
  if (timeControl == null || timeControl.isEmpty) return null;

  final lower = timeControl.toLowerCase();
  if (lower.contains('bullet')) return 'bullet';
  if (lower.contains('blitz')) return 'blitz';
  if (lower.contains('rapid')) return 'rapid';
  if (lower.contains('standard') || lower.contains('classic')) {
    return 'standard';
  }

  return lower;
}

class CalendarSearchHelper {
  CalendarSearchHelper._();

  static final Map<String, String?> _countryCodeCache = {};
  static final LocationService _locationService = LocationService();

  static bool matches({
    required String title,
    required String searchQuery,
    String? location,
  }) {
    if (searchQuery.isEmpty) return true;

    final tokens = _buildSearchTokens(title: title, location: location);
    return tokens.any((token) => token.contains(searchQuery));
  }

  static List<String> _buildSearchTokens({
    required String title,
    String? location,
  }) {
    final tokens = <String>{title.toLowerCase()};

    if (location != null && location.isNotEmpty) {
      tokens.add(location.toLowerCase());

      final countryCode = _getCountryCode(location);
      if (countryCode != null) {
        tokens.add(countryCode.toLowerCase());
        final countryName = CountryService().findByCode(countryCode)?.name;
        if (countryName != null && countryName.isNotEmpty) {
          tokens.add(countryName.toLowerCase());
        }
      }
    }

    return tokens.toList(growable: false);
  }

  static String? _getCountryCode(String? location) {
    if (location == null || location.trim().isEmpty) return null;
    if (_countryCodeCache.containsKey(location)) {
      return _countryCodeCache[location];
    }

    String? code = CountryUtils.getCountryCode(location);

    if (code == null || code.isEmpty) {
      final direct = _locationService.getValidCountryCode(location.trim());
      if (direct.isNotEmpty) {
        code = direct;
      } else {
        // Try to parse individual parts (e.g. "Baku, AZE")
        final parts = location.split(RegExp(r'[,|/]'));
        for (final part in parts) {
          final trimmed = part.trim();
          if (trimmed.isEmpty) continue;

          final mappedCode = _locationService.getValidCountryCode(trimmed);
          if (mappedCode.isNotEmpty) {
            code = mappedCode;
            break;
          }

          final fromName = _locationService.getValidCountryCodeFromName(trimmed);
          if (fromName.isNotEmpty) {
            code = fromName;
            break;
          }
        }
      }
    }

    if (code != null && code.isNotEmpty) {
      code = code.toUpperCase();
    } else {
      code = null;
    }

    _countryCodeCache[location] = code;
    return code;
  }

  static String? getCountryCodeForLocation(String? location) =>
      _getCountryCode(location);
}
