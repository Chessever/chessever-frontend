import 'dart:math' as math;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/widgets/glass_surface.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

/// What turning Live first on does to the list it floats over, so the
/// capsule can say it in words.
enum LiveFirstMode {
  /// The live ones lead and every other one stays listed (an event's Games,
  /// Favorites, Countrymen, Today, Events): "Live first" while on.
  reorder,

  /// Only the live ones are listed; the others are hidden until it is
  /// turned off: "Live only" while on. No list does this today.
  liveOnly,
}

/// Live first, floating, in words: a capsule of the floating buttons' glass
/// ([GlassSurface]) that says what it does instead of asking the reader to
/// decode a glyph.
///
/// Off, a small still live dot and a verb: "See 3 live", or "See live"
/// while the count is unknown. On, the glass takes a breath of the brand's
/// tonal blue, the dot draws itself into a check, and the capsule names the
/// order in force, as a sort option would: "Live first" where the live ones
/// only lead ([LiveFirstMode.reorder]), "Live only" where the others are
/// hidden ([LiveFirstMode.liveOnly]). What is read aloud says the same, and
/// what a second tap does: back to the usual order, or back to every game.
///
/// Between the two, and when the count gains or loses a digit, the width
/// springs (motor) and the words crossfade in place; with reduced motion both
/// snap. Words are only drawn where the glass already covers them: while
/// the spring is still making room for a wider label, that label waits,
/// faded, so nothing ever reaches past the rim. Whatever the motion does,
/// the capsule at rest always shows its one label at full strength.
///
/// It is as tall as the floating button of [size] (the small disc above a
/// page's search by default) and answers touches over at least 44pt.
class LiveFirstCapsule extends StatelessWidget {
  const LiveFirstCapsule({
    super.key,
    required this.on,
    required this.onTap,
    this.liveCount,
    this.subject = 'games',
    this.size = InkFabSize.small,
    this.mode = LiveFirstMode.reorder,
  });

  /// Whether live items are shown first right now.
  final bool on;

  /// Flips Live first. The capsule plays the toggle haptic itself.
  final VoidCallback onTap;

  /// How many are live, when the page knows. Null (or 0) reads "See live".
  final int? liveCount;

  /// What comes first, plural: "games" or "events". Only read aloud; the
  /// visible words stay short.
  final String subject;

  /// Which floating button the capsule matches in height: small above a
  /// page's search, regular when it is the page's main button.
  final InkFabSize size;

  /// What on does to the list: reorder it (the default) or hide what is not
  /// live. Sets the words while on and what is read aloud.
  final LiveFirstMode mode;

  /// The label's width and the on/off change: quick, with a hair of bounce.
  static const CupertinoMotion motion = CupertinoMotion.snappy(
    duration: Duration(milliseconds: 380),
    snapToEnd: true,
  );

  /// The words while on, where the live ones only lead.
  static const String onLabel = 'Live first';

  /// The words while on, where everything not live is hidden.
  static const String liveOnlyLabel = 'Live only';

  /// The words while off with no count: the verb, as with a count.
  static const String unknownLabel = 'See live';

  /// The capsule's height is fixed, so its words stop growing here.
  static const double maxTextScale = 1.3;

  /// How strongly the glass takes the brand's tonal blue while on: the
  /// floating buttons' own "on" tint.
  static const double onTintAlpha = 0.16;

  /// A wide capsule shrinks less than a disc for the same felt press.
  static const double _pressedScale = 0.94;

  /// The words while on, for [mode].
  static String onLabelFor(LiveFirstMode mode) => switch (mode) {
    LiveFirstMode.reorder => onLabel,
    LiveFirstMode.liveOnly => liveOnlyLabel,
  };

  /// The visible words for [on] and [liveCount]: off, a verb and how many
  /// ("See 3 live"); on, the order in force for [mode].
  static String labelFor({
    required bool on,
    int? liveCount,
    LiveFirstMode mode = LiveFirstMode.reorder,
  }) {
    if (on) return onLabelFor(mode);
    final count = liveCount;
    if (count == null || count <= 0) return unknownLabel;
    return 'See ${countText(count)} live';
  }

  /// A count as the capsule draws it: capped so a huge open cannot stretch
  /// the capsule across the screen.
  static String countText(int count) => count > 999 ? '999+' : '$count';

  /// What a screen reader announces: off, what a tap does; on, what is in
  /// force.
  static String semanticsLabelFor({
    required bool on,
    int? liveCount,
    String subject = 'games',
    LiveFirstMode mode = LiveFirstMode.reorder,
  }) {
    final count = liveCount;
    final known = count != null && count > 0;
    switch (mode) {
      case LiveFirstMode.reorder:
        if (on) return 'Live $subject shown first';
        if (!known) return 'Show live $subject first';
        if (count == 1) return 'Show the live ${_singular(subject)} first';
        return 'Show the $count live $subject first';
      case LiveFirstMode.liveOnly:
        if (on) return 'Only live $subject shown';
        if (!known) return 'Show only live $subject';
        if (count == 1) return 'Show only the live ${_singular(subject)}';
        return 'Show only the $count live $subject';
    }
  }

