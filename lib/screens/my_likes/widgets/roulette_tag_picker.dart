import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/constants/game_tags.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Presents the roulette tag picker as a modal sheet and resolves to the
/// chosen tag label, or `null` when the user skips / lets the spin run out /
/// dismisses. Tags are a My-Likes-only concept, so this is the single entry
/// point used both right after a like and from the liked-game save sheet.
Future<String?> showRouletteTagPicker(
  BuildContext context, {
  String? initialTag,
}) {
  return showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.62),
    builder: (_) => _RouletteTagPicker(initialTag: initialTag),
  );
}

/// Per-slice accent colours — muted enough to sit on the dark surface, distinct
/// enough to read as a gambling wheel. Index-aligned to [kOfficialGameTags].
const List<Color> _sliceColors = [
  Color(0xFFEF5350), // Wild Game
  Color(0xFFFFCA28), // Beautiful Mate
  Color(0xFFAB47BC), // Trap
  Color(0xFF26A69A), // Good Defense
  Color(0xFF66BB6A), // Comeback
  Color(0xFF42A5F5), // High Technique
  Color(0xFF5C6BC0), // Positional Masterpiece
  Color(0xFFFF7043), // Sacrifice
  Color(0xFF29B6F6), // Combination
  Color(0xFFEC407A), // Blunder
];

class _RouletteTagPicker extends StatefulWidget {
  const _RouletteTagPicker({this.initialTag});

  final String? initialTag;

  @override
  State<_RouletteTagPicker> createState() => _RouletteTagPickerState();
}

