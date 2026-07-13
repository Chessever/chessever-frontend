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
  });
}

GamesTourModel _game({
  required String id,
  required PlayerCard white,
  required PlayerCard black,
  required String slug,
}) => GamesTourModel(
  gameId: id,
  whitePlayer: white,
  blackPlayer: black,
  whiteTimeDisplay: '',
  blackTimeDisplay: '',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  gameStatus: GameStatus.draw,
  roundId: slug,
  roundSlug: slug,
  tourId: 'tour',
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
