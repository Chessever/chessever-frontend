import 'dart:collection';
import 'dart:math' as math;

import 'package:chessever2/screens/chessboard/game_review/classification_style.dart';
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/screens/my_space/widgets/pixel_art.dart'
    show PixelRandom, kLikesBitmap;
import 'package:chessever2/services/lichess_move_annotations_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

// ------------------------------------------------------------- legibility

/// WCAG 2 contrast of [fg] (composited over [bg] when translucent) on [bg].
double raceContrast(Color fg, Color bg) {
  final solidBg = bg.a >= 1
      ? bg
      : Color.alphaBlend(bg, const Color(0xFF000000));
  final solidFg = fg.a >= 1 ? fg : Color.alphaBlend(fg, solidBg);
  final a = solidFg.computeLuminance();
  final b = solidBg.computeLuminance();
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

final LinkedHashMap<(Color, Color, Color, double), Color> _legibleCache =
    LinkedHashMap();

/// [ink] as it should read on [on]: itself when it clears [min]:1, else the
/// first step toward [toward] (the page's primary ink) that does.
///
/// The race's quiet tones are chosen by hierarchy, not measured. This keeps
/// every one of them readable whatever the theme's tokens are: in light mode
/// the tertiary ink already clears AA on the page, while in dark mode it
/// needs a small lift.
Color raceLegible(
  Color ink, {
  required Color on,
  required Color toward,
  double min = 4.5,
}) {
  final key = (ink, on, toward, min);
  final cached = _legibleCache[key];
  if (cached != null) return cached;
  var result = toward;
  if (raceContrast(ink, on) >= min) {
    result = ink;
  } else {
    for (var step = 1; step <= 20; step++) {
      final candidate = Color.lerp(ink, toward, step / 20)!;
      if (raceContrast(candidate, on) >= min) {
        result = candidate;
        break;
      }
    }
  }
  if (_legibleCache.length > 96) _legibleCache.remove(_legibleCache.keys.first);
  _legibleCache[key] = result;
  return result;
}

/// The race's quiet ink (captions, meta, "of 8"), readable on [on] (the page
/// by default).
Color raceQuietInk(AppColors colors, {Color? on}) => raceLegible(
  colors.textTertiary,
  on: on ?? colors.background,
  toward: colors.textPrimary,
);

/// Solved or missed, as text. Dark keeps the review palette's green and
/// orange (both clear AA on black); on paper those read about 3.3:1, so light
/// mode takes the theme's deepened signal inks.
Color raceVerdictInk(BuildContext context, {required bool solved}) {
  final colors = context.colors;
  final ink = context.isLightTheme
      ? (solved ? colors.successStrong : colors.danger)
      : moveAnnotationColor(
          solved
              ? LichessMoveAnnotationType.bestMove
              : LichessMoveAnnotationType.mistake,
        );
  return raceLegible(ink, on: colors.background, toward: colors.textPrimary);
}

/// Puzzle Race's own marks, in the Feed's glyph style: authored in white on
/// a 24 grid, 1.7 strokes with round caps, tinted by [FeedGlyph].
abstract final class RaceGlyphs {
  /// A knight at full gallop: the Feed's way into a race.
  ///
  /// The outline knight faces left on its plinth, as the board's own
  /// knight does: two ears with a notch between them, a forehead running
  /// down to the muzzle, the throat cut in under the jaw. Three speed
  /// strokes trail off its back, so the mark says chess and hurry at once.
  /// The eye sits a full stroke clear of the jaw and forehead, so it stays
  /// a separate dot at the header's 22dp on a 2x screen. It keeps the
  /// speaker's 1.7 stroke, so the two header marks carry one weight, and
  /// sits a hair above the box's centre because the plinth pulls the eye
  /// down.
  static const rush =
      '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M8.6 18.7C8.6 16.2 11.2 15.2 11 12C9.5 12.8 7.4 14.5 5.5 14.8'
      'C4.3 15 3.3 14.2 3.6 12.9C4.1 11.1 5.7 9 7.1 7.5L7.5 4.9L9 6.9'
      'L10.4 4.8C14.1 6.5 15.7 11.4 15.6 18.7" stroke="#FFFFFF" '
      'stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>'
      '<circle cx="8.1" cy="10.6" r=".9" fill="#FFFFFF"/>'
      '<path d="M6.8 18.7H17.4M17.2 9.2H19.2M18 12.2H20.6M18.3 15.2H20.1" '
      'stroke="#FFFFFF" stroke-width="1.7" stroke-linecap="round"/></svg>';

  /// Back to where you came from.
  static const back =
      '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M14.6 5.4L8 12l6.6 6.6" stroke="#FFFFFF" stroke-width="1.9" '
      'stroke-linecap="round" stroke-linejoin="round"/></svg>';

  /// Ends the run: the same stroke as [back], crossed.
  static const close =
      '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M6.6 6.6l10.8 10.8M17.4 6.6L6.6 17.4" stroke="#FFFFFF" '
      'stroke-width="1.9" stroke-linecap="round"/></svg>';

  /// A small onward chevron for text links.
  static const onward =
      '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M9.4 5.4L16 12l-6.6 6.6" stroke="#FFFFFF" stroke-width="2.2" '
      'stroke-linecap="round" stroke-linejoin="round"/></svg>';
}

/// The way out, always in the top-left corner and always named: a glyph and
/// a word ("Feed", "Leave", "End"). At least 44x44, and pressed it settles
/// to 0.97 on a spring (a tonal step instead when motion is reduced).
class RaceBackControl extends StatefulWidget {
  const RaceBackControl({
    required this.glyph,
    required this.label,
    required this.onTap,
    this.semanticsLabel,
    super.key,
  });

  final String glyph;
  final String label;
  final String? semanticsLabel;
  final VoidCallback? onTap;

  static const double _glyphSize = 22;
  static const double _glyphGap = 2;
  static const EdgeInsets _padding = EdgeInsets.only(left: 2, right: 12);

  static TextStyle _labelStyle(Color ink) => AppTypography.textSmBold.copyWith(
    fontSize: 16,
    height: 22 / 16,
    fontWeight: FontWeight.w600,
    color: ink,
  );

  /// How wide the control is with [label] at the current text size, for a
  /// bar that balances its other side against it.
  static double widthFor(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: DefaultTextStyle.of(
          context,
        ).style.merge(_labelStyle(const Color(0xFF000000))),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return math.max(
      44,
      _padding.horizontal + _glyphSize + _glyphGap + width.ceilToDouble(),
    );
  }

  @override
  State<RaceBackControl> createState() => _RaceBackControlState();
}

class _RaceBackControlState extends State<RaceBackControl> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = widget.onTap != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final ink = !enabled
        ? raceQuietInk(colors)
        : _pressed && reduceMotion
        ? Color.lerp(colors.textPrimary, colors.textSecondary, 0.45)!
        : colors.textPrimary;
    final face = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      child: Padding(
        padding: RaceBackControl._padding,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FeedGlyph(
              widget.glyph,
              width: RaceBackControl._glyphSize,
              height: RaceBackControl._glyphSize,
              color: ink,
            ),
            const SizedBox(width: RaceBackControl._glyphGap),
            Text(
              widget.label,
              maxLines: 1,
              softWrap: false,
              style: RaceBackControl._labelStyle(ink),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticsLabel ?? widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTap: widget.onTap,
        child: reduceMotion
            ? face
            : SingleMotionBuilder(
                value: _pressed && enabled ? 0.97 : 1.0,
                motion: const CupertinoMotion.snappy(
                  duration: Duration(milliseconds: 220),
                ),
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: face,
              ),
      ),
    );
  }
}

