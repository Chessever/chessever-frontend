import 'dart:math' as math;

import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

class RatingTierFilter extends StatelessWidget {
  const RatingTierFilter({
    super.key,
    required this.selectedMinRating,
    required this.onChanged,
  });

  final int? selectedMinRating;
  final ValueChanged<int?> onChanged;

  static const tiers = <RatingTier>[
    RatingTier(label: 'GM', subtitle: '+2500', minRating: 2500),
    RatingTier(label: 'IM', subtitle: '+2400', minRating: 2400),
    RatingTier(label: 'FM', subtitle: '+2300', minRating: 2300),
    RatingTier(label: 'CM', subtitle: '+2200', minRating: 2200),
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
        return '${tier.label} ${tier.subtitle}';
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selected = normalizeMinRating(selectedMinRating);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.hasBoundedWidth
                ? math.min(constraints.maxWidth, 320.0)
                : 320.0;

        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: width,
            child: _TierGrid(selected: selected, onChanged: onChanged),
          ),
        );
      },
    );
  }
}

class _TierGrid extends StatelessWidget {
  const _TierGrid({required this.selected, required this.onChanged});

  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8.sp,
        crossAxisSpacing: 8.sp,
        childAspectRatio: 2.55,
      ),
      itemCount: RatingTierFilter.tiers.length,
      itemBuilder: (context, index) {
        final tier = RatingTierFilter.tiers[index];
        final isSelected = selected == tier.minRating;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(isSelected ? null : tier.minRating),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 7.h),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected ? kPrimaryColor : kBlack2Color,
              borderRadius: BorderRadius.circular(8.br),
              border: Border.all(
                color:
                    isSelected
                        ? kPrimaryColor
                        : kDarkGreyColor.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tier.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textSmBold.copyWith(
                    color: isSelected ? kBlackColor : kWhiteColor,
                  ),
                ),
                SizedBox(width: 5.w),
                Flexible(
                  child: Text(
                    tier.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textXsMedium.copyWith(
                      color:
                          isSelected
                              ? kBlackColor.withValues(alpha: 0.75)
                              : kSecondaryTextColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
