import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Two-segment control for selecting heads-up lead time: 10 or 30 minutes.
///
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
    return Opacity(
      opacity: onChanged != null ? 1.0 : 0.4,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8.br),
          border: Border.all(color: kDividerColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            _Segment(
              label: '10 minutes before',
              selected: value == 10,
              isFirst: true,
              onTap: onChanged != null ? () => onChanged!(10) : null,
            ),
            _Segment(
              label: '30 minutes before',
              selected: value == 30,
              isFirst: false,
              onTap: onChanged != null ? () => onChanged!(30) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.isFirst,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isFirst;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          padding: EdgeInsets.symmetric(vertical: 9.sp),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF2A2A2A) : Colors.transparent,
            borderRadius: BorderRadius.horizontal(
              left: isFirst ? Radius.circular(8.br) : Radius.zero,
              right: isFirst ? Radius.zero : Radius.circular(8.br),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.textSmRegular.copyWith(
              color: selected ? kWhiteColor : const Color(0xFF888888),
              fontSize: 12.f,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