/// The top of a race view: the way out in the corner, anything that acts on
/// the whole view at the other end, and the view's title under them, set
/// large on its own line so neither ever squeezes the other.
class RaceHeader extends StatelessWidget {
  const RaceHeader({required this.back, this.title, this.trailing, super.key});

  final Widget back;

  /// Usually a [RaceTitle].
  final Widget? title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    final trailing = this.trailing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Left 7: the back chevron's tip then sits on the 16 content line.
        Padding(
          padding: const EdgeInsets.only(left: 7, right: 6, top: 4),
          child: Row(children: [back, const Spacer(), ?trailing]),
        ),
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
            child: title,
          ),
      ],
    );
  }
}

/// A race view's title: one line at the sizes a phone allows, two at most.
class RaceTitle extends StatelessWidget {
  const RaceTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Text(
        text,
        maxLines: 2,
        style: AppTypography.displayXsBold.copyWith(
          fontSize: 28,
          height: 34 / 28,
          color: context.colors.textPrimary,
        ),
      ),
    );
  }
}

/// A quiet line that opens something ("Sign in to keep your flames"): the
/// secondary ink with a small chevron, 44 tall. A press darkens it to the
/// primary ink; nothing grows or underlines.
class RaceTextLink extends StatefulWidget {
  const RaceTextLink({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback? onTap;

  @override
  State<RaceTextLink> createState() => _RaceTextLinkState();
}

class _RaceTextLinkState extends State<RaceTextLink> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = _pressed
        ? colors.textPrimary
        : raceLegible(
            colors.textSecondary,
            on: colors.background,
            toward: colors.textPrimary,
          );
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapCancel: () => _setPressed(false),
        onTapUp: (_) => _setPressed(false),
        onTap: widget.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  widget.label,
                  style: AppTypography.textSmBold.copyWith(
                    fontSize: 14,
                    height: 20 / 14,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              FeedGlyph(RaceGlyphs.onward, width: 14, height: 14, color: ink),
              // A little run past the chevron, so the target is wider than
              // the words it carries.
              const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }
}

/// A player's name on one line, with " (you)" after it on this player's own
/// row. A long name gives way so "(you)" stays whole; only where the suffix
/// itself would take most of the room (the largest text in the narrowest
/// column) does the whole line shorten instead.
class RaceNameLine extends StatelessWidget {
  const RaceNameLine({
    required this.name,
    required this.isMe,
    required this.style,
    super.key,
  });

