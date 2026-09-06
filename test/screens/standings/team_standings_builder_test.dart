import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/team_standings_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/team_scoring_rules.dart';
import 'package:flutter_test/flutter_test.dart';

PlayerCard _card(String name, String team) => PlayerCard(
  name: name,
  federation: 'GRE',
  title: '',
  rating: 2000,
  countryCode: 'GRE',
  team: team,
);

GamesTourModel _game({
  required String round,
  required String whiteTeam,
  required String blackTeam,
  required GameStatus status,
  int board = 1,
  double? whiteCustomPoints,
  double? blackCustomPoints,
}) => GamesTourModel(
  gameId: '$round-$whiteTeam-$blackTeam-$board',
  whitePlayer: _card('W $board', whiteTeam).copyWith(customPoints: whiteCustomPoints),
  blackPlayer: _card('B $board', blackTeam).copyWith(customPoints: blackCustomPoints),
  whiteTimeDisplay: '',
  blackTimeDisplay: '',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  gameStatus: status,
  roundId: round,
  tourId: 't',
  boardNr: board,
);

void main() {
  test('completed 2-board win: 2 MP + 1.5 GP vs 0 MP + 0.5 GP', () {
    final games = [
      _game(
        round: 'r1',
        whiteTeam: 'A',
        blackTeam: 'B',
        status: GameStatus.whiteWins,
        board: 1,
      ),
      _game(
        round: 'r1',
        whiteTeam: 'B',
        blackTeam: 'A',
        status: GameStatus.draw,
        board: 2,
      ),
    ];
    final t = buildTeamStandings(games: games, playerStandings: const []);
    final a = t.firstWhere((e) => e.teamName == 'A');
    final b = t.firstWhere((e) => e.teamName == 'B');
    expect(a.matchPoints, 2);
    expect(a.gamePoints, 1.5);
    expect(a.matchesWon, 1);
    expect(b.matchPoints, 0);
    expect(b.gamePoints, 0.5);
    expect(b.matchesLost, 1);
    expect(a.rank, 1);
  });

  test('drawn completed match: 1 MP each', () {
    final games = [
      _game(
        round: 'r1',
        whiteTeam: 'A',
        blackTeam: 'B',
        status: GameStatus.whiteWins,
        board: 1,
      ),
      _game(
        round: 'r1',
        whiteTeam: 'B',
        blackTeam: 'A',
        status: GameStatus.whiteWins,
        board: 2,
      ),
    ];
    final t = buildTeamStandings(games: games, playerStandings: const []);
    expect(t.firstWhere((e) => e.teamName == 'A').matchPoints, 1);
    expect(t.firstWhere((e) => e.teamName == 'B').matchPoints, 1);
    expect(t.every((e) => e.matchesDrawn == 1), isTrue);
  });

  test('ongoing board keeps match provisional: GP counted, MP=0', () {
    final games = [
      _game(
        round: 'r1',
        whiteTeam: 'A',
        blackTeam: 'B',
        status: GameStatus.whiteWins,
        board: 1,
      ),
      _game(
        round: 'r1',
        whiteTeam: 'B',
        blackTeam: 'A',
        status: GameStatus.ongoing,
        board: 2,
      ),
    ];
    final t = buildTeamStandings(games: games, playerStandings: const []);
    final a = t.firstWhere((e) => e.teamName == 'A');
    expect(a.matchPoints, 0);
    expect(a.gamePoints, 1.0);
    expect(a.matchesWon, 0);
  });

  test('ranking: MP first, then GP', () {
    final games = [
      // A beats B 2-0 (2 MP, 2 GP)
      _game(
        round: 'r1',
        whiteTeam: 'A',
        blackTeam: 'B',
        status: GameStatus.whiteWins,
        board: 1,
      ),
      _game(
        round: 'r1',
        whiteTeam: 'B',
        blackTeam: 'A',
        status: GameStatus.blackWins,
        board: 2,
      ),
      // C beats D 1.5-0.5 (2 MP, 1.5 GP)
      _game(
        round: 'r1',
        whiteTeam: 'C',
        blackTeam: 'D',
        status: GameStatus.whiteWins,
        board: 1,
      ),
      _game(
        round: 'r1',
        whiteTeam: 'D',
        blackTeam: 'C',
        status: GameStatus.draw,
        board: 2,
      ),
    ];
    final t = buildTeamStandings(games: games, playerStandings: const []);
    expect(t[0].teamName, 'A'); // 2 MP, 2 GP
    expect(t[1].teamName, 'C'); // 2 MP, 1.5 GP
  });

  test('players attached by team', () {
    const p = PlayerStandingModel(
      countryCode: 'GRE',
      name: 'X',
      score: 2000,
      scoreChange: 0,
      matchScore: '1 / 1',
      team: 'A',
    );
    final games = [
      _game(
        round: 'r1',
        whiteTeam: 'A',
        blackTeam: 'B',
        status: GameStatus.draw,
        board: 1,
      ),
    ];
    final t = buildTeamStandings(games: games, playerStandings: [p]);
    expect(t.firstWhere((e) => e.teamName == 'A').players.length, 1);
  });

  group('buildTeamMatches', () {
    test('per-round matches with opponent + score split + result', () {
      final games = [
        // round-1: A beats B 1.5-0.5
        _game(
          round: 'round-1',
          whiteTeam: 'A',
          blackTeam: 'B',
          status: GameStatus.whiteWins,
          board: 1,
        ),
        _game(
          round: 'round-1',
          whiteTeam: 'B',
          blackTeam: 'A',
          status: GameStatus.draw,
          board: 2,
        ),
        // round-2: A loses to C 0-2
        _game(
          round: 'round-2',
          whiteTeam: 'A',
          blackTeam: 'C',
          status: GameStatus.blackWins,
          board: 1,
        ),
        _game(
          round: 'round-2',
          whiteTeam: 'C',
          blackTeam: 'A',
          status: GameStatus.whiteWins,
          board: 2,
        ),
      ];
      final m = buildTeamMatches(games: games, teamName: 'A');
      expect(m.length, 2);
      // Sorted by round number descending (latest first).
      expect(m[0].opponentTeam, 'C');
      expect(m[0].result, TeamMatchResult.loss);
      expect(m[0].matchPoints, 0);
      expect(m[0].roundLabel, '2.');
      expect(m[1].opponentTeam, 'B');
      expect(m[1].ourPoints, 1.5);
      expect(m[1].opponentPoints, 0.5);
      expect(m[1].result, TeamMatchResult.win);
      expect(m[1].matchPoints, 2);
      expect(m[1].roundLabel, '1.');
      // Each match carries its individual board games.
      expect(m[1].boardGames.length, 2);
      expect(m[1].boardGames.first.result, TeamMatchResult.win);
      expect(m[1].boardGames.first.ourIsWhite, isTrue);
    });

    test('latest round is top-most across three rounds', () {
      final games = [
        for (final round in ['round-1', 'round-3', 'round-2'])
          _game(
            round: round,
            whiteTeam: 'A',
            blackTeam: 'B',
            status: GameStatus.draw,
            board: 1,
          ),
      ];
      final m = buildTeamMatches(games: games, teamName: 'A');
      expect(m.map((e) => e.roundLabel).toList(), ['3.', '2.', '1.']);
      expect(m.first.roundId, 'round-3');
    });

    test('unfinished board leaves the match ongoing', () {
      final games = [
        _game(
          round: 'round-1',
          whiteTeam: 'A',
          blackTeam: 'B',
          status: GameStatus.whiteWins,
          board: 1,
        ),
        _game(
          round: 'round-1',
          whiteTeam: 'B',
          blackTeam: 'A',
          status: GameStatus.ongoing,
          board: 2,
        ),
      ];
      final m = buildTeamMatches(games: games, teamName: 'A');
      expect(m.length, 1);
      expect(m[0].complete, isFalse);
      expect(m[0].result, TeamMatchResult.ongoing);
      expect(m[0].ourPoints, 1.0);
    });
  });

  group('teamMatchesSectionHeading / round info', () {
    test('numeric rounds → null heading (use per-match round labels)', () {
      final games = [
        _game(
          round: 'round-1',
          whiteTeam: 'A',
          blackTeam: 'B',
          status: GameStatus.draw,
        ),
        _game(
          round: 'round-2',
          whiteTeam: 'A',
          blackTeam: 'C',
          status: GameStatus.draw,
        ),
      ];
      final m = buildTeamMatches(games: games, teamName: 'A');
      expect(teamMatchesHaveRoundInfo(m), isTrue);
      expect(teamMatchesSectionHeading(m), isNull);
      expect(teamMatchHasRoundNumber(m.first), isTrue);
      expect(m.first.roundLabel, '2.');
    });

    test('non-numeric knockout stages → MATCHES fallback', () {
      final games = [
        _game(
          round: 'semi-final',
          whiteTeam: 'A',
          blackTeam: 'B',
          status: GameStatus.whiteWins,
        ),
        _game(
          round: 'final',
          whiteTeam: 'A',
          blackTeam: 'C',
          status: GameStatus.draw,
        ),
      ];
      final m = buildTeamMatches(games: games, teamName: 'A');
      expect(teamMatchesHaveRoundInfo(m), isFalse);
      expect(teamMatchesSectionHeading(m), 'MATCHES');
      expect(teamMatchHasRoundNumber(m.first), isFalse);
    });

    test('empty list falls back to MATCHES', () {
      expect(teamMatchesSectionHeading(const <TeamMatch>[]), 'MATCHES');
      expect(teamMatchesHaveRoundInfo(const <TeamMatch>[]), isFalse);
    });
  });

  test('Lichess customPoints are board points; colour-weighted match is 3 MP', () {
    const scoring = TeamScoringRules(
      whiteWin: 3,
      blackWin: 4,
      draw: 1,
      loss: 0,
      matchWin: 3,
      matchDraw: 1,
      matchLoss: 0,
    );
    final games = [
      _game(
        round: 'r1',
        whiteTeam: 'A',
        blackTeam: 'B',
        status: GameStatus.whiteWins,
        board: 1,
        whiteCustomPoints: 3,
        blackCustomPoints: 0,
      ),
      _game(
        round: 'r1',
        whiteTeam: 'A',
        blackTeam: 'B',
        status: GameStatus.blackWins,
        board: 2,
        whiteCustomPoints: 0,
        blackCustomPoints: 4,
      ),
    ];
    final t = buildTeamStandings(
      games: games,
      playerStandings: const [],
      scoring: scoring,
    );
    expect(t.firstWhere((e) => e.teamName == 'A').gamePoints, 3);
    expect(t.firstWhere((e) => e.teamName == 'B').gamePoints, 4);
    expect(t.firstWhere((e) => e.teamName == 'B').matchPoints, 3);
    expect(t.firstWhere((e) => e.teamName == 'A').matchPoints, 0);
  });
}
