import 'package:chessever2/repository/lichess/broadcast/lichess_broadcast_pairings_repository.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';
import 'package:flutter_test/flutter_test.dart';

// Shape taken from a real response of
// GET https://lichess.org/api/broadcast/-/-/p37tSfIq (Naroditsky Memorial R4).
Map<String, dynamic> _roundJson() => {
  'round': {'id': 'p37tSfIq', 'name': 'Round 4', 'slug': 'round-4'},
  'tour': {'id': 'fkrN18wc', 'name': 'Naroditsky Memorial | Rapid'},
  'games': [
    {
      'id': 'sTSfpGCc',
      'name': 'Suleymanli, Aydin - Sevian, Samuel',
      'players': [
        {
          'name': 'Suleymanli, Aydin',
          'title': 'GM',
          'rating': 2561,
          'fideId': 13413937,
          'fed': 'AZE',
          'clock': 60500,
        },
        {
          'name': 'Sevian, Samuel',
          'title': 'GM',
          'rating': 2666,
          'fideId': 2040506,
          'fed': 'USA',
          'clock': 60500,
        },
      ],
      'status': '*',
    },
    // Pre-pairing placeholder board — must be dropped.
    {
      'id': 'zzPlaceh',
      'name': '? - ?',
      'players': [
        {'name': '?'},
        {'name': '?'},
      ],
      'status': '*',
    },
    // Malformed board without players — must be dropped.
    {'id': 'noPlayers'},
  ],
};

void main() {
  group('lichess pairing fallback parsing', () {
    test('maps resolved boards and drops placeholders', () {
      final games = LichessBroadcastPairingsRepository.parseRoundPairings(
        _roundJson(),
        roundId: 'p37tSfIq',
        tourId: 'fkrN18wc',
        tourSlug: '',
        roundSlug: '',
      );

      expect(games, hasLength(1));
      final game = games.single;
      expect(game.id, 'sTSfpGCc');
      expect(game.roundId, 'p37tSfIq');
      expect(game.tourId, 'fkrN18wc');
      expect(game.boardNr, 1);
      expect(game.status, '*');
      expect(game.players, hasLength(2));
      expect(game.players![0].name, 'Suleymanli, Aydin');
      expect(game.players![1].name, 'Sevian, Samuel');
      expect(game.lastMove, isNull);
      expect(game.pgn, isNull);
    });

    test('parsed boards convert to pairing-only tour models', () {
      final games = LichessBroadcastPairingsRepository.parseRoundPairings(
        _roundJson(),
        roundId: 'p37tSfIq',
        tourId: 'fkrN18wc',
        tourSlug: '',
        roundSlug: '',
      );

      final model = GamesTourModel.fromGame(games.single);
      // Pairing rows must NOT count as playable event boards (no moves)…
      expect(isEventBoardGameVisible(model), isFalse);
      // …but their players are resolved, which is what qualifies the round
      // as an upcoming pairing round in the Games tab.
      expect(model.whitePlayer.name, 'Suleymanli, Aydin');
      expect(model.blackPlayer.name, 'Sevian, Samuel');
    });

    test('returns empty for missing or malformed games array', () {
      expect(
        LichessBroadcastPairingsRepository.parseRoundPairings(
          {'round': {}, 'games': 'nope'},
          roundId: 'r',
          tourId: 't',
          tourSlug: '',
          roundSlug: '',
        ),
        isEmpty,
      );
      expect(
        LichessBroadcastPairingsRepository.parseRoundPairings(
          const {},
          roundId: 'r',
          tourId: 't',
          tourSlug: '',
          roundSlug: '',
        ),
        isEmpty,
      );
    });
  });
}
