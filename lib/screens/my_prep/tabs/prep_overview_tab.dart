import 'dart:math' as math;

import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// Desktop Prep's statistics dashboard, laid out for a phone: headline
/// numbers, the result split, each colour, openings, opponents, activity
/// by year and game length.
class PrepOverviewTab extends StatelessWidget {
  const PrepOverviewTab({
    super.key,
    required this.profile,
    required this.stats,
    required this.filter,
  });

  final PrepProfile profile;
  final PrepStats stats;
  final PrepFilter filter;

  @override
  Widget build(BuildContext context) {
    final gutter = ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);
    final s = stats;
    final mine = profile.kind == PrepKind.mine;
    String pct(double? v) => v == null ? '–' : '${(v * 100).round()}%';
    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 6.h, gutter, 40.h),
      children: [
        PrepStatStrip(
          items: [
            ('Games', prepCount(s.games)),
            ('Score', pct(s.overall.score)),
            ('Peak', s.peakRating?.toString() ?? '–'),
            ('Performance', s.performance?.toString() ?? '–'),
          ],
        ),
        SizedBox(height: 12.h),
        _Panel(
          title: 'Results',
          trailing: s.averageOpponent == null
              ? null
              : 'Avg. opponent ${s.averageOpponent}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PrepResultBar(tally: s.overall, height: 8),
              SizedBox(height: 10.h),
              Row(
                children: [
                  _Figure('Wins', s.overall.wins, context.colors.successStrong),
                  _Figure('Draws', s.overall.draws, context.colors.textSecondary),
                  _Figure('Losses', s.overall.losses, context.colors.danger),
                ],
              ),
            ],
          ),
        ),
        SizedBox(height: 12.h),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _ColorCard(
                label: mine ? 'As White' : 'Their White',
                tally: s.asWhite,
                white: true,
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: _ColorCard(
                label: mine ? 'As Black' : 'Their Black',
                tally: s.asBlack,
                white: false,
              ),
            ),
          ],
        ),
        if (s.whiteOpenings.isNotEmpty) ...[
          SizedBox(height: 12.h),
          _Panel(
            title: mine ? 'Openings as White' : 'Their openings as White',
            child: _OpeningList(lines: s.whiteOpenings),
          ),
        ],
        if (s.blackOpenings.isNotEmpty) ...[
          SizedBox(height: 12.h),
          _Panel(
            title: mine ? 'Openings as Black' : 'Their openings as Black',
            child: _OpeningList(lines: s.blackOpenings),
          ),
        ],
        if (s.opponents.isNotEmpty) ...[
          SizedBox(height: 12.h),
          _Panel(
            title: 'Most played opponents',
            child: Column(
              children: [
                for (final o in s.opponents)
                  _LineRow(
                    title: o.name,
                    meta: o.rating == null ? null : '${o.rating}',
                    tally: o.tally,
                  ),
              ],
            ),
          ),
        ],
        if (s.byYear.length > 1) ...[
          SizedBox(height: 12.h),
          _Panel(title: 'Games by year', child: _YearBars(years: s.byYear)),
        ],
        SizedBox(height: 12.h),
        _Panel(title: 'Game length', child: _LengthBars(lengths: s.lengths)),
        if (s.overall.total < s.games) ...[
          SizedBox(height: 12.h),
          Text(
            '${prepCount(s.games - s.overall.total)} games are not counted in '
            'results: unfinished, or the player’s name did not match.',
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});

  final String title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.all(14.sp),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.textSmBold.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: AppTypography.textXsRegular.copyWith(
                    color: colors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          SizedBox(height: 12.h),
          child,
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          prepCount(value),
          style: AppTypography.textLgBold.copyWith(
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          label,
          style: AppTypography.textXsRegular.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
      ],
    ),
  );
}

class _ColorCard extends StatelessWidget {
  const _ColorCard({required this.label, required this.tally, required this.white});

