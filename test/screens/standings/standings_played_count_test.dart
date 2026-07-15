import 'package:chessever2/screens/standings/standings_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveStandingsPlayedCount', () {
    test('prefers the source played count', () {
      expect(
        resolveStandingsPlayedCount(sourcePlayed: 3, countedFinishedGames: 4),
        3,
      );
    });

    test('falls back to counted finished games when source is unavailable', () {
      expect(
        resolveStandingsPlayedCount(sourcePlayed: 0, countedFinishedGames: 4),
        4,
      );
    });
  });
}
