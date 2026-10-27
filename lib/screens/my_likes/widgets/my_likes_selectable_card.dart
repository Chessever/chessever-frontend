import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// A liked game while My Likes is choosing games to remove: the card is laid
/// out untouched, with the selection drawn over it (an edge and a check in
/// its corner). Every gesture goes to [onToggle], so a tap, a hold or a
/// swipe can never open, menu or unlike the game while choosing.
class MyLikesSelectableCard extends StatelessWidget {
  const MyLikesSelectableCard({
    super.key,
    required this.selected,
    required this.onToggle,
    required this.child,
    this.semanticsLabel,
    this.cornerRadius = 12,
  });

  final bool selected;
  final VoidCallback onToggle;
  final Widget child;
  final String? semanticsLabel;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // The theme's accent ink: the brand cyan on dark, its deeper paper
    // shade on light, so the edge and the check both clear 3:1.
    final ink = colors.accentText;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: semanticsLabel,
      onTap: onToggle,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Painted over, never around: a parent border would re-lay the
          // card out and shave its fixed board row.
          ExcludeSemantics(child: child),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: selected
                      ? ink.withValues(alpha: 0.08)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(cornerRadius.br),
                  border: Border.all(
                    color: selected ? ink : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              onLongPress: onToggle,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            top: 8.h,
            right: 8.w,
            child: IgnorePointer(
              child: AnimatedContainer(
                key: const ValueKey('my_likes_select_mark'),
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                width: 24.w,
                height: 24.w,
                decoration: BoxDecoration(
                  color: selected ? ink : colors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? ink
                        : colors.textPrimary.withValues(alpha: 0.45),
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? Icon(
                        Icons.check_rounded,
                        size: 16.sp,
                        color: context.isLightTheme
                            ? colors.surface
                            : colors.background,
                      )
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
