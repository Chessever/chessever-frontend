import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/widgets.dart';

/// Base widget for the background of the chessboard.
///
/// See [SolidColorChessboardBackground] and [ImageChessboardBackground] for concrete implementations.
abstract class ChessboardBackground extends StatelessWidget {
  const ChessboardBackground({
    super.key,
    this.coordinates = false,
    this.orientation = Side.white,
    required this.lightSquare,
    required this.darkSquare,
  });

  final bool coordinates;
  final Side orientation;
  final Color lightSquare;
  final Color darkSquare;
}

// CHESSEVER PATCH (performance): coordinate labels are laid out once and
// reused. Upstream built and laid out 16 TextPainters inside every paint() of
// the board background, which runs on each frame of a piece animation and each
// time a board enters a scrolling list, and never disposed them. The style is
// fixed apart from the colour, so (text, colour) identifies a label; a laid-out
// TextPainter paints the same glyphs at any offset.
final Map<(String, Color), TextPainter> _coordPainters = {};
bool _coordPaintersListenToFonts = false;

TextPainter _coordPainter(String text, Color color) {
  if (!_coordPaintersListenToFonts) {
    _coordPaintersListenToFonts = true;
    // A font that loads later changes the metrics; drop the stale layouts.
    PaintingBinding.instance.systemFonts.addListener(_clearCoordPainters);
  }
  // 16 labels per colour pair per theme: far below this in practice.
  if (_coordPainters.length > 512) _clearCoordPainters();
  return _coordPainters[(text, color)] ??= TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        inherit: false,
        fontWeight: FontWeight.bold,
        fontSize: 10.0,
        color: color,
        fontFamily: 'Roboto',
        height: 1.0,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
}

void _clearCoordPainters() {
  for (final painter in _coordPainters.values) {
    painter.dispose();
  }
  _coordPainters.clear();
}

/// A chessboard background with solid color squares.
class SolidColorChessboardBackground extends ChessboardBackground {
  const SolidColorChessboardBackground({
    super.key,
    super.coordinates,
    super.orientation,
    required super.lightSquare,
    required super.darkSquare,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _SolidColorChessboardPainter(
        lightSquare: lightSquare,
        darkSquare: darkSquare,
        coordinates: coordinates,
        orientation: orientation,
      ),
    );
  }
}

class _SolidColorChessboardPainter extends CustomPainter {
  _SolidColorChessboardPainter({
    required this.lightSquare,
    required this.darkSquare,
    required this.coordinates,
    required this.orientation,
  });

  final Color lightSquare;
  final Color darkSquare;
  final bool coordinates;
  final Side orientation;

  @override
  void paint(Canvas canvas, Size size) {
    final squareSize = size.shortestSide / 8;
    for (var rank = 0; rank < 8; rank++) {
      for (var file = 0; file < 8; file++) {
        final square = Rect.fromLTWH(file * squareSize, rank * squareSize, squareSize, squareSize);
        final paint = Paint()..color = (rank + file).isEven ? lightSquare : darkSquare;
        canvas.drawRect(square, paint);
        if (coordinates && (file == 7 || rank == 7)) {
          final coordColor = (rank + file).isEven ? darkSquare : lightSquare;
          if (file == 7) {
            final coord = _coordPainter(
              orientation == Side.white ? '${8 - rank}' : '${rank + 1}',
              coordColor,
            );
            const edgeOffset = 2.0;
            final offset = Offset(
              file * squareSize + (squareSize - coord.width) - edgeOffset,
              rank * squareSize + edgeOffset,
            );
            coord.paint(canvas, offset);
          }
          if (rank == 7) {
            final coord = _coordPainter(
              orientation == Side.white
                  ? String.fromCharCode(97 + file)
                  : String.fromCharCode(97 + 7 - file),
              coordColor,
            );
            const edgeOffset = 2.0;
            final offset = Offset(
              file * squareSize + edgeOffset,
              rank * squareSize + (squareSize - coord.height) - edgeOffset,
            );
            coord.paint(canvas, offset);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

/// A chessboard background made of an image.
class ImageChessboardBackground extends ChessboardBackground {
  const ImageChessboardBackground({
    super.key,
    super.coordinates,
    super.orientation,
    required super.lightSquare,
    required super.darkSquare,
    required this.image,
  });

  final AssetImage image;

  @override
  Widget build(BuildContext context) {
    if (coordinates) {
      return Stack(
        fit: StackFit.expand,
        alignment: Alignment.topLeft,
        clipBehavior: Clip.none,
        children: [
          Image(image: image, fit: BoxFit.cover),
          CustomPaint(
            size: Size.infinite,
            painter: _ImageBackgroundCoordinatePainter(
              lightSquare: lightSquare,
              darkSquare: darkSquare,
              orientation: orientation,
            ),
          ),
        ],
      );
    } else {
      return Image(image: image, fit: BoxFit.cover);
    }
  }
}

class _ImageBackgroundCoordinatePainter extends CustomPainter {
  _ImageBackgroundCoordinatePainter({
    required this.lightSquare,
    required this.darkSquare,
    required this.orientation,
  });

  final Side orientation;
  final Color lightSquare;
  final Color darkSquare;

  @override
  void paint(Canvas canvas, Size size) {
    final squareSize = size.shortestSide / 8;
    for (var rank = 0; rank < 8; rank++) {
      for (var file = 0; file < 8; file++) {
        if (file == 7 || rank == 7) {
          final coordColor = (rank + file).isEven ? darkSquare : lightSquare;
          final square = Rect.fromLTWH(
            file * squareSize,
            rank * squareSize,
            squareSize,
            squareSize,
          );
          final paint = Paint()..color = const Color(0x00000000);
          canvas.drawRect(square, paint);
          if (file == 7) {
            final coord = _coordPainter(
              orientation == Side.white ? '${8 - rank}' : '${rank + 1}',
              coordColor,
            );
            const edgeOffset = 2.0;
            final offset = Offset(
              file * squareSize + (squareSize - coord.width) - edgeOffset,
              rank * squareSize + edgeOffset,
            );
            coord.paint(canvas, offset);
          }
          if (rank == 7) {
            final coord = _coordPainter(
              orientation == Side.white
                  ? String.fromCharCode(97 + file)
                  : String.fromCharCode(97 + 7 - file),
              coordColor,
            );
            const edgeOffset = 2.0;
            final offset = Offset(
              file * squareSize + edgeOffset,
              rank * squareSize + (squareSize - coord.height) - edgeOffset,
            );
            coord.paint(canvas, offset);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
