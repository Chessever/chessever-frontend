import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

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
    return Container(
      height: 44.h,
      padding: EdgeInsets.all(3.sp),
      decoration: BoxDecoration(
        color: context.colors.popup,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children:
            RankingActivity.values.map((activity) {
              final selected = activity == value;
              final label =
                  activity == RankingActivity.active ? 'Active' : 'All';
              return Semantics(
                selected: selected,
                button: true,
                child: InkWell(
                  key: ValueKey('ranking-activity-${activity.name}'),
                  borderRadius: BorderRadius.circular(9.br),
                  onTap: () => onChanged(activity),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    alignment: Alignment.center,
                    padding: EdgeInsets.symmetric(horizontal: 11.w),
                    decoration: BoxDecoration(
                      color:
                          selected
                              ? context.colors.brand.withValues(alpha: 0.18)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(9.br),
                      border: Border.all(
                        color:
                            selected
                                ? context.colors.brand
                                : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      label,
                      style: AppTypography.textXsMedium.copyWith(
                        color:
                            selected
                                ? context.colors.brand
                                : context.colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: RankingActivityControl(
              value: filters.activity,
              onChanged:
                  (value) => onChanged(filters.copyWith(activity: value)),
            ),
          ),
          SizedBox(height: 10.h),
        ],
        _HorizontalOptions<RankingTimeControl>(
          values: RankingTimeControl.values,
          selected: filters.timeControl,
          labelFor: (value) => value.label,
          iconAssetFor:
              (value) =>
                  'assets/pngs/${value.name == 'classical' ? 'classical' : value.name}.png',
          keyPrefix: 'ranking-time-control',
          onSelected:
              (value) => onChanged(filters.copyWith(timeControl: value)),
        ),
        SizedBox(height: 8.h),
        _HorizontalOptions<RankingCategory>(
          values: RankingCategory.values,
          selected: filters.category,
          labelFor: (value) => value.label,
          keyPrefix: 'ranking-category',
          onSelected: (value) => onChanged(filters.copyWith(category: value)),
        ),
      ],
    );
  }
}

class _HorizontalOptions<T> extends StatelessWidget {
  const _HorizontalOptions({
    required this.values,
    required this.selected,
    required this.labelFor,
    required this.keyPrefix,
    required this.onSelected,
    this.iconAssetFor,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelFor;
  final String? Function(T)? iconAssetFor;
  final String keyPrefix;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children:
            values.map((value) {
              final isSelected = value == selected;
              final asset = iconAssetFor?.call(value);
              return Padding(
                padding: EdgeInsets.only(right: 8.w),
                child: Semantics(
                  selected: isSelected,
                  button: true,
                  child: InkWell(
                    key: ValueKey(
                      '$keyPrefix-${labelFor(value).toLowerCase()}',
                    ),
                    borderRadius: BorderRadius.circular(12.br),
                    onTap: () => onSelected(value),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      constraints: BoxConstraints(minHeight: 44.h),
                      padding: EdgeInsets.symmetric(
                        horizontal: 13.w,
                        vertical: 8.h,
                      ),
                      decoration: BoxDecoration(
                        color:
                            isSelected
                                ? context.colors.brand.withValues(alpha: 0.16)
                                : context.colors.popup,
                        borderRadius: BorderRadius.circular(12.br),
                        border: Border.all(
                          color:
                              isSelected
                                  ? context.colors.brand
                                  : context.colors.divider,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (asset != null) ...[
                            Image.asset(
                              asset,
                              width: 24.ic,
                              height: 24.ic,
                              fit: BoxFit.contain,
                            ),
                            SizedBox(width: 7.w),
                          ],
                          Text(
                            labelFor(value),
                            style: AppTypography.textXsMedium.copyWith(
                              color:
                                  isSelected
                                      ? context.colors.textPrimary
                                      : context.colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }
}
