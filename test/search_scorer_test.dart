import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:chessever2/widgets/search/search_scorer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SearchScorer tournament relevance', () {
    test('keeps close event-name matches when the queried year differs', () {
      final score = SearchScorer.calculateScore(
        'norway chess 2015',
        'Norway Chess 2026',
        SearchResultType.tournament,
      );

      expect(score, greaterThan(10));
    });

    test(
      'rejects generic chess-only matches for a specific historical event query',
      () {
        final score = SearchScorer.calculateScore(
          'norway chess 2015',
          'Asian Individual Chess Championship 2026',
          SearchResultType.tournament,
        );

        expect(score, 0);
      },
    );

    test('rejects broad player or country matches outside the event title', () {
      final match = SearchScorer.bestTournamentMatch(
        query: 'norway chess',
        name:
            '5th FIDE Intercontinental Online Chess Championship for Prisoners',
        aliases: const [
          '5th FIDE Intercontinental Online Chess Championship for Prisoners',
          '5th FIDE Intercontinental Online Chess Championship for Prisoners Men Group 6',
          'Norway_AA',
          'Norway_BB',
          'Norway_CC',
        ],
      );

      expect(match.score, 0);
    });

    test('rejects player-name hits from tournament results', () {
      final match = SearchScorer.bestTournamentMatch(
        query: 'magnus carlsen',
        name: 'Norway Chess 2026',
        aliases: const [
          'Norway Chess 2026',
          'Norway Chess 2026 | Open',
          'Carlsen, Magnus',
        ],
      );

      expect(match.score, 0);
    });

    test('uses title-like aliases but ignores unrelated search terms', () {
      final match = SearchScorer.bestTournamentMatch(
        query: 'norway chess open may',
        name: 'Norway Chess Open 2026',
        aliases: const [
          'Norway Chess Open 2026 MAY',
          'Urkedal, Frode Olav Olsen',
        ],
      );

      expect(match.score, greaterThan(10));
      expect(match.matchedText, 'Norway Chess Open 2026 MAY');
    });

    test('keeps Norway Chess results for the plain branded query', () {
      final score = SearchScorer.calculateScore(
        'norway chess',
        'Norway Chess 2026',
        SearchResultType.tournament,
      );

      expect(score, greaterThan(10));
    });

    test('ranks exact historical event above same-name current event', () {
      final exactScore = SearchScorer.calculateScore(
        'norway chess 2015',
        'Norway Chess 2015',
        SearchResultType.tournament,
      );
      final currentScore = SearchScorer.calculateScore(
        'norway chess 2015',
        'Norway Chess 2026',
        SearchResultType.tournament,
      );

      expect(exactScore, greaterThan(currentScore));
    });
  });
}
