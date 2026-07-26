import 'dart:async';

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// The contextual "Did you like this game?" reminder, shown over the bottom of
/// the board once a user has finished a long run of games without liking any.
///
/// Why it is shaped like this:
///
/// * **It is the same floating object as [showAppSnack]'s capsule** — the same
///   ink, radius, self-coloured lip and single tight shadow. A second, differently
///   styled "message layer" would read as a bolted-on component; this reads as
///   the app talking.
/// * **The affirmative is a bare heart, not a labelled button.** Answering yes
///   performs the real double-tap-like, burst and flight included, so the control
///   is the same object the gesture produces. A filled "Yes, like it" button
///   beside an outlined "No" would teach nothing and is the stock action-row.
/// * **The heart beats twice on arrival.** That is the lesson — the double-tap
///   rhythm — carried by motion instead of a third line of copy.
class LikeNudge extends StatefulWidget {
  const LikeNudge({super.key, required this.onLike, required this.onDismiss});

  /// Fires the real like path (burst → flight → tag chip), carrying the global
  /// centre of the heart that was tapped so the burst grows out of that mark.
  final ValueChanged<Offset> onLike;

  /// Quiet dismissal. The game still counts toward the cadence.
  final VoidCallback onDismiss;

  @override
  State<LikeNudge> createState() => _LikeNudgeState();
}

class _LikeNudgeState extends State<LikeNudge> {
  /// Vertical settle only. Opacity is never animated: a reminder that renders
  /// invisible because a spring did not run is worse than no reminder at all.
  double _rise = 1.0;

  /// Scale target for the heart, retargeted twice to read as a double-tap.
  double _beat = 1.0;

  final List<Timer> _beats = <Timer>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _rise = 0.0);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_beats.isEmpty && !MediaQuery.disableAnimationsOf(context)) {
      _scheduleDoubleBeat();
    }
  }

  /// Two pulses 140ms apart — the cadence of an actual double-tap, not a
  /// decorative throb. Runs once; the capsule is calm after that.
  void _scheduleDoubleBeat() {
    const beats = <(int, double)>[
      (300, 1.20),
      (440, 1.0),
      (580, 1.20),
      (720, 1.0),
    ];
    for (final (delayMs, target) in beats) {
      _beats.add(
        Timer(Duration(milliseconds: delayMs), () {
          if (!mounted) return;
          setState(() => _beat = target);
        }),
      );
    }
  }

  @override
  void dispose() {
    for (final beat in _beats) {
      beat.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16.br);

    return SingleMotionBuilder(
      motion: const CupertinoMotion.smooth(),
      value: _rise,
      builder: (context, rise, child) {
        return Transform.translate(
          // Rests 20.h off the board's bottom edge and travels 16 — so even a
          // frame where the spring never advances leaves the whole capsule
          // on-board rather than clipped by the edge it rose from.
          offset: Offset(0, rise.clamp(0.0, 1.0) * 16),
          child: child,
        );
      },
      child: Semantics(
        container: true,
        label: 'Did you like this game? Tap the heart to like it.',
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            decoration: BoxDecoration(
              color: _nudgeInk,
              borderRadius: radius,
              // Self-coloured lip catching light, not a drawn outline.
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              boxShadow: [
                // One tight, low-offset, directional shadow. Never a bloom.
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            // The heart and close targets each clear 44dp and supply the right
            // gutter themselves, so the row keeps one optical rhythm instead of
            // double-padding its controls.
            padding: EdgeInsets.fromLTRB(16.sp, 10.sp, 6.sp, 10.sp),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Did you like this game?',
                        style: AppTypography.textSmSemiBold.copyWith(
                          color: Colors.white.withValues(alpha: 0.95),
                          height: 1.25,
                        ),
                      ),
                      SizedBox(height: 3.h),
                      Text(
                        'Tap the heart, or double-tap any board.',
                        style: AppTypography.textXsRegular.copyWith(
                          color: Colors.white.withValues(alpha: 0.52),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8.w),
                _HeartAnswer(
                  scale: _beat,
                  color: context.colors.danger,
                  onPressed: widget.onLike,
                ),
                _DismissAnswer(onPressed: widget.onDismiss),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pure neutral ink, matched to the app snack capsule so both read as the same
/// floating layer over the product rather than two different components.
const Color _nudgeInk = Color(0xFF08080A);

/// The affirmative: the bare like mark, no tile, no chip, no fill behind it.
class _HeartAnswer extends StatefulWidget {
  const _HeartAnswer({
    required this.scale,
    required this.color,
    required this.onPressed,
  });

  final double scale;
  final Color color;
  final ValueChanged<Offset> onPressed;

  @override
  State<_HeartAnswer> createState() => _HeartAnswerState();
}

class _HeartAnswerState extends State<_HeartAnswer> {
  final GlobalKey _heartKey = GlobalKey();

  void _handleTap() {
    final renderBox = _heartKey.currentContext?.findRenderObject();
    final centre =
        renderBox is RenderBox
            ? renderBox.localToGlobal(renderBox.size.center(Offset.zero))
            : Offset.zero;
    widget.onPressed(centre);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Like this game',
      child: InkResponse(
        onTap: _handleTap,
        radius: 26.sp,
        // 44dp floor, unscaled: on a 390pt phone a scaled 44.sp lands at 43.6
        // and the target quietly drops under the minimum.
        child: ConstrainedBox(
          key: _heartKey,
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: SizedBox(
            width: 44.sp,
            height: 44.sp,
            child: Center(
              child: SingleMotionBuilder(
                motion: const CupertinoMotion.bouncy(),
                value: widget.scale,
                builder: (context, value, child) {
                  return Transform.scale(scale: value, child: child);
                },
                child: Icon(
                  Icons.favorite_rounded,
                  size: 24.sp,
                  color: widget.color,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The quiet way out. Deliberately not a second button competing with the
/// heart — it is a dismissal, and it should read as one.
class _DismissAnswer extends StatelessWidget {
  const _DismissAnswer({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Dismiss',
      child: InkResponse(
        onTap: onPressed,
        radius: 24.sp,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: SizedBox(
            width: 44.sp,
            height: 44.sp,
            child: Center(
              child: Icon(
                Icons.close_rounded,
                size: 17.sp,
                color: Colors.white.withValues(alpha: 0.42),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
