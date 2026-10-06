import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart' show TappableScale;
import 'package:flutter/material.dart';

/// Which side the prepared player had.
enum PrepSide { both, white, black }

/// The slice of games every tab of a profile shows.
@immutable
class PrepFilter {
  const PrepFilter({this.source, this.speed, this.side = PrepSide.both});

  final PrepSource? source;
  final PrepTimeControl? speed;
  final PrepSide side;

  PrepFilter copyWith({
    Object? source = _keep,
    Object? speed = _keep,
    PrepSide? side,
  }) => PrepFilter(
    source: identical(source, _keep) ? this.source : source as PrepSource?,
    speed: identical(speed, _keep) ? this.speed : speed as PrepTimeControl?,
    side: side ?? this.side,
  );

  bool matches(PrepGame g) =>
      (source == null || g.source == source) &&
      (speed == null || g.speed == speed) &&
      switch (side) {
        PrepSide.both => true,
        PrepSide.white => g.playerIsWhite == true,
        PrepSide.black => g.playerIsWhite == false,
      };

  List<PrepGame> apply(List<PrepGame> games) =>
      source == null && speed == null && side == PrepSide.both
      ? games
      : [for (final g in games) if (matches(g)) g];
}

const Object _keep = Object();

/// Source and clock chips, showing only what the downloaded games contain.
class PrepFilterBar extends StatelessWidget {
  const PrepFilterBar({
    super.key,
    required this.games,
    required this.profile,
    required this.filter,
    required this.onChanged,
  });

  final List<PrepGame> games;
  final PrepProfile profile;
  final PrepFilter filter;
  final ValueChanged<PrepFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final speeds = <PrepTimeControl, int>{};
    final sources = <PrepSource>{};
    for (final g in games) {
      if (g.speed != null) speeds[g.speed!] = (speeds[g.speed!] ?? 0) + 1;
      sources.add(g.source);
    }
    final orderedSpeeds = PrepTimeControl.values.where(speeds.containsKey);
    final single = sources.length == 1 ? sources.first : null;
    if (games.isEmpty) return SizedBox(height: 8.h);
    final gutter = ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);
    return SizedBox(
      height: 52.h,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.fromLTRB(gutter, 10.h, gutter, 6.h),
        children: [
          if (sources.length > 1) ...[
            for (final source in PrepSource.values.where(sources.contains))
              PrepChip(
                leading: PrepSourceMark(source: source, size: 14.sp),
                label: source.label,
                selected: filter.source == source,
                onTap: () => onChanged(
                  filter.copyWith(source: filter.source == source ? null : source),
                ),
              ),
            _Divider(),
          ],
          PrepChip(
            label: 'All games',
            selected: filter.speed == null,
            onTap: () => onChanged(filter.copyWith(speed: null)),
          ),
          for (final speed in orderedSpeeds)
            PrepChip(
              label: speed.labelFor(filter.source ?? single),
              count: speeds[speed],
              selected: filter.speed == speed,
              onTap: () => onChanged(
                filter.copyWith(speed: filter.speed == speed ? null : speed),
              ),
            ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 6.h),
    child: VerticalDivider(width: 1, color: context.colors.divider),
  );
}

/// A compact toggle chip; filled ink when on.
class PrepChip extends StatelessWidget {
  const PrepChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = selected ? colors.textInverse : colors.textPrimary;
    return Padding(
      padding: EdgeInsets.only(right: 6.w),
      child: Semantics(
        button: true,
        selected: selected,
        child: TappableScale(
          scaleDown: 0.97,
          onTap: () {
            HapticFeedbackService.selection();
            onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            constraints: BoxConstraints(minHeight: 36.h),
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? colors.textPrimary : colors.surface,
              borderRadius: BorderRadius.circular(10.br),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[leading!, SizedBox(width: 6.w)],
                Text(
                  label,
                  style: AppTypography.textXsMedium.copyWith(color: ink),
                ),
                if (count != null) ...[
                  SizedBox(width: 5.w),
                  Text(
                    prepCount(count!),
                    style: AppTypography.textXsRegular.copyWith(
                      color: ink.withValues(alpha: 0.6),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
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

/// White / Black / Both, as one segmented row.
class PrepSidePicker extends StatelessWidget {
  const PrepSidePicker({
    super.key,
    required this.side,
    required this.onChanged,
    this.mine = false,
  });

  final PrepSide side;
  final ValueChanged<PrepSide> onChanged;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    String label(PrepSide s) => switch (s) {
      PrepSide.both => 'Both colours',
      PrepSide.white => mine ? 'As White' : 'Their White',
      PrepSide.black => mine ? 'As Black' : 'Their Black',
    };
    return Row(
      children: [
        for (final s in [PrepSide.white, PrepSide.black, PrepSide.both])
          PrepChip(
            label: label(s),
            selected: side == s,
            onTap: () => onChanged(s),
          ),
      ],
    );
  }
}