  /// The hint read after the label while on, where the label says what is,
  /// not what a tap does: back to the usual order where nothing was hidden,
  /// back to every one where the rest was. Off, the label is the action.
  static String? semanticsHintFor({
    required bool on,
    String subject = 'games',
    LiveFirstMode mode = LiveFirstMode.reorder,
  }) {
    if (!on) return null;
    return switch (mode) {
      LiveFirstMode.reorder => 'Double tap to restore the usual order',
      LiveFirstMode.liveOnly => 'Double tap to show all $subject',
    };
  }

  static String _singular(String subject) =>
      subject.length > 1 && subject.endsWith('s')
      ? subject.substring(0, subject.length - 1)
      : subject;

  /// The words' style, before colour.
  static TextStyle textStyleOf(BuildContext context) {
    var style = DefaultTextStyle.of(context).style.merge(
      AppTypography.textSmMedium.copyWith(
        // A tight line with even leading, so the words sit on the capsule's
        // centre rather than riding high on a tall line box.
        height: 1.2,
        leadingDistribution: TextLeadingDistribution.even,
        letterSpacing: 0,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    return style;
  }

  /// The width the capsule settles at for [label]: its chrome plus the words.
  static double widthFor(BuildContext context, String label, InkFabSize size) =>
      _Metrics(size.disc).settledWidth(_wordsWidth(context, label));

  /// How wide [label]'s words are drawn, rounded up to a whole point.
  static double _wordsWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: textStyleOf(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(
        context,
      ).clamp(maxScaleFactor: maxTextScale),
      maxLines: 1,
    )..layout();
    final words = painter.width.ceilToDouble();
    painter.dispose();
    return words;
  }

  void _activate() {
    HapticFeedbackService.toggle();
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final metrics = _Metrics(size.disc);
    final glass = GlassStyle.of(context);
    final accent = context.colors.accentText;
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: maxTextScale);
    final textStyle = textStyleOf(context);
    final offText = labelFor(on: false, liveCount: liveCount);
    final onText = onLabelFor(mode);
    final offWidth = _wordsWidth(context, offText);
    final onWidth = _wordsWidth(context, onText);
    final width = metrics.settledWidth(on ? onWidth : offWidth);

    Widget words(String text, Color color, String key) => Text(
      text,
      key: ValueKey<String>('live_first_capsule_$key'),
      maxLines: 1,
      softWrap: false,
      textScaler: scaler,
      style: textStyle.copyWith(color: color),
    );

    return Semantics(
      container: true,
      button: true,
      toggled: on,
      enabled: true,
      label: semanticsLabelFor(
        on: on,
        liveCount: liveCount,
        subject: subject,
        mode: mode,
      ),
      hint: semanticsHintFor(on: on, subject: subject, mode: mode),
      onTap: _activate,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _activate,
        child: SingleMotionBuilder(
          motion: motion,
          value: width,
          active: !reduce,
          builder: (context, springWidth, _) {
            final glassWidth = math.max(springWidth, metrics.height);
            return SizedBox(
              width: glassWidth,
              height: size.side,
              child: SingleMotionBuilder(
                motion: motion,
                value: on ? 1.0 : 0.0,
                active: !reduce,
                builder: (context, raw, _) {
                  final t = raw.clamp(0.0, 1.0);
                  // One label at a time: the leaving words are gone before
                  // the arriving ones show, so the two never overlap into a
                  // smudge. On top of that each label shows only as far as
                  // the glass covers it at this width ([_Metrics.fit]): a
                  // count that gains digits, or a wider label arriving,
                  // waits faded until the spring has made room, instead of
                  // poking past the rim. At rest the glass fits its label,
                  // so one of them is at full strength.
                  final offOpacity =
                      (1 - t / 0.45).clamp(0.0, 1.0) *
                      metrics.fit(glassWidth, offWidth);
                  final onOpacity =
                      ((t - 0.5) / 0.5).clamp(0.0, 1.0) *
                      metrics.fit(glassWidth, onWidth);
                  final content = OverflowBox(
                    // The words keep their own width while the capsule
                    // springs toward it; [_Metrics.fit] above keeps any
                    // that the glass does not cover yet out of sight.
                    alignment: AlignmentDirectional.centerStart,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    child: Padding(
                      padding: EdgeInsetsDirectional.only(start: metrics.lead),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CustomPaint(
                            size: Size.square(metrics.mark),
                            painter: _LiveMarkPainter(
                              progress: t,
                              color: accent,
                            ),
                          ),
                          SizedBox(width: metrics.gap),
                          Stack(
                            alignment: AlignmentDirectional.centerStart,
                            children: [
                              if (offOpacity > 0)
                                Opacity(
                                  opacity: offOpacity,
                                  child: words(offText, glass.ink, 'off'),
                                ),
                              if (onOpacity > 0)
                                Opacity(
                                  opacity: onOpacity,
                                  child: words(onText, accent, 'on'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                  return Center(
                    child: SizedBox(
                      height: metrics.height,
                      width: double.infinity,
                      // The app's press, as on every floating button: down
                      // under the finger, back with a little pop, the glass
                      // brightening while held.
                      child: PressSpring(
                        pressedScale: _pressedScale,
                        child: content,
                        builder: (context, press, child) {
                          final scale = 1 - (1 - _pressedScale) * press;
                          return Transform.scale(
                            scale: (scale - 1).abs() < 0.001 ? 1.0 : scale,
                            child: GlassSurface(
                              borderRadius: BorderRadius.circular(
                                metrics.height / 2,
                              ),
                              tint: t > 0
                                  ? accent.withValues(alpha: onTintAlpha * t)
                                  : null,
                              lift: press.clamp(0.0, 1.0),
                              child: child,
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The capsule's chrome, scaled with its height (44 at the base phone).
class _Metrics {
  _Metrics(this.height) : _k = height / 44;

  final double height;
  final double _k;

  /// Before the mark. With the dot inset in its box, the dot's edge sits as
  /// far from the rim as the words' end does on the other side.
  double get lead => 14 * _k;

  /// After the words.
  double get trail => 16 * _k;

  /// The dot / check box.
  double get mark => 11 * _k;

  /// Between the mark and the words.
  double get gap => 6 * _k;

  double get chrome => lead + mark + gap + trail;

  /// The width the capsule settles at for words [words] wide.
  double settledWidth(double words) => math.max(height, chrome + words);

  /// Words end at least this far inside the rim to be drawn at full
  /// strength: well clear of the capsule's rounded end, with room for the
  /// spring's last hair of undershoot so a settling label never flickers.
  double get _clearFull => 10 * _k;

  /// Words this close to the rim, or past it, are not drawn at all.
  double get _clearNone => 4 * _k;

  /// How strongly words [words] wide may be drawn on glass [glassWidth]
  /// wide: 1 while they end at least [_clearFull] inside the rim, fading to
  /// 0 by [_clearNone]. At a label's settled width it ends [trail] inside,
  /// so a capsule at rest always draws its label whole.
  double fit(double glassWidth, double words) {
    final clearance = glassWidth - (lead + mark + gap + words);
    return ((clearance - _clearNone) / (_clearFull - _clearNone)).clamp(
      0.0,
      1.0,
    );
  }
}

/// The live dot drawing itself into a check: one mark, never two. At 0 a
/// still dot in the middle of its box. Up to [_slide] the dot slides to the
/// check's foot and narrows to the stroke's width, so it becomes the round
/// cap the check is drawn from; past it the stroke runs out from there. Run
/// backwards, the check winds back into its foot and the dot rolls home.
class _LiveMarkPainter extends CustomPainter {
  const _LiveMarkPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  /// The share of the change spent turning the dot into the pen.
  static const double _slide = 0.35;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    // On a 12 grid, centred on the box both ways once the round caps are
    // counted.
    final unit = side / 12;
    final origin = Offset((size.width - side) / 2, (size.height - side) / 2);
    Offset at(double x, double y) => origin + Offset(x * unit, y * unit);
    final foot = at(1.5, 6.1);
    final stroke = unit * 1.9;
    final fill = Paint()..color = color;

    if (progress <= _slide) {
      final p = progress / _slide;
      canvas.drawCircle(
        Offset.lerp(size.center(Offset.zero), foot, p)!,
        // The dot: 0.3 of the box across its radius, down to the cap's.
        _lerp(side * 0.3, stroke / 2, p),
        fill,
      );
      return;
    }

    final check = Path()
      ..moveTo(foot.dx, foot.dy)
      ..lineTo(at(4.7, 9.2).dx, at(4.7, 9.2).dy)
      ..lineTo(at(10.5, 2.9).dx, at(10.5, 2.9).dy);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final draw = ((progress - _slide) / (1 - _slide)).clamp(0.0, 1.0);
    if (draw >= 1) {
      canvas.drawPath(check, pen);
      return;
    }
    // The pen at rest on the foot, then the stroke running out from it.
    canvas.drawCircle(foot, stroke / 2, fill);
    final contour = check.computeMetrics().first;
    canvas.drawPath(contour.extractPath(0, contour.length * draw), pen);
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  @override
  bool shouldRepaint(_LiveMarkPainter old) =>
      old.progress != progress || old.color != color;
}
