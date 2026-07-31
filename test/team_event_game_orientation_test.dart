import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/games_tour_content_provider.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

PlayerCard _card(String name, String team) => PlayerCard(
  name: name,
  federation: '',
  title: '',
  rating: 2000,
  countryCode: '',
  team: team,
);

GamesTourModel _game({
  required String id,
  required String whiteName,
  required String whiteTeam,
  required String blackName,
  required String blackTeam,
}) => GamesTourModel(
  gameId: id,
  whitePlayer: _card(whiteName, whiteTeam),
  blackPlayer: _card(blackName, blackTeam),
  whiteTimeDisplay: '',
  blackTimeDisplay: '',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  gameStatus: GameStatus.ongoing,
  roundId: 'round-1',
  tourId: 'team-event',
);

void main() {
  final games = [
    _game(
      id: 'board-1',
      whiteName: 'A One',
      whiteTeam: 'Team A',
      blackName: 'B One',
      blackTeam: 'Team B',
    ),
    _game(
      id: 'board-2',
      whiteName: 'B Two',
      whiteTeam: 'Team B',
      blackName: 'A Two',
      blackTeam: 'Team A',
    ),
  ];

  test('one team stays on one side when its board colors alternate', () {
    final grouped = groupTeamGamesByMatchup(
      selectedRoundId: 'round-1',
      games: games,
    );

    expect(grouped.keys, ['Team A vs Team B']);
    final boards = grouped.values.single;
    expect(boards.map((board) => board.comparison), [
      MatchComparison.sameOrder,
      MatchComparison.oppositeOrder,
    ]);
    expect(boards.map((board) => teamOneBottomSide(board.comparison)), [
      Side.white,
      Side.black,
    ]);
    expect(boards.map((board) => teamOrderedPlayers(board).teamOne.team), [
      'Team A',
      'Team A',
    ]);
    expect(boards.map((board) => teamOrderedPlayers(board).teamTwo.team), [
      'Team B',
      'Team B',
    ]);
  });

  group('matchComparisonForSelectedTeamSide', () {
    test('selected team White → sameOrder (left is White)', () {
      final comparison = matchComparisonForSelectedTeamSide(
        selectedTeamIsWhite: true,
      );
      expect(comparison, MatchComparison.sameOrder);
      expect(teamOneBottomSide(comparison), Side.white);

      final ordered = teamOrderedPlayers(
        MatchWithComparison(game: games[0], comparison: comparison),
      );
      expect(ordered.teamOne.team, 'Team A');
      expect(ordered.teamOne.name, 'A One');
      expect(ordered.teamTwo.team, 'Team B');
    });

    test('selected team Black → oppositeOrder (left is Black)', () {
      // Board 2: Team A is Black. Score card must still put Team A on left.
      final comparison = matchComparisonForSelectedTeamSide(
        selectedTeamIsWhite: false,
      );
      expect(comparison, MatchComparison.oppositeOrder);
      expect(teamOneBottomSide(comparison), Side.black);

      final ordered = teamOrderedPlayers(
        MatchWithComparison(game: games[1], comparison: comparison),
      );
      expect(ordered.teamOne.team, 'Team A');
      expect(ordered.teamOne.name, 'A Two');
      expect(ordered.teamTwo.team, 'Team B');
      expect(ordered.teamTwo.name, 'B Two');
    });

    test(
      'alternating board colors keep selected team on left for every board',
      () {
        // Mirrors team score card / standings expand path: each board's
        // ourIsWhite drives comparison (games[0] Team A White, games[1] Black).
        final ourIsWhitePerBoard = [true, false];
        final comparisons = [
          for (final oursWhite in ourIsWhitePerBoard)
            matchComparisonForSelectedTeamSide(selectedTeamIsWhite: oursWhite),
        ];

        expect(comparisons, [
          MatchComparison.sameOrder,
          MatchComparison.oppositeOrder,
        ]);

        for (var i = 0; i < games.length; i++) {
          final ordered = teamOrderedPlayers(
            MatchWithComparison(game: games[i], comparison: comparisons[i]),
          );
          expect(
            ordered.teamOne.team,
            'Team A',
            reason: 'board ${i + 1}: selected team must stay left',
          );
          expect(ordered.teamTwo.team, 'Team B');
        }
      },
    );
  });
}
