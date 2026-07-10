import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/standings_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:flutter_test/flutter_test.dart';

PlayerCard _card({
  required String name,
  required String team,
  required int fideId,
}) => PlayerCard(
  name: name,
  federation: 'IND',
  title: 'GM',
  rating: 2700,
  countryCode: 'IND',
  fideId: fideId,
  team: team,
);

GamesTourModel _game({
  required String id,
  required PlayerCard white,
  required PlayerCard black,
}) => GamesTourModel(
  gameId: id,
  whitePlayer: white,
  blackPlayer: black,
  whiteTimeDisplay: '',
  blackTimeDisplay: '',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  gameStatus: GameStatus.draw,
  roundId: 'round-1',
  tourId: 'olympiad-open-i',
);

void main() {
  group('mergeTournamentRosterWithGamePlayers', () {
    test('adds game players when a non-empty roster is only partial', () {
      final games = [
        _game(
          id: 'g1',
          white: _card(name: 'Gukesh D', team: 'India', fideId: 46616543),
          black: _card(
            name: 'Carlsen, Magnus',
            team: 'Norway',
            fideId: 1503014,
          ),
        ),
        // A repeated player in another game must not create another chip.
        _game(
          id: 'g2',
          white: _card(name: 'Erigaisi Arjun', team: 'India', fideId: 35009192),
          black: _card(name: 'Gukesh D', team: 'India', fideId: 46616543),
        ),
      ];

      final merged = mergeTournamentRosterWithGamePlayers(
        tournamentPlayers: [
          TournamentPlayer(
            name: 'Carlsen, Magnus',
            fideId: 1503014,
            played: 11,
            rating: 2832,
            team: 'Norway',
          ),
        ],
        gamesTourModels: games,
      );

      expect(merged, hasLength(3));
      expect(
        merged.where((player) => player.team == 'India').map((p) => p.name),
        containsAll(<String>['Gukesh D', 'Erigaisi Arjun']),
      );
      expect(merged.where((player) => player.fideId == 46616543), hasLength(1));
      // Authoritative roster fields win when the player already exists.
      expect(
        merged.singleWhere((player) => player.fideId == 1503014).rating,
        2832,
      );
    });

    test('fills a missing roster team from the matching game card', () {
      final merged = mergeTournamentRosterWithGamePlayers(
        tournamentPlayers: [
          TournamentPlayer(
            name: 'Gukesh D',
            fideId: 46616543,
            played: 11,
            rating: 2764,
          ),
        ],
        gamesTourModels: [
          _game(
            id: 'g1',
            white: _card(name: 'Gukesh D', team: 'India', fideId: 46616543),
            black: _card(
              name: 'Carlsen, Magnus',
              team: 'Norway',
              fideId: 1503014,
            ),
          ),
        ],
      );

      expect(
        merged.singleWhere((player) => player.fideId == 46616543).team,
        'India',
      );
    });

    test('uses the game team when the roster team label is stale', () {
      final merged = mergeTournamentRosterWithGamePlayers(
        tournamentPlayers: [
          TournamentPlayer(
            name: 'Gukesh D',
            fideId: 46616543,
            played: 11,
            rating: 2764,
            team: 'IND',
          ),
        ],
        gamesTourModels: [
          _game(
            id: 'g1',
            white: _card(name: 'Gukesh D', team: 'India', fideId: 46616543),
            black: _card(
              name: 'Carlsen, Magnus',
              team: 'Norway',
              fideId: 1503014,
            ),
          ),
        ],
      );

      expect(
        merged.singleWhere((player) => player.fideId == 46616543).team,
        'India',
      );
    });

    test('does not merge different FIDE IDs that share a name and team', () {
      final merged = mergeTournamentRosterWithGamePlayers(
        tournamentPlayers: [
          TournamentPlayer(
            name: 'Same Name',
            fideId: 101,
            played: 1,
            team: 'Team A',
          ),
          TournamentPlayer(
            name: 'Same Name',
            fideId: 202,
            played: 1,
            team: 'Team A',
          ),
        ],
        gamesTourModels: const [],
      );

      expect(merged.map((player) => player.fideId), [101, 202]);
    });
  });
}
