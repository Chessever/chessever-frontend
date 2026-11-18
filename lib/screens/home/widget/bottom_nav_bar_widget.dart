import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/discovery_dot.dart';
import 'package:chessever2/widgets/press_spring.dart';
import 'package:flutter/material.dart';

/// A phone navigation target: the section's mark over its name.
///
/// The whole slot answers, from the bar's top edge down through the strip
/// above the home indicator ([bottomInset]), so a thumb landing anywhere in
/// the column gets the tab. A press takes the mark and name down at once,
/// under the finger; letting go springs them back with a little overshoot,
/// and a tab change ticks the selection haptic. No ripple: the slot itself
/// moving is the feedback.
class BottomNavBarWidget extends StatefulWidget {
  const BottomNavBarWidget({
    required this.isSelected,
    required this.onTap,
    required this.glyph,
    required this.title,
    required this.width,
    this.bottomInset = 0,
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
  final String title;
  final double width;

  /// The device's bottom safe area, which the slot takes into its own hit
  /// area instead of leaving a dead strip under the names.
  final double bottomInset;

  /// Discovery-dot anchor id, so the admin console can point at this tab.
  final String? dotId;

  /// The mark's side: square on every phone (`20.h` by `20.w` went 15 by 18
  /// on short ones).
  static double get iconSide => 26.ic.clamp(24.0, 28.0);

  /// How far a press takes the mark and name down.
  static const pressedScale = 0.9;

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

    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        label: widget.title,
        onLongPress: widget.onLongPress,
        onLongPressHint: widget.onLongPress == null
            ? null
            : 'Make ${widget.title} the start screen',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tap,
          onLongPress: widget.onLongPress,
          child: SizedBox(
            width: widget.width,
            child: Padding(
              padding: EdgeInsets.only(bottom: widget.bottomInset),
              child: PressSpring(
                pressedScale: BottomNavBarWidget.pressedScale,
                // The mark over its name: the name says what the slot is
                // (the reader's avatar reads as "Profile"), the weight and
                // ink say which one is open.
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DiscoveryDotAnchor(
                        id: widget.dotId,
                        selected: selected,
                        alignment: Alignment.center,
                        // Off the mark's top-right shoulder, clear of it.
                        offset: Offset(iconSide / 2 + 4, -(iconSide / 2 + 2)),
                        child: SizedBox(
                          height: iconSide + 6,
                          // The slot is named by its title; the mark (the
                          // reader's initials on Profile) would only
                          // repeat it.
                          child: Center(
                            child: ExcludeSemantics(
                              child: widget.glyph(ink, iconSide),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      // Announced once, by the slot's own label.
                      MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.3,
                        child: Text(
                          semanticsLabel: '',
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: AppTypography.textXsMedium.copyWith(
                            color: ink,
                            fontSize: 12,
                            height: 1.2,
                            letterSpacing: 0.1,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
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
