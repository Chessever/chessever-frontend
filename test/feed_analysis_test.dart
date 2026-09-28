import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:chessever2/screens/feed/logic/feed_analysis.dart';
import 'package:chessever2/screens/feed/logic/feed_exploration.dart';
import 'package:chessever2/screens/feed/logic/feed_moments.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pgn =
      '[Result "1-0"]\n\n'
      '1. e4 {A comment} e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0';

  for (final ply in [0, 1, 4, 7]) {
    test('Analyze snapshots displayed ply $ply with the whole game', () {
      final item = _item(pgn);
      final snapshot = feedAnalysisSnapshot(item: item, shownPly: ply);
      final restored = ChessGameNavigatorState(
        game: snapshot.chessGame,
        movePointer: snapshot.movePointer!,
      );
      expect(restored.currentFen, item.plies[ply].fen);
      expect(snapshot.movePointer, ply == 0 ? isEmpty : [ply - 1]);
      expect(snapshot.chessGame.mainline, hasLength(7));
      expect(snapshot.chessGame.mainline.first.comments, contains('A comment'));
      expect(snapshot.analysisId, isNull);
      expect(snapshot.sourceGameId, item.game.likeId);
    });
  }

  test('repeated position keeps the exact occurrence', () {
    final item = _item('1. Nf3 Nf6 2. Ng1 Ng8 3. Nf3 Nf6 *');
    final snapshot = feedAnalysisSnapshot(item: item, shownPly: 5);
    expect(snapshot.movePointer, [4]);
    expect(
      ChessGameNavigatorState(
        game: snapshot.chessGame,
        movePointer: snapshot.movePointer!,
      ).currentFen,
      item.plies[5].fen,
    );
  });

  for (final fork in [0, 2]) {
    for (final cursor in [-1, 0, 1]) {
      test('explored line from ply $fork opens at cursor $cursor', () {
        final item = _item(pgn);
        var line = FeedExploration(
          forkPly: fork,
          start: Chess.fromSetup(Setup.parseFen(item.plies[fork].fen)),
        );
        line = line.play(Move.parse('g1f3')!)!.$1;
        line = line.play(Move.parse('g8f6')!)!.$1;
        line = line.jumpTo(cursor);
        final snapshot = feedAnalysisSnapshot(
          item: item,
          shownPly: fork,
          exploration: line,
        );
        final restored = ChessGameNavigatorState(
          game: snapshot.chessGame,
          movePointer: snapshot.movePointer!,
        );
        expect(restored.currentFen, line.position.fen);
        expect(snapshot.chessGame.mainline, hasLength(7));
        expect(snapshot.chessGame.mainline.last.san, 'Qxf7#');
        expect(
          snapshot.chessGame.mainline[fork == 0 ? 0 : fork - 1].variations,
          isNotEmpty,
        );
      });
    }
  }

  test('materialized positions suffice when inline PGN is absent', () {
    final item = _item(pgn, inlinePgn: false);
    final snapshot = feedAnalysisSnapshot(item: item, shownPly: 4);
    expect(snapshot.chessGame.mainline, hasLength(7));
    expect(
      ChessGameNavigatorState(
        game: snapshot.chessGame,
        movePointer: snapshot.movePointer!,
      ).currentFen,
      item.plies[4].fen,
    );
  });
}

FeedItem _item(String pgn, {bool inlinePgn = true}) {
  final parsed = feedClipFromPgn(pgn)!;
  final player = PlayerCard(
    name: 'Player',
    federation: '',
    title: '',
    rating: 0,
    countryCode: '',
    team: null,
  );
  return FeedItem(
    game: GamesTourModel(
      gameId: 'feed-analysis-game',
      whitePlayer: player,
      blackPlayer: player,
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.whiteWins,
      pgn: inlinePgn ? pgn : null,
      tourId: '',
      roundId: '',
    ),
    plies: parsed.plies,
    reason: 'Test game',
    result: parsed.result,
  );
}
