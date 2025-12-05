import 'dart:async';

import 'package:chessever2/providers/event_favorite_players_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/calendar/calendar_screen.dart';
import 'package:chessever2/screens/calendar/provider/calendar_search_isolate.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/location_service_provider.dart';
import 'package:chessever2/utils/month_provider.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/foundation.dart';
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

/// Provider that tracks the IDs of favorite events (starred + favorite players)
/// This is kept separate from the main calendar provider to allow immediate badge updates
final calendarFavoriteEventIdsProvider =
    AutoDisposeAsyncNotifierProvider<_CalendarFavoriteEventIdsNotifier, Set<String>>(
  _CalendarFavoriteEventIdsNotifier.new,
);

class _CalendarFavoriteEventIdsNotifier extends AutoDisposeAsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    // Watch dependencies to rebuild when they change
    ref.watch(favoriteEventsProvider);
    ref.watch(favoritePlayersNotifierProvider);

    return _computeFavoriteEventIds();
  }

  Future<Set<String>> _computeFavoriteEventIds() async {
    final favoriteIds = <String>{};

    // 1. Get starred events
    try {
      final favorites = await ref.read(favoriteEventsProvider.future);
      for (final e in favorites) {
        favoriteIds.add(e.eventId);
      }
    } catch (_) {
      // Ignore errors loading favorites
    }

    // 2. Get events with favorite players from cache
    final cache = ref.read(eventFavoritePlayersCacheProvider);
    for (final entry in cache.entries) {
      if (entry.value.hasFavorites) {
        favoriteIds.add(entry.key);
      }
    }

    return favoriteIds;
  }
}

