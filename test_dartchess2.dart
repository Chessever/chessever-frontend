import 'package:dartchess/dartchess.dart';

void main() {
  final pgn = '1. d4 { [%clk 0:03:00] } 1... c5 { [%clk 0:03:00] } 2. e4 { [%clk 0:02:58] } 2... cxd4 { [%clk 0:02:59] } 3. c3 { [%clk 0:02:58] }';
  final game = PgnGame.parsePgn(pgn);
  for (final node in game.moves.mainline()) {
    print('Move: ' + node.san + ', Comments: ' + node.comments.toString());
  }
}
