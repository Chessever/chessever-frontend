import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

/// A broadcast game as the board parses it: live-flagged PGN movetext.
ChessGame live(String moves) => ChessGame.fromPgn(
  'live',
  '[Event "Live"]\n[Result "*"]\n\n$moves *',
).copyWith(metadata: const {ChessGame.metadataIsLiveKey: true});

List<String> sans(ChessLine line) => [for (final move in line) move.san];

ChessMove liveMove(String fromFen, String uci) {
  final position = Chess.fromSetup(Setup.parseFen(fromFen));
  final (next, san) = position.makeSan(Move.parse(uci)!);
  return ChessMove(
    num: position.fullmoves,
    fen: next.fen,
    san: san,
    uci: uci,
    turn: position.turn == Side.white ? ChessColor.white : ChessColor.black,
  );
}

ChessGameNavigator boardOn(ChessGame game) => ChessGameNavigator(game)
  ..noteBroadcastMainline(game.mainline)
  ..goToTail();

void main() {
  group('broadcast corrects a move it already published', () {
    test('replaces the move and keeps the follower on the tail', () {
      final navigator = boardOn(live('1. e4 e5 2. Nf3'));

      navigator.updateWithLatestGame(live('1. e4 e5 2. Nc3'));

      expect(sans(navigator.state.game.mainline), ['e4', 'e5', 'Nc3']);
      // The retracted move is not the reader's analysis: no variation.
      expect(navigator.state.game.mainline[1].variations, isNull);
      expect(navigator.state.movePointer, [2]);
      expect(
        navigator.state.currentFen,
        live('1. e4 e5 2. Nc3').mainline.last.fen,
      );
    });

    test('an earlier rewrite keeps the reader on the same ply', () {
      final navigator = boardOn(live('1. e4 e5 2. Nf3 Nc6'))
        ..goToMovePointerUnchecked([1]);

      navigator.updateWithLatestGame(live('1. e4 c5 2. Nf3 d6'));

      expect(sans(navigator.state.game.mainline), ['e4', 'c5', 'Nf3', 'd6']);
      expect(navigator.state.movePointer, [1]);
      expect(
        navigator.state.currentFen,
        isNot(navigator.state.game.startingFen),
      );
    });

    test('the next live move still follows after the correction', () {
      final navigator = boardOn(live('1. e4 e5 2. Nf3'));

      navigator.updateWithLatestGame(live('1. e4 e5 2. Nc3'));
      navigator.updateWithLatestGame(
        live('1. e4 e5 2. Nc3 Nf6'),
        goToTail: true,
      );

      expect(navigator.state.movePointer, [3]);
      expect(navigator.state.currentMove?.san, 'Nf6');
    });

    test('a branch the reader hung off the retracted move is kept', () {
      final navigator = boardOn(live('1. e4 e5 2. Nf3'))
        ..goToMovePointerUnchecked([2])
        ..makeOrGoToMove('b8c6');

      navigator.updateWithLatestGame(live('1. e4 e5 2. Nc3'));

      final e5 = navigator.state.game.mainline[1];
      expect(sans(navigator.state.game.mainline), ['e4', 'e5', 'Nc3']);
      expect(e5.variations?.map(sans), [
        ['Nf3'],
      ]);
      expect(sans(e5.variations!.single.single.variations!.single), ['Nc6']);
      // The reader stays on their own move, now inside the kept branch.
      expect(navigator.state.currentMove?.san, 'Nc6');
    });
  });

  group('the reader changed the mainline of a live game', () {
    test('a promoted line survives the next live move', () {
      final navigator = boardOn(live('1. e4 e5'))
        ..goToMovePointerUnchecked([0])
        ..makeOrGoToMove('c7c5');
      navigator.promoteVariationToMainline(
        List.of(navigator.state.movePointer),
      );
      expect(sans(navigator.state.game.mainline), ['e4', 'c5']);

      navigator.updateWithLatestGame(live('1. e4 e5 2. Nf3'), goToTail: true);

      final mainline = navigator.state.game.mainline;
      expect(sans(mainline), ['e4', 'e5', 'Nf3']);
      // The game's move is re-lifted from the demoted branch, so it is not
      // also left behind as a duplicate variation.
      expect(mainline.first.variations?.map(sans), [
        ['c5'],
      ]);
      expect(navigator.state.currentMove?.san, 'c5');
      expect(
        navigator.state.currentFen,
        isNot(navigator.state.game.startingFen),
      );
    });

    test('with no broadcast noted, a diverging line is never dropped', () {
      final navigator = ChessGameNavigator(live('1. e4 e5 2. Nf3'))..goToTail();

      navigator.updateWithLatestGame(live('1. e4 e5 2. Nc3'));

      expect(sans(navigator.state.game.mainline), ['e4', 'e5', 'Nc3']);
      expect(navigator.state.game.mainline[1].variations?.map(sans), [
        ['Nf3'],
      ]);
      expect(navigator.state.currentMove?.san, 'Nf3');
    });
  });

  group('appendLiveMove', () {
    test('extends the broadcast mainline, not a promoted reader line', () {
      final broadcast = live('1. e4 e5');
      final navigator = boardOn(broadcast)
        ..goToMovePointerUnchecked([0])
        ..makeOrGoToMove('c7c5');
      navigator.promoteVariationToMainline(
        List.of(navigator.state.movePointer),
      );

      final appended = navigator.appendLiveMove(
        liveMove(broadcast.mainline.last.fen, 'g1f3'),
        fromFen: broadcast.mainline.last.fen,
      );

      expect(appended, isTrue);
      expect(sans(navigator.state.game.mainline), ['e4', 'e5', 'Nf3']);
      expect(navigator.state.game.mainline.first.variations?.map(sans), [
        ['c5'],
      ]);
    });

    test('refuses a move that does not follow the broadcast position', () {
      final broadcast = live('1. e4 e5');
      final navigator = boardOn(broadcast);

      final appended = navigator.appendLiveMove(
        liveMove(broadcast.mainline.first.fen, 'g8f6'),
        fromFen: broadcast.mainline.first.fen,
      );

      expect(appended, isFalse);
      expect(sans(navigator.state.game.mainline), ['e4', 'e5']);
    });
  });
}
