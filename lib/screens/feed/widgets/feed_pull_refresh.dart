import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// Pull-to-refresh for the Feed's vertical page views, drawn by the Feed
/// itself rather than the platform.
///
/// The page view is clamped at its top edge (see [feedPagePhysics]), so on
/// both platforms a pull past the first page arrives as overscroll and this
/// widget moves the page itself:
///
/// * **Follow with friction.** The page trails the finger through a rubber
///   band that stiffens the further it goes, so the edge gives rather than
///   stops.
/// * **One tick.** Crossing the trigger is marked by a single selection
///   haptic and the rank indicator filling its last square; pulling back
///   under it re-arms.
/// * **Release.** The page springs to a short hold while [onRefresh] runs,
///   then springs home carrying its velocity. When [onRefresh] completes at
///   once (the Feed keeps a ready reserve) there is no hold at all: the new
///   page rises straight into place from where the finger let go.
///
/// The indicator is a rank of eight board squares, not a spinner: they fill
/// one by one with the pull and, while waiting, a light travels along them
/// like a rook down a rank. Content is never hidden: only its offset moves.
class FeedPullRefresh extends StatefulWidget {
  const FeedPullRefresh({
    required this.onRefresh,
    required this.child,
    this.enabled = true,
    super.key,
  });

  final Future<void> Function() onRefresh;

  /// False while something on the page owns the finger (a piece being
  /// dragged, the scrub bar); the pull then never starts.
  final bool enabled;
  final Widget child;

  @override
  State<FeedPullRefresh> createState() => _FeedPullRefreshState();
}

/// Page physics that pair with [FeedPullRefresh]: pages snap as usual but
/// never bounce at the top, so the pull is the Feed's own on every
/// platform.
const ScrollPhysics feedPagePhysics = PageScrollPhysics(
  parent: ClampingScrollPhysics(),
);

