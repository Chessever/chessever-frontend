import 'package:chessever2/utils/favorite_event_ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('favorite_event_ids', () {
    test('calendarEventFavoriteIdFromName matches calendar card sanitization', () {
      expect(
        calendarEventFavoriteIdFromName('Quantbox Chennai Grand Masters 2026'),
        'cal_event_quantbox_chennai_grand_masters_2026',
      );
      expect(
        calendarEventFavoriteIdFromName(
          '11th International Chess Tournament of Anogia "Idaion Andron"',
        ),
        'cal_event_11th_international_chess_tournament_of_anogia_idaion_andron',
      );
    });

    test('isSyntheticFavoriteEventId detects calendar and twic prefixes', () {
      expect(isSyntheticFavoriteEventId('cal_event_foo'), isTrue);
      expect(isSyntheticFavoriteEventId('twic_event_Foo Bar'), isTrue);
      expect(
        isSyntheticFavoriteEventId('59th_biel_international_chess_festival_2026'),
        isFalse,
      );
    });

    test('favoriteEventIdCandidates always includes card id + cal alias', () {
      final ids = favoriteEventIdCandidates(
        'serbia_open_2026',
        eventName: 'Serbia Open 2026',
      );
      expect(ids, contains('serbia_open_2026'));
      expect(ids, contains('cal_event_serbia_open_2026'));
    });

    test('favoriteEventMatchesId bridges GBID and cal_event via metadata', () {
      expect(
        favoriteEventMatchesId(
          storedEventId: 'serbia_open_2026',
          candidateId: 'cal_event_serbia_open_2026',
          eventName: 'Serbia Open 2026',
          metadata: {
            'cal_event_alias': 'cal_event_serbia_open_2026',
            'source_event_id': 'cal_event_serbia_open_2026',
          },
        ),
        isTrue,
      );

      expect(
        favoriteEventMatchesId(
          storedEventId: 'serbia_open_2026',
          candidateId: 'unrelated_event',
          eventName: 'Serbia Open 2026',
        ),
        isFalse,
      );
    });

    test('favoriteEventMatchesId matches calendar alias of stored name', () {
      expect(
        favoriteEventMatchesId(
          storedEventId: '59th_biel_international_chess_festival_2026',
          candidateId: 'cal_event_59th_biel_international_chess_festival_2026',
          eventName: '59th Biel International Chess Festival 2026',
        ),
        isTrue,
      );
    });
  });
}
