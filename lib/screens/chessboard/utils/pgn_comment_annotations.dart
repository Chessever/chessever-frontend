import 'package:chessever2/screens/chessboard/notation/notation_token_builder.dart'
    show cleanPgnCommentText;
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/painting.dart';

/// The colour a graphical annotation's code draws in (`G`reen, `R`ed,
/// `Y`ellow, `B`lue, `O`range): the analysis board's own palette, shared so
/// every board that draws a PGN's arrows draws them alike.
Color pgnShapeColor(String code) => switch (code.toUpperCase()) {
  'G' => const Color(0xFF15781B).withValues(alpha: 0.8),
  'Y' => const Color(0xFFE58F00).withValues(alpha: 0.8),
  'B' => const Color(0xFF003088).withValues(alpha: 0.8),
  'R' => const Color(0xFF882020).withValues(alpha: 0.8),
  'O' => const Color(0xFFE68F00).withValues(alpha: 0.8),
  _ => const Color(0xFF15781B).withValues(alpha: 0.8),
};

final RegExp _arrowsCommand = RegExp(r'\[%cal\s+([^\]]+)\]');
final RegExp _squaresCommand = RegExp(r'\[%csl\s+([^\]]+)\]');

/// The arrows (`[%cal Ge2e4,...]`) and marked squares (`[%csl Rd4,...]`) a
/// move's [comments] carry, as the analysis board draws them.
List<Shape> pgnCommentShapes(Iterable<String> comments) {
  final shapes = <Shape>[];
  for (final comment in comments) {
    for (final match in _arrowsCommand.allMatches(comment)) {
      for (final item in match.group(1)!.split(',')) {
        final code = item.trim();
        // e.g. Gg8g7
        if (code.length != 5) continue;
        final orig = _square(code.substring(1, 3));
        final dest = _square(code.substring(3, 5));
        // An arrow from a square to itself has no direction: chessground
        // asserts on it in debug and draws a broken stub in release.
        if (orig == null || dest == null || orig == dest) continue;
        shapes.add(
          Arrow(color: pgnShapeColor(code[0]), orig: orig, dest: dest),
        );
      }
    }
    for (final match in _squaresCommand.allMatches(comment)) {
      for (final item in match.group(1)!.split(',')) {
        final code = item.trim();
        // e.g. Re2
        if (code.length != 3) continue;
        final square = _square(code.substring(1, 3));
        if (square == null) continue;
        shapes.add(Circle(color: pgnShapeColor(code[0]), orig: square));
      }
    }
  }
  return shapes;
}

/// [name] as a square (`e4`), or null when it names none.
Square? _square(String name) {
  try {
    return Square.fromName(name);
  } catch (_) {
    return null;
  }
}

/// Any command a PGN tool writes into a comment (`[%clk]`, `[%eval]`,
/// `[%emt]`, `[%cal]`, `[%csl]`, a tool's own): machine data, never prose.
/// Its arguments may hold brackets of their own (`[%evp 1,2,[3]]`).
final RegExp _anyCommand = RegExp(r'\[%(?:[^\[\]]|\[[^\[\]]*\])*\]');

/// A command left open to the comment's end (`Good. [%cal Ge2e4`): the rest
/// is its arguments, never words.
final RegExp _openCommand = RegExp(r'\[%.*$', dotAll: true);
final RegExp _space = RegExp(r'\s+');

/// ChessBase's diagram marker (`{[#]}`): a layout cue for printed books,
/// never words or an annotation.
final RegExp _diagram = RegExp(r'\[#\]');

/// The words a person wrote in a move's [comments], commands stripped and
/// whitespace folded to single spaces; null when nothing human is left.
String? pgnCommentProse(Iterable<String> comments) {
  final parts = <String>[
    for (final comment in comments)
      cleanPgnCommentText(comment)
          .replaceAll(_diagram, ' ')
          .replaceAll(_anyCommand, ' ')
          .replaceAll(_openCommand, ' ')
          .replaceAll(_space, ' ')
          .trim(),
  ]..removeWhere((part) => part.isEmpty);
  return parts.isEmpty ? null : parts.join(' ');
}
