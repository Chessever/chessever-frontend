import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/widgets/event_search_placeholder.dart';
import 'package:chessever2/widgets/search/gameSearch/game_result_search.dart';
import 'package:flutter_test/flutter_test.dart';

Games _game({String? status, String? pgn}) {
  return Games(
    id: 'game-1',
    roundId: 'round-1',
    roundSlug: 'round-1',
    tourId: 'tour-1',
    tourSlug: 'tour-1',
    status: status,
    pgn: pgn,
  );
}

void main() {
  group('event search placeholders', () {
    test('covers plain search and supported example searches', () {
      final placeholders = List.generate(
        eventSearchPlaceholderCount,
        (index) => eventSearchPlaceholderForIndex(index, countryCode: 'AZ'),
      );

      expect(placeholders, contains('Search'));
      expect(placeholders, contains('Search by player: Caruana'));
      expect(placeholders, contains('Search by opening: Ruy Lopez'));
      expect(placeholders, contains('Search by ECO: B90'));
      expect(placeholders, contains('Search by country: AZE'));
      expect(placeholders, contains('Search by title: GM'));
      expect(placeholders, contains('Search by result: 1-0'));
    });

    test('uses AZE fallback when the user country is not loaded yet', () {
      expect(eventSearchPlaceholderForIndex(4), 'Search by country: AZE');
    });
  });

  group('game result search', () {
    test('matches exact standard result tokens from status', () {
      expect(gameResultMatchesSearchQuery(_game(status: '1-0'), '1-0'), isTrue);
      expect(gameResultMatchesSearchQuery(_game(status: '0-1'), '0-1'), isTrue);
      expect(
        gameResultMatchesSearchQuery(_game(status: '1/2-1/2'), '1/2-1/2'),
        isTrue,
      );
    });

    test('falls back to PGN Result tag when status is not a result', () {
      final game = _game(
        status: '*',
        pgn: '[Event "Example"]\n[Result "0-1"]\n\n1. e4 c5 0-1',
      );

      expect(gameResultSearchText(game), '0-1');
      expect(gameResultMatchesSearchQuery(game, '0-1'), isTrue);
    });

    test('does not match unsupported natural-language aliases', () {
      final game = _game(status: '1/2-1/2');

      expect(gameResultMatchesSearchQuery(game, 'draw'), isFalse);
      expect(gameResultMatchesSearchQuery(game, 'white won'), isFalse);
      expect(gameResultMatchesSearchQuery(game, 'black won'), isFalse);
    });
  });
}
