import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/widgets.dart';

import 'responsive_helper.dart';

/// Map piece letters to PieceKind for figurine notation.
/// Uses white pieces for clean, elegant appearance on dark backgrounds.
const pieceLetterToKind = {
  'K': PieceKind.whiteKing,
  'Q': PieceKind.whiteQueen,
  'R': PieceKind.whiteRook,
  'B': PieceKind.whiteBishop,
  'N': PieceKind.whiteKnight,
};

/// Build rich text spans with inline piece images for figurine notation.
/// Creates an elegant display where piece letters are replaced with actual
/// piece images from the user's selected piece set.
List<InlineSpan> buildFigurineSpans({
  required String text,
  required PieceAssets pieceAssets,
  required TextStyle style,
  required double pieceSize,
}) {
  final spans = <InlineSpan>[];
  final buffer = StringBuffer();
  var i = 0;

  void flushBuffer() {
    if (buffer.isNotEmpty) {
      spans.add(TextSpan(text: buffer.toString(), style: style));
      buffer.clear();
    }
  }

  while (i < text.length) {
    final char = text[i];

    // Track if we're past move number (e.g., "1. " or "12... ")
    if (char.contains(RegExp(r'[0-9.]'))) {
      buffer.write(char);
      i++;
      continue;
    }

    if (char == ' ') {
      buffer.write(char);
      i++;
      continue;
    }

    // Check if this is a piece letter that should be converted
    final pieceKind = pieceLetterToKind[char];
    if (pieceKind != null) {
      flushBuffer();
      final pieceImage = pieceAssets[pieceKind];
      if (pieceImage != null) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: EdgeInsets.only(right: 1.sp),
              child: Image(
                image: pieceImage,
                width: pieceSize,
                height: pieceSize,
                filterQuality: FilterQuality.high,
              ),
            ),
          ),
        );
      } else {
        buffer.write(char);
      }
    } else {
      buffer.write(char);
    }
    i++;
  }

  flushBuffer();
  return spans;
}
