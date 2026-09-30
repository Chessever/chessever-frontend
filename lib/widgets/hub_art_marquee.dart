import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Favorites-sized marks on an irregular, continuously sliding strip.
/// Geometry is stable while data arrives; only the contents of a cell change.
class HubArtMarquee extends StatefulWidget {
  const HubArtMarquee({
    super.key,
    required this.itemBuilder,
    required this.seed,
    this.slideKey,
    this.rows = 3,
    this.itemGap = 9,
  }) : assert(rows > 0),
       assert(itemGap >= 0);

  final Widget Function(int index, double size) itemBuilder;
  final int seed;
  final Key? slideKey;
  final int rows;
  final double itemGap;
  static const cycle = Duration(seconds: 45);

  @override
  State<HubArtMarquee> createState() => _HubArtMarqueeState();
}

class _HubArtMarqueeState extends State<HubArtMarquee>
    with SingleTickerProviderStateMixin {
  late final _slide = AnimationController(
    vsync: this,
    duration: HubArtMarquee.cycle,
    animationBehavior: AnimationBehavior.preserve,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (enabled && !_slide.isAnimating) _slide.repeat();
    if (!enabled) _slide.stop();
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: ClipRect(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            if (!width.isFinite ||
                !height.isFinite ||
                width <= 0 ||
                height <= 8) {
              return const SizedBox.shrink();
            }
            // Keep the portrait scale close to Favorites, even for one row.
            final rows = widget.rows;
            const columns = 8;
            const gap = 4.0;
            final rowHeight = (height - (rows - 1) * gap) / rows;
            final base = math.max(1.0, math.min(32.0, rowHeight - 2));
            final pitch = base + widget.itemGap;
            final period = columns * pitch;
            final copies = (width / period).ceil() + 1;
            final random = math.Random(widget.seed);
            final cells = <Widget>[];
            for (var row = 0; row < rows; row++) {
              for (var column = 0; column < columns; column++) {
                final index = row * columns + column;
                final side = base * (.88 + random.nextDouble() * .12);
                final x =
                    column * pitch +
                    (row.isOdd ? pitch * .5 : 0) +
                    (base - side) * .5 +
                    (random.nextDouble() - .5) * 3;
                final y = row * (rowHeight + gap) + (rowHeight - side) * .5;
                for (var copy = -1; copy < copies; copy++) {
                  cells.add(
                    Positioned(
                      left: x + copy * period,
                      top: y,
                      child: SizedBox.square(
                        dimension: side,
                        child: widget.itemBuilder(index, side),
                      ),
                    ),
                  );
                }
              }
            }
            return RepaintBoundary(
              child: AnimatedBuilder(
                animation: _slide,
                child: RepaintBoundary(
                  child: Stack(clipBehavior: Clip.none, children: cells),
                ),
                builder: (context, child) => Transform.translate(
                  key: widget.slideKey,
                  offset: Offset(-_slide.value * period, 0),
                  child: child,
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
