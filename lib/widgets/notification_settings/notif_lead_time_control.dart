import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Two-segment control for selecting heads-up lead time: 10 or 30 minutes.
///
/// Features a sliding pill indicator that animates smoothly between segments.
/// Disabled when [onChanged] is null (e.g. when the heads-up toggle is off
/// or push notifications are globally disabled).
class NotifLeadTimeControl extends StatelessWidget {
  const NotifLeadTimeControl({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// Must be either 10 or 30.
  final int value;

  /// Null disables interaction.
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onChanged != null;

    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Container(
        height: 36.sp,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(8.br),
          border: Border.all(color: context.colors.divider.withValues(alpha: 0.4)),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // ── Sliding pill ─────────────────────────────────────────────
            AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              alignment:
                  value == 10 ? Alignment.centerLeft : Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                child: Container(
                  decoration: BoxDecoration(
                    color: context.colors.surfaceRecessed,
                    borderRadius: BorderRadius.circular(7.br),
                  ),
                ),
              ),
            ),

            // ── Labels (sit above the pill) ───────────────────────────────
            Row(
              children: [
                _SegmentLabel(
                  label: '10 min before',
                  selected: value == 10,
                  onTap: enabled ? () => onChanged!(10) : null,
                ),
                _SegmentLabel(
                  label: '30 min before',
                  selected: value == 30,
                  onTap: enabled ? () => onChanged!(30) : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.expand(
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              style: AppTypography.textSmRegular.copyWith(
                color: selected ? context.colors.textPrimary : const Color(0xFF888888),
                fontSize: 12.f,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
              child: Text(label, textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }
}
