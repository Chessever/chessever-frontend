import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/chessboard/utils/legible_ink.dart';
import 'package:chessever2/screens/my_space/widgets/space_glyphs.dart';
import 'package:chessever2/screens/streaks/widgets/wall_common.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';

/// Side gutter of every Discovery section: the hub pages' one gutter
/// ([hubGutter]), so Discovery and My Space start on the same edge.
double get discoveryGutter => hubGutter;

/// InterDisplay at an exact size and line, the same way the streak wall and
/// My Space set theirs. Sections reach it through [discoveryType], never
/// with a size of their own.
TextStyle discoveryText(
  BuildContext context, {
  required double size,
  required double line,
  FontWeight weight = FontWeight.w500,
  Color? color,
  bool tabular = false,
}) {
  return AppTypography.textSmMedium.copyWith(
    fontSize: size.f,
    height: line / size,
    fontWeight: weight,
    color: color ?? context.colors.textPrimary,
    fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
  );
}

/// Discovery's whole type scale. Five steps and no others:
///
/// * [display]: a streak's run length, the one big figure on a tile.
/// * [title]: a section title. Always one line.
/// * [body]: names and tile titles.
/// * [label]: tabs, actions and the date between the stepper arrows.
/// * [meta]: everything that is information about a thing (a card's rank
///   and likes, a miniature's length, a rating, a date).
enum DiscoveryType { display, title, body, label, meta }

/// The style of one [DiscoveryType] step. [weight] and [color] adjust within
/// the step (a selected tab, an action's accent ink); figures pass [tabular]
/// so a count never shifts the line it sits in.
TextStyle discoveryType(
  BuildContext context,
  DiscoveryType type, {
  Color? color,
  FontWeight? weight,
  bool tabular = false,
}) {
  final colors = context.colors;
  final (size, line, base, ink, spacing) = switch (type) {
    DiscoveryType.display => (
      28.0,
      30.0,
      FontWeight.w700,
      colors.textPrimary,
      0.0,
    ),
    DiscoveryType.title => (
      17.0,
      22.0,
      FontWeight.w700,
      colors.textPrimary,
      -0.2,
    ),
    DiscoveryType.body => (
      14.0,
      20.0,
      FontWeight.w600,
      colors.textPrimary,
      0.0,
    ),
    DiscoveryType.label => (
      13.0,
      18.0,
      FontWeight.w500,
      colors.textPrimary,
      0.0,
    ),
    DiscoveryType.meta => (
      12.0,
      16.0,
      FontWeight.w500,
      colors.textSecondary,
      0.0,
    ),
  };
  final style = discoveryText(
    context,
    size: size,
    line: line,
    weight: weight ?? base,
    color: color ?? ink,
    tabular: tabular || type == DiscoveryType.display,
  );
  return spacing == 0 ? style : style.copyWith(letterSpacing: spacing);
}

/// "1184" -> "1,184 likes", "1" -> "1 like".
String discoveryLikes(int n) => n == 1 ? '1 like' : '${wallCount(n)} likes';

/// Width the app's grid game card draws at. On phones the card sizes itself
/// from the screen (half of it, less the grid gutters) whatever its parent
/// says, so the rail slot must match it exactly or the card spills.
double discoveryGridCardWidth(BuildContext context) {
  if (ResponsiveHelper.isPhone) {
    return (MediaQuery.sizeOf(context).width / 2) - 24.sp;
  }
  return 200.w;
}

/// The return target Discovery hands the upgrade flow for one of its
/// sections ('for_you/discovery/most_liked'): a fixed route-like name.
String discoveryReturnTo(String section) => 'for_you/discovery/$section';

/// Runs [action] once Premium is confirmed: straight away for subscribers,
/// after the paywall for everyone else (once its purchase celebration has
/// closed). Nothing happens if the viewer backs out, so the intended action
/// resumes only on a real unlock.
///
/// [featureId] names the outcome being unlocked ('most_liked_rankings') and
/// [returnTo] the section the action resumes in (see [discoveryReturnTo]).
/// Both ride into the paywall and its analytics, so they are fixed
/// identifiers, never user or player data.
Future<void> unlockThen(
  BuildContext context,
  WidgetRef ref,
  FutureOr<void> Function() action, {
  required String featureId,
  required String returnTo,
}) async {
  HapticFeedbackService.buttonPress();
  await requirePremiumGuard(
    context,
    ref,
    featureId: featureId,
    returnTo: returnTo,
    onEntitled: action,
  );
}

/// The rose a like is drawn in: soft on the dark stage, and on paper the
/// same hue deepened until the glyph holds 3:1 against the page.
Color discoveryHeartInk(BuildContext context) {
  if (!context.isLightTheme) return const Color(0xFFE0787C);
  return legibleHueInk(
    context,
    const Color(0xFFC0394A),
    minContrast: 3,
    on: context.colors.background,
  );
}

// ---------------------------------------------------------------- padlock

/// A word joiner: set between a line's last word and an inline glyph after
/// it (a padlock, an arrow), so a wrap takes the glyph along with the word
/// instead of leaving it alone on a line.
const String kDiscoveryGlue = '\u2060';

