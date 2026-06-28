import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Level (minimum-Elo tier) picker rendered in the shared filter-chip
/// language: kPrimary when selected, recessed surface otherwise, two
/// equal-width chips per row so the four tiers read as a tidy grid.
class RatingTierFilter extends StatelessWidget {
  const RatingTierFilter({
    super.key,
    required this.selectedMinRating,
    required this.onChanged,
  });

  final int? selectedMinRating;
  final ValueChanged<int?> onChanged;

  static const tiers = <RatingTier>[
    RatingTier(label: '2500+', subtitle: '', minRating: 2500),
    RatingTier(label: '2400+', subtitle: '', minRating: 2400),
    RatingTier(label: '2300+', subtitle: '', minRating: 2300),
    RatingTier(label: '2200+', subtitle: '', minRating: 2200),
  ];

  static int? normalizeMinRating(int? minRating) {
    if (minRating == null) return null;

    for (final tier in tiers) {
      if (minRating >= tier.minRating) return tier.minRating;
    }

    return null;
  }

  static String? labelForMinRating(int? minRating) {
    final normalized = normalizeMinRating(minRating);
    if (normalized == null) return null;

    for (final tier in tiers) {
      if (tier.minRating == normalized) {
        return tier.label;
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selected = normalizeMinRating(selectedMinRating);

    // Cap matches the historical 320 width so wide hosts (tablet panels,
    // board sidebars) don't stretch the chips across the whole pane; in the
    // 320-wide filter dialogs the grid simply fills the content width.
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _RatingChip(
                    label: 'Any',
                    isSelected: selected == null,
                    onTap: () => onChanged(null),
                  ),
                ),
                SizedBox(width: 8.w),
                const Expanded(child: SizedBox.shrink()),
              ],
            ),
            SizedBox(height: 8.h),
            for (var i = 0; i < tiers.length; i += 2) ...[
              if (i > 0) SizedBox(height: 8.h),
              Row(
                children: [
                  Expanded(
                    child: _TierChip(
                      tier: tiers[i],
                      isSelected: selected == tiers[i].minRating,
                      onChanged: onChanged,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: i + 1 < tiers.length
                        ? _TierChip(
                            tier: tiers[i + 1],
                            isSelected: selected == tiers[i + 1].minRating,
                            onChanged: onChanged,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? kPrimaryColor : context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(8.br),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.textXsMedium.copyWith(
            color: isSelected ? kBlackColor : context.colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _TierChip extends StatelessWidget {
  const _TierChip({
    required this.tier,
    required this.isSelected,
    required this.onChanged,
  });

  final RatingTier tier;
  final bool isSelected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(isSelected ? null : tier.minRating),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? kPrimaryColor : context.colors.surfaceRecessed,
          borderRadius: BorderRadius.circular(8.br),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              tier.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textXsMedium.copyWith(
                color: isSelected ? kBlackColor : context.colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (tier.subtitle.isNotEmpty) ...[
              SizedBox(width: 4.w),
              Flexible(
                child: Text(
                  tier.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textXsMedium.copyWith(
                    color: isSelected
                        ? kBlackColor.withValues(alpha: 0.7)
                        : context.colors.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class RatingTier {
  const RatingTier({
    required this.label,
    required this.subtitle,
    required this.minRating,
  });

  final String label;
  final String subtitle;
  final int minRating;
}
