import 'package:chessever2/repository/supabase/tour/published_tiebreak.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:flutter_test/flutter_test.dart';

TeamStandingModel _team(List<PublishedTiebreak> tiebreaks) => TeamStandingModel(
  teamName: 'ŠK Oroslavje',
  rank: 1,
  officialRound: 8,
  matchPoints: 13,
  gamePoints: 19,
  matchesWon: 6,
  matchesDrawn: 1,
  matchesLost: 1,
  boardsPlayed: 0,
  players: const [],
  tiebreaks: tiebreaks,
);

void main() {
  test('Chess-Results TB1/TB2 match and game points are not repeated', () {
    const sb = PublishedTiebreak(
      points: 154,
      description:
          'Olympiad-Sonneborn-Berger-Tie-Break without lowest result '
          '(Khanty-Mansiysk)',
      extendedCode: 'TB3',
    );
    final team = _team(const [
      PublishedTiebreak(
        points: 13,
        description: 'Matchpoints (2 for wins, 1 for Draws, 0 for Losses)',
        extendedCode: 'TB1',
      ),
      PublishedTiebreak(
        points: 19,
        description: 'points (game-points)',
        extendedCode: 'TB2',
      ),
      sb,
    ]);
    expect(team.extraTiebreaks, [sb]);
    expect(team.tiebreaks, hasLength(3));
  });

  test('Info64 MP/GP go, derived match-point tiebreaks stay', () {
    const derived = [
      PublishedTiebreak(
        points: 13,
        description: 'BH:MP',
        extendedCode: 'BH:MP',
      ),
      PublishedTiebreak(
        points: 1,
        description: 'Dir_MP',
        extendedCode: 'Dir_MP',
      ),
      PublishedTiebreak(
        points: 19,
        description: 'EMMSB',
        extendedCode: 'EMMSB',
      ),
    ];
    final team = _team(const [
      PublishedTiebreak(points: 13, description: 'MP', extendedCode: 'MP'),
      PublishedTiebreak(points: 19, description: 'GP', extendedCode: 'GP'),
      ...derived,
    ]);
    expect(team.extraTiebreaks, derived);
  });

  test('a published column that disagrees with the row is kept', () {
    const mp = PublishedTiebreak(
      points: 14,
      description: 'Matchpoints (3 for wins, 1 for Draws, 0 for Losses)',
      extendedCode: 'TB1',
    );
    const gp = PublishedTiebreak(
      points: 18.5,
      description: 'points (game-points)',
      extendedCode: 'TB2',
    );
    expect(_team(const [mp, gp]).extraTiebreaks, [mp, gp]);
  });
}
