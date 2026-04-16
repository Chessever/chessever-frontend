import 'package:dartchess/dartchess.dart';

void main() {
  final pgn = '1. e4 { [%clk 1:00:00] } e5 { [%clk 0:59:58] } 2. Nf3';
  final game = PgnGame.parsePgn(pgn);
  for (final node in game.moves.mainline()) {
    print('Move: ' + node.san + ', Comments: ' + node.comments.toString());
  }
}
