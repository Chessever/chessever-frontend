import 'package:chessever2/utils/player_name_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('playerNameSearchMatchScore', () {
    test('treats first-name searches as strong matches for comma names', () {
      final carlsenScore = playerNameSearchMatchScore(
        'Carlsen, Magnus',
        'Magnus',
      );
      final magnussonScore = playerNameSearchMatchScore(
        'Magnusson,Gu',
        'Magnus',
      );

      expect(carlsenScore, greaterThan(magnussonScore));
    });

    test('matches natural-order full names against FIDE name order', () {
      expect(
        playerNameSearchMatchScore('Carlsen, Magnus', 'Magnus Carlsen'),
        100,
      );
      expect(
        playerNameSearchMatchScore('Carlsen, Magnus', 'Carlsen Magnus'),
        100,
      );
    });

    test('keeps surname prefix searches strong', () {
      expect(playerNameSearchMatchScore('Giri, Anish', 'Giri'), 95);
      expect(playerNameSearchMatchScore('Giri, Anish', 'Anish'), 95);
    });

    test('keeps short Magnus Carlsen prefixes strong', () {
      for (final query in ['mag', 'carl', 'carlsen']) {
        expect(
          playerNameSearchMatchScore('Carlsen, Magnus', query),
          greaterThanOrEqualTo(90),
          reason: query,
        );
      }
    });

    test('matches reordered short name fragments (Md Imran)', () {
      expect(playerNameSearchMatchScore('Imran, Md', 'Md Imran'), 100);
      expect(
        playerNameSearchMatchScore('Imran, Md', 'Imran Md'),
        greaterThanOrEqualTo(85),
      );
      expect(
        playerNameSearchMatchScore('Md Imran', 'Imran Md'),
        greaterThanOrEqualTo(85),
      );
    });
  });
}