  final String label;
  final PrepTally tally;
  final bool white;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final score = tally.score;
    return Container(
      padding: EdgeInsets.all(14.sp),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12.sp,
                height: 12.sp,
                decoration: BoxDecoration(
                  color: white ? Colors.white : Colors.black,
                  borderRadius: BorderRadius.circular(3.br),
                  border: Border.all(color: colors.dividerStrong),
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                label,
                style: AppTypography.textXsMedium.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            score == null ? '–' : '${(score * 100).round()}%',
            style: AppTypography.textXlBold.copyWith(
              color: colors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text(
            prepGamesLabel(tally.total),
            style: AppTypography.textXsRegular.copyWith(
              color: colors.textTertiary,
            ),
          ),
          SizedBox(height: 10.h),
          PrepResultBar(tally: tally),
          SizedBox(height: 6.h),
          PrepTallyText(tally: tally),
        ],
      ),
    );
  }
}

class _OpeningList extends StatelessWidget {
  const _OpeningList({required this.lines});
  final List<PrepOpeningLine> lines;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final line in lines)
        _LineRow(title: line.name, meta: line.eco, tally: line.tally),
    ],
  );
}

/// A named row with its game count, score and result bar.
class _LineRow extends StatelessWidget {
  const _LineRow({required this.title, required this.tally, this.meta});

  final String title;
  final String? meta;
  final PrepTally tally;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final score = tally.score;
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: title),
                      if (meta != null)
                        TextSpan(
                          text: '  $meta',
                          style: TextStyle(color: colors.textTertiary),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textSmMedium.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                '${prepCount(tally.total)} · ${score == null ? '–' : '${(score * 100).round()}%'}',
                style: AppTypography.textXsMedium.copyWith(
                  color: colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          SizedBox(height: 6.h),
          PrepResultBar(tally: tally, height: 4),
        ],
      ),
    );
  }
}

class _YearBars extends StatelessWidget {
  const _YearBars({required this.years});
  final List<(int, PrepTally)> years;

  @override
  Widget build(BuildContext context) {
    final shown = years.length > 10 ? years.sublist(years.length - 10) : years;
    final most = shown.fold<int>(1, (m, y) => math.max(m, y.$2.total));
    return SizedBox(
      height: 120.h,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (year, tally) in shown)
            Expanded(
              child: _Bar(
                fraction: tally.total / most,
                tally: tally,
                label: "'${(year % 100).toString().padLeft(2, '0')}",
                value: prepCount(tally.total),
              ),
            ),
        ],
      ),
    );
  }
}

class _LengthBars extends StatelessWidget {
  const _LengthBars({required this.lengths});
  final List<int> lengths;

  static const _labels = ['≤20', '21–40', '41–60', '61–80', '80+'];

  @override
  Widget build(BuildContext context) {
    final most = lengths.fold<int>(1, math.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 100.h,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < lengths.length; i++)
                Expanded(
                  child: _Bar(
                    fraction: lengths[i] / most,
                    label: _labels[i],
                    value: prepCount(lengths[i]),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: 6.h),
        Text(
          'Moves per game',
          style: AppTypography.textXsRegular.copyWith(
            color: context.colors.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// One column of a small bar chart; split by result when [tally] is given.
class _Bar extends StatelessWidget {
  const _Bar({
    required this.fraction,
    required this.label,
    required this.value,
    this.tally,
  });

  final double fraction;
  final String label;
  final String value;
  final PrepTally? tally;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = tally;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 3.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            value,
            maxLines: 1,
            style: AppTypography.textXxsRegular.copyWith(
              color: colors.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(height: 3.h),
          Flexible(
            child: FractionallySizedBox(
              heightFactor: fraction.clamp(0.02, 1.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3.br),
                child: t == null || t.total == 0
                    ? ColoredBox(
                        color: colors.textPrimary.withValues(alpha: 0.35),
                        child: const SizedBox.expand(),
                      )
                    : Column(
                        children: [
                          if (t.losses > 0)
                            Expanded(
                              flex: t.losses,
                              child: ColoredBox(
                                color: colors.danger,
                                child: const SizedBox.expand(),
                              ),
                            ),
                          if (t.draws > 0)
                            Expanded(
                              flex: t.draws,
                              child: ColoredBox(
                                color: colors.textTertiary,
                                child: const SizedBox.expand(),
                              ),
                            ),
                          if (t.wins > 0)
                            Expanded(
                              flex: t.wins,
                              child: ColoredBox(
                                color: colors.successStrong,
                                child: const SizedBox.expand(),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            label,
            maxLines: 1,
            style: AppTypography.textXxsRegular.copyWith(
              color: colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
