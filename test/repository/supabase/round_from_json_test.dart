import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _roundJson({
  required String name,
  required String slug,
  required String url,
}) {
  return {
    'id': 'AlyVP7Tj',
    'slug': slug,
    'tour_id': 'Y9YjcDKG',
    'tour_slug': 'german-bundesliga-202526',
    'name': name,
    'created_at': '2025-09-27T05:23:52.500Z',
    'starts_at': '2025-12-08T09:15:00.000Z',
    'url': url,
  };
}

void main() {
  group('Round.fromJson', () {
    test('uses canonical Lichess broadcast URL slug for stale round labels', () {
      final round = Round.fromJson(
        _roundJson(
          name: 'Round 4.1',
          slug: 'round-4-1',
          url:
              'https://lichess.org/broadcast/german-bundesliga-202526/round-11/AlyVP7Tj',
        ),
      );

      expect(round.name, 'Round 11');
      expect(round.slug, 'round-11');
    });

    test('preserves non-Lichess custom round labels', () {
      final round = Round.fromJson(
        _roundJson(
          name: 'Pool A',
          slug: 'pool-a',
          url: 'https://example.com/broadcast/round-11/AlyVP7Tj',
        ),
      );

      expect(round.name, 'Pool A');
      expect(round.slug, 'pool-a');
    });
  });
}
