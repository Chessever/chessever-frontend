import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// The panel under the search row while games are being picked to save:
/// how many are picked, a quick select, and the save itself. One widget for
/// every screen that lists a player's games.
class PlayerGamesSelectionToolbar extends StatelessWidget {
  const PlayerGamesSelectionToolbar({
    super.key,
    required this.selectedCount,
    required this.subtitle,
    required this.selectAllLabel,
    required this.onSelectAll,
    required this.onAddSelected,
    required this.onClose,
  });

  /// Picked games among those the list shows.
  final int selectedCount;
  final String subtitle;
  final String selectAllLabel;

  /// Null while a quick select is still gathering its games.
  final VoidCallback? onSelectAll;

  /// Offered once a game is picked.
  final VoidCallback onAddSelected;
  final VoidCallback onClose;

  /// The room the panel takes in the header that reserves it, with its gap
  /// below. Larger text adds what its four lines gain.
  static double heightOf(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    double gain(double line) => (scaler.scale(line) - line).clamp(0, 400);
    return 136.h + gain(22.f) * 2 + gain(20.f) * 2;
  }

  @override
  Widget build(BuildContext context) {
    final title =
        selectedCount == 0 ? 'Choose games to save' : '$selectedCount selected';
    return SingleMotionBuilder(
      motion: const CupertinoMotion.bouncy(),
      value: 1.0,
      builder: (context, progress, child) {
        return Opacity(
          opacity: progress.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1.0 - progress) * -10),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(16.br),
                border: Border.all(color: kPrimaryColor.withValues(alpha: 0.3)),
                // No cyan bloom on paper: one tight contact shadow instead.
                boxShadow: [
                  context.isLightTheme
                      ? BoxShadow(
                        color: context.colors.shadow,
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      )
                      : BoxShadow(
                        color: kPrimaryColor.withValues(alpha: 0.1),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: AppTypography.textSmMedium.copyWith(
                                color:
                                    selectedCount == 0
                                        ? context.colors.textPrimary.withValues(
                                          alpha: 0.75,
                                        )
                                        : context.colors.accentText,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 2.h),
                            Text(
                              subtitle,
                              style: AppTypography.textXsRegular.copyWith(
                                color: context.textInk(0.58),
                              ),
                              maxLines: 2,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 8.w),
                      GestureDetector(
                        onTap: onClose,
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10.w,
                            vertical: 8.h,
                          ),
                          decoration: BoxDecoration(
                            color: context.colors.textPrimary.withValues(
                              alpha: 0.1,
                            ),
                            borderRadius: BorderRadius.circular(10.br),
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16.sp,
                            color: context.colors.textPrimary.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10.h),
                  Row(
                    children: [
                      Expanded(
                        child: _SelectionActionButton(
                          label: selectAllLabel,
                          icon: Icons.select_all_rounded,
                          onTap: onSelectAll,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: _SelectionActionButton(
                          label:
                              selectedCount > 0
                                  ? 'Add selected'
                                  : 'Select first',
                          icon: Icons.library_add_rounded,
                          emphasized: selectedCount > 0,
                          onTap: selectedCount > 0 ? onAddSelected : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A game card while games are being picked: the card as it is, with the
/// pick mark and ring painted over it.
class PlayerGamesSelectableCard extends StatelessWidget {
  const PlayerGamesSelectableCard({
    super.key,
    required this.card,
    required this.isSelected,
    this.onTap,
    this.cornerRadius = 14,
  });

  final Widget card;
  final bool isSelected;

  /// Takes every gesture from a card that would otherwise open itself.
  /// Left null for a card whose own tap already picks.
  final VoidCallback? onTap;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // The card is laid out untouched. Selection chrome is painted OVER it,
        // never around it: a `Border` on a parent inflates the box by its width
        // and re-lays the card out, which cost grid cells 1.2px and tripped a
        // RenderFlex overflow on their fixed-width board row.
        card,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(cornerRadius.br),
                border: Border.all(
                  color:
                      isSelected
                          ? (context.isLightTheme
                              ? context.colors.accentText
                              : kPrimaryColor.withValues(alpha: 0.85))
                          : Colors.transparent,
                  width: 1.6,
                ),
                boxShadow:
                    isSelected && !context.isLightTheme
                        ? [
                          BoxShadow(
                            color: kPrimaryColor.withValues(alpha: 0.22),
                            blurRadius: 18,
                            spreadRadius: 0.5,
                            offset: const Offset(0, 2),
                          ),
                        ]
                        : null,
              ),
            ),
          ),
        ),
        // Board and grid cards own their tap/long-press (navigate, context
        // menu). In selection mode that has to become "toggle this game", so an
        // opaque layer takes every gesture before the card sees it.
        if (onTap != null)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              onLongPress: onTap,
              child: const SizedBox.expand(),
            ),
          ),
        Positioned(
          top: -6.h,
          right: -6.w,
          child: Container(
            width: 24.w,
            height: 24.h,
            decoration: BoxDecoration(
              color:
                  isSelected
                      ? kPrimaryColor
                      : context.colors.surface.withValues(alpha: 0.95),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: context.colors.background.withValues(alpha: 0.55),
                  blurRadius: 8,
                  spreadRadius: 0.5,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(
                color:
                    isSelected
                        ? context.colors.textPrimary
                        : context.colors.textPrimary.withValues(alpha: 0.24),
                width: 1.2,
              ),
            ),
            child: Icon(
              isSelected
                  ? Icons.check_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 14.5.sp,
              color: context.colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _SelectionActionButton extends StatelessWidget {
  const _SelectionActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.emphasized = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 9.h),
        decoration: BoxDecoration(
          color:
              enabled
                  ? (emphasized
                      ? kPrimaryColor
                      : context.colors.textPrimary.withValues(alpha: 0.1))
                  : context.colors.textPrimary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10.br),
          border: Border.all(
            color:
                enabled
                    ? (emphasized
                        // Paper: the cyan fill sits near the page's value,
                        // so the rim carries the 3:1 edge in accent ink.
                        ? (context.isLightTheme
                            ? context.colors.accentText
                            : kPrimaryColor.withValues(alpha: 0.8))
                        : context.colors.textPrimary.withValues(alpha: 0.18))
                    : context.colors.textPrimary.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16.sp,
              color:
                  enabled
                      ? context.colors.textPrimary
                      : context.textInk(0.45),
            ),
            SizedBox(width: 6.w),
            Flexible(
              child: Text(
                label,
                style: AppTypography.textSmBold.copyWith(
                  color:
                      enabled
                          ? context.colors.textPrimary
                          : context.textInk(0.45),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