  final String name;
  final bool isMe;
  final TextStyle style;

  static const String _suffix = ' (you)';

  @override
  Widget build(BuildContext context) {
    Widget whole(String text) =>
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    if (!isMe) return whole(name);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedWidth) return whole('$name$_suffix');
        final painter = TextPainter(
          text: TextSpan(
            text: _suffix,
            style: DefaultTextStyle.of(context).style.merge(style),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final suffixWidth = painter.width;
        painter.dispose();
        if (suffixWidth > constraints.maxWidth * 0.6) {
          return whole('$name$_suffix');
        }
        return Row(
          children: [
            Flexible(child: whole(name)),
            Text(_suffix, maxLines: 1, softWrap: false, style: style),
          ],
        );
      },
    );
  }
}

/// A 44x44 glyph control, like the Feed header's. Pressed, the glyph settles
/// to 0.97 on a spring (a tonal step instead when motion is reduced).
class RaceIconButton extends StatefulWidget {
  const RaceIconButton({
    required this.glyph,
    required this.label,
    required this.onTap,
    this.color,
    this.toggled,
    this.hint,
    super.key,
  });

  final String glyph;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  /// For an on/off control (the speaker): read out as a toggle.
  final bool? toggled;

  /// Why the control reads the way it does, when its label cannot say.
  final String? hint;

  @override
  State<RaceIconButton> createState() => _RaceIconButtonState();
}

class _RaceIconButtonState extends State<RaceIconButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = widget.onTap != null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final base = widget.color ?? colors.textPrimary;
    final ink = !enabled
        ? raceQuietInk(colors)
        : _pressed && reduceMotion
        ? Color.lerp(base, colors.textSecondary, 0.45)!
        : base;
    final face = SizedBox(
      width: 44,
      height: 44,
      child: Center(
        child: FeedGlyph(widget.glyph, width: 22, height: 22, color: ink),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      toggled: widget.toggled,
      label: widget.label,
      hint: widget.hint,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTap: widget.onTap,
        child: reduceMotion
            ? face
            : SingleMotionBuilder(
                value: _pressed && enabled ? 0.97 : 1.0,
                motion: const CupertinoMotion.snappy(
                  duration: Duration(milliseconds: 220),
                ),
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: face,
              ),
      ),
    );
  }
}

