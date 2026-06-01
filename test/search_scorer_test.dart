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
