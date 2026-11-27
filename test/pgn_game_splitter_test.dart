import 'package:chessever2/screens/library/pgn_import_preview_screen.dart'
    show pgnImportEventName;
import 'package:chessever2/utils/pgn_multi_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// A PGN database is its games, whatever tag each one opens with. Splitting
/// at `[Event` alone read a file whose games open with `[Date` as one game:
/// opened from a chat app it went straight to a board with its first game,
/// and Import PGN listed "1 game".
void main() {
  // The shape of the file that showed it: a byte order mark, CRLF line
  // ends, set-up positions, and no Event tag anywhere.
  final eventless = [
    '\uFEFF[Date "1954.??.??"]',
    '[Round "?"]',
    '[White "Botvinnik"]',
    '[Black "Smyslov"]',
    '[Result "*"]',
    '[SetUp "1"]',
    '[FEN "r4rk1/pp1n1pp1/2p2np1/2q5/P1B1P3/2N2P2/1P2Q1PP/R4R1K b - - 0 1"]',
    '[PlyCount "4"]',
    '[EventDate "1954.??.??"]',
    '',
    '1... g5 2. g3 Rad8 3. Ba2 *',
    '',
    '[Date "1972.??.??"]',
    '[Round "?"]',
    '[White "Fischer"]',
    '[Black "Spassky"]',
    '[Result "*"]',
    '[SetUp "1"]',
    '[FEN "2r3k1/r2nqpp1/p3b2p/2pp4/8/Q3PN2/PP2BPPP/2R2RK1 w - - 0 1"]',
    '[PlyCount "3"]',
    '[EventDate "1972.??.??"]',
    '',
    '1. Nd4 Qf8 2. Nxe6 *',
    '',
    '[Date "1960.??.??"]',
    '[Round "?"]',
    '[White "Uhlmann"]',
    '[Black "Kotnauer"]',
    '[Result "*"]',
    '[SetUp "1"]',
    '[FEN "r1r2q1k/6p1/5n1p/p1p5/2Bp1P2/1P4Q1/P5PP/4RRK1 w - - 0 1"]',
    '[PlyCount "2"]',
    '',
    '1. Re5 a4 *',
    '',
  ].join('\r\n');

  test('a database whose games never name an Event is still a database', () {
    final games = parsePgnsToChessGames(eventless);

    expect(
      [for (final entry in games) entry.chessGame.metadata['White']],
      ['Botvinnik', 'Fischer', 'Uhlmann'],
    );
    expect(
      [for (final entry in games) entry.chessGame.metadata['Black']],
      ['Smyslov', 'Spassky', 'Kotnauer'],
    );
    expect(
      [for (final entry in games) entry.chessGame.mainline.length],
      [4, 3, 2],
    );
    // Each game keeps its own headers and nothing of its neighbours'.
    expect(games.first.rawPgn, startsWith('[Date "1954.??.??"]'));
    expect(games.first.rawPgn, endsWith('3. Ba2 *'));
    expect(games.last.rawPgn, isNot(contains('Fischer')));
    expect({for (final entry in games) entry.chessGame.gameId}, hasLength(3));
  });

  test('a game with no Event is not called "?" on its import card', () {
    final game = parsePgnsToChessGames(eventless).first.chessGame;

    expect(pgnImportEventName(game.metadata), 'Imported');
    expect(pgnImportEventName({'Event': '?', 'Site': 'Moscow'}), 'Moscow');
    expect(pgnImportEventName({'Event': 'Zurich 1953'}), 'Zurich 1953');
  });

  test('games that open with Event split into the text they always did', () {
    const first = '[Event "A"]\n[Result "1-0"]\n\n1. e4 e5 2. Qh5 Nc6 1-0';
    const second = '[Event "B"]\n[Result "0-1"]\n\n1. f3 e5 2. g4 Qh4# 0-1';

    // An imported game's id is a hash of this text: it must not move.
    expect(splitPgnGames('$first\r\n\r\n$second\r\n'), [first, second]);
    expect(splitPgnGames(first), [first]);
    expect(splitPgnGames('  \n'), isEmpty);
  });

  test('tags written above Event stay with their own game', () {
    final games = splitPgnGames(
      '[Site "Riga"]\n[Event "One"]\n\n1. e4 *\n\n'
      '[Site "Kyiv"]\n[Event "Two"]\n\n1. d4 *\n',
    );

    expect(games, [
      '[Site "Riga"]\n[Event "One"]\n\n1. e4 *',
      '[Site "Kyiv"]\n[Event "Two"]\n\n1. d4 *',
    ]);
  });

  test('a tag written inside a comment starts no game', () {
    final games = splitPgnGames(
      '[White "A"]\n[Black "B"]\n\n'
      '1. e4 { a note that runs\n[White "Ghost"] over lines } e5\n'
      '2. Nf3 ; [Black "Ghost"]\n'
      '% [Event "escaped"]\n'
      '2... Nc6 *\n\n'
      '[White "C"]\n[Black "D"]\n\n1. d4 *\n',
    );

    expect(games, hasLength(2));
    expect(games.first, contains('[White "Ghost"] over lines'));
    expect(games.last, startsWith('[White "C"]'));
  });

  test('a game with no movetext at all does not swallow the next one', () {
    final games = parsePgnsToChessGames(
      '[Event "Forfeit"]\n[White "A"]\n[Black "B"]\n\n'
      '[Event "Played"]\n[White "C"]\n[Black "D"]\n\n1. e4 e5 *\n',
    );

    expect(games, hasLength(1));
    expect(games.single.chessGame.metadata['Event'], 'Played');
    expect(games.single.chessGame.metadata['White'], 'C');
    expect(games.single.rawPgn, isNot(contains('Forfeit')));
  });

  test('a comment that is never closed ends where the next game starts', () {
    final games = splitPgnGames(
      '[White "A"]\n\n1. e4 { the brace is never closed\n\n'
      '[White "B"]\n\n1. d4 d5 *\n\n'
      '[White "C"]\n\n1. c4 *\n',
    );

    expect(games, hasLength(3));
    expect(games[1], '[White "B"]\n\n1. d4 d5 *');
  });
}