/// How a [RaceButton] reads.
enum RaceButtonTone {
  /// Ink on the page colour: the one forward action.
  primary,

  /// A tonal step off the page.
  tonal,
}

/// Flat 48px button, 4px corners. A press settles it to 0.97 on a spring and
/// shifts its fill a tone; nothing glows. A null [onTap] dims it.
class RaceButton extends StatefulWidget {
  const RaceButton({
    required this.label,
    required this.onTap,
    this.tone = RaceButtonTone.tonal,
    this.semanticsLabel,
    this.height = 48,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final RaceButtonTone tone;
  final String? semanticsLabel;
  final double height;

  @override
  State<RaceButton> createState() => _RaceButtonState();
}

class _RaceButtonState extends State<RaceButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = widget.onTap != null;
    final primary = widget.tone == RaceButtonTone.primary;
    final base = primary ? colors.textPrimary : colors.surfaceRecessed;
    // A disabled button still says what it is doing ("Starting"), so its
    // label keeps AA on the recessed slab.
    final ink = !enabled
        ? raceLegible(
            colors.textSecondary,
            on: colors.surfaceRecessed,
            toward: colors.textPrimary,
          )
        : primary
        ? colors.background
        : colors.textPrimary;
    final fill = !enabled && primary
        ? colors.surfaceRecessed
        : _pressed && enabled
        ? Color.lerp(base, ink, 0.12)!
        : base;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final face = Container(
      height: widget.height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(4),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          widget.label,
          maxLines: 1,
          style: AppTypography.textSmMedium.copyWith(
            fontSize: 15,
            height: 20 / 15,
            fontWeight: primary ? FontWeight.w700 : FontWeight.w600,
            color: ink,
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticsLabel ?? widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _setPressed(true) : null,
        onTapCancel: enabled ? () => _setPressed(false) : null,
        onTapUp: enabled ? (_) => _setPressed(false) : null,
        onTap: widget.onTap,
        child: reduceMotion
            ? face
            : SingleMotionBuilder(
                value: _pressed && enabled ? 0.97 : 1.0,
                motion: const CupertinoMotion.snappy(
                  duration: Duration(milliseconds: 220),
                ),
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: face,
              ),
      ),
    );
  }
}

/// Survival's lives: pixel-block hearts in the My Space pixel language (the
/// Likes door's heart bitmap, the same block gap, corner and opacity
/// jitter). A lost heart breaks: its blocks drop a little and go dark, and
/// stay as a ghost outline so the three slots never move.
class RaceHearts extends StatelessWidget {
  const RaceHearts({
    required this.total,
    required this.left,
    this.size = 20,
    this.gap = 6,
    super.key,
  });

  final int total;
  final int left;