class _CalendarScreenNotifier
    extends StateNotifier<AsyncValue<List<MonthEventsSummary>>> {
  _CalendarScreenNotifier(this.ref) : super(const AsyncValue.loading()) {
    _init();
  }

  final Ref ref;
  final Set<String> _primingInProgress = {};
  Timer? _debounceTimer;
  int _filterVersion = 0; // For cancellation of stale queries
  bool _initialPrimingDone = false;

  List<GroupEventCardModel> _yearEvents = [];
  List<CalendarEventData> _yearEventsData = []; // Cached isolate-safe data

  Future<void> _init() async {
    try {
      // Listen to filter changes
      ref.listen(calendarSearchQueryProvider, (_, __) => _applyFilters());
      ref.listen(calendarTimeControlProvider, (_, __) => _applyFilters());
      ref.listen(
        calendarFilterModeProvider,
        (prev, next) {
          // When switching to favorites mode, prime all events first
          if (next == CalendarFilterMode.favorites && !_initialPrimingDone) {
            _primeAllEventsAndFilter();
          } else {
            _applyFilters(showLoading: prev != next);
          }
        },
      );
      ref.listen(selectedYearProvider, (_, __) {
        _initialPrimingDone = false;
        _fetchYearEvents();
      });
      ref.listen(favoriteEventsProvider, (_, __) => _applyFilters());
      ref.listen(favoritePlayersNotifierProvider, (_, __) {
        // When favorite players change, re-prime and re-filter
        _initialPrimingDone = false;
        if (ref.read(calendarFilterModeProvider) == CalendarFilterMode.favorites) {
          _primeAllEventsAndFilter();
        } else {
          _applyFilters();
        }
      });
      ref.listen(eventFavoritePlayersCacheProvider, (_, __) => _applyFilters());

      await _fetchYearEvents();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Prime all events for favorite players check, then apply filters
  Future<void> _primeAllEventsAndFilter() async {
    if (!mounted) return;
    state = const AsyncValue.loading();

    try {
      // Prime all events in parallel
      final futures = <Future>[];
      for (final event in _yearEvents) {
        if (!_primingInProgress.contains(event.id)) {
          futures.add(_primeEventFavoritePlayers(event.id));
        }
      }

      if (futures.isNotEmpty) {
        await Future.wait(futures);
      }

      _initialPrimingDone = true;

      // Now run the filters
      await _runFilters();
    } catch (e, st) {
      if (!mounted) return;
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> _primeEventFavoritePlayers(String eventId) async {
    if (_primingInProgress.contains(eventId)) return;
    _primingInProgress.add(eventId);

    try {
      final result = await ref.read(eventFavoritePlayersProvider(eventId).future);
      ref.read(eventFavoritePlayersCacheProvider.notifier).updateCache(eventId, result);
    } catch (_) {
      // Ignore errors - event just won't show as having favorites
    } finally {
      _primingInProgress.remove(eventId);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
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

      // Pre-build isolate-safe data for faster filtering
      _yearEventsData = _yearEvents.map(_toEventData).toList();

      // Run filters immediately after fetch (no debounce for initial load)
      _runFilters();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  CalendarEventData _toEventData(GroupEventCardModel event) {
    return CalendarEventData(
      id: event.id,
      title: event.title,
      location: event.location,
      timeControl: event.timeControl,
      startDate: event.startDate,
      endDate: event.endDate,
      searchTerms: event.searchTerms,
      dates: event.dates,
      maxAvgElo: event.maxAvgElo,
      timeUntilStart: event.timeUntilStart,
      tourEventCategory: event.tourEventCategory.name,
      eventSource: event.eventSource.name,
    );
  }

  /// Debounced filter application for user-triggered filter changes
  void _applyFilters({bool showLoading = false}) {
    _debounceTimer?.cancel();

    // Show shimmer/loading state when filter mode changes
    if (showLoading) {
      state = const AsyncValue.loading();
    }

    // Increase debounce time for search queries to avoid hanging
    final searchQuery = ref.read(calendarSearchQueryProvider);
    final debounceTime = searchQuery.isNotEmpty
        ? const Duration(milliseconds: 500) // Longer debounce for search
        : const Duration(milliseconds: 200); // Normal debounce for other filters

    _debounceTimer = Timer(debounceTime, _runFilters);
  }

  Future<void> _runFilters() async {
    try {
      if (_yearEventsData.isEmpty) {
        _setEmptyMonths();
        return;
      }

      // Increment version to cancel any in-flight filter operations
      final currentVersion = ++_filterVersion;

      final selectedYear = ref.read(selectedYearProvider);
      final searchQuery = ref.read(calendarSearchQueryProvider).trim();
      final timeControl = ref.read(calendarTimeControlProvider);
      final filterMode = ref.read(calendarFilterModeProvider);
      final monthConverter = ref.read(monthProvider);

      // Build favorite data for isolate
      final favoriteEventIds = <String>{};
      if (filterMode == CalendarFilterMode.favorites) {
        final favoritesAsync = ref.read(favoriteEventsProvider);
        try {
          final List<FavoriteEvent> favorites =
              favoritesAsync.valueOrNull ??
              await ref.read(favoriteEventsProvider.future);
          favoriteEventIds.addAll(favorites.map((e) => e.eventId));
        } catch (_) {
          // If favorites fail to load, fall back to player-based favorites only
        }
      }

      final favoritePlayersCache = ref.read(eventFavoritePlayersCacheProvider);
      final favoritePlayersMap = <String, bool>{};
      for (final entry in favoritePlayersCache.entries) {
        favoritePlayersMap[entry.key] = entry.value.hasFavorites;
      }

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Build month names list
      final monthNames = List.generate(
        12,
        (i) => monthConverter.monthNumberToName(i + 1),
      );

      // Prepare params for isolate
      final params = CalendarSearchParams(
        events: _yearEventsData,
        searchQuery: searchQuery,
        timeControl: timeControl,
        selectedYear: selectedYear,
        today: today,
        filterMode: filterMode.name,
        favoriteEventIds: favoriteEventIds,
        favoritePlayersMap: favoritePlayersMap,
        monthNames: monthNames,
      );

      // Run filtering in background isolate
      final result = await compute(filterCalendarEventsIsolate, params);

      // Check if this result is still current (cancellation check)
      if (!mounted || _filterVersion != currentVersion) return;

      // Prime favorite players for events that need it (background, non-blocking)
      for (final eventId in result.eventsToPrime) {
        _primeEventInBackground(eventId);
      }

      // Convert back to GroupEventCardModel for UI
      final summaries = result.summaries.map((monthData) {
        final events = monthData.events.map((data) {
          return _yearEvents.firstWhere(
            (e) => e.id == data.id,
            orElse: () => _fromEventData(data),
          );
        }).toList();

        return MonthEventsSummary(
          monthName: monthData.monthName,
          monthNumber: monthData.monthNumber,
          events: events,
        );
      }).toList();

      if (!mounted) return;
      state = AsyncValue.data(summaries);
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

  /// Background priming for events not yet in cache (non-blocking)
  void _primeEventInBackground(String eventId) {
    if (_primingInProgress.contains(eventId)) return;
    _primingInProgress.add(eventId);

    ref
        .read(eventFavoritePlayersProvider(eventId).future)
        .then(
          (result) => ref
              .read(eventFavoritePlayersCacheProvider.notifier)
              .updateCache(eventId, result),
        )
        .whenComplete(() => _primingInProgress.remove(eventId));
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

    if (!mounted) return;
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
  static final Map<String, List<String>> _tokenCache = {};
  static const List<String> _months = [
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december',
  ];
  static const List<String> _monthShort = [
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];

  static bool matches({
    required String title,
    required String searchQuery,
    String? location,
    List<String>? extraTokens,
    DateTime? startDate,
    DateTime? endDate,
    String? cacheKey,
  }) {
    try {
      final normalizedQuery = searchQuery.trim().toLowerCase();
      if (normalizedQuery.isEmpty) return true;

      // For short queries (< 3 chars), only check title and location directly
      // to avoid expensive token building
      if (normalizedQuery.length < 3) {
        final titleLower = title.toLowerCase();
        final locationLower = location?.toLowerCase() ?? '';
        return titleLower.contains(normalizedQuery) ||
               locationLower.contains(normalizedQuery);
      }

      final tokens =
          cacheKey != null && _tokenCache.containsKey(cacheKey)
              ? _tokenCache[cacheKey]!
              : _buildSearchTokens(
                title: title,
                location: location,
                extraTokens: extraTokens,
                startDate: startDate,
                endDate: endDate,
                // Skip country parsing during search for performance
                skipCountryParsing: normalizedQuery.length < 5,
              );

      if (cacheKey != null && !_tokenCache.containsKey(cacheKey)) {
        _tokenCache[cacheKey] = tokens;
      }

      return tokens.any((token) => token.contains(normalizedQuery));
    } catch (_) {
      // In case of unexpected parsing issues, avoid crashing the search flow
      return false;
    }
  }

  static List<String> _buildSearchTokens({
    required String title,
    String? location,
    List<String>? extraTokens,
    DateTime? startDate,
    DateTime? endDate,
    bool skipCountryParsing = false,
  }) {
    final tokens = <String>{};

    void addToken(String value, {bool includeCountryData = true}) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty) return;

      tokens.add(normalized);

      // Skip expensive country parsing when doing quick searches
      if (!includeCountryData || skipCountryParsing) return;

      final countryCode = _getCountryCode(value);
      if (countryCode != null) {
        tokens.add(countryCode.toLowerCase());
        final countryName = CountryService().findByCode(countryCode)?.name;
        if (countryName != null && countryName.isNotEmpty) {
          tokens.add(countryName.toLowerCase());
        }
      }
    }

    // Titles rarely match country names, so skip costly country parsing here
    addToken(title, includeCountryData: false);

    void addDateTokens(DateTime date) {
      final index = date.month - 1;
      if (index >= 0 && index < _months.length) {
        tokens.add(_months[index]);
        tokens.add(_monthShort[index]);
      }
      tokens.add(date.year.toString());
    }

    if (startDate != null) {
      addDateTokens(startDate);
    }
    if (endDate != null) {
      addDateTokens(endDate);
    }

    if (location != null && location.isNotEmpty) {
      addToken(location);
    }

    if (extraTokens != null) {
      for (final token in extraTokens) {
        if (token.trim().isEmpty) continue;
        addToken(token);
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

          final fromName = _locationService.getValidCountryCodeFromName(
            trimmed,
          );
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
