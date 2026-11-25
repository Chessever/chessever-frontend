import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/discovery_dot.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:flutter/material.dart';

/// A phone navigation target: the section's mark alone, large, in a slot
/// that answers anywhere in its column.
///
/// The whole slot is the target, from the dock's top edge down through the
/// strip under it to the screen's edge ([bottomInset]). A press anywhere in
/// it takes the mark down under the finger ([PressSpring]); letting go
/// springs it back with a little overshoot, and a tab change ticks the
/// selection haptic. The name is announced, never drawn: the marks carry
/// the dock, and Profile is the reader's own avatar.
///
/// The mark keeps one size where the dock leaves whole as the reader reads
/// on. On Feed the dock draws in instead: the mark is drawn at its full
/// [iconSide] and scaled by [markScale], so nothing inside it (a photo's
/// cache, the dot on its shoulder) changes size under it.
class BottomNavBarWidget extends StatefulWidget {
  const BottomNavBarWidget({
    required this.isSelected,
    required this.onTap,
    required this.glyph,
    required this.title,
    required this.width,
    this.bottomInset = 0,
    this.markScale = 1,
    this.semanticsValue,
    this.onLongPress,
    this.dotId,
    super.key,
  });

  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// The slot's mark, drawn in the ink it is handed at the size it is
  /// handed.
  final Widget Function(Color ink, double side) glyph;

  /// The section's name, for assistive technology.
  final String title;
  final double width;

  /// The strip under the dock, to the screen's edge, which the slot takes
  /// into its own hit area instead of leaving it dead under the marks.
  final double bottomInset;

  /// How large the mark is drawn, of [iconSide]: 1 on the full dock, less
  /// as Feed's dock draws in.
  final double markScale;

  /// Extra state read after the name ("Unread Inbox messages" on Profile).
  final String? semanticsValue;

  /// Discovery-dot anchor id, so the admin console can point at this tab.
  final String? dotId;

  /// The mark's side: square on every phone (`20.h` by `20.w` went 15 by 18
  /// on short ones).
  static double get iconSide => 28.ic.clamp(26.0, 30.0);

  /// How far a press takes the mark down.
  static const pressedScale = 0.86;

  /// The full dock's height above the strip under it.
  static const barHeight = 56.0;

  @override
  State<BottomNavBarWidget> createState() => _BottomNavBarWidgetState();
}

class _BottomNavBarWidgetState extends State<BottomNavBarWidget> {
  void _tap() {
    HapticFeedbackService.selection();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final selected = widget.isSelected;
    final ink = selected ? colors.textPrimary : colors.textSecondary;
    final iconSide = BottomNavBarWidget.iconSide;
    final inset = widget.bottomInset;
    final markScale = widget.markScale;

    return Semantics(
      button: true,
      selected: selected,
      label: widget.title,
      value: widget.semanticsValue,
      onLongPress: widget.onLongPress,
      onLongPressHint: widget.onLongPress == null
          ? null
          : 'Make ${widget.title} the start screen',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        onLongPress: widget.onLongPress,
        child: SizedBox(
          width: widget.width,
          // The press covers the whole slot, inset strip included; only the
          // mark scales, about its own centre.
          child: PressSpring(
            pressedScale: BottomNavBarWidget.pressedScale,
            builder: (context, press, child) {
              final scale = 1 - (1 - BottomNavBarWidget.pressedScale) * press;
              return Padding(
                padding: EdgeInsets.only(bottom: inset),
                child: Transform.scale(
                  scale: (scale - 1).abs() < 0.001 ? 1.0 : scale,
                  child: child,
                ),
              );
            },
            child: Center(
              child: DiscoveryDotAnchor(
                id: widget.dotId,
                selected: selected,
                alignment: Alignment.center,
                // Off the mark's top-right shoulder, clear of it, at the
                // size the mark is drawn.
                offset: navMarkShoulder(iconSide * markScale),
                child: SizedBox.square(
                  dimension: iconSide + 6,
                  child: Transform.scale(
                    scale: (markScale - 1).abs() < 0.001 ? 1.0 : markScale,
                    child: Center(child: widget.glyph(ink, iconSide)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where a slot's dot sits from its mark's centre: the top-right shoulder.
/// The discovery dot and Profile's unread-Inbox dot share it, so the two
/// never sit side by side.
Offset navMarkShoulder(double iconSide) =>
    Offset(iconSide / 2 + 4, -(iconSide / 2 + 2));
