import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'board_scan_image.dart';

class BoardScanCrop extends StatelessWidget {
  const BoardScanCrop({
    super.key,
    required this.image,
    required this.corners,
    required this.onChanged,
    this.enabled = true,
  });
  final BoardScanImage image;
  final List<Offset> corners;
  final ValueChanged<List<Offset>> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: image.width / image.height,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Image.memory(
                image.bytes,
                fit: BoxFit.fill,
                gaplessPlayback: true,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _BoardScanGrid(corners)),
              ),
            ),
            for (var i = 0; i < 4; i++)
              Positioned(
                left: corners[i].dx * size.width - 22,
                top: corners[i].dy * size.height - 22,
                child: Semantics(
                  label:
                      'Board corner ${i + 1}. Drag to the outer edge of the squares.',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanUpdate: !enabled
                        ? null
                        : (event) {
                            final next = List<Offset>.of(corners);
                            next[i] = Offset(
                              (corners[i].dx + event.delta.dx / size.width)
                                  .clamp(0, 1),
                              (corners[i].dy + event.delta.dy / size.height)
                                  .clamp(0, 1),
                            );
                            onChanged(next);
                          },
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFF151515),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
}

class _BoardScanGrid extends CustomPainter {
  _BoardScanGrid(this.corners);
  final List<Offset> corners;
  @override
  void paint(Canvas canvas, Size size) {
    final points = corners
        .map((p) => Offset(p.dx * size.width, p.dy * size.height))
        .toList();
    final outline = Path()..moveTo(points[0].dx, points[0].dy);
    for (final p in points.skip(1)) {
      outline.lineTo(p.dx, p.dy);
    }
    outline.close();
    canvas.drawPath(
      outline,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    if (!validBoardScanCorners(corners)) return;
    final h = boardScanHomography(corners);
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .40)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    Offset at(double x, double y) {
      final p = boardScanProject(h, x, y);
      return Offset(p.dx * size.width, p.dy * size.height);
    }

    for (var i = 1; i < 8; i++) {
      final t = i / 8;
      canvas.drawLine(at(t, 0), at(t, 1), paint);
      canvas.drawLine(at(0, t), at(1, t), paint);
    }
  }

  @override
  bool shouldRepaint(_BoardScanGrid old) => !listEquals(old.corners, corners);
}

// Start inside the image so every handle has a full 44dp target.
const initialBoardScanCorners = [
  Offset(.06, .06),
  Offset(.94, .06),
  Offset(.94, .94),
  Offset(.06, .94),
];
