import 'dart:math' as math;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/glass_surface.dart';
import 'package:chessever2/widgets/live_first_mark.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:chessever2/widgets/search_morph.dart';
import 'package:flutter/material.dart';

/// The two sizes a floating button comes in: the page's main action, and a
/// smaller one stacked above it.
enum InkFabSize {
  regular,
  small;

  /// The drawn disc.
  double get disc => switch (this) {
    InkFabSize.regular => 52.ic.clamp(50.0, 58.0),
    InkFabSize.small => 44.ic.clamp(42.0, 48.0),
  };

  /// The square the button takes and answers touches in: its [disc], but
  /// never under the 44pt minimum target. The small disc draws at 42 on most
  /// phones narrower or shorter than the 393x852 base, so it is centred in
  /// the square there. Pages that clear the floating buttons read this.
  double get side => math.max(disc, 44.0);
}

/// A round floating button of frosted glass ([GlassSurface]): the list under
/// it shows through, blurred, behind a thin plate of the page's tone, with
/// the glyph in the glass's quiet ink. It floats in reach without pulling
/// the eye off the boards. While [on] (a toggle) the glass and the glyph take
/// the brand's tonal blue.
///
/// The glyph is drawn by [glyph] in the colour it is handed, at the size it
/// is handed, so any mark (an icon, a painter) takes the button's ink.
class InkFab extends StatefulWidget {
  const InkFab({
    super.key,
    required this.label,
    required this.glyph,
    required this.onTap,
    this.size = InkFabSize.regular,
    this.on,
    this.badgeCount = 0,
  });

  /// What the button announces and its tooltip.
  final String label;
  final Widget Function(Color color, double size) glyph;
  final VoidCallback? onTap;
  final InkFabSize size;

  /// Null for a plain action; true/false for a toggle.
  final bool? on;

  /// A count (applied filters) on the button's shoulder; hidden at 0.
  final int badgeCount;

  @override
  State<InkFab> createState() => _InkFabState();
}

class _InkFabState extends State<InkFab> {
  void _activate() {
    final tap = widget.onTap;
    if (tap == null) return;
    HapticFeedbackService.buttonPress();
    tap();
  }

  @override
  Widget build(BuildContext context) {
    final disc = widget.size.disc;
    final on = widget.on ?? false;
    final style = GlassStyle.of(context);
    final accent = context.colors.accentText;
    // Quiet at rest: the glyph in the glass's own ink. On, the glass takes a
    // breath of the brand's tonal blue and the glyph wears it, which reads
    // across the room without a bright disc shouting from the corner.
    final glyphColor = on ? accent : style.ink;
    final glyph = widget.glyph(glyphColor, disc * 0.42);

    // The app's press ([PressSpring]): down under the finger, back with a
    // little pop, and the glass brightening while held.
    final button = SizedBox.square(
      dimension: disc,
      child: PressSpring(
        pressedScale: 0.9,
        child: Center(child: glyph),
        builder: (context, press, child) {
          final scale = 1 - 0.1 * press;
          return Transform.scale(
            scale: (scale - 1).abs() < 0.001 ? 1.0 : scale,
            child: GlassSurface(
              tint: on ? accent.withValues(alpha: 0.16) : null,
              lift: press.clamp(0.0, 1.0),
              child: child,
            ),
          );
        },
      ),
    );

    final count = widget.badgeCount;
    return Tooltip(
      message: widget.label,
      excludeFromSemantics: true,
      child: Semantics(
        container: true,
        button: true,
        toggled: widget.on,
        enabled: widget.onTap != null,
        label: count > 0 ? '${widget.label}, $count applied' : widget.label,
        onTap: widget.onTap == null ? null : _activate,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _activate,
          child: SizedBox.square(
            dimension: widget.size.side,
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  button,
                  if (count > 0)
                    Positioned(
                      top: -2,
                      right: -2,
                      child: _CountBadge(count: count),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The applied-filters count: a small solid disc of the brand's tonal blue
/// with the page's colour for its number, ringed by the page so it sits
/// cleanly on the glass's shoulder.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: context.colors.accentText,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.background, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 9 ? '9+' : '$count',
        textScaler: TextScaler.noScaling,
        style: AppTypography.textXsMedium.copyWith(
          color: context.colors.background,
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// The page's search: opens the full-page search of whatever list it floats
/// over.
class SearchInkFab extends StatelessWidget {
  const SearchInkFab({
    super.key,
    required this.onTap,
    this.label = 'Search',
    this.badgeCount = 0,
  });

  final VoidCallback onTap;
  final String label;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return InkFab(
      label: label,
      badgeCount: badgeCount,
      onTap: () {
        // Where the glass is now, before the page swaps it for the field.
        final box = context.findRenderObject();
        final from = box is RenderBox && box.hasSize
            ? Rect.fromCenter(
                center: box.localToGlobal(box.size.center(Offset.zero)),
                width: InkFabSize.regular.disc,
                height: InkFabSize.regular.disc,
              )
            : null;
        onTap();
        if (from != null) SearchMorph.play(context, from);
      },
      glyph: (color, size) =>
          Icon(Icons.search_rounded, size: size * 1.12, color: color),
    );
  }
}

/// Live first, floating: shown only while something is live (Trello #1420),
/// stacked above the page's search.
class LiveFirstInkFab extends StatelessWidget {
  const LiveFirstInkFab({
    super.key,
    required this.on,
    required this.onTap,
    this.subject = 'games',
    this.size = InkFabSize.small,
  });

  final bool on;
  final VoidCallback onTap;

  /// Small above a page's search; regular when it is the page's only button.
  final InkFabSize size;

  /// What comes first: "games" or "events".
  final String subject;

  @override
  Widget build(BuildContext context) {
    return InkFab(
      label: on ? 'Live $subject are shown first' : 'Show live $subject first',
      size: size,
      on: on,
      onTap: onTap,
      glyph: (color, side) => LiveFirstMark(size: side, color: color),
    );
  }
}

/// A column of floating buttons: the main one at the bottom where the thumb
/// rests, the smaller ones above it, centred on it.
class InkFabStack extends StatelessWidget {
  const InkFabStack({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          children[i],
        ],
      ],
    );
  }
}
