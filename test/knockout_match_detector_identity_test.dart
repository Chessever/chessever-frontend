import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/utils/knockout_match_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KnockoutMatchDetector participant identity', () {
    test('groups legs by FIDE ids despite title and case changes', () {
      final matches = KnockoutMatchDetector.groupByMatches([
        _game(
          id: 'g1',
          white: _player('GM Alpha Player', fideId: 11),
          black: _player('Beta Player', fideId: 22),
          slug: 'game-1',
        ),
        _game(
          id: 'g2',
          white: _player('beta player', fideId: 22),
          black: _player('ALPHA PLAYER', fideId: 11),
          slug: 'game-2',
        ),
      ]);

      expect(matches, hasLength(1));
      expect(matches.values.single.map((game) => game.gameId), ['g1', 'g2']);
      expect(matches.keys.single, 'fide:11|fide:22');
    });

    test('uses title-free case-normalized names without FIDE ids', () {
      final matches = KnockoutMatchDetector.groupByMatches([
        _game(
          id: 'g1',
          white: _player('IM Gamma  Player'),
          black: _player('WGM Delta Player'),
          slug: 'game-1',
        ),
        _game(
          id: 'g2',
          white: _player('delta player'),
          black: _player('gamma player'),
          slug: 'game-2',
        ),
      ]);

      expect(matches, hasLength(1));
      expect(matches.keys.single, 'name:delta player|name:gamma player');
    });

    test('fills a missing leg FIDE id from an unambiguous normalized name', () {
      final matches = KnockoutMatchDetector.groupByMatches([
        _game(
          id: 'g1',
          white: _player('GM Alpha Player', fideId: 11),
          black: _player('Beta Player', fideId: 22),
          slug: 'game-1',
        ),
        _game(
          id: 'g2',
          white: _player('beta player'),
          black: _player('alpha player'),
          slug: 'game-2',
        ),
      ]);

      expect(matches, hasLength(1));
      expect(matches.keys.single, 'fide:11|fide:22');
    });

    test('does not create repeatable matchups from placeholder players', () {
      final games = [
        _game(
          id: 'g1',
          white: _player('?'),
          black: _player('TBD'),
          slug: 'game-1',
        ),
        _game(
          id: 'g2',
          white: _player('Unknown Player'),
          black: _player('TBA'),
          slug: 'game-2',
        ),
        _game(
          id: 'g3',
          white: _player('?'),
          black: _player('TBD'),
          slug: 'game-1',
        ),
        _game(
          id: 'g4',
          white: _player('Unknown Player'),
          black: _player('TBA'),
          slug: 'game-2',
        ),
      ];

      expect(KnockoutMatchDetector.groupByMatches(games), isEmpty);
      expect(KnockoutMatchDetector.isKnockoutMatchFormat(games), isFalse);
    });

    test('detects replay games appended to one source round', () {
      final alpha = _player('Alpha', fideId: 11);
      final beta = _player('Beta', fideId: 22);
      final gamma = _player('Gamma', fideId: 33);
      final delta = _player('Delta', fideId: 44);
      final games = [
        _game(
          id: 'board-1',
          white: alpha,
          black: beta,
          slug: 'lower-round-1',
          roundId: 'source-round',
          boardNr: 1,
        ),
        _game(
          id: 'board-2',
          white: gamma,
          black: delta,
          slug: 'lower-round-1',
          roundId: 'source-round',
          boardNr: 2,
        ),
        _game(
          id: 'board-3',
          white: beta,
          black: alpha,
          slug: 'lower-round-1',
          roundId: 'source-round',
          boardNr: 3,
        ),
      ];

      expect(
        KnockoutMatchDetector.hasRepeatedMatchupInSingleSourceRound(
          isKnockoutTournament: true,
          games: games,
        ),
        isTrue,
      );
      expect(
        KnockoutMatchDetector.hasRepeatedMatchupInSingleSourceRound(
          isKnockoutTournament: false,
          games: games,
        ),
        isFalse,
        reason: 'ordinary tournament formats must retain board order',
      );
    });

    test(
      'does not treat legs from separate source rounds as appended boards',
      () {
        final alpha = _player('Alpha', fideId: 11);
        final beta = _player('Beta', fideId: 22);
        final games = [
          _game(
            id: 'leg-1',
            white: alpha,
            black: beta,
            slug: 'game-1',
            roundId: 'round-game-1',
          ),
          _game(
            id: 'leg-2',
            white: beta,
            black: alpha,
            slug: 'game-2',
            roundId: 'round-game-2',
          ),
        ];

        expect(
          KnockoutMatchDetector.hasRepeatedMatchupInSingleSourceRound(
            isKnockoutTournament: true,
            games: games,
          ),
          isFalse,
        );
      },
    );

    test('uses descending board number when timestamps and slugs tie', () {
      final alpha = _player('Alpha', fideId: 11);
      final beta = _player('Beta', fideId: 22);
      final syncedAt = DateTime.utc(2026, 8, 13, 12, 12);
      final ordered = KnockoutMatchDetector.orderMatchGamesLatestFirst([
        _game(
          id: 'z-older',
          white: alpha,
          black: beta,
          slug: 'lower-round-1',
          boardNr: 1,
          lastMoveTime: syncedAt,
        ),
        _game(
          id: 'a-newer',
          white: beta,
          black: alpha,
          slug: 'lower-round-1',
          boardNr: 3,
          lastMoveTime: syncedAt,
        ),
      ]);

      expect(ordered.map((game) => game.gameId), ['a-newer', 'z-older']);
    });
  });
}

GamesTourModel _game({
  required String id,
  required PlayerCard white,
  required PlayerCard black,
  required String slug,
  String? roundId,
  int? boardNr,
  DateTime? lastMoveTime,
}) => GamesTourModel(
  gameId: id,
  whitePlayer: white,
  blackPlayer: black,
  whiteTimeDisplay: '',
  blackTimeDisplay: '',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  gameStatus: GameStatus.draw,
  roundId: roundId ?? slug,
  roundSlug: slug,
  tourId: 'tour',
  boardNr: boardNr,
  lastMoveTime: lastMoveTime,
);

PlayerCard _player(String name, {int? fideId}) => PlayerCard(
  name: name,
  federation: 'FIDE',
  title: '',
  rating: 2500,
  countryCode: 'FIDE',
  team: null,
  fideId: fideId,
);
