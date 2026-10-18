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

  test('a variable match-point column that repeats the row is hidden', () {
    // Andalucía rapid teams: "Tie Break1: Matchpoints (variabel)" (3/1/0).
    const mp = PublishedTiebreak(
      points: 21,
      description: 'Matchpoints (variabel)',
      extendedCode: 'TB1',
    );
    const bh = PublishedTiebreak(
      points: 116.5,
      description: 'Buchholz Tie-Breaks (variabel with parameter)',
      extendedCode: 'TB3',
    );
    final team = TeamStandingModel(
      teamName: 'Prodomasa Coin',
      rank: 1,
      tiebreaks: const [mp, bh],
      matchPoints: 21,
      gamePoints: 24,
      matchesWon: 7,
      matchesDrawn: 0,
      matchesLost: 0,
      boardsPlayed: 0,
      players: const [],
    );
    expect(team.extraTiebreaks, [bh]);
  });

  test('a later variable column stays on every row, even at 0 = 0', () {
    // Russian Rapid Teams Women: TB1 is the 2/1/0 match points the card
    // shows; TB4 "Matchpoints (variabel)" is another number. A team on 0 MP
    // also has 0 in TB4, and used to lose that column while its neighbours
    // kept it.
    List<PublishedTiebreak> tbs(num mp, num gp, num variable) => [
      PublishedTiebreak(
        points: mp,
        description: 'Matchpoints (2 for wins, 1 for Draws, 0 for Losses)',
        extendedCode: 'TB1',
      ),
      PublishedTiebreak(
        points: gp,
        description: 'points (game-points)',
        extendedCode: 'TB2',
      ),
      const PublishedTiebreak(
        points: 0,
        description:
            'The results of the teams in then same point group according '
            'to Matchpoints',
        extendedCode: 'TB3',
      ),
      PublishedTiebreak(
        points: variable,
        description: 'Matchpoints (variabel)',
        extendedCode: 'TB4',
      ),
    ];
    TeamStandingModel row(num mp, num gp, num variable) => TeamStandingModel(
      teamName: 'Team $mp',
      rank: 1,
      tiebreaks: tbs(mp, gp, variable),
      matchPoints: mp.toDouble(),
      gamePoints: gp.toDouble(),
      matchesWon: 0,
      matchesDrawn: 0,
      matchesLost: 6,
      boardsPlayed: 0,
      players: const [],
    );
    for (final team in [row(11, 15, 5), row(0, 4, 0)]) {
      expect(
        [for (final t in team.extraTiebreaks) t.extendedCode],
        ['TB3', 'TB4'],
        reason: team.teamName,
      );
    }
  });
}
