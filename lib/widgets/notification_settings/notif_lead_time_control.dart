import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Three-segment control for selecting heads-up lead time: 5, 10 or 30 minutes.
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

  /// Must be 5, 10 or 30.
  final int value;

  /// Null disables interaction.
  final ValueChanged<int>? onChanged;

  static const _options = [5, 10, 30];

  @override
  Widget build(BuildContext context) {
    final bool enabled = onChanged != null;
    final int selectedIndex =
        _options.indexOf(value).clamp(0, _options.length - 1).toInt();

    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Container(
        height: 36.sp,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8.br),
          border: Border.all(color: kDividerColor.withValues(alpha: 0.4)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final segmentWidth = constraints.maxWidth / _options.length;
            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                // ── Sliding pill ─────────────────────────────────────────
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  left: selectedIndex * segmentWidth,
                  top: 0,
                  bottom: 0,
                  width: segmentWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(7.br),
                    ),
                  ),
                ),

                // ── Labels (sit above the pill) ───────────────────────────
                Row(
                  children: [
                    for (final minutes in _options)
                      _SegmentLabel(
                        label: '$minutes min before',
                        selected: value == minutes,
                        onTap: enabled ? () => onChanged!(minutes) : null,
                      ),
                  ],
                ),
              ],
            );
          },
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
                color: selected ? kWhiteColor : const Color(0xFF888888),
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
