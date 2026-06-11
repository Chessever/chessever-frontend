import 'package:chessever2/screens/chessboard/chess_board_screen_new.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter_test/flutter_test.dart';

PlayerCard _player() {
  return PlayerCard(
    name: 'Player',
    federation: 'NO',
    title: 'GM',
    rating: 2700,
    countryCode: 'NO',
    team: null,
  );
}

GamesTourModel _game({String tourId = '', String? tourSlug, String? pgn}) {
  final player = _player();
  return GamesTourModel(
    gameId: 'game-1',
    whitePlayer: player,
    blackPlayer: player,
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: GameStatus.ongoing,
    roundId: 'round-1',
    tourId: tourId,
    tourSlug: tourSlug,
    pgn: pgn,
  );
}

void main() {
  group('event info fallback lookup title', () {
    test('uses PGN Event title even when tourId is only a UUID', () {
      final game = _game(
        tourId: '11111111-2222-3333-4444-555555555555',
        pgn: '[Event "2026 Norway Chess Open"]\n[Site "Oslo, NO"]\n\n*',
      );

      expect(
        resolveEventInfoFallbackEventNameForTesting(game, null),
        '2026 Norway Chess Open',
      );
    });

    test('falls back to a readable tour slug before plain game info', () {
      final game = _game(
        tourId: '11111111-2222-3333-4444-555555555555',
        tourSlug: 'norway-chess-open',
      );

      expect(
        resolveEventInfoFallbackEventNameForTesting(game, null),
        'Norway Chess Open',
      );
    });

    test('does not display a UUID as an event title', () {
      final game = _game(tourId: '11111111-2222-3333-4444-555555555555');

      expect(
        resolveEventInfoFallbackEventNameForTesting(game, null),
        'Game Info',
      );
    });

    test('keeps short non-UUID tour ids as a last display fallback', () {
      final game = _game(tourId: 'U9AdmoyQ');

      expect(
        resolveEventInfoFallbackEventNameForTesting(game, null),
        'U9AdmoyQ',
      );
    });
  });
}