class _FeedPullRefreshState extends State<FeedPullRefresh>
    with TickerProviderStateMixin {
  /// Displayed offset at which a release refreshes.
  static const double _trigger = 64;

  /// Where the page waits while a refresh is still loading.
  static const double _hold = 56;

  /// The rubber band's ceiling: no pull moves the page further than this.
  static const double _ceiling = 150;

  late final SingleMotionController _offset = SingleMotionController(
    motion: const CupertinoMotion.smooth(),
    vsync: this,
  );

  /// The travelling light while a refresh loads. Linear and quick: a fast
  /// indicator makes the same wait feel shorter.
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
  );

  /// Raw finger travel past the top edge, before the rubber band.
  double _pull = 0;

  /// Where the finger was (globally) when the pull began, less any pull
  /// already on screen. Global, because the page it drags is itself moving:
  /// its local deltas shrink as it follows the finger.
  double? _originY;

  /// Page speed at release, px/s, handed to the first spring after it.
  double _releaseVelocity = 0;
  bool _pulling = false;
  bool _armed = false;
  bool _refreshing = false;

  /// The refresh just landed: the rank shows full while the page settles.
  bool _landed = false;

  @override
  void dispose() {
    _offset.dispose();
    _wave.dispose();
    super.dispose();
  }

  /// Asymptotic damping: 1:0.85 at the start, never past [_ceiling].
  static double _rubber(double raw) =>
      _ceiling * (1 - 1 / (raw * 0.85 / _ceiling + 1));

  void _follow() {
    final shown = _rubber(_pull);
    _offset.value = shown;
    final armed = shown >= _trigger;
    if (armed != _armed) {
      _armed = armed;
      if (armed) unawaited(HapticFeedbackService.selection());
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    if (_refreshing || !widget.enabled) {
      if (_pulling) _settle();
      return false;
    }
    switch (n) {
      case ScrollStartNotification(:final dragDetails):
        if (dragDetails != null && n.metrics.extentBefore <= 0) {
          _pulling = true;
          _originY =
              dragDetails.globalPosition.dy - _inverseRubber(_offset.value);
          _landed = false;
        }
      case OverscrollNotification(:final dragDetails):
        _track(dragDetails?.globalPosition);
      case ScrollUpdateNotification(:final dragDetails):
        // Pushing back up takes the pull in on the way.
        _track(dragDetails?.globalPosition);
      case ScrollEndNotification(:final dragDetails):
        if (_pulling) {
          // The finger's own speed, through the band's slope, so the spring
          // picks up the flick instead of starting from rest.
          _releaseVelocity =
              (dragDetails?.velocity.pixelsPerSecond.dy ?? 0) *
              _bandSlope(_pull);
          _release();
        }
      default:
        break;
    }
    return false;
  }

  void _track(Offset? finger) {
    final origin = _originY;
    if (!_pulling || finger == null || origin == null) return;
    _pull = math.max(0, finger.dy - origin);
    _follow();
  }

  /// d(shown)/d(raw) of [_rubber] at [raw].
  static double _bandSlope(double raw) {
    final k = raw * 0.85 / _ceiling + 1;
    return 0.85 / (k * k);
  }

  /// Springs to [target], spending the release velocity once.
  void _springTo(double target) {
    final velocity = _releaseVelocity;
    _releaseVelocity = 0;
    unawaited(_offset.animateTo(target, withVelocity: velocity));
  }

  static double _inverseRubber(double shown) {
    final s = shown.clamp(0.0, _ceiling - 1);
    return (_ceiling / 0.85) * (1 / (1 - s / _ceiling) - 1);
  }

  void _release() {
    _pulling = false;
    _originY = null;
    if (_armed) {
      unawaited(_refresh());
    } else {
      _settle();
    }
  }

  void _settle() {
    _pulling = false;
    _originY = null;
    _pull = 0;
    _armed = false;
    if (MediaQuery.disableAnimationsOf(context)) {
      _offset.value = 0;
    } else {
      _springTo(0);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _refreshing = true;
      _landed = false;
    });
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final task = widget.onRefresh();
    var done = false;
    // A reserve lands within a frame: no hold, no wave, straight home.
    await Future.any([
      task.then((_) => done = true, onError: (_) => done = true),
      Future<void>.delayed(const Duration(milliseconds: 90)),
    ]);
    if (!done && mounted) {
      if (!reduceMotion) {
        unawaited(_wave.repeat());
        _springTo(_hold);
      } else {
        _offset.value = _hold;
      }
      try {
        await task;
      } catch (_) {
        // The caller reports failures; the pull only lets go.
      }
    }
    if (!mounted) return;
    _wave.stop();
    setState(() {
      _refreshing = false;
      _landed = true;
    });
    _pull = 0;
    _armed = false;
    if (reduceMotion) {
      _offset.value = 0;
    } else {
      _springTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ScrollConfiguration(
        // The page itself is the overscroll feedback; no platform glow.
        behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            AnimatedBuilder(
              animation: _offset,
              child: widget.child,
              builder: (context, child) {
                // Always the same tree: swapping a Transform in mid-drag
                // would remount the page view and drop the finger.
                return Transform.translate(
                  offset: Offset(0, _offset.value),
                  child: child,
                );
              },
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_offset, _wave]),
                  builder: (context, _) {
                    final y = _offset.value;
                    if (y < 1) return const SizedBox.shrink();
                    final progress = (y / _trigger).clamp(0.0, 1.0);
                    return Semantics(
                      liveRegion: true,
                      label: _refreshing ? 'Refreshing Feed' : null,
                      child: SizedBox(
                        height: y,
                        child: Center(
                          child: Opacity(
                            opacity: progress,
                            child: _RankIndicator(
                              progress: progress,
                              wave: _refreshing ? _wave.value : null,
                              full: _landed,
                              ink: colors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Eight board squares in a row. [progress] fills them left to right in
/// the board's two tones; [wave] (0..1) runs a light along them; [full]
/// shows every square lit.
class _RankIndicator extends StatelessWidget {
  const _RankIndicator({
    required this.progress,
    required this.wave,
    required this.full,
    required this.ink,
  });

  final double progress;
  final double? wave;
  final bool full;
  final Color ink;

  static const double _square = 7;
  static const double _gap = 3;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(8 * _square + 7 * _gap, _square),
      painter: _RankPainter(
        progress: full ? 1 : progress,
        wave: full ? null : wave,
        ink: ink,
      ),
    );
  }
}

class _RankPainter extends CustomPainter {
  _RankPainter({required this.progress, required this.wave, required this.ink});

  final double progress;
  final double? wave;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    const s = _RankIndicator._square;
    const g = _RankIndicator._gap;
    final paint = Paint()..isAntiAlias = true;
    for (var i = 0; i < 8; i++) {
      // Light and dark squares, as on a rank.
      final tone = i.isEven ? 1.0 : 0.62;
      double lit;
      final w = wave;
      if (w != null) {
        // A light a square and a half wide, sliding off one end and back in
        // at the other.
        final d = ((w * 9 - i) % 9 + 9) % 9;
        final bump = d < 1.5 ? math.sin(d / 1.5 * math.pi) : 0.0;
        lit = 0.28 + 0.72 * bump;
      } else {
        lit = ((progress * 8) - i).clamp(0.0, 1.0);
      }
      final alpha = 0.14 + (tone - 0.14) * lit;
      paint.color = ink.withValues(alpha: alpha);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * (s + g), 0, s, s),
          const Radius.circular(1.6),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RankPainter old) =>
      old.progress != progress || old.wave != wave || old.ink != ink;
}
