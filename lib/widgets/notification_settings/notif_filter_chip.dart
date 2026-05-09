import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Teal pill chip used in the Push Notifications card for category filters
/// (e.g. "Favorite players", "Classical", "Rapid").
///
/// Selected  → teal background, white text.
/// Unselected → dark background, grey text.
/// Disabled  → reduced opacity, no interaction.
class NotifFilterChip extends StatelessWidget {
  const NotifFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 7.sp),
          decoration: BoxDecoration(
            color: selected ? kPrimaryColor : context.colors.surfaceRecessed,
            borderRadius: BorderRadius.circular(30.br),
          ),
          child: Text(
            label,
            style: AppTypography.textSmRegular.copyWith(
              color: selected ? context.colors.textPrimary : const Color(0xFF9E9E9E),
              fontSize: 12.f,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
