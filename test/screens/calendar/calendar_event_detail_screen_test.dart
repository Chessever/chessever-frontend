import 'package:chessever2/repository/supabase/calendar_event/calendar_event.dart';
import 'package:chessever2/screens/calendar/calendar_event_detail_screen.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CalendarEventDetailScreen favorites', () {
    test('uses the same calendar-event favorite id as month-list cards', () {
      final event = CalendarEvent(
        name: '16. Gütersloher Sparkassen-Cup',
        startDate: DateTime.utc(2026, 8, 21),
        endDate: DateTime.utc(2026, 8, 23),
        location: 'Gütersloh Germany',
        timeControl: 'standard',
        createdAt: DateTime.utc(2026),
      );

      final listModel = GroupEventCardModel.fromCalendarEvent(event);

      expect(calendarEventFavoriteId(event), listModel.id);
      expect(calendarEventFavoriteModel(event).title, listModel.title);
      expect(calendarEventFavoriteModel(event).dates, listModel.dates);
      expect(
        calendarEventFavoriteModel(event).timeControl,
        listModel.timeControl,
      );
      expect(
        calendarEventFavoriteModel(event).eventSource,
        EventSource.communityEvent,
      );
    });

    test('shortens special-character event names into stable favorite ids', () {
      final event = CalendarEvent(
        name: '11th International Chess Tournament of Anogia “Idaion Andron”',
        createdAt: DateTime.utc(2026),
      );

      expect(
        calendarEventFavoriteId(event),
        'cal_event_11th_international_chess_tournament_of_anogia_idaion_andron',
      );
    });
  });
}
