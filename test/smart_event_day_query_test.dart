import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:flutter_test/flutter_test.dart';

Games _buildGame({
  required String id,
  required int whiteRating,
  required int blackRating,
}) {
  return Games(
    id: id,
    roundId: 'round1',
    roundSlug: 'round1',
    tourId: 'tour1',
    tourSlug: 'tour1',
    status: '*',
    players: [
      Player(
        name: 'White',
        fideId: 1,
        title: 'GM',
        fed: 'USA',
        rating: whiteRating,
        clock: 0,
        team: '',
      ),
      Player(
        name: 'Black',
        fideId: 2,
        title: 'GM',
        fed: 'IND',
        rating: blackRating,
        clock: 0,
        team: '',
      ),
    ],
  );
}

void main() {
  group('gameStructuredAverageRating', () {
    test('uses structured player ratings when PGN rating tags are missing', () {
      final game = _buildGame(
        id: 'g1',
        whiteRating: 2520,
        blackRating: 2510,
      );

      expect(gameStructuredAverageRating(game), 2515);
      expect(gameStructuredAverageRating(game) >= 2500, isTrue);
    });

    test('requires both player ratings for GM qualification', () {
      final game = _buildGame(id: 'g2', whiteRating: 2600, blackRating: 0);

      expect(gameStructuredAverageRating(game), 0);
      expect(gameStructuredAverageRating(game) >= 2500, isFalse);
    });
  });

  group('smart collection day is read whole', () {
    test('day cursor is formatted the way a date column compares', () {
      expect(formatSmartEventDay(DateTime(2026, 8, 2)), '2026-08-02');
      expect(formatSmartEventDay(DateTime(2026, 8, 2, 23, 59)), '2026-08-02');
      expect(formatSmartEventDay(DateTime(2026, 12, 31)), '2026-12-31');
      expect(formatSmartEventDay(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('a day wider than one response is read in successive ranges', () {
      final first = GameRepository.smartEventReadRange(0);
      expect(first, isNotNull);
      expect(first!.from, 0);
      expect(first.to, 999);

      final second = GameRepository.smartEventReadRange(1000);
      expect(second, isNotNull);
      expect(second!.from, 1000);
      expect(second.to, 1999);
    });

    test('the last page is short rather than overshooting the cap', () {
      final range = GameRepository.smartEventReadRange(900, cap: 1200);
      expect(range!.from, 900);
      expect(range.to, 1199);
    });

    test('the walk stops at the cap instead of paging forever', () {
      expect(GameRepository.smartEventReadRange(1200, cap: 1200), isNull);
      expect(GameRepository.smartEventReadRange(5000, cap: 1200), isNull);
    });

    test("a day maps to its own UTC window, not the reader's", () {
      final bounds = GameRepository.smartEventDayUtcBounds(
        DateTime(2026, 8, 2, 22, 30),
      );
      expect(bounds.startIso, '2026-08-02T00:00:00.000Z');
      expect(bounds.endIso, '2026-08-03T00:00:00.000Z');
    });
  });

  group('completed collections exclude live statuses', () {
    test('ongoing and live are not finished games', () {
      expect(smartEventGameStatusIsCompleted('*'), isFalse);
      expect(smartEventGameStatusIsCompleted('ongoing'), isFalse);
      expect(smartEventGameStatusIsCompleted('live'), isFalse);
      expect(smartEventGameStatusIsCompleted('LIVE'), isFalse);
      expect(smartEventGameStatusIsCompleted(null), isFalse);
      expect(smartEventGameStatusIsCompleted(''), isFalse);
    });

    test('results and other terminal statuses are completed', () {
      expect(smartEventGameStatusIsCompleted('1-0'), isTrue);
      expect(smartEventGameStatusIsCompleted('0-1'), isTrue);
      expect(smartEventGameStatusIsCompleted('1/2-1/2'), isTrue);
      expect(smartEventGameStatusIsCompleted('aborted'), isTrue);
    });

    test('live statuses are the complement of completed', () {
      expect(smartEventGameStatusIsLive('*'), isTrue);
      expect(smartEventGameStatusIsLive('ongoing'), isTrue);
      expect(smartEventGameStatusIsLive('1-0'), isFalse);
    });
  });
}
