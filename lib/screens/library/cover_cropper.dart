import 'dart:math' as math;

import 'package:chessever2/repository/library/collection_cover.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Pick a photo, let the author frame it, and return the prepared 2:3 cover,
/// or null when they cancel at either step. Overridden in tests.
final collectionCoverPickerProvider =
    Provider<Future<Uint8List?> Function(BuildContext context)>(
      (ref) => (context) async {
        final source = await ref.read(collectionCoverSourceProvider)();
        if (source == null || !context.mounted) return null;
        final size = await collectionCoverSourceSize(source);
        if (!collectionCoverFits(size)) {
          throw const FormatException(
            'This photo is too small for a cover. Use one at least 600 × 900 pixels.',
          );
        }
        if (!context.mounted) return null;
        final crop = await Navigator.of(context).push<Rect>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => CoverCropper(bytes: source, photoSize: size),
          ),
        );
        if (crop == null) return null;
        return prepareCollectionCover(source, crop: crop);
      },
    );

/// Frames a photo as a 2:3 cover. The frame stays put; the photo moves under
/// it (drag) and scales (pinch, or scroll on a trackpad). Zoom stops before
/// the framed window drops below the 600×900 pixels a cover needs, and the
/// photo always fills the frame. Pops with the window as fractions of the
/// photo, or nothing on Cancel.
class CoverCropper extends StatefulWidget {
  const CoverCropper({super.key, required this.bytes, required this.photoSize});

  final Uint8List bytes;
  final Size photoSize;

  @override
  State<CoverCropper> createState() => _CoverCropperState();
}

class _CoverCropperState extends State<CoverCropper> {
  final _transform = TransformationController();
  Size? _frame;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// Photo scale at which it just covers the frame (zoom 1).
  double _cover(Size frame) => math.max(
    frame.width / widget.photoSize.width,
    frame.height / widget.photoSize.height,
  );

  void _centre(Size frame) {
    final s = _cover(frame);
    final dx = (widget.photoSize.width * s - frame.width) / 2;
    final dy = (widget.photoSize.height * s - frame.height) / 2;
    _transform.value = Matrix4.translationValues(-dx, -dy, 0);
  }

  void _use() {
    final frame = _frame;
    if (frame == null) return;
    final m = _transform.value;
    final k = m.getMaxScaleOnAxis();
    final s = _cover(frame);
    final childW = widget.photoSize.width * s;
    final childH = widget.photoSize.height * s;
    final left = -m.storage[12] / k;
    final top = -m.storage[13] / k;
    Navigator.of(context).pop(
      Rect.fromLTWH(
        left / childW,
        top / childH,
        frame.width / k / childW,
        frame.height / k / childH,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final action = AppTypography.textSmMedium.copyWith(color: Colors.white);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                height: 52,
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                        minimumSize: const Size(64, 44),
                      ),
                      child: const Text('Cancel'),
                    ),
                    Expanded(
                      child: Text(
                        'Frame your cover',
                        textAlign: TextAlign.center,
                        style: action,
                      ),
                    ),
                    TextButton(
                      key: const ValueKey('cover_crop_use'),
                      onPressed: _use,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        minimumSize: const Size(64, 44),
                        textStyle: AppTypography.textSmMedium,
                      ),
                      child: const Text('Use photo'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    const inset = 28.0;
                    final fw = math.min(
                      box.maxWidth - inset * 2,
                      (box.maxHeight - inset * 2) * 2 / 3,
                    );
                    final frame = Size(fw, fw * 3 / 2);
                    if (_frame != frame) {
                      _frame = frame;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _centre(frame);
                      });
                    }
                    final s = _cover(frame);
                    // Visible photo width at zoom 1, in photo pixels.
                    final widest = frame.width / s;
                    final maxZoom = math.max(
                      1.0,
                      widest / collectionCoverMinWidth,
                    );
                    final rect = Rect.fromCenter(
                      center: box.biggest.center(Offset.zero),
                      width: frame.width,
                      height: frame.height,
                    );
                    return Stack(
                      children: [
                        Positioned.fromRect(
                          rect: rect,
                          child: InteractiveViewer(
                            transformationController: _transform,
                            constrained: false,
                            minScale: 1,
                            maxScale: maxZoom,
                            boundaryMargin: EdgeInsets.zero,
                            clipBehavior: Clip.none,
                            child: Image.memory(
                              widget.bytes,
                              width: widget.photoSize.width * s,
                              height: widget.photoSize.height * s,
                              fit: BoxFit.fill,
                              cacheWidth: math
                                  .min(widget.photoSize.width, 2000)
                                  .round(),
                              gaplessPlayback: true,
                            ),
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(painter: _FramePainter(rect)),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                child: Text(
                  'Pinch to zoom, drag to move. This is exactly what the cover shows.',
                  textAlign: TextAlign.center,
                  style: AppTypography.textXsRegular.copyWith(
                    color: Colors.white60,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dims everything outside the frame and draws its edge.
class _FramePainter extends CustomPainter {
  const _FramePainter(this.frame);
  final Rect frame;

  @override
  void paint(Canvas canvas, Size size) {
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(frame);
    canvas.drawPath(
      shade,
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );
    canvas.drawRect(
      frame.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.frame != frame;
}
