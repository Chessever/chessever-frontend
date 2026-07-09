import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
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

    test('matches punctuation-free brand queries against event titles', () {
      final match = SearchScorer.bestTournamentMatch(
        query: 'chesscom open',
        name: '2026 Chess.com Open',
        aliases: const ['2026 Chess.com Open | Playoffs | Winners'],
      );

      expect(match.score, greaterThan(10));
      expect(match.matchedText, '2026 Chess.com Open');
    });

    test('ignores calendar noise tokens in tournament identity matching', () {
      final match = SearchScorer.bestTournamentMatch(
        query: 'titled tuesday june 30',
        name: 'Titled Tuesday Blitz',
        aliases: const [],
      );

      expect(match.score, greaterThan(10));
      expect(match.matchedText, 'Titled Tuesday Blitz');
    });
  });

  group('flexible event search player terms', () {
    test('surfaces a player event from common partial name searches', () {
      const aliases = [
        'Norway Chess 2026 | Open',
        'Carlsen, Magnus',
        'Nakamura, Hikaru',
      ];

      for (final query in ['mag', 'carl', 'carlsen', 'magnus carlsen']) {
        final match = bestFlexibleEventSearchMatch(
          query: query,
          name: 'Norway Chess 2026',
          aliases: aliases,
        );

        expect(match.score, greaterThan(10), reason: query);
        expect(match.matchedText, 'Carlsen, Magnus', reason: query);
      }
    });

    test('keeps event-name matches above player-term event hits', () {
      final match = bestFlexibleEventSearchMatch(
        query: 'norway chess',
        name: 'Norway Chess 2026',
        aliases: const ['Norway Chess 2026 | Open', 'Carlsen, Magnus'],
      );

      expect(match.score, greaterThan(90));
      expect(match.matchedText, 'Norway Chess 2026');
    });

    test('surfaces surname-named memorials from full player searches', () {
      final match = bestFlexibleEventSearchMatch(
        query: 'daniel naroditsky',
        name: '2026 Naroditsky Memorial',
        aliases: const ['2026 Naroditsky Memorial Rapid & Blitz'],
      );

      expect(match.score, greaterThan(10));
      expect(match.matchedText, '2026 Naroditsky Memorial');
    });

    test('ranks direct event-name prefix matches above player-term events', () {
      final memorialMatch = bestFlexibleEventSearchMatch(
        query: 'naro',
        name: '2026 Naroditsky Memorial',
        aliases: const ['2026 Naroditsky Memorial | Rapid'],
      );
      final playerEventMatch = bestFlexibleEventSearchMatch(
        query: 'naro',
        name: 'CCT Chess.com Classic 2025',
        aliases: const ['Naroditsky, Daniel'],
      );

      expect(memorialMatch.matchedText, '2026 Naroditsky Memorial');
      expect(memorialMatch.score, greaterThan(playerEventMatch.score));
    });

    test('keeps surname-named event text above the same player-term hit', () {
      final memorialMatch = bestFlexibleEventSearchMatch(
        query: 'daniel naroditsky',
        name: '2026 Naroditsky Memorial',
        aliases: const [
          '2026 Naroditsky Memorial Rapid & Blitz',
          'Naroditsky, Daniel',
        ],
      );
      final playerEventMatch = bestFlexibleEventSearchMatch(
        query: 'daniel naroditsky',
        name: 'CCT Chess.com Classic 2025',
        aliases: const ['Naroditsky, Daniel'],
      );

      expect(memorialMatch.matchedText, '2026 Naroditsky Memorial');
      expect(memorialMatch.score, greaterThan(playerEventMatch.score));
    });

    test('does not surface generic event titles from country/team aliases', () {
      final match = bestFlexibleEventSearchMatch(
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

    test('does not treat country/team aliases as player event matches', () {
      final match = bestPlayerSearchTermMatch(
        query: 'norway',
        searchTerms: const ['Norway_AA', 'Norway_BB', 'Norway_CC'],
      );

      expect(match.score, 0);
    });
  });
}