/// The Premium padlock (the design's 12 x 14 lock), drawn bare in brand cyan
/// unless [color] says otherwise (a disabled action draws it muted).
///
/// One placement for every locked control on the page: the lock trails the
/// words (or the chevron) it gates, [gap] after them, at the default size,
/// centred on their line. Once per boundary: it marks the locked control
/// itself (a tab, the date arrow, the players row, a tour tile's outcome),
/// never the outcome line that sells a boundary those controls already
/// mark ([DiscoveryUpgradeLine]).
class DiscoveryPadlock extends StatelessWidget {
  const DiscoveryPadlock({
    super.key,
    this.width = 8,
    this.height = 10,
    this.color,
  });

  /// Space between the gated words and the lock, the same everywhere.
  static double get gap => 4.w;

  final double width;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(width.w, height.w),
        painter: _PadlockPainter(color ?? context.colors.accentText),
      ),
    );
  }
}

class _PadlockPainter extends CustomPainter {
  const _PadlockPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Fitted like the SVG viewBox: uniform scale, centred both ways.
    final k = size.width / 12 < size.height / 14
        ? size.width / 12
        : size.height / 14;
    canvas.save();
    canvas.translate((size.width - 12 * k) / 2, (size.height - 14 * k) / 2);
    canvas.scale(k);
    final shackle = Path()
      ..moveTo(3.25, 6.2)
      ..lineTo(3.25, 4.3)
      ..arcToPoint(const Offset(8.75, 4.3), radius: const Radius.circular(2.75))
      ..lineTo(8.75, 6.2);
    canvas.drawPath(
      shackle,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(1, 6.2, 10, 7),
        const Radius.circular(1.8),
      ),
      Paint()..color = color,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PadlockPainter oldDelegate) => oldDelegate.color != color;
}

/// Which corner a [DiscoveryLockNotch] is cut into.
enum DiscoveryNotchCorner { topRight, bottomRight }

/// A square cut out of a locked surface's corner in the page colour, with the
/// padlock centred in it. Reads as a notch in the object, not a badge on it.
class DiscoveryLockNotch extends StatelessWidget {
  const DiscoveryLockNotch({
    super.key,
    required this.size,
    this.corner = DiscoveryNotchCorner.topRight,
  });

  final double size;
  final DiscoveryNotchCorner corner;

  @override
  Widget build(BuildContext context) {
    final radius = Radius.circular(3.w);
    final lock = (size * 0.42).clamp(8.0, 12.0);
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.background,
          borderRadius: switch (corner) {
            DiscoveryNotchCorner.topRight => BorderRadius.only(
              bottomLeft: radius,
            ),
            DiscoveryNotchCorner.bottomRight => BorderRadius.only(
              topLeft: radius,
            ),
          },
        ),
        child: Center(
          child: CustomPaint(
            size: Size(lock * 12 / 14, lock),
            painter: _PadlockPainter(context.colors.accentText),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- glyphs

/// The design's round-capped 8 x 12 chevron, pointing right at [turns] 0 and
/// turned clockwise by [turns] quarter turns (fractions allowed, so a
/// disclosure can spin between down and up).
class DiscoveryChevron extends StatelessWidget {
  const DiscoveryChevron({
    super.key,
    required this.color,
    this.turns = 0,
    this.width = 7,
    this.height = 11,
  });

  final Color color;
  final double turns;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final glyph = CustomPaint(
      size: Size(width.w, height.w),
      painter: _ChevronPainter(color),
    );
    if (turns == 0) return glyph;
    // Square slot, so a quarter turn never changes the glyph's footprint.
    final side = math.max(width, height).w;
    return SizedBox.square(
      dimension: side,
      child: Center(
        child: Transform.rotate(angle: turns * math.pi / 2, child: glyph),
      ),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 8;
    final sy = size.height / 12;
    final path = Path()
      ..moveTo(1.5 * sx, 1.5 * sy)
      ..lineTo(6 * sx, 6 * sy)
      ..lineTo(1.5 * sx, 10.5 * sy);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8 * sx
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => oldDelegate.color != color;
}

/// The design's round-capped plus, drawn rather than taken from an icon font.
class _PlusPainter extends CustomPainter {
  const _PlusPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 20;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2.4 * k
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(10 * k, 3 * k), Offset(10 * k, 17 * k), stroke);
    canvas.drawLine(Offset(3 * k, 10 * k), Offset(17 * k, 10 * k), stroke);
  }

  @override
  bool shouldRepaint(_PlusPainter oldDelegate) => oldDelegate.color != color;
}

// ---------------------------------------------------------------- headers

/// How every Discovery section opens: its title on the gutter and, on the
/// far side, one action or the date stepper. Nothing sits above the title.
///
/// The row holds at least 44 so a trailing target is a full tap target; a
/// large text size grows it rather than clipping the title. The trailing
/// control only ever shrinks (scaled, never wrapped) and the title gives way
/// with an ellipsis before either overflows.
class DiscoverySectionHeader extends StatelessWidget {
  const DiscoverySectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.trailingReachesEdge = false,
    this.count,
    this.onTitleTap,
    this.gutter,
  });

  final String title;

  /// One [DiscoveryAction] or a [DiscoveryDateStepper].
  final Widget? trailing;

