/// Month name constants for search matching
const _monthNamesLower = [
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
const _monthShortLower = [
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

/// Parameters for isolate-based calendar search filtering
class CalendarSearchParams {
  final List<CalendarEventData> events;
  final String searchQuery;
  final String? timeControl;
  final int selectedYear;
  final DateTime today;
  final String filterMode; // 'all', 'upcoming', 'favorites'
  final Set<String> favoriteEventIds;
  final Map<String, bool> favoritePlayersMap;
  final List<String> monthNames;

  const CalendarSearchParams({
    required this.events,
    required this.searchQuery,
    required this.timeControl,
    required this.selectedYear,
    required this.today,
    required this.filterMode,
    required this.favoriteEventIds,
    required this.favoritePlayersMap,
    required this.monthNames,
  });
}

/// Lightweight event data for isolate transfer
class CalendarEventData {
  final String id;
  final String title;
  final String? location;
  final String? timeControl;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<String> searchTerms;
  final String dates;
  final int maxAvgElo;
  final String timeUntilStart;
  final String tourEventCategory;
  final String eventSource;

  const CalendarEventData({
    required this.id,
    required this.title,
    this.location,
    this.timeControl,
    this.startDate,
    this.endDate,
    this.searchTerms = const [],
    required this.dates,
    required this.maxAvgElo,
    required this.timeUntilStart,
    required this.tourEventCategory,
    required this.eventSource,
  });
}

/// Result of isolate filtering
class CalendarSearchResult {
  final List<MonthEventsData> summaries;
  final List<String> eventsToPrime; // Events needing favorite player priming

  const CalendarSearchResult({
    required this.summaries,
    required this.eventsToPrime,
  });
}

class MonthEventsData {
  final String monthName;
  final int monthNumber;
  final List<CalendarEventData> events;

  const MonthEventsData({
    required this.monthName,
    required this.monthNumber,
    required this.events,
  });
}

/// Top-level function for compute() - runs in isolate
CalendarSearchResult filterCalendarEventsIsolate(CalendarSearchParams params) {
  final searchQuery = params.searchQuery.trim().toLowerCase();
  final eventsToPrime = <String>[];
  final Map<int, List<CalendarEventData>> monthEvents = {};

  for (int i = 1; i <= 12; i++) {
    monthEvents[i] = [];
  }

  // Check if search query is a month name - if so, filter to that month only
  final searchedMonth = _parseMonthFromQuery(searchQuery);

  for (final event in params.events) {
    // Time control filter
    if (!_matchesTimeControl(event.timeControl, params.timeControl)) {
      continue;
    }

    // Search query filter
    if (!_matchesSearch(event, searchQuery)) {
      continue;
    }

    // If searching for a specific month, only include events that START in that month
    if (searchedMonth != null) {
      final startDate = event.startDate ?? event.endDate;
      if (startDate == null || startDate.month != searchedMonth) {
        continue;
      }
    }

    // Filter mode checks
    if (params.filterMode == 'upcoming') {
      final startDate = event.startDate ?? event.endDate;
      if (startDate == null || startDate.isBefore(params.today)) {
        continue;
      }
    } else if (params.filterMode == 'favorites') {
      // favoriteEventIds now contains both starred events AND events with favorite players
      if (!params.favoriteEventIds.contains(event.id)) {
        continue;
      }
    }

    // Date range check and month assignment
    final range = _resolveRange(event.startDate, event.endDate);
    if (range == null) continue;

    final firstDate = range.$1;
    final lastDate = range.$2;

    if (firstDate.year > params.selectedYear ||
        lastDate.year < params.selectedYear) {
      continue;
    }

    DateTime current = DateTime(firstDate.year, firstDate.month);
    final endMonth = DateTime(lastDate.year, lastDate.month);

    while (!current.isAfter(endMonth)) {
      if (current.year == params.selectedYear) {
        monthEvents[current.month]!.add(event);
      }
      current = DateTime(current.year, current.month + 1);
    }
  }

  final summaries = <MonthEventsData>[];
  for (int i = 1; i <= 12; i++) {
    final sorted = _sortEvents(monthEvents[i]!, filterMode: params.filterMode);
    summaries.add(
      MonthEventsData(
        monthName: params.monthNames[i - 1],
        monthNumber: i,
        events: sorted,
      ),
    );
  }

  return CalendarSearchResult(
    summaries: summaries,
    eventsToPrime: eventsToPrime,
  );
}

/// Parse month number from search query if it matches a month name
int? _parseMonthFromQuery(String query) {
  if (query.isEmpty) return null;

  // Check full month names
  for (int i = 0; i < _monthNamesLower.length; i++) {
    if (_monthNamesLower[i] == query || _monthNamesLower[i].startsWith(query)) {
      // Only match if query is substantial (at least 3 chars for short names)
      if (query.length >= 3) return i + 1;
    }
  }

  // Check short month names (exact match only)
  for (int i = 0; i < _monthShortLower.length; i++) {
    if (_monthShortLower[i] == query) {
      return i + 1;
    }
  }

  return null;
}

bool _matchesTimeControl(String? eventTimeControl, String? filterTimeControl) {
  final normalizedFilter = _normalizeTimeControl(filterTimeControl);
  if (normalizedFilter == null) return true;

  final eventTime = _normalizeTimeControl(eventTimeControl);
  return eventTime == normalizedFilter;
}

String? _normalizeTimeControl(String? timeControl) {
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

bool _matchesSearch(CalendarEventData event, String searchQuery) {
  if (searchQuery.isEmpty) return true;

  // For short queries, only check title and location for performance
  if (searchQuery.length < 3) {
    final titleLower = event.title.toLowerCase();
    final locationLower = event.location?.toLowerCase() ?? '';
    return titleLower.contains(searchQuery) ||
        locationLower.contains(searchQuery);
  }

  // Build tokens and check
  final tokens = _buildSearchTokens(event);
  return tokens.any((token) => token.contains(searchQuery));
}

List<String> _buildSearchTokens(CalendarEventData event) {
  final tokens = <String>{};

  tokens.add(event.title.toLowerCase());

  if (event.location != null && event.location!.isNotEmpty) {
    tokens.add(event.location!.toLowerCase());
  }

  // Add date tokens
  if (event.startDate != null) {
    _addDateTokens(tokens, event.startDate!);
  }
  if (event.endDate != null) {
    _addDateTokens(tokens, event.endDate!);
  }

  // Add search terms
  for (final term in event.searchTerms) {
    if (term.trim().isNotEmpty) {
      tokens.add(term.toLowerCase());
    }
  }

  return tokens.toList();
}

void _addDateTokens(Set<String> tokens, DateTime date) {
  const months = [
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
  const monthShort = [
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

  final index = date.month - 1;
  if (index >= 0 && index < months.length) {
    tokens.add(months[index]);
    tokens.add(monthShort[index]);
  }
  tokens.add(date.year.toString());
}

(DateTime, DateTime)? _resolveRange(DateTime? start, DateTime? end) {
  if (start == null && end == null) return null;

  if (start != null && end != null) {
    if (end.isBefore(start)) {
      return (end, start);
    }
    return (start, end);
  }

  final singleDate = start ?? end!;
  return (singleDate, singleDate);
}

List<CalendarEventData> _sortEvents(
  List<CalendarEventData> events, {
  required String filterMode,
}) {
  if (events.isEmpty) return events;

  final sorted = List<CalendarEventData>.from(events);

  if (filterMode == 'favorites') {
    // Favorites: combine starred + hearted and sort by newest date first
    sorted.sort((a, b) => _compareByDate(a, b, descending: true));
  } else if (filterMode == 'upcoming') {
    // Upcoming: date ascending (soonest first)
    sorted.sort(_compareByDate);
  } else {
    // Category-based sorting for regular view
    const categoryOrder = {
      'live': 0,
      'ongoing': 1,
      'upcoming': 2,
      'completed': 3,
    };

    sorted.sort((a, b) {
      final catA = categoryOrder[a.tourEventCategory] ?? 3;
      final catB = categoryOrder[b.tourEventCategory] ?? 3;

      if (catA != catB) return catA.compareTo(catB);

      // For upcoming events, sort by start date ascending
      if (a.tourEventCategory == 'upcoming') {
        final dateA = a.startDate ?? a.endDate;
        final dateB = b.startDate ?? b.endDate;
        if (dateA != null && dateB != null) {
          return dateA.compareTo(dateB);
        }
      }

      // For other categories, sort by ELO descending
      return b.maxAvgElo.compareTo(a.maxAvgElo);
    });
  }

  return sorted;
}

int _compareByDate(
  CalendarEventData a,
  CalendarEventData b, {
  bool descending = false,
}) {
  // Always use start date as primary, fall back to end date
  final dateA = a.startDate ?? a.endDate;
  final dateB = b.startDate ?? b.endDate;

  if (dateA != null && dateB != null) {
    return descending ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
  }
  if (dateA != null) return descending ? 1 : -1;
  if (dateB != null) return descending ? -1 : 1;
  return 0;
}

/// Parameters for detail screen filtering
class DetailSearchParams {
  final List<CalendarEventData> events;
  final String searchQuery;
  final String? timeControl;
  final int month;
  final int year;
  final DateTime today;
  final String filterMode;
  final Set<String> favoriteEventIds;
  final Map<String, bool> favoritePlayersMap;

  const DetailSearchParams({
    required this.events,
    required this.searchQuery,
    required this.timeControl,
    required this.month,
    required this.year,
    required this.today,
    required this.filterMode,
    required this.favoriteEventIds,
    required this.favoritePlayersMap,
  });
}

class DetailSearchResult {
  final List<CalendarEventData> events;
  final List<String> eventsToPrime;

  const DetailSearchResult({required this.events, required this.eventsToPrime});
}

/// Top-level function for detail screen filtering
DetailSearchResult filterDetailEventsIsolate(DetailSearchParams params) {
  final searchQuery = params.searchQuery.trim().toLowerCase();
  final eventsToPrime = <String>[];
  final filteredEvents = <CalendarEventData>[];

  final monthStart = DateTime(params.year, params.month, 1);
  final monthEnd = DateTime(params.year, params.month + 1, 0, 23, 59, 59);

  // Check if search query is a month name
  final searchedMonth = _parseMonthFromQuery(searchQuery);

  for (final event in params.events) {
    // Date range check
    final range = _resolveRange(event.startDate, event.endDate);
    if (range == null) continue;

    if (!_overlapsMonth(range, monthStart, monthEnd)) continue;

    // Time control filter
    if (!_matchesTimeControl(event.timeControl, params.timeControl)) {
      continue;
    }

    // Search query filter
    if (!_matchesSearch(event, searchQuery)) {
      continue;
    }

    // If searching for a specific month, only include events that START in that month
    if (searchedMonth != null) {
      final startDate = event.startDate ?? event.endDate;
      if (startDate == null || startDate.month != searchedMonth) {
        continue;
      }
    }

    // Filter mode checks
    if (params.filterMode == 'upcoming') {
      final startDate = event.startDate ?? event.endDate;
      if (startDate == null || startDate.isBefore(params.today)) {
        continue;
      }
    } else if (params.filterMode == 'favorites') {
      // favoriteEventIds now contains both starred events AND events with favorite players
      if (!params.favoriteEventIds.contains(event.id)) {
        continue;
      }
    }

    filteredEvents.add(event);
  }

  return DetailSearchResult(
    events: _sortEvents(filteredEvents, filterMode: params.filterMode),
    eventsToPrime: eventsToPrime,
  );
}

bool _overlapsMonth(
  (DateTime, DateTime) range,
  DateTime monthStart,
  DateTime monthEnd,
) {
  return !range.$1.isAfter(monthEnd) && !range.$2.isBefore(monthStart);
}
