import 'dart:async';

import 'package:chessever2/repository/supabase/calendar_event/calendar_event.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event_repository.dart';
import 'package:chessever2/repository/supabase/fetch_all_pages.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/screens/calendar/provider/calendar_detail_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// How long a fetched month stays cached once nothing watches it. Reopening
/// the sidebar, or paging back to a month just seen, reuses the rows instead
/// of asking again.
const calendarMonthCacheTtl = Duration(minutes: 5);

/// Every event row that overlaps one calendar month, unfiltered.
///
/// These are the two month queries the month detail screen has always made.
/// They live in one provider so the sidebar month view, the day view on
/// `CalendarScreen` and the month detail screen fetch a month once between
/// them. Nothing here needs the live-broadcast subscription, so the sidebar
/// can show a month without opening one.
class CalendarMonthEvents {
  CalendarMonthEvents({
    required this.year,
    required this.month,
    required this.broadcasts,
    required this.calendarEvents,
  });

  final int year;
  final int month;
  final List<GroupBroadcast> broadcasts;
  final List<CalendarEvent> calendarEvents;

  /// Days of the month on which at least one event runs.
  late final Set<int> eventDays = calendarEventDaysInMonth(
    [
      for (final b in broadcasts) (b.dateStart, b.dateEnd),
      for (final e in calendarEvents) (e.startDate, e.endDate),
    ],
    year: year,
    month: month,
  );
}

final calendarMonthEventsProvider = FutureProvider.autoDispose
    .family<CalendarMonthEvents, CalendarFilterArgs>((ref, args) async {
      // Held from the start so a fetch outlives the drawer closing on it;
      // released after the TTL, or at once on failure so the next look
      // retries instead of replaying the error.
      final link = ref.keepAlive();
      Timer? release;
      ref.onDispose(() => release?.cancel());
      try {
        // Every row of the month, not the first page of it: the sidebar
        // marks a day as empty on the strength of this list, so a cut-off
        // month would draw days with events as days without them.
        final broadcastRepo = ref.read(groupBroadcastRepositoryProvider);
        final calendarRepo = ref.read(calendarEventRepositoryProvider);
        final rows = await Future.wait<Object>([
          fetchAllPages<GroupBroadcast>(
            (offset, limit) => broadcastRepo.getCurrentMonthGroupBroadcasts(
              selectedMonth: args.month,
              selectedYear: args.year,
              limit: limit,
              offset: offset,
            ),
            keyOf: (b) => b.id,
          ),
          // Ordered by `name`, the table's unique key, so offset paging is
          // stable; every consumer sorts the rows itself.
          fetchAllPages<CalendarEvent>(
            (offset, limit) => calendarRepo.getCalendarEventsForMonth(
              selectedMonth: args.month,
              selectedYear: args.year,
              limit: limit,
              offset: offset,
              orderBy: 'name',
              ascending: true,
            ),
            keyOf: (e) => e.name,
          ),
        ]);
        release = Timer(calendarMonthCacheTtl, link.close);
        return CalendarMonthEvents(
          year: args.year,
          month: args.month,
          broadcasts: rows[0] as List<GroupBroadcast>,
          calendarEvents: rows[1] as List<CalendarEvent>,
        );
      } catch (_) {
        link.close();
        rethrow;
      }
    });

/// The local calendar day [value] falls on. Event cards print their dates
/// through `toLocal()`, so a day mark and the card it leads to agree.
DateTime calendarLocalDay(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Inclusive local-day span of an event, or null when it has no dates. A lone
/// start or end is a one-day event, and a reversed pair is read forwards, as
/// the calendar's filters already do.
({DateTime first, DateTime last})? calendarEventDaySpan(
  DateTime? start,
  DateTime? end,
) {
  if (start == null && end == null) return null;
  final a = calendarLocalDay(start ?? end!);
  final b = calendarLocalDay(end ?? start!);
  return b.isBefore(a) ? (first: b, last: a) : (first: a, last: b);
}

/// Whether an event dated [start]..[end] runs on the local day [day].
bool calendarEventRunsOn(DateTime? start, DateTime? end, DateTime day) {
  final span = calendarEventDaySpan(start, end);
  if (span == null) return false;
  final target = DateTime(day.year, day.month, day.day);
  return !target.isBefore(span.first) && !target.isAfter(span.last);
}

/// Day-of-month numbers in [year]/[month] covered by any of [ranges], each a
/// `(start, end)` pair. Spans running past either end of the month are
/// clipped to it.
Set<int> calendarEventDaysInMonth(
  Iterable<(DateTime?, DateTime?)> ranges, {
  required int year,
  required int month,
}) {
  final monthFirst = DateTime(year, month);
  final monthLast = DateTime(year, month + 1, 0);
  final days = <int>{};
  for (final (start, end) in ranges) {
    final span = calendarEventDaySpan(start, end);
    if (span == null) continue;
    if (span.last.isBefore(monthFirst) || span.first.isAfter(monthLast)) {
      continue;
    }
    final from = span.first.isBefore(monthFirst) ? 1 : span.first.day;
    final to = span.last.isAfter(monthLast) ? monthLast.day : span.last.day;
    for (var day = from; day <= to; day++) {
      days.add(day);
    }
    if (days.length == monthLast.day) break;
  }
  return days;
}
