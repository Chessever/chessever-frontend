import 'package:chessever2/screens/feed/logic/feed_moments.dart';
import 'package:chessever2/screens/feed/logic/feed_pgn.dart';
import 'package:chessever2/utils/pgn_clock_utils.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Feed replay shows each player the clock they had at the ply on the
/// board, read off the PGN the way the board screen reads it.
void main() {
  const pgn =
      '1. e4 {[%eval 0.2] [%clk 1:29:55]} e5 {[%clk 1:29:40]} '
      '2. Bc4 {[%clk 1:20:00]} Nc6 3. Qh5 {[%clk 0:59:30]} '
      'Nf6 {[%clk 0:04:07]} 4. Qxf7# {[%clk 0:59:01]} 1-0';

  List<String> clocks() {
    final plies = buildFlowPlies(parseFlowPgn(pgn)!);
    return [for (var i = 1; i < plies.length; i++) plies[i].clock ?? '-:--:--'];
  }

  String? at(int ply, {required bool white}) =>
      clockDisplayAtMove(clocks(), moveIndex: ply - 1, isWhitePlayer: white);

  test('plies carry the PGN clocks in the board screen format', () {
    expect(clocks(), [
      '1:29:55',
      '1:29:40',
      '1:20:00',
      '-:--:--',
      '59:30',
      '04:07',
      '59:01',
    ]);
  });

  test('each side shows the clock it last stopped on', () {
    expect(at(1, white: true), '1:29:55');
    expect(at(2, white: true), '1:29:55');
    expect(at(2, white: false), '1:29:40');
    expect(at(3, white: true), '1:20:00');
    expect(at(7, white: true), '59:01');
    expect(at(7, white: false), '04:07');
  });

  test('a move without a clock keeps the side on its previous sample', () {
    expect(at(4, white: false), '1:29:40');
    expect(at(5, white: false), '1:29:40');
  });

  test('before a side has moved it shows its first sample', () {
    expect(at(0, white: true), '1:29:55');
    expect(at(0, white: false), '1:29:40');
    expect(at(1, white: false), '1:29:40');
  });

  test('a PGN without clocks yields none', () {
    final plies = buildFlowPlies(parseFlowPgn('1. e4 e5 2. Nf3 1-0')!);
    expect(plies.every((ply) => ply.clock == null), isTrue);
    expect(
      clockDisplayAtMove(
        const ['-:--:--', '-:--:--'],
        moveIndex: 1,
        isWhitePlayer: true,
      ),
      isNull,
    );
  });
}
