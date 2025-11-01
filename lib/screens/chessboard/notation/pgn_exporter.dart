import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';

/// Utility to export ChessGame to PGN format with variations
class PgnExporter {
  /// Convert a ChessGame to PGN string with variations
  static String toPgn(ChessGame game, {bool includeHeaders = true}) {
    final buffer = StringBuffer();

    // Add headers if requested
    if (includeHeaders) {
      game.metadata.forEach((key, value) {
        buffer.writeln('[$key "$value"]');
      });
      if (game.metadata.isNotEmpty) {
        buffer.writeln();
      }
    }

    // Add moves with variations
    _writeMoveLine(game.mainline, buffer, startingMoveNumber: 1);

    return buffer.toString().trim();
  }

  /// Recursively write a line of moves with variations
  static void _writeMoveLine(
    ChessLine line,
    StringBuffer buffer, {
    required int startingMoveNumber,
    bool isVariation = false,
  }) {
    for (int i = 0; i < line.length; i++) {
      final move = line[i];

      // Add move number for white moves (or first black move in variation)
      if (move.turn == ChessColor.white) {
        buffer.write('${move.num}. ');
      } else if (i == 0 && isVariation) {
        // For variations starting with black, show move number with ellipsis
        buffer.write('${move.num}... ');
      }

      // Write the move
      buffer.write(move.san);

      // Add clock time if available
      if (move.clockTime != null) {
        buffer.write(' {[%clk ${move.clockTime}]}');
      }

      buffer.write(' ');

      // Write variations if they exist
      if (move.variations != null && move.variations!.isNotEmpty) {
        for (final variation in move.variations!) {
          if (variation.isNotEmpty) {
            buffer.write('(');
            _writeMoveLine(
              variation,
              buffer,
              startingMoveNumber: move.num,
              isVariation: true,
            );
            buffer.write(') ');
          }
        }
      }
    }
  }

  /// Convert ChessGame to PGN and include only moves up to a specific pointer
  static String toPgnUpToPointer(
    ChessGame game,
    List<int> pointer, {
    bool includeHeaders = true,
  }) {
    // If pointer is empty, return full game
    if (pointer.isEmpty) {
      return toPgn(game, includeHeaders: includeHeaders);
    }

    final buffer = StringBuffer();

    // Add headers if requested
    if (includeHeaders) {
      game.metadata.forEach((key, value) {
        buffer.writeln('[$key "$value"]');
      });
      if (game.metadata.isNotEmpty) {
        buffer.writeln();
      }
    }

    // Build line up to pointer
    _writeLineUpToPointer(game.mainline, pointer, buffer, 0);

    return buffer.toString().trim();
  }

  /// Write moves up to a specific pointer position
  static void _writeLineUpToPointer(
    ChessLine line,
    List<int> pointer,
    StringBuffer buffer,
    int pointerIndex,
  ) {
    if (pointerIndex >= pointer.length) return;

    final targetMoveIndex = pointer[pointerIndex];

    for (int i = 0; i <= targetMoveIndex && i < line.length; i++) {
      final move = line[i];

      // Add move number for white moves
      if (move.turn == ChessColor.white) {
        buffer.write('${move.num}. ');
      }

      // Write the move
      buffer.write(move.san);

      // Add clock time if available
      if (move.clockTime != null) {
        buffer.write(' {[%clk ${move.clockTime}]}');
      }

      buffer.write(' ');

      // If this is the target move and we have more pointer indices, dive into variation
      if (i == targetMoveIndex && pointerIndex + 1 < pointer.length) {
        final varIndex = pointer[pointerIndex + 1];
        if (move.variations != null && varIndex < move.variations!.length) {
          final variation = move.variations![varIndex];
          buffer.write('(');
          _writeLineUpToPointer(
            variation,
            pointer,
            buffer,
            pointerIndex + 2,
          );
          buffer.write(') ');
        }
      }
    }
  }

  /// Get a compact notation string (just moves, no move numbers or variations)
  static String toCompactNotation(ChessLine line) {
    return line.map((move) => move.san).join(' ');
  }

  /// Get a line of moves as a list of SAN strings
  static List<String> lineToSanList(ChessLine line) {
    return line.map((move) => move.san).toList();
  }
}
