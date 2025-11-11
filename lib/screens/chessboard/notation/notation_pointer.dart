import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game_navigator.dart';

class NotationPointer {
  static const _separator = '-';
  static const _rootId = 'root';

  static String encode(ChessMovePointer pointer) {
    if (pointer.isEmpty) {
      return _rootId;
    }
    return pointer.join(_separator);
  }

  static ChessMovePointer decode(String id) {
    if (id.isEmpty || id == _rootId) {
      return const [];
    }
    return id.split(_separator).map(int.parse).toList();
  }

  static String variationId(
    ChessMovePointer parentPointer,
    int variationIndex,
  ) {
    return encode([...parentPointer, variationIndex]);
  }

  static ChessMovePointer parent(ChessMovePointer pointer) {
    if (pointer.isEmpty) {
      return const [];
    }
    return pointer.sublist(0, pointer.length - 1);
  }

  static ChessMovePointer clone(ChessMovePointer pointer) {
    return List<Number>.of(pointer);
  }
}
