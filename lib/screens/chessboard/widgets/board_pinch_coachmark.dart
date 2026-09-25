import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A board-local hint. Only the close button accepts touches, so a user can
/// perform the demonstrated pinch directly on the board.
class BoardPinchCoachmark extends StatefulWidget {
  const BoardPinchCoachmark({super.key, required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  State<BoardPinchCoachmark> createState() => _BoardPinchCoachmarkState();
}

class _BoardPinchCoachmarkState extends State<BoardPinchCoachmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: ColoredBox(
            color: Colors.black.withValues(alpha: .62),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final hintWidth = math.min(width, 320.0);
                final spread = math.min(46.0, hintWidth * .13);
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _motion,
                      builder: (context, _) {
                        final travel =
                            spread * Curves.easeInOut.transform(_motion.value);
                        return SizedBox(
                          width: hintWidth,
                          height: 94,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Transform.translate(
                                offset: Offset(-24 - travel, 0),
                                child: Transform.rotate(
                                  angle: -.35,
                                  child: const Icon(
                                    Icons.touch_app_rounded,
                                    color: Colors.white,
                                    size: 64,
                                  ),
                                ),
                              ),
                              Transform.translate(
                                offset: Offset(24 + travel, 0),
                                child: Transform.rotate(
                                  angle: .35,
                                  child: const Icon(
                                    Icons.touch_app_rounded,
                                    color: Colors.white,
                                    size: 64,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 0,
                                left: hintWidth / 2 - 92 - travel,
                                child: const Icon(
                                  Icons.north_west_rounded,
                                  color: Color(0xFFFF8A50),
                                  size: 25,
                                ),
                              ),
                              Positioned(
                                top: 0,
                                right: hintWidth / 2 - 92 - travel,
                                child: const Icon(
                                  Icons.north_east_rounded,
                                  color: Color(0xFFFF8A50),
                                  size: 25,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Pinch to resize the board',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Move two fingers together or apart',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: IconButton(
            key: const ValueKey('dismiss_board_pinch_coachmark'),
            tooltip: 'Dismiss pinch hint',
            onPressed: widget.onDismiss,
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
