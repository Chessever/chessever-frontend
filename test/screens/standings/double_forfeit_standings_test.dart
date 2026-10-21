import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/standings/team_standings_builder.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/utils/broadcast_custom_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

GamesTourModel board({bool forfeit = true, int number = 1}) => GamesTourModel(
  gameId: 'board-$number',
  whitePlayer: PlayerCard(
    name: 'White',
    federation: '',
    title: '',
    rating: 2000,
    countryCode: '',
    team: 'A',
  ),
  blackPlayer: PlayerCard(
    name: 'Black',
    federation: '',
    title: '',
    rating: 2000,
    countryCode: '',
    team: 'B',
  ),
  whiteTimeDisplay: '',
  blackTimeDisplay: '',
  whiteClockCentiseconds: 0,
  blackClockCentiseconds: 0,
  gameStatus: forfeit ? GameStatus.unknown : GameStatus.whiteWins,
  isDoubleForfeit: forfeit,
  roundId: 'round-1',
  tourId: 'tour',
  boardNr: number,
);

void main() {
  test(
    'source 0-0 survives conversion and a later played result replaces it',
    () {
      final source = Games.fromJson({
        'id': 'double-forfeit',
        'round_id': 'round-1',
        'round_slug': 'round-1',
        'tour_id': 'tour',
        'tour_slug': 'tour',
        'status': '0-0',
        'players': [
          {'name': 'White', 'team': 'A'},
          {'name': 'Black', 'team': 'B'},
        ],
      });
      final model = GamesTourModel.fromGame(source);
      expect(model.isDoubleForfeit, isTrue);
      expect(
        model.copyWith(gameStatus: GameStatus.whiteWins).isDoubleForfeit,
        isFalse,
      );
    },
  );

  test('double forfeit completes a match and credits neither team a draw', () {
    final game = board();
    final rows = buildTeamStandings(games: [game], playerStandings: const []);
    for (final row in rows) {
      expect(row.gamePoints, 0);
      expect(row.matchPoints, 0);
      expect(row.matchesLost, 1);
      expect(row.matchesDrawn, 0);
      expect(row.boardsPlayed, 0);
    }
    for (final team in ['A', 'B']) {
      final match = buildTeamMatches(games: [game], teamName: team).single;
      expect(match.complete, isTrue);
      expect(match.result, TeamMatchResult.loss);
      expect(match.boardGames.single.result, TeamMatchResult.loss);
      expect(match.matchPoints, 0);
    }
    expect(boardResultLabelForSide(game, isWhite: true), '0');
    expect(boardResultLabelForSide(game, isWhite: false), '0');
    expect(game.copyWith().isDoubleForfeit, isTrue);
  });

  test(
    'a forfeited board does not prevent other boards deciding the match',
    () {
      final games = [board(), board(forfeit: false, number: 2)];
      final rows = buildTeamStandings(games: games, playerStandings: const []);
      final a = rows.firstWhere((row) => row.teamName == 'A');
      final b = rows.firstWhere((row) => row.teamName == 'B');
      expect(a.gamePoints, 1);
      expect(a.matchPoints, 2);
      expect(b.gamePoints, 0);
      expect(b.matchPoints, 0);
      expect(
        buildTeamMatches(games: games, teamName: 'A').single.complete,
        isTrue,
      );
    },
  );
}