class _RouletteTagPickerState extends State<_RouletteTagPicker>
    with SingleTickerProviderStateMixin {
  // ── Physics state (radians; canvas angle 0 = +x, clockwise) ──────────────
  final ValueNotifier<double> _angle = ValueNotifier<double>(0);
  double _velocity = 0; // rad/s
  bool _dragging = false;
  bool _settled = false;
  bool _resolved = false;

  // ── Countdown (1 → 0) ────────────────────────────────────────────────────
  static const double _countdownSeconds = 5.0;
  final ValueNotifier<double> _countdown = ValueNotifier<double>(1);
  double _remaining = _countdownSeconds;

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  // Cached icon glyph painters, one per slice.
  late final List<TextPainter> _iconPainters;

  int get _sliceCount => kOfficialGameTags.length;
  double get _sliceAngle => (2 * math.pi) / _sliceCount;

  // Pointer sits at the top of the wheel (12 o'clock). In canvas space (y down)
  // that is -π/2.
  static const double _pointerAngle = -math.pi / 2;

  @override
  void initState() {
    super.initState();
    _iconPainters = [
      for (final tag in kOfficialGameTags)
        TextPainter(
          textDirection: TextDirection.ltr,
          text: TextSpan(
            text: String.fromCharCode(tag.icon.codePoint),
            style: TextStyle(
              fontSize: 20,
              fontFamily: tag.icon.fontFamily,
              package: tag.icon.fontPackage,
              color: Colors.white,
            ),
          ),
        )..layout(),
    ];

    // Pre-position the wheel so the user's existing tag (if any) starts under
    // the pointer — editing feels continuous rather than random.
    final startIndex =
        widget.initialTag == null
            ? 0
            : kOfficialGameTagLabels.indexOf(widget.initialTag!);
    _angle.value = _angleForIndex(startIndex < 0 ? 0 : startIndex);

    _ticker = createTicker(_onTick);
    if (!_reduceMotion) {
      _ticker.start();
      // A gentle inviting kick so the wheel breathes on entry.
      _velocity = 3.2;
      _settled = false;
    }
  }

  bool get _reduceMotion {
    final v = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return v.disableAnimations;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _angle.dispose();
    _countdown.dispose();
    for (final p in _iconPainters) {
      p.dispose();
    }
    super.dispose();
  }

  // The wheel angle that places slice [index]'s centre under the top pointer.
  double _angleForIndex(int index) {
    final centerLocal = (index + 0.5) * _sliceAngle;
    return _normalize(_pointerAngle - centerLocal);
  }

  double _normalize(double a) {
    final twoPi = 2 * math.pi;
    var r = a % twoPi;
    if (r < 0) r += twoPi;
    return r;
  }

  // Shortest signed delta from a → b, in (-π, π].
  double _shortestDelta(double from, double to) {
    var d = (to - from) % (2 * math.pi);
    if (d > math.pi) d -= 2 * math.pi;
    if (d < -math.pi) d += 2 * math.pi;
    return d;
  }

  int get _selectedIndex {
    final localAtPointer = _normalize(_pointerAngle - _angle.value);
    return localAtPointer ~/ _sliceAngle % _sliceCount;
  }

  double _nearestCenterAngle() => _angleForIndex(_selectedIndex);

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 1 / 60
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0) return;

    if (!_dragging) {
      // Countdown pauses while the user is actively positioning the wheel, so a
      // careful spin is never cut short; it resumes the moment they let go.
      _remaining -= dt;
      _countdown.value = (_remaining / _countdownSeconds).clamp(0.0, 1.0);

      // Detent spring toward the nearest slice centre + exponential friction.
      // Reuses the heart-burst language: lightly underdamped, settles clean.
      final target = _nearestCenterAngle();
      final diff = _shortestDelta(_angle.value, target);
      const detentStiffness = 42.0; // pull-to-centre
      const friction = 2.4; // rad/s decay
      _velocity += diff * detentStiffness * dt;
      _velocity *= math.exp(-friction * dt);
      _angle.value = _normalize(_angle.value + _velocity * dt);

      final atRest = _velocity.abs() < 0.05 && diff.abs() < 0.012;
      if (atRest) {
        _angle.value = target;
        _velocity = 0;
        if (!_settled) {
          _settled = true;
          HapticFeedback.selectionClick();
        }
      } else {
        _settled = false;
      }
    }

    if (_remaining <= 0 && !_resolved) {
      // Stop on a slice → that tag. Still spinning → no commitment → null.
      _resolve(_settled ? kOfficialGameTags[_selectedIndex].label : null);
    }
  }

  void _onPanStart(DragStartDetails d) {
    _dragging = true;
    _settled = false;
    _velocity = 0;
  }

  void _onPanUpdate(DragUpdateDetails d, Offset center) {
    // Convert the drag into rotation about the wheel centre: the tangential
    // component of the finger movement spins the wheel.
    final pos = d.localPosition - center;
    final r = pos.distance;
    if (r < 8) return;
    final tangent = Offset(-pos.dy, pos.dx) / r; // unit tangent (clockwise)
    final dTheta = (d.delta.dx * tangent.dx + d.delta.dy * tangent.dy) / r;
    _angle.value = _normalize(_angle.value + dTheta);
    // Track instantaneous velocity for the fling on release.
    final dt = 1 / 60;
    _velocity = dTheta / dt;
    if (!_ticker.isActive && !_reduceMotion) _ticker.start();
  }

  void _onPanEnd(DragEndDetails d) {
    _dragging = false;
    // Clamp absurd flings so it always settles within the countdown.
    _velocity = _velocity.clamp(-22.0, 22.0);
  }

  void _lockNow() {
    HapticFeedback.mediumImpact();
    // Force-settle to the slice currently under the pointer and commit it.
    _angle.value = _nearestCenterAngle();
    _resolve(kOfficialGameTags[_selectedIndex].label);
  }

  void _skip() {
    HapticFeedback.lightImpact();
    _resolve(null);
  }

  void _resolve(String? tag) {
    if (_resolved) return;
    _resolved = true;
    if (_ticker.isActive) _ticker.stop();
    if (tag != null) HapticFeedback.heavyImpact();
    if (mounted) Navigator.of(context).pop(tag);
  }

  @override
  Widget build(BuildContext context) {
    if (_reduceMotion) return _buildReducedMotionFallback();

    final wheelSize = math.min(ResponsiveHelper.screenWidth * 0.84, 360.0.w);

    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          SizedBox(height: 8.h),
          // The wheel is anchored low and clipped to its upper portion so it
          // reads as a rising "half circle" gauge while still rotating as a
          // full detented wheel underneath.
          ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: 0.62,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: _onPanStart,
                onPanUpdate:
                    (d) => _onPanUpdate(
                      d,
                      Offset(wheelSize / 2, wheelSize / 2),
                    ),
                onPanEnd: _onPanEnd,
                onTap: _lockNow,
                child: SizedBox(
                  width: wheelSize,
                  height: wheelSize,
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _WheelPainter(
                        repaint: Listenable.merge([_angle, _countdown]),
                        angle: _angle,
                        countdown: _countdown,
                        iconPainters: _iconPainters,
                        sliceColors: _sliceColors,
                        sliceAngle: _sliceAngle,
                        pointerAngle: _pointerAngle,
                        hubColor: context.colors.surface,
                        ringTrackColor:
                            context.colors.textPrimary.withValues(alpha: 0.12),
                        ringColor: kPrimaryColor,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          _buildLiveLabel(),
          SizedBox(height: 16.h),
          _buildActions(),
          SizedBox(height: 8.h),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Text(
          'Tag this game',
          style: AppTypography.textLgBold.copyWith(
            color: context.colors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          'Spin and let it rest on a slice. Skip to leave it untagged.',
          textAlign: TextAlign.center,
          style: AppTypography.textXsRegular.copyWith(
            color: context.colors.textPrimary.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveLabel() {
    return AnimatedBuilder(
      animation: _angle,
      builder: (context, _) {
        final tag = kOfficialGameTags[_selectedIndex];
        final color = _sliceColors[_selectedIndex];
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(20.br),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tag.icon, size: 16.sp, color: color),
              SizedBox(width: 8.w),
              Text(
                tag.label,
                style: AppTypography.textSmBold.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _skip,
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 14.h),
                decoration: BoxDecoration(
                  color: context.colors.textPrimary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14.br),
                  border: Border.all(
                    color: context.colors.textPrimary.withValues(alpha: 0.1),
                  ),
                ),
                child: Center(
                  child: Text(
                    'Skip',
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: _lockNow,
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 14.h),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kPrimaryColor, kPrimaryColor.withValues(alpha: 0.8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14.br),
                  boxShadow: [
                    BoxShadow(
                      color: kPrimaryColor.withValues(alpha: 0.3),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    'Lock it in',
                    style: AppTypography.textSmBold.copyWith(
                      color: context.colors.textPrimary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Accessibility / low-power path: a plain single-choice chip grid, no motion.
  Widget _buildReducedMotionFallback() {
    return _SheetShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          SizedBox(height: 16.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < kOfficialGameTags.length; i++)
                GestureDetector(
                  onTap: () => _resolve(kOfficialGameTags[i].label),
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: _sliceColors[i].withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20.br),
                      border:
                          Border.all(color: _sliceColors[i].withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          kOfficialGameTags[i].icon,
                          size: 14.sp,
                          color: _sliceColors[i],
                        ),
                        SizedBox(width: 6.w),
                        Text(
                          kOfficialGameTags[i].label,
                          style: AppTypography.textXsMedium.copyWith(
                            color: context.colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 16.h),
          _buildActions(),
          SizedBox(height: 8.h),
        ],
      ),
    );
  }
}

/// Shared dark rounded sheet shell with a drag handle.
class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface.withValues(alpha: 0.98),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.br)),
        border: Border.all(
          color: context.colors.textPrimary.withValues(alpha: 0.06),
        ),
      ),
      padding: EdgeInsets.only(bottom: 16.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: EdgeInsets.symmetric(vertical: 12.h),
            width: 40.w,
            height: 4.h,
            decoration: BoxDecoration(
              color: context.colors.textPrimary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2.br),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({
    required Listenable repaint,
    required this.angle,
    required this.countdown,
    required this.iconPainters,
    required this.sliceColors,
    required this.sliceAngle,
    required this.pointerAngle,
    required this.hubColor,
    required this.ringTrackColor,
    required this.ringColor,
  }) : super(repaint: repaint);

  final ValueNotifier<double> angle;
  final ValueNotifier<double> countdown;
  final List<TextPainter> iconPainters;
  final List<Color> sliceColors;
  final double sliceAngle;
  final double pointerAngle;
  final Color hubColor;
  final Color ringTrackColor;
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final a = angle.value;
    final n = iconPainters.length;

    final localAtPointer = _norm(pointerAngle - a);
    final selected = localAtPointer ~/ sliceAngle % n;

    // ── Slices ──────────────────────────────────────────────────────────
    for (var i = 0; i < n; i++) {
      final start = i * sliceAngle + a;
      final isSelected = i == selected;
      final color = sliceColors[i];

      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = isSelected
            ? color.withValues(alpha: 0.92)
            : color.withValues(alpha: 0.42);

      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..arcTo(
          Rect.fromCircle(center: center, radius: radius),
          start,
          sliceAngle,
          false,
        )
        ..close();
      canvas.drawPath(path, paint);

      // Slice divider.
      final edge = Offset(
        center.dx + radius * math.cos(start),
        center.dy + radius * math.sin(start),
      );
      canvas.drawLine(
        center,
        edge,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.25)
          ..strokeWidth = 1.0,
      );

      // Icon glyph at mid-radius, kept upright.
      final mid = start + sliceAngle / 2;
      final iconR = radius * 0.66;
      final ip = iconPainters[i];
      final pos = Offset(
        center.dx + iconR * math.cos(mid) - ip.width / 2,
        center.dy + iconR * math.sin(mid) - ip.height / 2,
      );
      // Dim unselected icons slightly for focus on the pointer slice.
      final iconOpacity = isSelected ? 1.0 : 0.85;
      canvas.saveLayer(
        Rect.fromCircle(center: pos + Offset(ip.width / 2, ip.height / 2), radius: 18),
        Paint()..color = Colors.white.withValues(alpha: iconOpacity),
      );
      ip.paint(canvas, pos);
      canvas.restore();
    }

    // ── Outer rim ───────────────────────────────────────────────────────
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.black.withValues(alpha: 0.35),
    );

    // ── Hub + countdown ring ────────────────────────────────────────────
    final hubR = radius * 0.26;
    canvas.drawCircle(
      center,
      hubR,
      Paint()
        ..style = PaintingStyle.fill
        ..color = hubColor,
    );
    canvas.drawCircle(
      center,
      hubR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.08),
    );

    final ringR = hubR - 6;
    canvas.drawCircle(
      center,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = ringTrackColor,
    );
    final sweep = 2 * math.pi * countdown.value;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: ringR),
      -math.pi / 2,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = ringColor,
    );

    // ── Top pointer (fixed) ─────────────────────────────────────────────
    final tipY = center.dy - radius + 2;
    final pointer = Path()
      ..moveTo(center.dx, tipY + 18)
      ..lineTo(center.dx - 11, tipY - 4)
      ..lineTo(center.dx + 11, tipY - 4)
      ..close();
    canvas.drawShadow(pointer, Colors.black, 3, false);
    canvas.drawPath(
      pointer,
      Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.white,
    );
  }

  double _norm(double v) {
    final twoPi = 2 * math.pi;
    var r = v % twoPi;
    if (r < 0) r += twoPi;
    return r;
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) => false;
}