  /// The trailing control runs to the screen edge and insets its own ink
  /// onto the gutter (the date stepper's next-arrow target does), so its
  /// target keeps its full width without pulling the ink off the gutter.
  final bool trailingReachesEdge;

  /// How many the section holds, in quiet ink right after the title. Left
  /// out where no honest total is known.
  final int? count;

  /// Makes the title (and its count) a target of its own: the same place
  /// the section's See all opens, 44 tall, giving under the finger.
  final VoidCallback? onTitleTap;

  /// The side inset; [discoveryGutter] unless the header already stands
  /// inside one (a tablet column).
  final double? gutter;

  @override
  Widget build(BuildContext context) {
    final style = discoveryType(context, DiscoveryType.title);
    final number = count;
    final words = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (number != null) ...[
          SizedBox(width: 8.w),
          Text(
            '$number',
            maxLines: 1,
            style: style.copyWith(
              fontWeight: FontWeight.w500,
              color: context.colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );
    final open = onTitleTap;
    final said = number == null ? title : '$title, $number';
    // The title is its own node (never merged into the section's list item,
    // which would make the whole section one button), fixed for the life of
    // the head: whether it is a target is set by the section, not toggled.
    final Widget heading = open == null
        ? Semantics(
            container: true,
            header: true,
            label: said,
            excludeSemantics: true,
            child: words,
          )
        : Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              container: true,
              header: true,
              button: true,
              label: said,
              onTap: open,
              excludeSemantics: true,
              child: WallPressable(
                pressScale: 0.97,
                onTap: open,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: 44.w),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: 1,
                    child: words,
                  ),
                ),
              ),
            ),
          );
    final end = trailing;
    final side = gutter ?? discoveryGutter;
    return Padding(
      padding: EdgeInsets.only(
        left: side,
        right: end != null && trailingReachesEdge ? 0 : side,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 44.w),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              children: [
                Expanded(child: heading),
                if (end != null) ...[
                  SizedBox(width: 12.w),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.64,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: end,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The one head every hub section that leads somewhere wears, on Discovery
/// and on My Space alike: the title (a target of its own), the count after
/// it where one is known, and "See all" with the up-right arrow at the far
/// end. The title and See all open the same place, so the whole line reads
/// as one way in. See all is always there, whatever the section shows.
class DiscoverySeeAllHeader extends StatelessWidget {
  const DiscoverySeeAllHeader({
    super.key,
    required this.title,
    required this.onOpen,
    this.count,
    this.gutter,
    this.seeAllSemanticsLabel,
  });

  final String title;
  final VoidCallback onOpen;
  final int? count;
  final double? gutter;

  /// What a screen reader says for See all; "See all [title]" by default.
  final String? seeAllSemanticsLabel;

  @override
  Widget build(BuildContext context) {
    return DiscoverySectionHeader(
      title: title,
      count: count,
      gutter: gutter,
      onTitleTap: onOpen,
      trailing: DiscoveryAction(
        label: 'See all',
        arrow: true,
        onTap: onOpen,
        semanticsLabel: seeAllSemanticsLabel ?? 'See all $title',
      ),
    );
  }
}

// ---------------------------------------------------------------- segments

/// Tabs that look like tabs: a recessed track with a thumb under the picked
/// segment, every segment the same width. The thumb slides on a motor
/// spring (and jumps under reduced motion); the labels trade ink with it as
/// it passes, so colour and position move as one.
///
/// Each segment is a 44-high target over the 34-high track. A [locked]
/// segment carries the padlock after its label; [leading] sets a glyph
/// before it (a time control). With [enabled] off the labels stay in place
/// as the boundary but offer nothing: no track, no thumb, no padlocks, no
/// taps, one quiet announcement.
class DiscoverySegments<T> extends StatelessWidget {
  const DiscoverySegments({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelect,
    required this.semanticsPrefix,
    this.locked,
    this.leading,
    this.enabled = true,
    this.disabledSuffix = 'not live yet',
  });

  final List<T> values;
  final T selected;
  final String Function(T value) label;
  final ValueChanged<T> onSelect;
  final String semanticsPrefix;
  final bool Function(T value)? locked;
  final Widget Function(T value)? leading;
  final bool enabled;

  /// Read after the labels while [enabled] is off.
  final String disabledSuffix;

  static double get _track => 34.w;
  static double get _inset => 2.w;

  /// Track and thumb fills. Dark: the thumb steps up from the card grey the
  /// track shares with the tiles. Paper: a recessed well with the card's
  /// own white as the thumb.
  static (Color track, Color thumb) fills(BuildContext context) {
    final colors = context.colors;
    if (context.isLightTheme) {
      return (
        Color.alphaBlend(
          colors.surfaceRecessed.withValues(alpha: 0.55),
          colors.background,
        ),
        colors.surface,
      );
    }
    return (colors.surface, colors.surfaceRecessed);
  }

  @override
  Widget build(BuildContext context) {
    final index = values.indexOf(selected);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final (trackFill, thumbFill) = fills(context);

    Widget visual = SizedBox(
      height: _track,
      child: DecoratedBox(
        // Off, the labels keep their places but lose the track: muted words
        // on the page, the way a boundary that is not live yet has always
        // read here, not a control that looks broken.
        decoration: BoxDecoration(
          color: enabled ? trackFill : null,
          borderRadius: BorderRadius.circular(9.w),
        ),
        child: Padding(
          padding: EdgeInsets.all(_inset),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final segment = constraints.maxWidth / values.length;
              return SingleMotionBuilder(
                motion: const CupertinoMotion.snappy(),
                value: index < 0 ? 0.0 : index.toDouble(),
                active: !reduceMotion,
                builder: (context, at, _) {
                  return Stack(
                    children: [
                      if (enabled && index >= 0)
                        Positioned(
                          left: at * segment,
                          top: 0,
                          bottom: 0,
                          width: segment,
                          child: _Thumb(fill: thumbFill),
                        ),
                      Row(
                        children: [
                          for (var i = 0; i < values.length; i++)
                            Expanded(
                              child: _SegmentLabel(
                                text: label(values[i]),
                                // 1 under the thumb, 0 a segment away.
                                on: enabled
                                    ? (1 - (at - i).abs()).clamp(0.0, 1.0)
                                    : 0.0,
                                enabled: enabled,
                                locked:
                                    enabled &&
                                    (locked?.call(values[i]) ?? false),
                                leading: leading?.call(values[i]),
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
    visual = ExcludeSemantics(child: visual);

    final Widget control;
    if (!enabled) {
      control = Semantics(
        container: true,
        label: [
          semanticsPrefix,
          ...values.map(label),
          disabledSuffix,
        ].join(', '),
        child: SizedBox(
          height: 44.w,
          child: Center(child: visual),
        ),
      );
    } else {
      control = SizedBox(
        height: 44.w,
        child: Stack(
          children: [
            Positioned.fill(child: Center(child: visual)),
            // The targets sit over the track, each the full 44 high.
            Positioned.fill(
              child: Row(
                children: [
                  for (var i = 0; i < values.length; i++)
                    Expanded(child: _target(values[i], i == index)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: discoveryGutter),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.isPhone ? double.infinity : 420.w,
          ),
          child: control,
        ),
      ),
    );
  }

  Widget _target(T value, bool isSelected) {
    final isLocked = locked?.call(value) ?? false;
    void select() {
      if (isSelected) return;
      HapticFeedbackService.selection();
      onSelect(value);
    }

    return Semantics(
      container: true,
      button: true,
      selected: isSelected,
      inMutuallyExclusiveGroup: true,
      label: [
        semanticsPrefix,
        label(value),
        if (isLocked) 'Premium',
      ].join(', '),
      onTap: select,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: select,
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// The picked segment's plate: the thumb fill with the light catching its
/// top lip (a hair of white along the edge, clipped by the same corners),
/// so it reads as raised without a shadow.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.fill});

  final Color fill;

  @override
  Widget build(BuildContext context) {
    final lip = context.isLightTheme
        ? Colors.white.withValues(alpha: 0.9)
        : Colors.white.withValues(alpha: 0.06);
    return ClipRRect(
      borderRadius: BorderRadius.circular(7.w),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: fill),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 1,
            child: ColoredBox(color: lip),
          ),
        ],
      ),
    );
  }
}

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel({
    required this.text,
    required this.on,
    required this.enabled,
    required this.locked,
    this.leading,
  });

  final String text;

  /// How far the thumb sits under this segment, 0 to 1.
  final double on;
  final bool enabled;
  final bool locked;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = enabled
        ? Color.lerp(colors.textSecondary, colors.textPrimary, on)!
        : colors.textTertiary;
    final style = discoveryType(
      context,
      DiscoveryType.label,
      color: ink,
      weight: on > 0.5 ? FontWeight.w600 : FontWeight.w500,
    );
    final glyph = leading;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.w),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (glyph != null) ...[
                // The glyph steps back with its label, so an unselected
                // colour mark never outweighs the selected segment.
                Opacity(
                  opacity: enabled ? 0.55 + 0.45 * on : 0.5,
                  child: glyph,
                ),
                SizedBox(width: 5.w),
              ],
              // Laid out at the selected weight too, so the thumb arriving
              // never nudges the label.
              Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: 0,
                    child: Text(
                      text,
                      maxLines: 1,
                      style: style.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(text, maxLines: 1, style: style),
                ],
              ),
              if (locked) ...[
                SizedBox(width: DiscoveryPadlock.gap),
                const DiscoveryPadlock(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- actions

/// What sits before an action's label.
enum DiscoveryActionLead { none, plus }

/// Discovery's one action look: accent ink at label size, a plus before it
/// when it creates something, the Premium padlock after the words when the
/// action is locked ([DiscoveryPadlock]'s one placement), and the up-right
/// arrow after it when the action leaves for somewhere else. Every action
/// on the page wears this and nothing else does, so accent ink always means
/// "tap here" and plain ink always means "information".
///
/// A null [onTap] draws the same line in the quietest ink with no target: a
/// boundary that is visible but not for sale yet. [wraps] lets a long
/// outcome take a second line (a footer) instead of an ellipsis. An
/// [endsSection] action is its section's last line: the room its 44 target
/// leaves under the words is not counted in the gap to the next section.
class DiscoveryAction extends StatelessWidget {
  const DiscoveryAction({
    super.key,
    required this.label,
    required this.onTap,
    this.lead = DiscoveryActionLead.none,
    this.trailingPadlock = false,
    this.arrow = false,
    this.wraps = false,
    this.endsSection = false,
    this.semanticsLabel,
  });

  final String label;
  final VoidCallback? onTap;
  final DiscoveryActionLead lead;
  final bool trailingPadlock;
  final bool arrow;
  final bool wraps;
  final bool endsSection;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final ink = enabled
        ? context.colors.accentText
        : context.colors.textTertiary;
    final style = discoveryType(
      context,
      DiscoveryType.label,
      weight: FontWeight.w600,
      color: ink,
    );
    // A leading glyph sits on the first line, so a wrapped label keeps it
    // beside the words it belongs to.
    final line = MediaQuery.textScalerOf(context).scale(13.f) * 18 / 13;
    Widget onLine(Widget glyph) => SizedBox(
      height: line,
      child: Center(child: glyph),
    );

    // Trailing glyphs ride inline, so on a wrapped outcome they follow the
    // last word instead of hanging off the far edge; the word joiner keeps
    // them on that word's line, never alone on a line of their own.
    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: label),
          if (trailingPadlock || arrow) const TextSpan(text: kDiscoveryGlue),
          if (trailingPadlock)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: EdgeInsets.only(left: DiscoveryPadlock.gap),
                child: DiscoveryPadlock(color: ink),
              ),
            ),
          if (arrow)
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: EdgeInsets.only(left: 4.w),
                child: SpaceGlyph(
                  SpaceGlyphKind.arrowUpRight,
                  size: 10.w,
                  ink: ink,
                ),
              ),
            ),
        ],
      ),
      maxLines: wraps ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (lead == DiscoveryActionLead.plus) ...[
          onLine(
            CustomPaint(size: Size.square(12.w), painter: _PlusPainter(ink)),
          ),
          SizedBox(width: 6.w),
        ],
        if (wraps) Flexible(child: text) else text,
      ],
    );
    // A 44 floor, the text centred in it on one line; a second line grows
    // the target downwards.
    final body = DiscoveryInkFloor(
      minHeight: 44.w,
      inset: math.max(0, (44.w - line) / 2),
      endsSection: endsSection,
      child: row,
    );

    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: semanticsLabel ?? label,
      onTap: onTap,
      excludeSemantics: true,
      child: enabled
          ? WallPressable(pressScale: 0.97, onTap: onTap, child: body)
          : body,
    );
  }
}

/// A Premium outcome under a section's content: the exact outcome ("View
/// weekly, monthly, and yearly rankings") and the arrow, on the gutter,
/// always its section's last line. It sells a boundary the section's own
/// locked controls already mark (the Week tab, the earlier-days arrow, a
/// locked card), so it carries no padlock of its own: the boundary is
/// stated once, and the sentence itself appears once per page. Its screen
/// reader label still says Premium. [onTap] null shows it as a boundary
/// that is not live yet.
///
/// [quiet] is the hub's form, under a preview whose header already carries
/// "See all": the padlock and the outcome in quiet ink, no arrow, so a
/// section offers one link out and the boundary reads as a fact about it.
/// The line still opens the paywall.
class DiscoveryUpgradeLine extends StatelessWidget {
  const DiscoveryUpgradeLine({
    super.key,
    required this.label,
    required this.onTap,
    this.semanticsLabel,
    this.quiet = false,
  });

  final String label;
  final VoidCallback? onTap;
  final String? semanticsLabel;
  final bool quiet;

  Widget _quiet(BuildContext context) {
    final ink = context.colors.textSecondary;
    final line = MediaQuery.textScalerOf(context).scale(13.f) * 18 / 13;
    final body = DiscoveryInkFloor(
      minHeight: 44.w,
      inset: math.max(0, (44.w - line) / 2),
      endsSection: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: line,
            child: Center(child: DiscoveryPadlock(color: ink)),
          ),
          SizedBox(width: 6.w),
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: discoveryType(context, DiscoveryType.label, color: ink),
            ),
          ),
        ],
      ),
    );
    final tap = onTap;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: discoveryGutter),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          container: true,
          button: tap != null,
          label: semanticsLabel ?? '$label, Premium',
          onTap: tap,
          excludeSemantics: true,
          child: tap == null
              ? body
              : WallPressable(pressScale: 0.97, onTap: tap, child: body),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (quiet) return _quiet(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: discoveryGutter),
      child: Align(
        alignment: Alignment.centerLeft,
        child: DiscoveryAction(
          label: label,
          onTap: onTap,
          arrow: onTap != null,
          wraps: true,
          endsSection: true,
          semanticsLabel: semanticsLabel ?? '$label, Premium',
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- stepper

/// "‹  Thu 24 Sep  ›": the one date control on the page. The arrows are 44
/// targets; a [previousLocked] arrow carries the padlock after its chevron
/// (the page's one placement, see [DiscoveryPadlock]); a null callback
/// draws its chevron in the divider ink and takes no tap.
///
/// Set in a header with `trailingReachesEdge`, [edgeInset] puts the next
/// chevron's ink on the gutter while its target runs to the screen edge.
class DiscoveryDateStepper extends StatelessWidget {
  const DiscoveryDateStepper({
    super.key,
    required this.label,
    required this.previousSemantics,
    required this.nextSemantics,
    required this.onPrevious,
    required this.onNext,
    this.previousLocked = false,
    this.labelSemantics,
    this.edgeInset = 0,
  });

  final String label;
  final String previousSemantics;
  final String nextSemantics;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final bool previousLocked;
  final String? labelSemantics;
  final double edgeInset;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepArrow(
          pointsLeft: true,
          locked: previousLocked && onPrevious != null,
          semanticLabel: previousSemantics,
          onTap: onPrevious,
        ),
        Semantics(
          container: true,
          label: labelSemantics ?? label,
          excludeSemantics: true,
          child: Text(
            label,
            maxLines: 1,
            style: discoveryType(context, DiscoveryType.label, tabular: true),
          ),
        ),
        _StepArrow(
          pointsLeft: false,
          locked: false,
          reserveLock: previousLocked && onPrevious != null,
          semanticLabel: nextSemantics,
          onTap: onNext,
          endInset: edgeInset,
        ),
      ],
    );
  }
}

