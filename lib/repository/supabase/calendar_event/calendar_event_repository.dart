import 'package:chessever2/repository/supabase/base_repository.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final calendarEventRepositoryProvider =
    AutoDisposeProvider<CalendarEventRepository>((ref) {
      return CalendarEventRepository();
    });

class CalendarEventRepository extends BaseRepository {
  /// Fetch calendar events for a specific month.
  ///
  /// This remains the full FIDE calendar feed. Upcoming month details use
  /// [getMajorUpcomingCalendarEventsForMonth].
  Future<List<CalendarEvent>> getCalendarEventsForMonth({
    required int selectedYear,
    required int selectedMonth,
    int limit = 100,
    int? offset,
    String orderBy = 'start_date',
    bool ascending = true,
  }) async {
    return _getCalendarEventsForMonth(
      selectedYear: selectedYear,
      selectedMonth: selectedMonth,
      limit: limit,
      offset: offset,
      orderBy: orderBy,
      ascending: ascending,
    );
  }

  /// Fetch FIDE Main Events Calendar entries for Upcoming month details.
  Future<List<CalendarEvent>> getMajorUpcomingCalendarEventsForMonth({
    required int selectedYear,
    required int selectedMonth,
    int limit = 100,
    int? offset,
    String orderBy = 'start_date',
    bool ascending = true,
  }) async {
    return _getCalendarEventsForMonth(
      selectedYear: selectedYear,
      selectedMonth: selectedMonth,
      limit: limit,
      offset: offset,
      orderBy: orderBy,
      ascending: ascending,
      majorUpcomingOnly: true,
    );
  }

  Future<List<CalendarEvent>> _getCalendarEventsForMonth({
    required int selectedYear,
    required int selectedMonth,
    required int limit,
    int? offset,
    required String orderBy,
    required bool ascending,
    bool majorUpcomingOnly = false,
  }) async {
    return handleApiCall(() async {
      final supabaseClient = supabase;

      // Calculate first and last day of the selected month
      final startOfMonth = DateTime(selectedYear, selectedMonth, 1);
      final endOfMonth = DateTime(
        selectedYear,
        selectedMonth + 1,
        0,
        23,
        59,
        59,
      );

      // Build query to find events that overlap with the month
      // An event overlaps if: start_date <= month_end AND end_date >= month_start
      final startDateStr = startOfMonth.toIso8601String().split('T')[0];
      final endDateStr = endOfMonth.toIso8601String().split('T')[0];

      // Handle missing start/end dates by including:
      // - Events with both dates that overlap the month
      // - Events with only a start_date inside the month
      // - Events with only an end_date inside the month
      var filterQuery = supabaseClient
          .from('calendar_events')
          .select()
          .or(
            'and(start_date.lte.$endDateStr,end_date.gte.$startDateStr),'
            'and(end_date.is.null,start_date.gte.$startDateStr,start_date.lte.$endDateStr),'
            'and(start_date.is.null,end_date.gte.$startDateStr,end_date.lte.$endDateStr)',
          );

      if (majorUpcomingOnly) {
        filterQuery = filterQuery.eq('is_major_upcoming_event', true);
      }

      var query = filterQuery.order(orderBy, ascending: ascending).limit(limit);

      if (offset != null) {
        query = query.range(offset, offset + limit - 1);
      }

      final response = await query;

      return (response as List)
          .map((json) => CalendarEvent.fromJson(json))
          .toList();
    });
  }

  /// Search calendar events by query string
  Future<List<CalendarEvent>> searchCalendarEvents(String query) async {
    if (query.trim().isEmpty) return [];

    return handleApiCall(() async {
      final q = query.trim().toLowerCase();

      final response = await supabase
          .from('calendar_events')
          .select()
          .or('name.ilike.%$q%,location.ilike.%$q%,time_control.ilike.%$q%');

      return (response as List)
          .map((json) => CalendarEvent.fromJson(json))
          .toList();
    });
  }

  /// Get all calendar events for a specific year.
  ///
  /// This remains the full FIDE calendar feed for search/enrichment and other
  /// non-Upcoming surfaces. Upcoming uses [getMajorUpcomingCalendarEventsForYear]
  /// so regular FIDE-rated tournaments do not overwhelm the feed.
  Future<List<CalendarEvent>> getCalendarEventsForYear({
    required int year,
    int limit = 500,
    String orderBy = 'start_date',
    bool ascending = true,
  }) async {
    return _getCalendarEventsForYear(
      year: year,
      limit: limit,
      orderBy: orderBy,
      ascending: ascending,
    );
  }

  /// Get FIDE Main Events Calendar entries that are appropriate for Upcoming.
  Future<List<CalendarEvent>> getMajorUpcomingCalendarEventsForYear({
    required int year,
    int limit = 500,
    String orderBy = 'start_date',
    bool ascending = true,
  }) async {
    return _getCalendarEventsForYear(
      year: year,
      limit: limit,
      orderBy: orderBy,
      ascending: ascending,
      majorUpcomingOnly: true,
    );
  }

  Future<List<CalendarEvent>> _getCalendarEventsForYear({
    required int year,
    required int limit,
    required String orderBy,
    required bool ascending,
    bool majorUpcomingOnly = false,
  }) async {
    return handleApiCall(() async {
      final startOfYear = DateTime(year, 1, 1);
      final endOfYear = DateTime(year, 12, 31, 23, 59, 59);

      final startDateStr = startOfYear.toIso8601String().split('T')[0];
      final endDateStr = endOfYear.toIso8601String().split('T')[0];

      var filterQuery = supabase
          .from('calendar_events')
          .select()
          .or(
            'and(start_date.lte.$endDateStr,end_date.gte.$startDateStr),'
            'and(end_date.is.null,start_date.gte.$startDateStr,start_date.lte.$endDateStr),'
            'and(start_date.is.null,end_date.gte.$startDateStr,end_date.lte.$endDateStr)',
          );

      if (majorUpcomingOnly) {
        filterQuery = filterQuery.eq('is_major_upcoming_event', true);
      }

      final response = await filterQuery
          .order(orderBy, ascending: ascending)
          .limit(limit);

      return (response as List)
          .map((json) => CalendarEvent.fromJson(json))
          .toList();
    });
  }
}
