import 'package:chessever2/screens/calendar/provider/calendar_search_isolate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('calendar event sorting', () {
    test('month summaries sort events by start date ascending', () {
      final result = filterCalendarEventsIsolate(
        CalendarSearchParams(
          events: [
            _event(
              id: 'jul-23-a',
              title: '30.Battle of Senta',
              startDate: DateTime.utc(2026, 7, 23),
              endDate: DateTime.utc(2026, 7, 29),
              category: 'live',
              maxAvgElo: 2700,
            ),
            _event(
              id: 'jun-27',
              title: '32. Open Klatovy',
              startDate: DateTime.utc(2026, 6, 27),
              endDate: DateTime.utc(2026, 7, 5),
              category: 'completed',
              maxAvgElo: 1800,
            ),
            _event(
              id: 'jul-9',
              title: '34th National Men Chess Championship 2026',
              startDate: DateTime.utc(2026, 7, 9),
              endDate: DateTime.utc(2026, 7, 13),
              category: 'upcoming',
              maxAvgElo: 2100,
            ),
            _event(
              id: 'jul-18',
              title: '3rd Dole Open 2026',
              startDate: DateTime.utc(2026, 7, 18),
              endDate: DateTime.utc(2026, 7, 26),
              category: 'ongoing',
              maxAvgElo: 2400,
            ),
          ],
          searchQuery: '',
          timeControl: null,
          selectedYear: 2026,
          today: DateTime.utc(2026, 7),
          filterMode: 'all',
          favoriteEventIds: const {},
          favoritePlayersMap: const {},
          monthNames: _monthNames,
        ),
      );

      final julyTitles = result.summaries[6].events.map((e) => e.title);

      expect(julyTitles, [
        '32. Open Klatovy',
        '34th National Men Chess Championship 2026',
        '3rd Dole Open 2026',
        '30.Battle of Senta',
      ]);
    });

    test('detail results sort by start date ascending across categories', () {
      final result = filterDetailEventsIsolate(
        DetailSearchParams(
          events: [
            _event(
              id: 'later-live',
              title: 'Later Live Event',
              startDate: DateTime.utc(2026, 7, 23),
              category: 'live',
              maxAvgElo: 2700,
            ),
            _event(
              id: 'early-completed',
              title: 'Early Completed Event',
              startDate: DateTime.utc(2026, 7, 7),
              category: 'completed',
              maxAvgElo: 1500,
            ),
            _event(
              id: 'middle-upcoming',
              title: 'Middle Upcoming Event',
              startDate: DateTime.utc(2026, 7, 18),
              category: 'upcoming',
              maxAvgElo: 2600,
            ),
          ],
          searchQuery: '',
          timeControl: null,
          month: 7,
          year: 2026,
          today: DateTime.utc(2026, 7),
          filterMode: 'all',
          favoriteEventIds: const {},
          favoritePlayersMap: const {},
        ),
      );

      expect(result.events.map((e) => e.id), [
        'early-completed',
        'middle-upcoming',
        'later-live',
      ]);
    });

    test('favorites and upcoming filters keep start-date ascending order', () {
      final favoriteResult = filterDetailEventsIsolate(
        DetailSearchParams(
          events: [
            _event(
              id: 'favorite-later',
              title: 'Favorite Later Event',
              startDate: DateTime.utc(2026, 7, 20),
              category: 'upcoming',
            ),
            _event(
              id: 'favorite-earlier',
              title: 'Favorite Earlier Event',
              startDate: DateTime.utc(2026, 7, 10),
              category: 'upcoming',
            ),
          ],
          searchQuery: '',
          timeControl: null,
          month: 7,
          year: 2026,
          today: DateTime.utc(2026, 7),
          filterMode: 'favorites',
          favoriteEventIds: const {'favorite-later', 'favorite-earlier'},
          favoritePlayersMap: const {},
        ),
      );
      final upcomingResult = filterDetailEventsIsolate(
        DetailSearchParams(
          events: [
            _event(
              id: 'upcoming-later',
              title: 'Upcoming Later Event',
              startDate: DateTime.utc(2026, 7, 20),
              category: 'upcoming',
              isMajorUpcoming: true,
            ),
            _event(
              id: 'upcoming-earlier',
              title: 'Upcoming Earlier Event',
              startDate: DateTime.utc(2026, 7, 10),
              category: 'upcoming',
              isMajorUpcoming: true,
            ),
          ],
          searchQuery: '',
          timeControl: null,
          month: 7,
          year: 2026,
          today: DateTime.utc(2026, 7),
          filterMode: 'upcoming',
          favoriteEventIds: const {},
          favoritePlayersMap: const {},
        ),
      );

      expect(favoriteResult.events.map((e) => e.id), [
        'favorite-earlier',
        'favorite-later',
      ]);
      expect(upcomingResult.events.map((e) => e.id), [
        'upcoming-earlier',
        'upcoming-later',
      ]);
    });
  });
}

CalendarEventData _event({
  required String id,
  required String title,
  required DateTime startDate,
  DateTime? endDate,
  required String category,
  int maxAvgElo = 0,
  bool isMajorUpcoming = false,
}) {
  return CalendarEventData(
    id: id,
    title: title,
    location: 'Test location',
    timeControl: 'Standard',
    startDate: startDate,
    endDate: endDate ?? startDate,
    dates: '${startDate.month}/${startDate.day}',
    maxAvgElo: maxAvgElo,
    timeUntilStart: '',
    tourEventCategory: category,
    eventSource: 'communityEvent',
    isMajorUpcoming: isMajorUpcoming,
  );
}

const _monthNames = [
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
