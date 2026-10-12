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

GamesTourModel _game({
  String tourId = '',
  String? tourSlug,
  String? pgn,
  String? roundSlug,
  GameSource source = GameSource.supabase,
}) {
  final player = _player();
  return GamesTourModel(
    gameId: 'game-1',
    source: source,
    roundSlug: roundSlug,
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
  // Archive rows keep their ECO code in `roundSlug` for the list card, and
  // Event info used to print it as the round ("Round: A22").
  group('event info round line', () {
    test('an archive game takes its round from the PGN, not its ECO code', () {
      final game = _game(source: GameSource.gamebase, roundSlug: 'A22');

      expect(
        resolveEventInfoRoundLabelForTesting(game, const {'Round': '6.2'}),
        'Round 6',
      );
      expect(
        resolveEventInfoRoundLabelForTesting(game, const {
          'Round': '6.2',
          'ChessEverRoundName': 'Round 6 | Tiebreak',
        }),
        'Round 6 | Tiebreak',
      );
      expect(
        resolveEventInfoRoundLabelForTesting(game, const {'Round': 'Final'}),
        'Final',
      );
    });

    test('an archive game with no round in its PGN shows no round', () {
      for (final slug in const ['A22', 'RAPID', null]) {
        final game = _game(source: GameSource.gamebase, roundSlug: slug);
        expect(
          resolveEventInfoRoundLabelForTesting(game, const {'Round': '?'}),
          isNull,
          reason: '$slug',
        );
      }
    });

    test('a real round label on an archive game is kept', () {
      final game = _game(source: GameSource.twic, roundSlug: 'Round 5');

      expect(
        resolveEventInfoRoundLabelForTesting(game, const {'Round': '9'}),
        'Round 5',
      );
    });

    test('a broadcast game still reads its round slug', () {
      final game = _game(roundSlug: 'round-7');

      expect(
        resolveEventInfoRoundLabelForTesting(game, const {'Round': '7.3'}),
        'Round 7',
      );
    });
  });

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

    // Trello #1228: a miniature played in a broadcast is opened with the
    // "Miniatures" label on its row and the pairing in its PGN Event.
    test('an opened broadcast miniature shows its tournament', () {
      final game = _game(tourId: 'Miniatures', tourSlug: 'Miniatures');
      const pgn =
          '[Event "Round 6: Del Rio Baena, Dani - Garcia Canals, Gerard"]\n'
          '[Site "https://lichess.org/broadcast/catalan-age-group-team-championship-2026-sub-18/round-6/rkYWEnda/R3kJFF30"]\n'
          '[White "Del Rio Baena, Dani"]\n'
          '[Black "Garcia Canals, Gerard"]\n\n*';

      expect(
        resolveEventInfoFallbackEventNameForTesting(game, pgn),
        'Catalan Age Group Team Championship 2026 Sub 18',
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
