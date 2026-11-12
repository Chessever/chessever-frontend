import 'dart:math' as math;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Local 768px artwork with no network dependency or animated loading swap.
/// Study scenes keep their scale and fade their own pixels clear of the label.
class HubIllustration extends StatelessWidget {
  const HubIllustration({
    super.key,
    required this.asset,
    this.alignment = Alignment.topCenter,
    this.framed = false,
    this.shift = 0,
  });

  final String asset;
  final Alignment alignment;

  /// Fits a wide study scene above the text rather than enlarging it to cover.
  final bool framed;

  /// How far right a framed scene's picture sits of the card's edge.
  final double shift;

  /// The study scenes' own quiet field. The dark tile is this tone already,
  /// so a scene narrower than its card ends unseen there. Paper is not: the
  /// field is carried on to the card's far edge, or the wash would stop
  /// partway across and read as a picture cut short.
  static const _field = Color(0xFF0E0E10);

  /// Luma key: the field (about 0x0E) turns transparent, while the board's
  /// darkest squares (0x17 and up) and the subjects stay opaque.
  static const _fieldKey = ColorFilter.matrix(<double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    5.315, 17.88, 1.805, 0, -382.5,
  ]);

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: Opacity(
        opacity: context.isLightTheme ? .32 : 1,
        child: framed
            ? LayoutBuilder(
                builder: (context, constraints) {
                  // Both study sources are 3:1. Only their quiet left field
                  // can extend beyond a compact card; the subjects keep the
                  // closer crop and top-right position in either card format.
                  final height = 100.sp.clamp(0.0, constraints.maxHeight);
                  final width = height * 3;
                  final onPaper = context.isLightTheme;
                  // The board floor is carried to the card's far edge in
                  // both themes, so a wide card (iPhone Duo, tablets) never
                  // shows the picture's board stopping partway across.
                  final span = math.max(width, constraints.maxWidth);
                  return ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topRight,
                      minWidth: span,
                      maxWidth: span,
                      minHeight: height,
                      maxHeight: height,
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (bounds) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white,
                            Colors.white,
                            Colors.transparent,
                          ],
                          stops: [0, 0.6, 1],
                        ).createShader(bounds),
                        child: Stack(
                          children: [
                            // Under the same fade to the label as the
                            // picture, so the two are one wash.
                            if (onPaper)
                              const Positioned.fill(
                                child: ColoredBox(color: _field),
                              ),
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _BoardFloorPainter(
                                  pictureLeft: span + shift - width,
                                  pictureHeight: height,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 0,
                              right: -shift,
                              width: width,
                              height: height,
                              child: ShaderMask(
                                blendMode: BlendMode.dstIn,
                                // A full-row card exposes the source's left edge.
                                // Fade those pixels before the subjects begin so
                                // neither theme shows a rectangular image seam.
                                shaderCallback: (bounds) =>
                                    const LinearGradient(
                                      colors: [
                                        Colors.transparent,
                                        Color(0x08ffffff),
                                        Color(0x24ffffff),
                                        Color(0x51ffffff),
                                        Color(0x88ffffff),
                                        Color(0xbaffffff),
                                        Color(0xe1ffffff),
                                        Color(0xf8ffffff),
                                        Colors.white,
                                        Colors.white,
                                      ],
                                      stops: [
                                        0,
                                        .05,
                                        .1,
                                        .15,
                                        .2,
                                        .25,
                                        .3,
                                        .35,
                                        .4,
                                        1,
                                      ],
                                    ).createShader(bounds),
                                // The picture's flat field drops out, so the
                                // painted floor below shows exactly where the
                                // picture's own board fades away.
                                child: ColorFiltered(
                                  colorFilter: _fieldKey,
                                  child: Image.asset(
                                    asset,
                                    width: width,
                                    height: height,
                                    fit: BoxFit.contain,
                                    cacheWidth: 768,
                                    filterQuality: FilterQuality.medium,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              )
            : Image.asset(
                asset,
                fit: BoxFit.cover,
                alignment: alignment,
                cacheWidth: 768,
                filterQuality: FilterQuality.medium,
              ),
      ),
    ),
  );
}

/// The study scenes' perspective board floor, continued past the picture.
///
/// Measured from the 768x256 sources (both share one floor): every column
/// line runs to one vanishing point, rows are evenly spaced in depth, and the
/// tones step down the way the art's do. Painting in the source's own pixel
/// space keeps every line on the picture's lines, so the two read as one.
class _BoardFloorPainter extends CustomPainter {
  const _BoardFloorPainter({
    required this.pictureLeft,
    required this.pictureHeight,
  });

  /// Where the picture's left edge sits, in this painter's coordinates.
  final double pictureLeft;
  final double pictureHeight;

  static const double _sourceHeight = 256;
  static const Offset _vanish = Offset(852, -726);

  /// Column lines cross y = 5 every 70.67px from x = 540.
  static const double _columnY = 5;
  static const double _columnX0 = 540;
  static const double _columnStep = 70.67;

  /// Row lines: 1 / (y - vanish.dy) falls by a constant step per row.
  static const double _rowInv0 = 1 / 759; // row line at y = 33
  static const double _rowInvStep = 7.39e-5;

  static const _light = [Color(0xFF2D2D2E), Color(0xFF222223)];
  static const _dark = [Color(0xFF19191A), Color(0xFF161617)];

  double _columnXAt(double column, double y) {
    final x0 = _columnX0 + column * _columnStep;
    return _vanish.dx +
        (x0 - _vanish.dx) * (y - _vanish.dy) / (_columnY - _vanish.dy);
  }

  double _columnAt(double x, double y) {
    final x0 =
        _vanish.dx +
        (x - _vanish.dx) * (_columnY - _vanish.dy) / (y - _vanish.dy);
    return (x0 - _columnX0) / _columnStep;
  }

  double _rowY(int row) => _vanish.dy + 1 / (_rowInv0 - row * _rowInvStep);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || pictureHeight <= 0) return;
    final scale = pictureHeight / _sourceHeight;
    final left = -pictureLeft / scale;
    final right = (size.width - pictureLeft) / scale;
    final bottom = math.min(_sourceHeight, size.height / scale);
    final area = Rect.fromLTRB(left, 0, right, bottom);

    canvas.save();
    canvas.translate(pictureLeft, 0);
    canvas.scale(scale);
    canvas.clipRect(area);

    Paint tone(List<Color> colors) => Paint()
      ..isAntiAlias = true
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: colors,
      ).createShader(const Rect.fromLTWH(0, 0, 1, _sourceHeight));

    // Dark squares are the floor; light squares are drawn over it, so
    // neighbouring quads never leave an anti-aliasing hairline.
    canvas.drawRect(area, tone(_dark));
    final light = tone(_light);

    final firstColumn =
        math.min(_columnAt(left, 0), _columnAt(left, bottom)).floor() - 1;
    final lastColumn =
        math.max(_columnAt(right, 0), _columnAt(right, bottom)).ceil() + 1;
    for (var row = -1; _rowY(row) < bottom; row++) {
      final top = math.max(0.0, _rowY(row));
      final base = math.min(bottom, _rowY(row + 1));
      if (base <= top) continue;
      for (var column = firstColumn; column < lastColumn; column++) {
        if ((column + row).isEven) continue;
        canvas.drawPath(
          Path()
            ..moveTo(_columnXAt(column.toDouble(), top), top)
            ..lineTo(_columnXAt(column + 1.0, top), top)
            ..lineTo(_columnXAt(column + 1.0, base), base)
            ..lineTo(_columnXAt(column.toDouble(), base), base)
            ..close(),
          light,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BoardFloorPainter old) =>
      old.pictureLeft != pictureLeft || old.pictureHeight != pictureHeight;
}
