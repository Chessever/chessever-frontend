import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_tour_screen_provider.dart';
import 'package:flutter_test/flutter_test.dart';

TeamStandingModel _team(String name, {bool withPlayer = false}) =>
    TeamStandingModel(
      teamName: name,
      rank: withPlayer ? 1 : 0,
      matchPoints: 0,
      gamePoints: 0,
      matchesWon: 0,
      matchesDrawn: 0,
      matchesLost: 0,
      boardsPlayed: 0,
      players:
          withPlayer
              ? const [
                PlayerStandingModel(
                  countryCode: 'IND',
                  name: 'Gukesh D',
                  score: 2764,
                  scoreChange: 0,
                  matchScore: '9 / 10',
                  team: 'India',
                ),
              ]
              : const [],
    );

void main() {
  test('an early empty selection upgrades when team standings arrive', () {
    final placeholder = _team('India');
    final complete = _team('India', withPlayer: true);

    final resolved = resolveSelectedTeamStanding(
      selected: placeholder,
      standings: [complete],
    );

    expect(resolved, same(complete));
    expect(resolved!.players.single.name, 'Gukesh D');
  });

  test('team lookup ignores harmless case and surrounding whitespace', () {
    final complete = _team('India', withPlayer: true);

    final resolved = resolveSelectedTeamStanding(
      selected: _team('  INDIA  '),
      standings: [complete],
    );

    expect(resolved, same(complete));
  });
}
