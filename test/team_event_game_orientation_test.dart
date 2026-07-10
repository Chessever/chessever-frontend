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
}