class _StepArrow extends StatelessWidget {
  const _StepArrow({
    required this.pointsLeft,
    required this.locked,
    required this.semanticLabel,
    required this.onTap,
    this.endInset = 0,
    this.reserveLock = false,
  });

  final bool pointsLeft;
  final bool locked;
  final String semanticLabel;
  final VoidCallback? onTap;

  /// Keeps the padlock's room (empty) between the label and this chevron,
  /// so a date whose other arrow carries the padlock sits evenly between
  /// its two chevrons.
  final bool reserveLock;

  /// Space kept clear after the chevron inside the target.
  final double endInset;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final ink = enabled
        ? context.colors.textSecondary
        : context.colors.dividerStrong;
    final lockRoom = DiscoveryPadlock.gap + const DiscoveryPadlock().width.w;
    final glyph = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (reserveLock) SizedBox(width: lockRoom),
        DiscoveryChevron(color: ink, turns: pointsLeft ? 2 : 0),
        if (locked) ...[
          SizedBox(width: DiscoveryPadlock.gap),
          const DiscoveryPadlock(),
        ],
      ],
    );
    final target = 44.w;
    final box = SizedBox(
      width: endInset > 0
          ? math.max(target, endInset + 20.w + (reserveLock ? lockRoom : 0))
          : target,
      height: target,
      child: endInset > 0
          ? Padding(
              padding: EdgeInsets.only(right: endInset),
              child: Align(alignment: Alignment.centerRight, child: glyph),
            )
          : Center(child: glyph),
    );
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: enabled
          ? WallPressable(
              pressScale: 0.94,
              onTap: () {
                HapticFeedbackService.selection();
                onTap!();
              },
              child: box,
            )
          : box,
    );
  }
}

