import 'dart:convert';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';
import 'notation_tree.dart';

class NotationCacheEntry {
  final String signature;
  final List<NotationNode> nodes;
  const NotationCacheEntry(this.signature, this.nodes);
}

class NotationCache {
  NotationCacheEntry? _last;

  String _signature(ChessGameNavigatorState state) {
    final buf = StringBuffer();
    void walk(ChessLine line) {
      for (final m in line) {
        buf.write('${m.uci};');
        final vars = m.variations ?? const <ChessLine>[];
        buf.write('v${vars.length}|');
        for (final v in vars) {
          walk(v);
          buf.write('|');
        }
      }
    }

    walk(state.game.mainline);
    return base64Url.encode(utf8.encode(buf.toString()));
  }

  List<NotationNode> build(ChessGameNavigatorState state) {
    final sig = _signature(state);
    if (_last != null && _last!.signature == sig) return _last!.nodes;
    final nodes = NotationTreeBuilder.build(state);
    _last = NotationCacheEntry(sig, nodes);
    return nodes;
  }
}

