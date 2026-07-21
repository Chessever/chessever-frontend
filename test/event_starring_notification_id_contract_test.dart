import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/utils/favorite_event_ids.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contract: starring from Current / For You / Calendar must resolve to a
/// notification-matchable id, and dispatch accepts GBID + cal_event alias.
void main() {
  group('Event star ID contract for notification dispatch', () {
    test(
      'Current / For You (Lichess) star stores group_broadcasts.id',
      () {
        final broadcast = GroupBroadcast(
          id: '59th_biel_international_chess_festival_2026',
          createdAt: DateTime.utc(2026, 1, 1),
          name: '59th Biel International Chess Festival 2026',
          search: const [],
          timeControl: 'standard',
        );

        final card = GroupEventCardModel.fromGroupBroadcast(broadcast, const []);

        expect(card.id, broadcast.id);
        expect(isSyntheticFavoriteEventId(card.id), isFalse);
        expect(card.eventSource, EventSource.lichessBroadcast);

        final insert = FavoriteEvent(
          id: 'temp',
          userId: 'user-1',
          eventId: card.id,
          eventName: card.title,
          metadata: {
            'cal_event_alias': calendarEventFavoriteIdFromName(card.title),
          },
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ).toSupabaseInsert();

        expect(insert['event_id'], broadcast.id);
        expect(
          (insert['metadata'] as Map)['cal_event_alias'],
          calendarEventFavoriteIdFromName(card.title),
        );
      },
    );

    test(
      'Calendar card id is synthetic; dispatch still matches via alias set',
      () {
        final event = CalendarEvent(
          name: 'Quantbox Chennai Grand Masters 2026',
          startDate: DateTime.utc(2026, 8, 1),
          endDate: DateTime.utc(2026, 8, 10),
          timeControl: 'standard',
          createdAt: DateTime.utc(2026),
        );

        final card = GroupEventCardModel.fromCalendarEvent(event);
        expect(card.id, startsWith('cal_event_'));
        expect(isSyntheticFavoriteEventId(card.id), isTrue);

        // After remap (or via dispatch alias expansion), recipients resolve
        // if either the GBID or the cal_event alias is stored.
        const liveGroupBroadcastId = 'quantbox_chennai_grand_masters_2026';
        final dispatchIds = favoriteEventIdCandidates(
          liveGroupBroadcastId,
          eventName: event.name,
        );
        expect(dispatchIds, contains(liveGroupBroadcastId));
        expect(dispatchIds, contains(card.id));

        final favorites = <String, String>{
          'user-remapped': liveGroupBroadcastId,
          'user-legacy-cal': card.id,
          'user-other': 'unrelated',
        };
        final recipients =
            favorites.entries
                .where((e) => dispatchIds.contains(e.value))
                .map((e) => e.key)
                .toList()
              ..sort();

        expect(recipients, ['user-legacy-cal', 'user-remapped']);
      },
    );

    test(
      'FavoriteEvent.fromSupabase / toSupabaseInsert round-trip server columns',
      () {
        final fromServer = FavoriteEvent.fromSupabase({
          'id': 'row-uuid',
          'user_id': 'user-1',
          'event_id': 'serbia_open_2026',
          'event_name': 'Serbia Open 2026',
          'metadata': {
            'timeControl': 'Standard',
            'cal_event_alias': 'cal_event_serbia_open_2026',
          },
          'created_at': '2026-07-01T12:00:00.000Z',
          'updated_at': '2026-07-01T12:00:00.000Z',
        });

        expect(fromServer.eventId, 'serbia_open_2026');
        expect(
          favoriteEventMatchesId(
            storedEventId: fromServer.eventId,
            candidateId: 'cal_event_serbia_open_2026',
            eventName: fromServer.eventName,
            metadata: fromServer.metadata,
          ),
          isTrue,
        );
      },
    );
  });
}
