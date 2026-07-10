import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldFetchAnotherTourGamesPage', () {
    test('continues when Supabase returns a full page', () {
      expect(shouldFetchAnotherTourGamesPage(1000), isTrue);
    });

    test('stops when Supabase returns a partial page', () {
      expect(shouldFetchAnotherTourGamesPage(999), isFalse);
      expect(shouldFetchAnotherTourGamesPage(0), isFalse);
    });

    test('honors smaller explicit requested page sizes', () {
      expect(shouldFetchAnotherTourGamesPage(25, pageSize: 25), isTrue);
      expect(shouldFetchAnotherTourGamesPage(24, pageSize: 25), isFalse);
    });
  });

  test('tour safety-net snapshot parses only set-level fields', () {
    final snapshot = TourGameSafetyNetSnapshot.fromJson({
      'id': 'game-1',
      'round_id': 'round-1',
      'round_slug': 'round-one',
      'status': '*',
      'pgn': 'large field intentionally ignored',
    });

    expect(snapshot.id, 'game-1');
    expect(snapshot.roundId, 'round-1');
    expect(snapshot.roundSlug, 'round-one');
    expect(snapshot.status, '*');
  });
}