// ---------------------------------------------------------------- likes

/// A like count drawn, not written: the heart and the figure. The sentence
/// ("1,184 likes") is what a screen reader hears.
class DiscoveryLikes extends StatelessWidget {
  const DiscoveryLikes({super.key, required this.likes, this.size});

  final int likes;

  /// Glyph side; defaults to the meta line's 12.
  final double? size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: discoveryLikes(likes),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SpaceGlyph(
            SpaceGlyphKind.heart,
            size: size ?? 12.w,
            ink: discoveryHeartInk(context),
          ),
          SizedBox(width: 3.w),
          Text(
            wallCount(likes),
            maxLines: 1,
            style: discoveryType(
              context,
              DiscoveryType.meta,
              weight: FontWeight.w700,
              color: context.colors.textPrimary,
              tabular: true,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- lines

/// A one-line status for a section that has nothing to show: an honest
/// sentence, and a retry when there is something to retry.
class DiscoveryNotice extends StatelessWidget {
  const DiscoveryNotice({
    super.key,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final action = actionLabel;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: discoveryGutter),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 44.w),
        child: Row(
          children: [
            Expanded(
              // A notice is often its section's last line: the room under
              // the sentence is not counted in the gap to the next section.
              child: DiscoveryInkFloor(
                minHeight: 44.w,
                endsSection: true,
                child: Text(
                  text,
                  style: discoveryType(
                    context,
                    DiscoveryType.label,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            ),
            if (action != null && onAction != null) ...[
              SizedBox(width: 12.w),
              DiscoveryAction(label: action, onTap: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- rhythm

/// The 44 floor a line of ink stands in (an action, a notice, the players
/// row): the ink centred in it with at least [inset] clear above and below,
/// the whole floor the tap target. An [endsSection] floor also tells the
/// [DiscoverySectionSlot] around its section how much room it leaves under
/// the ink, so a section that ends on a line of text is spaced from the next
/// section by that text, not by its invisible target.
class DiscoveryInkFloor extends SingleChildRenderObjectWidget {
  const DiscoveryInkFloor({
    super.key,
    required this.minHeight,
    this.inset = 0,
    this.endsSection = false,
    super.child,
  });

  final double minHeight;
  final double inset;
  final bool endsSection;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderInkFloor(minHeight, inset, endsSection);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderInkFloor)
      ..minHeight = minHeight
      ..inset = inset
      ..endsSection = endsSection;
  }
}

class _RenderInkFloor extends RenderShiftedBox {
  _RenderInkFloor(this._minHeight, this._inset, this._endsSection)
    : super(null);

  double _minHeight;
  set minHeight(double value) {
    if (value == _minHeight) return;
    _minHeight = value;
    markNeedsLayout();
  }

  double _inset;
  set inset(double value) {
    if (value == _inset) return;
    _inset = value;
    markNeedsLayout();
  }

  bool _endsSection;
  set endsSection(bool value) {
    if (value == _endsSection) return;
    _endsSection = value;
    if (!attached) return;
    final before = _slot;
    _leave();
    _join();
    (before ?? _slot)?.markNeedsLayout();
  }

  /// This floor's height and the room under its ink from the last layout,
  /// kept as plain numbers: the slot reads them while it lays out, where a
  /// descendant's [size] is off limits.
  double _height = 0;
  double _room = 0;

  _RenderSectionSlot? _slot;

  void _join() {
    if (!_endsSection) return;
    for (var node = parent; node != null; node = node.parent) {
      if (node is _RenderSectionSlot) {
        _slot = node.._floors.add(this);
        return;
      }
    }
  }

  void _leave() {
    _slot?._floors.remove(this);
    _slot = null;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    // Inserting or dropping this floor relays out its section, and the
    // section's slot with it, so joining needs no layout request of its own.
    _join();
  }

  @override
  void detach() {
    _leave();
    super.detach();
  }

  BoxConstraints _enforced(BoxConstraints constraints) =>
      BoxConstraints(minHeight: _minHeight).enforce(constraints);

  /// The ink's natural height inside the floor's width.
  BoxConstraints _inner(BoxConstraints enforced) => enforced
      .deflate(EdgeInsets.symmetric(vertical: _inset))
      .copyWith(minHeight: 0);

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final enforced = _enforced(constraints);
    final child = this.child;
    if (child == null) return enforced.constrain(Size.zero);
    final ink = child.getDryLayout(_inner(enforced));
    return enforced.constrain(Size(ink.width, ink.height + 2 * _inset));
  }

  @override
  double? computeDryBaseline(
    covariant BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final child = this.child;
    if (child == null) return null;
    final enforced = _enforced(constraints);
    final inner = _inner(enforced);
    final base = child.getDryBaseline(inner, baseline);
    if (base == null) return null;
    final ink = child.getDryLayout(inner);
    final height = enforced.constrainHeight(ink.height + 2 * _inset);
    return base + (height - ink.height) / 2;
  }

  @override
  double computeMinIntrinsicHeight(double width) => math.max(
    _minHeight,
    (child?.getMinIntrinsicHeight(width) ?? 0) + 2 * _inset,
  );

  @override
  double computeMaxIntrinsicHeight(double width) => math.max(
    _minHeight,
    (child?.getMaxIntrinsicHeight(width) ?? 0) + 2 * _inset,
  );

  @override
  void performLayout() {
    final enforced = _enforced(constraints);
    final child = this.child;
    if (child == null) {
      size = enforced.constrain(Size.zero);
      _height = size.height;
      _room = 0;
      return;
    }
    child.layout(_inner(enforced), parentUsesSize: true);
    final ink = child.size;
    size = enforced.constrain(Size(ink.width, ink.height + 2 * _inset));
    final top = (size.height - ink.height) / 2;
    (child.parentData! as BoxParentData).offset = Offset(0, top);
    _height = size.height;
    _room = math.max(0, size.height - top - ink.height);
  }
}

/// One Discovery section in the page's list. The section is laid out whole,
/// then the room an [DiscoveryInkFloor] with `endsSection` leaves under its
/// ink is given back when that floor is the section's last line, so every
/// section-to-section gap is measured from the last ink: a section ending
/// on an upgrade line sits as far from the next title as one ending on a
/// card. The floor's target still reaches into the gap below, and hits there
/// are passed on to it.
///
/// It must be the list's item itself (the list adds no repaint boundary or
/// semantic index around it): anything wrapped around it would stop those
/// hits at the trimmed edge.
class DiscoverySectionSlot extends SingleChildRenderObjectWidget {
  const DiscoverySectionSlot({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSectionSlot();
}

class _RenderSectionSlot extends RenderProxyBox {
  final Set<_RenderInkFloor> _floors = <_RenderInkFloor>{};

  /// The floor's bottom edge in this box, from layout offsets alone (a
  /// press-scale transform between them never moves it). Null when the
  /// floor sits in a nested scroll, whose offsets are not layout.
  double? _bottomOf(_RenderInkFloor floor) {
    var bottom = floor._height;
    RenderObject node = floor;
    while (!identical(node, this)) {
      final data = node.parentData;
      if (data is BoxParentData) {
        bottom += data.offset.dy;
      } else if (data is SliverPhysicalParentData ||
          data is SliverLogicalParentData) {
        return null;
      }
      final up = node.parent;
      if (up == null) return null;
      node = up;
    }
    return bottom;
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints, parentUsesSize: true);
    final whole = child.size;
    var room = 0.0;
    for (final floor in _floors) {
      final bottom = _bottomOf(floor);
      if (bottom != null && (whole.height - bottom).abs() < 0.5) {
        room = math.max(room, floor._room);
      }
    }
    size = constraints.constrain(Size(whole.width, whole.height - room));
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // The whole section, the last line's target below the trimmed edge
    // included.
    final reach = child?.size ?? size;
    if (!(Offset.zero & reach).contains(position)) return false;
    if (hitTestChildren(result, position: position) ||
        hitTestSelf(position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}

// ---------------------------------------------------------------- rails

/// A horizontal rail that starts on the page gutter and scrolls past it. The
/// row takes the height of its tallest item, so cards of any height fit.
///
/// A rail's cards are one size, and each mounts only once it comes within
/// half a screen of the viewport: an off-screen card costs nothing (no eval
/// fetch, no video prefetch, no ending animation) until the rail is scrolled
/// towards it. Slots not mounted yet hold the first card's measured size, so
/// the scroll extent is right from the start. [lazy] false mounts every card
/// up front, for a rail of cheap static tiles.
class DiscoveryRail extends StatefulWidget {
  const DiscoveryRail({
    super.key,
    required this.children,
    this.gap = 12,
    this.lazy = true,
  });

  final List<Widget> children;
  final double gap;
  final bool lazy;

  @override
  State<DiscoveryRail> createState() => _DiscoveryRailState();
}

class _DiscoveryRailState extends State<DiscoveryRail> {
  final _controller = ScrollController();

  /// The first card's size, once it has laid out.
  Size? _slot;

  /// How many cards have mounted. Only ever grows, so a card that has
  /// mounted keeps its state when the rail scrolls back.
  int _mounted = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_reveal);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Before the first card is measured, cover the screen at the narrowest
    // card any rail draws, so the first frame never shows an empty slot.
    final view = MediaQuery.sizeOf(context).width;
    final floor = ((view - discoveryGutter) / (96.w + widget.gap.w)).ceil();
    if (floor > _mounted) _mounted = floor;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _measured(Size size) {
    if (!mounted || size == _slot) return;
    setState(() => _slot = size);
    _reveal();
  }

  void _reveal() {
    final slot = _slot;
    final count = widget.children.length;
    if (!mounted || slot == null || _mounted >= count) return;
    if (!_controller.hasClients) return;
    final position = _controller.position;
    if (!position.hasPixels || !position.hasViewportDimension) return;
    final reach =
        position.pixels + position.viewportDimension * 1.5 - discoveryGutter;
    final pitch = slot.width + widget.gap.w;
    if (pitch <= 0) return;
    final need = math.min(count, (reach / pitch).floor() + 1);
    if (need > _mounted) setState(() => _mounted = need);
  }

  @override
  Widget build(BuildContext context) {
    final children = widget.children;
    final live = widget.lazy
        ? math.min(_mounted, children.length)
        : children.length;
    return SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: discoveryGutter),
      physics: const BouncingScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(width: widget.gap.w),
            if (i == 0)
              _SizeProbe(onSize: _measured, child: children[0])
            else if (i < live)
              children[i]
            else
              SizedBox.fromSize(size: _slot ?? Size.zero),
          ],
        ],
      ),
    );
  }
}

/// Reports its child's size after each layout that changes it.
class _SizeProbe extends SingleChildRenderObjectWidget {
  const _SizeProbe({required this.onSize, super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeProbe(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeProbe renderObject) {
    renderObject.onSize = onSize;
  }
}

class _RenderSizeProbe extends RenderProxyBox {
  _RenderSizeProbe(this.onSize);

  ValueChanged<Size> onSize;
  Size? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final measured = size;
    if (measured == _reported) return;
    _reported = measured;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(measured));
  }
}

/// Loading placeholders for a rail: [count] plates of the final card size, so
/// nothing jumps when the real cards land.
class DiscoverySkeletonRail extends StatelessWidget {
  const DiscoverySkeletonRail({
    super.key,
    required this.width,
    required this.height,
    this.count = 3,
  });

  final double width;
  final double height;
  final int count;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SkeletonWidget(
        ignoreContainers: true,
        child: DiscoveryRail(
          children: [
            for (var i = 0; i < count; i++)
              SizedBox(
                width: width,
                height: height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: context.colors.surfaceRecessed,
                    borderRadius: BorderRadius.circular(4.w),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- boards

/// A small still board in the viewer's own board theme and piece set.
class DiscoveryMiniBoard extends ConsumerWidget {
  const DiscoveryMiniBoard({
    super.key,
    required this.fen,
    required this.size,
    this.lastMove,
  });

  final String fen;
  final double size;
  final String? lastMove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(boardSettingsProviderNew).valueOrNull ??
        const BoardSettingsNew();
    final uci = lastMove;
    final move = uci == null ? null : Move.parse(uci);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: StaticChessboard(
          size: size,
          orientation: Side.white,
          fen: fen,
          lastMove: move,
          settings: StaticChessboardSettings(
            colorScheme: settings.colorScheme,
            pieceAssets: settings.pieceAssets,
            enableCoordinates: false,
          ),
        ),
      ),
    );
  }
}
