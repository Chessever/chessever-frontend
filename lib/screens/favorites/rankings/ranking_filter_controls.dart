import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// Horizontal inset matching the Rankings search row.
double get _stripInset => 12.w;

/// Vertical padding outside the painted chip (keeps the tap target large while
/// the pill itself stays compact).
double get _chipTouchPadding => 8.h;

/// Gap between chips inside the same group (time controls, or categories).
double get _intraGroupGap => 2.w;

/// Gap between the time-control group and the category group.
double get _interGroupGap => 6.w;

double get _chipPadH => 5.w;
double get _chipPadV => 5.h;
double get _chipIconSize => 12.ic;

/// Dense label style so owl/rabbit/lightning + Overall/Women/Juniors/Girls can
/// share one phone-width row. Tighter than [AppTypography.textXsMedium] (which
/// uses a tall 20/12 line-height and wide default tracking).
TextStyle _chipLabelStyle({required Color color, required bool selected}) {
  return TextStyle(
    fontFamily: 'InterDisplay',
    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
    fontSize: 11.f,
    height: 1.15,
    letterSpacing: -0.2,
    color: color,
  );
}

/// Spring used when a time-control chip expands to show its label.
const _labelMotion = CupertinoMotion.smooth();

/// One ranking filter chip: compact bordered pill, not a tappable slab.
///
/// [showLabel] always paints the text. [expandLabelWhenSelected] is for the
/// icon time-control group: unselected chips stay icon-only; the selected one
/// springs the label in with Motor.
class _RankingChip extends StatelessWidget {
  const _RankingChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.iconAsset,
    this.showLabel = true,
    this.expandLabelWhenSelected = false,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final String? iconAsset;
  final bool showLabel;
  final bool expandLabelWhenSelected;

  @override
  Widget build(BuildContext context) {
    final labelColor =
        isSelected ? kBlackColor : context.colors.textPrimary;
    final style = _chipLabelStyle(color: labelColor, selected: isSelected);

    return Semantics(
      label: label,
      excludeSemantics: true,
      selected: isSelected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: _chipTouchPadding),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(
              horizontal: _chipPadH,
              vertical: _chipPadV,
            ),
            decoration: BoxDecoration(
              color:
                  isSelected ? kPrimaryColor : context.colors.surfaceRecessed,
              borderRadius: BorderRadius.circular(14.br),
              border: Border.all(
                color: isSelected ? kPrimaryColor : context.colors.divider,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (iconAsset != null)
                  Image.asset(
                    iconAsset!,
                    width: _chipIconSize,
                    height: _chipIconSize,
                    fit: BoxFit.contain,
                  ),
                if (expandLabelWhenSelected)
                  SingleMotionBuilder(
                    motion: _labelMotion,
                    value: isSelected ? 1.0 : 0.0,
                    builder: (context, t, child) {
                      if (t <= 0.001) return const SizedBox.shrink();
                      return ClipRect(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          widthFactor: t.clamp(0.0, 1.0),
                          child: Opacity(
                            opacity: t.clamp(0.0, 1.0),
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 2.w),
                        Text(
                          label,
                          maxLines: 1,
                          softWrap: false,
                          style: style,
                        ),
                      ],
                    ),
                  )
                else if (showLabel) ...[
                  if (iconAsset != null) SizedBox(width: 2.w),
                  Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: style,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tight row of chips that belong to one filter group.
class _ChipGroup extends StatelessWidget {
  const _ChipGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: _intraGroupGap),
          children[i],
        ],
      ],
    );
  }
}

/// One-line rail of chip groups. Uses [FittedBox] scale-down so the full
/// time-control + category set stays on screen at phone width without a
/// horizontal scroll (gaps stay proportional if a slight scale is needed).
class _ChipStrip extends StatelessWidget {
  const _ChipStrip({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: _stripInset),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(width: _interGroupGap),
                children[i],
              ],
            ],
          ),
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
          if (activity != RankingActivity.values.first)
            SizedBox(width: _intraGroupGap),
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
        ],
        _ChipStrip(
          children: [
            _ChipGroup(
              children: [
                for (final timeControl in RankingTimeControl.values)
                  _RankingChip(
                    key: ValueKey(
                      'ranking-time-control-${timeControl.label.toLowerCase()}',
                    ),
                    label: timeControl.label,
                    iconAsset: timeControl.iconAsset,
                    showLabel: false,
                    expandLabelWhenSelected: true,
                    isSelected: timeControl == filters.timeControl,
                    onTap:
                        () => onChanged(
                          filters.copyWith(timeControl: timeControl),
                        ),
                  ),
              ],
            ),
            _ChipGroup(
              children: [
                for (final category in RankingCategory.values)
                  _RankingChip(
                    key: ValueKey(
                      'ranking-category-${category.label.toLowerCase()}',
                    ),
                    label: category.label,
                    isSelected: category == filters.category,
                    onTap:
                        () =>
                            onChanged(filters.copyWith(category: category)),
                  ),
              ],
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
