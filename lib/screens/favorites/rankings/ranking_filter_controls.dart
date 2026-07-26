import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Horizontal inset for the scrolling strips. The padding lives *inside* the
/// scroll view (as it does on the Games tab) so the edge fade falls on empty
/// gutter at rest and only ever eats into a chip once the strip is actually
/// scrolled.
/// A getter, not a `final`: a top-level final is computed once and cached, so
/// it would freeze the first scale it ever saw and go stale when the responsive
/// metrics change.
double get _stripInset => 16.w;

/// One ranking filter chip.
///
/// Selected chips take a solid [kPrimaryColor] fill with black text — the same
/// treatment the rating-tier and Games filter chips use. These controls sit
/// directly under the Favorites/Games/Rankings switcher, so a chip with its own
/// accent language would read as a second design bolted onto the screen.
class _RankingChip extends StatelessWidget {
  const _RankingChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.iconAsset,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final String? iconAsset;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isSelected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          // The text alone sits well under a comfortable tap target, so the
          // chip holds a floor height rather than relying on padding.
          constraints: BoxConstraints(minHeight: 44.h),
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? kPrimaryColor : context.colors.surfaceRecessed,
            borderRadius: BorderRadius.circular(8.br),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (iconAsset != null) ...[
                Image.asset(
                  iconAsset!,
                  width: 18.ic,
                  height: 18.ic,
                  fit: BoxFit.contain,
                ),
                SizedBox(width: 6.w),
              ],
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.textXsMedium.copyWith(
                  color: isSelected ? kBlackColor : context.colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A swipeable strip of chips that fades at both edges instead of guillotining
/// whichever chip happens to land on the boundary.
///
/// Children are laid out in a plain [Row] rather than a builder: there are only
/// ever three or four of them, and building them all keeps every option
/// reachable to semantics even when it starts off-screen.
class _ChipStrip extends StatelessWidget {
  const _ChipStrip({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback:
          (bounds) => const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Colors.transparent,
              Colors.white,
              Colors.white,
              Colors.transparent,
            ],
            stops: [0.0, 0.03, 0.97, 1.0],
          ).createShader(bounds),
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: _stripInset),
        child: Row(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: 8.w),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Active / All scope. Compact enough to sit beside the search field.
class RankingActivityControl extends StatelessWidget {
  const RankingActivityControl({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final RankingActivity value;
  final ValueChanged<RankingActivity> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final activity in RankingActivity.values) ...[
          if (activity != RankingActivity.values.first) SizedBox(width: 6.w),
          _RankingChip(
            key: ValueKey('ranking-activity-${activity.name}'),
            label: activity == RankingActivity.active ? 'Active' : 'All',
            isSelected: activity == value,
            onTap: () => onChanged(activity),
          ),
        ],
      ],
    );
  }
}

class RankingFilterControls extends StatelessWidget {
  const RankingFilterControls({
    super.key,
    required this.filters,
    required this.onChanged,
    this.showActivity = true,
  });

  final RankingFilters filters;
  final ValueChanged<RankingFilters> onChanged;
  final bool showActivity;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showActivity) ...[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: _stripInset),
            child: RankingActivityControl(
              value: filters.activity,
              onChanged:
                  (value) => onChanged(filters.copyWith(activity: value)),
            ),
          ),
          SizedBox(height: 10.h),
        ],
        _ChipStrip(
          children: [
            for (final timeControl in RankingTimeControl.values)
              _RankingChip(
                key: ValueKey(
                  'ranking-time-control-${timeControl.label.toLowerCase()}',
                ),
                label: timeControl.label,
                iconAsset: timeControl.iconAsset,
                isSelected: timeControl == filters.timeControl,
                onTap:
                    () => onChanged(filters.copyWith(timeControl: timeControl)),
              ),
          ],
        ),
        SizedBox(height: 8.h),
        _ChipStrip(
          children: [
            for (final category in RankingCategory.values)
              _RankingChip(
                key: ValueKey(
                  'ranking-category-${category.label.toLowerCase()}',
                ),
                label: category.label,
                isSelected: category == filters.category,
                onTap: () => onChanged(filters.copyWith(category: category)),
              ),
          ],
        ),
      ],
    );
  }
}

extension _RankingTimeControlIcon on RankingTimeControl {
  String get iconAsset => switch (this) {
    RankingTimeControl.classical => PngAsset.classicalIcon,
    RankingTimeControl.rapid => PngAsset.rapidIcon,
    RankingTimeControl.blitz => PngAsset.blitzIcon,
  };
}
