import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/library/pgn_import_preview_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PGN search opens the visible list and visible index', () {
    final allGames = [
      _game('one', white: 'Magnus Carlsen', black: 'Ian Nepomniachtchi'),
      _game('two', white: 'Fabiano Caruana', black: 'Hikaru Nakamura'),
      _game('three', white: 'Hikaru Nakamura', black: 'Wesley So'),
    ];

    final visible = filterPgnImportGames(allGames, 'hikaru');
    final navigation = buildPgnImportBoardNavigation(
      visibleGames: visible,
      selectedIndex: 1,
    );

    expect(visible.map((game) => game.gameId), ['two', 'three']);
    expect(navigation.games.map((game) => game.gameId), ['two', 'three']);
    expect(navigation.selectedIndex, 1);
    expect(navigation.games[navigation.selectedIndex].gameId, 'three');
  });
}

ChessGame _game(String id, {required String white, required String black}) {
  return ChessGame.fromPgn(id, '''
[Event "Imported collection"]
[White "$white"]
[Black "$black"]
[Result "1-0"]

1. e4 e5 1-0
''');
}
