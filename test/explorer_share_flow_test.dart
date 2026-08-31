import 'dart:io';

import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/utils/game_share_utils.dart';
import 'package:chessever2/screens/gamebase/utils/explorer_share_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Explorer share exports only the line ending at the visible position',
    () {
      final game = ChessGame.fromPgn(
        'explorer-test',
        '''[Event "Opening Explorer"]
[Site "ChessEver"]
[Result "*"]

1. e4 e5 2. Nf3 Nc6 *''',
      );
      final visibleFen = game.mainline[1].fen;

      final payload = buildExplorerSharePayload(
        game: game,
        movePointer: const [1],
        currentFen: visibleFen,
      );

      expect(payload.snapshot.positionFen, visibleFen);
      expect(payload.snapshot.moveSans, ['e4', 'e5']);
      expect(payload.snapshot.currentMoveIndex, 1);
      expect(payload.pgn, contains('1. e4 e5'));
      expect(payload.pgn, isNot(contains('Nf3')));
      expect(buildGameShareUrl(game: payload.tourGame), isNull);
    },
  );

  test('Explorer share keeps an initial position useful for image and FEN', () {
    final game = ChessGame.fromPgn(
      'explorer-initial',
      '''[Event "Opening Explorer"]
[Site "ChessEver"]
[Result "*"]

*''',
    );

    final payload = buildExplorerSharePayload(
      game: game,
      movePointer: const [],
      currentFen: game.startingFen,
    );

    expect(payload.snapshot.positionFen, game.startingFen);
    expect(payload.snapshot.moveSans, isEmpty);
    expect(payload.snapshot.currentMoveIndex, -1);
    expect(payload.tourGame.source.name, 'openingExplorer');
    expect(buildGameShareUrl(game: payload.tourGame), isNull);
  });

  test('Explorer Share opens the polished card without a cloud link', () {
    final source =
        File(
          'lib/screens/gamebase/gamebase_explorer_screen.dart',
        ).readAsStringSync();
    final start = source.indexOf('Future<void> _shareExplorerBoard()');
    final end = source.indexOf('  Future<void> _openBoardEditor()', start);

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final shareFlow = source.substring(start, end);
    expect(shareFlow, contains('buildExplorerSharePayload('));
    expect(shareFlow, contains('await pushGameShareScreen('));
    expect(shareFlow, contains('shareUrl: null'));
    expect(shareFlow, isNot(contains('Share.share(')));
  });
}
