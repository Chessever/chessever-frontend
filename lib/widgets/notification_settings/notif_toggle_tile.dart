import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// A self-contained settings tile: title/subtitle + adaptive switch.
///
/// By default ([showCard] = true) the tile wraps itself in its own card
/// container.  Set [showCard] = false when embedding multiple tiles inside a
/// shared card (e.g. a grouped section) — the tile then renders only its
/// content so the parent can provide the card decoration.
///
/// Pass [trailing] to render extra content below the subtitle (e.g. a
/// segmented lead-time control). Pass [badge] to show a pill label next to
/// the title (e.g. [BetaBadge]).
class NotifToggleTile extends StatelessWidget {
  const NotifToggleTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.badge,
    this.trailing,
    this.showCard = true,
  });

  final String title;
  final String subtitle;
  final bool value;

  /// Null disables the switch (greyed out).
  final ValueChanged<bool>? onChanged;

  /// Optional widget placed to the right of the title (e.g. BetaBadge).
  final Widget? badge;

  /// Optional widget rendered below the subtitle (e.g. NotifLeadTimeControl).
  final Widget? trailing;

  /// When false the tile renders without its own card decoration.
  /// Use this when grouping multiple tiles inside a shared card.
  final bool showCard;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: AppTypography.textMdMedium.copyWith(
                          color: context.colors.textPrimary,
                          fontSize: 13.f,
                        ),
                      ),
                      if (badge != null) ...[SizedBox(width: 6.sp), badge!],
                    ],
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    subtitle,
                    style: AppTypography.textSmRegular.copyWith(
                      color: context.colors.textPrimaryMuted,
                      fontSize: 11.f,
                    ),
                  ),
                ],
              ),
            ),
            Switch.adaptive(
              value: value,
              onChanged: onChanged,
              thumbColor: WidgetStateProperty.resolveWith(
                (states) =>
                    states.contains(WidgetState.selected)
                        ? kPrimaryColor
                        : kWhiteColor.withValues(alpha: 0.6),
              ),
              trackColor: WidgetStateProperty.resolveWith(
                (states) =>
                    states.contains(WidgetState.selected)
                        ? kPrimaryColor.withValues(alpha: 0.35)
                        : kDividerColor.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
        if (trailing != null) ...[SizedBox(height: 12.h), trailing!],
      ],
    );

    if (!showCard) return content;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 14.sp),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kDividerColor.withValues(alpha: 0.5)),
      ),
      child: content,
    );
  }
}
