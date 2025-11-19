import 'package:chessever2/repository/supabase/base_repository.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final calendarEventRepositoryProvider =
    AutoDisposeProvider<CalendarEventRepository>((ref) {
  return CalendarEventRepository();
});

class CalendarEventRepository extends BaseRepository {
  /// Fetch calendar events for a specific month
  Future<List<CalendarEvent>> getCalendarEventsForMonth({
    required int selectedYear,
    required int selectedMonth,
    int limit = 100,
    int? offset,
    String orderBy = 'start_date',
    bool ascending = true,
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
      PostgrestTransformBuilder<PostgrestList> query = supabaseClient
          .from('calendar_events')
          .select()
          .or(
            'and(start_date.gte.${startOfMonth.toIso8601String().split('T')[0]},start_date.lte.${endOfMonth.toIso8601String().split('T')[0]}),'
            'and(end_date.gte.${startOfMonth.toIso8601String().split('T')[0]},end_date.lte.${endOfMonth.toIso8601String().split('T')[0]})',
          )
          .order(orderBy, ascending: ascending)
          .limit(limit);

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

  /// Get all calendar events for a specific year
  Future<List<CalendarEvent>> getCalendarEventsForYear({
    required int year,
    int limit = 500,
    String orderBy = 'start_date',
    bool ascending = true,
  }) async {
    return handleApiCall(() async {
      final startOfYear = DateTime(year, 1, 1);
      final endOfYear = DateTime(year, 12, 31, 23, 59, 59);

      final response = await supabase
          .from('calendar_events')
          .select()
          .or(
            'and(start_date.gte.${startOfYear.toIso8601String().split('T')[0]},start_date.lte.${endOfYear.toIso8601String().split('T')[0]}),'
            'and(end_date.gte.${startOfYear.toIso8601String().split('T')[0]},end_date.lte.${endOfYear.toIso8601String().split('T')[0]})',
          )
          .order(orderBy, ascending: ascending)
          .limit(limit);

      return (response as List)
          .map((json) => CalendarEvent.fromJson(json))
          .toList();
    });
  }
}
