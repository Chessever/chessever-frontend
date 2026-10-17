import 'package:chessever2/utils/pgn_multi_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// An imported game's id is its identity for its board, its saved copies and
/// its likes: two imports must not hand different games the same one.
void main() {
  const first = '[Event "A"]\n[Result "1-0"]\n\n1. e4 e5 2. Qh5 Nc6 1-0';
  const second = '[Event "B"]\n[Result "0-1"]\n\n1. f3 e5 2. g4 Qh4# 0-1';

  test(
    'different games in the same place of two imports get different ids',
    () {
      final a = parsePgnsToChessGames(first).single.chessGame.gameId;
      final b = parsePgnsToChessGames(second).single.chessGame.gameId;
      expect(a, isNot(b));
      expect(a, startsWith('imported_'));
    },
  );

  test('the same game in the same place keeps its id, run after run', () {
    expect(importedGameId(first, 0), importedGameId(first, 0));
    expect(importedGameId(first, 0), importedGameId('  $first\n', 0));
    // Two copies of one game in one file are still two places.
    expect(importedGameId(first, 0), isNot(importedGameId(first, 1)));
  });

  test('every game of a multi-game file has its own id', () {
    final games = parsePgnsToChessGames('$first\n\n$second');
    expect(games, hasLength(2));
    expect(games[0].chessGame.gameId, isNot(games[1].chessGame.gameId));
  });
}