  /// One heart's width.
  final double size;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final n = math.max(0, total);
    return Semantics(
      label: left == 1 ? '1 life left' : '$left lives left',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < n; i++) ...[
            if (i > 0) SizedBox(width: gap),
            _PixelHeart(
              seed: i,
              alive: i < left,
              size: size,
              fill: colors.danger,
              // An empty slot is still a slot: its outline clears 3:1.
              ghost: raceLegible(
                colors.textPrimary.withValues(alpha: 0.16),
                on: colors.background,
                toward: colors.textPrimary,
                min: 3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PixelHeart extends StatelessWidget {
  const _PixelHeart({
    required this.seed,
    required this.alive,
    required this.size,
    required this.fill,
    required this.ghost,
  });

  final int seed;
  final bool alive;
  final double size;
  final Color fill;
  final Color ghost;

  static const int _cols = 11;
  static const int _rows = 10;

  @override
  Widget build(BuildContext context) {
    final height = size * _rows / _cols;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final pixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    Widget paint(double broken) => CustomPaint(
      size: Size(size, height),
      painter: _PixelHeartPainter(
        seed: seed,
        broken: broken,
        fill: fill,
        ghost: ghost,
        pixelRatio: pixelRatio,
      ),
    );
    if (reduceMotion) return paint(alive ? 0 : 1);
    return SingleMotionBuilder(
      value: alive ? 0.0 : 1.0,
      motion: const CupertinoMotion.smooth(
        duration: Duration(milliseconds: 420),
        snapToEnd: true,
      ),
      builder: (context, t, _) => paint(t.clamp(0.0, 1.0)),
    );
  }
}

class _PixelHeartPainter extends CustomPainter {
  _PixelHeartPainter({
    required this.seed,
    required this.broken,
    required this.fill,
    required this.ghost,
    required this.pixelRatio,
  });

  final int seed;

  /// 0 = whole, 1 = lost (ghost outline).
  final double broken;
  final Color fill;
  final Color ghost;
  final double pixelRatio;

  /// Below this width a cell is under ~1.3pt: the block gaps and the alpha
  /// grain blend into a faded mesh (about 2.3:1 on the page), so the heart
  /// is drawn as one solid shape instead.
  static const double _solidBelow = 14;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < _solidBelow) {
      _paintSolid(canvas, size);
      return;
    }
    final bitmap = kLikesBitmap;
    final cols = bitmap.first.length;
    final unit = size.width / cols;
    final gap = unit * 0.16;
    final radius = Radius.circular(unit * 0.12);
    final side = unit - gap;
    final rnd = PixelRandom.forKey('race-heart-$seed');
    final paint = Paint()..isAntiAlias = true;
    // The drop peaks mid-break and settles back, so the ghost sits in the
    // heart's own slot.
    final drop = math.sin(broken * math.pi) * unit * 0.9;
    for (var r = 0; r < bitmap.length; r++) {
      final row = bitmap[r];
      for (var c = 0; c < row.length; c++) {
        if (row[c] == '.') continue;
        final jitter = rnd.next();
        final edge = _isEdge(bitmap, r, c);
        final whole = fill.withValues(alpha: 0.78 + jitter * 0.22);
        // The ghost keeps only the outline, so a lost life reads as empty.
        final lost = edge ? ghost : ghost.withValues(alpha: 0);
        paint.color = Color.lerp(whole, lost, broken)!;
        if (paint.color.a <= 0.001) continue;
        final fall = drop * (0.4 + (c % 3) * 0.3);
        final origin = Offset(c * unit + gap / 2, r * unit + gap / 2 + fall);
        canvas.drawRRect(
          RRect.fromRectAndRadius(origin & Size(side, side), radius),
          paint,
        );
      }
    }
  }

  /// The small heart: no block gap and no grain, every cell at full ink and
  /// snapped to device pixels, merged into one path per ink so no seam or
  /// half-covered pixel lightens the shape. Whole, it is [fill] at full
  /// alpha, which clears 3:1 on the page in both themes; lost, only its
  /// outline remains, in [ghost].
  void _paintSolid(Canvas canvas, Size size) {
    final bitmap = kLikesBitmap;
    final cols = bitmap.first.length;
    final unit = size.width / cols;
    final ratio = pixelRatio > 0 ? pixelRatio : 1.0;
    double snap(double v) => (v * ratio).roundToDouble() / ratio;
    final drop = math.sin(broken * math.pi) * unit * 0.9;
    final whole = Color.lerp(fill, ghost, broken)!;
    final inner = Color.lerp(fill, ghost.withValues(alpha: 0), broken)!;
    final edges = Path();
    final core = Path();
    for (var r = 0; r < bitmap.length; r++) {
      final row = bitmap[r];
      for (var c = 0; c < row.length; c++) {
        if (row[c] == '.') continue;
        final fall = drop * (0.4 + (c % 3) * 0.3);
        final cell = Rect.fromLTRB(
          snap(c * unit),
          snap(r * unit) + fall,
          snap((c + 1) * unit),
          snap((r + 1) * unit) + fall,
        );
        // Resting, both inks are the same: one path, one fill, no seam.
        final target = broken == 0 || _isEdge(bitmap, r, c) ? edges : core;
        target.addRect(cell);
      }
    }
    final paint = Paint()..isAntiAlias = true;
    if (inner.a > 0.001) {
      canvas.drawPath(core, paint..color = inner);
    }
    if (whole.a > 0.001) {
      canvas.drawPath(edges, paint..color = whole);
    }
  }

  static bool _isEdge(List<String> bitmap, int r, int c) {
    bool filled(int rr, int cc) =>
        rr >= 0 &&
        rr < bitmap.length &&
        cc >= 0 &&
        cc < bitmap[rr].length &&
        bitmap[rr][cc] != '.';
    return !filled(r - 1, c) ||
        !filled(r + 1, c) ||
        !filled(r, c - 1) ||
        !filled(r, c + 1);
  }

  @override
  bool shouldRepaint(_PixelHeartPainter old) =>
      old.broken != broken ||
      old.seed != seed ||
      old.fill != fill ||
      old.ghost != ghost ||
      old.pixelRatio != pixelRatio;
}

/// The race's frame: four corner brackets that reach further along each
/// edge as the level climbs, until at level 13 they meet and the frame is
/// closed. Round caps, a 4px bend; tone, not glow.
class RaceFramePainter extends CustomPainter {
  RaceFramePainter({
    required this.reach,
    required this.color,
    this.strokeWidth = 2,
    this.inset = 1,
  });

  /// 0..1: how far each bracket reaches toward the middle of its edges.
  final double reach;
  final Color color;
  final double strokeWidth;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(inset + strokeWidth / 2);
    if (rect.width <= 0 || rect.height <= 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    const bend = 4.0;
    final t = reach.clamp(0.0, 1.0);
    final armX = math.max(14.0, t * rect.width / 2);
    final armY = math.max(14.0, t * rect.height / 2);

    // All four brackets go into ONE path and ONE drawPath. At reach 1 the
    // neighbouring arms end on the same edge midpoint, and on a small rect
    // they overlap earlier; stroked as separate paths their round caps
    // stacked there, so a translucent tone (the miss flash, the last-life
    // red) double-blended into brighter nubs. One path strokes a single
    // outline, so every pixel is covered once.
    final path = Path();
    void corner(Offset at, double dx, double dy) {
      path
        ..moveTo(at.dx + dx * armX, at.dy)
        ..lineTo(at.dx + dx * bend, at.dy)
        ..quadraticBezierTo(at.dx, at.dy, at.dx, at.dy + dy * bend)
        ..lineTo(at.dx, at.dy + dy * armY);
    }

    corner(rect.topLeft, 1, 1);
    corner(rect.topRight, -1, 1);
    corner(rect.bottomLeft, 1, -1);
    corner(rect.bottomRight, -1, -1);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(RaceFramePainter old) =>
      old.reach != reach ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.inset != inset;
}

/// How far the frame's brackets reach at [displayLevel].
double raceFrameReach(int displayLevel) =>
    0.08 + 0.92 * ((displayLevel - 1) / 12).clamp(0.0, 1.0);

/// The frame's resting tone at [displayLevel]: tonal steps up from the
/// divider to the ink as the race climbs. On [paper] (light mode) the divider
/// all but vanishes into the mint page, so the steps start from the tertiary
/// ink and darken from there; every one clears 3:1.
Color raceFrameTone(AppColors colors, int displayLevel, {bool paper = false}) {
  if (paper) {
    if (displayLevel >= 13) return colors.textPrimary.withValues(alpha: 0.9);
    if (displayLevel >= 10) return colors.titleAccent;
    if (displayLevel >= 7) return colors.textSecondary;
    if (displayLevel >= 4) return colors.textTertiary;
    return colors.textTertiary.withValues(alpha: 0.8);
  }
  if (displayLevel >= 13) return colors.textPrimary.withValues(alpha: 0.9);
  if (displayLevel >= 10) return colors.titleAccent.withValues(alpha: 0.8);
  if (displayLevel >= 7) return colors.textSecondary;
  if (displayLevel >= 4) return colors.textTertiary;
  return colors.dividerStrong;
}
