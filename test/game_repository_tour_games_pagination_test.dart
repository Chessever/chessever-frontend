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
}
