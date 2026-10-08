import 'dart:math' as math;

import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_rating_history.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';

/// The player profile's quiet summary, with secondary analysis on demand.
class PrepOverviewTab extends StatelessWidget {
  const PrepOverviewTab({
    super.key,
    required this.profile,
    required this.stats,
    required this.filter,
    this.header,
    this.onOpenGames,
    this.onSources,
  });

  final PrepProfile profile;
  final PrepStats stats;
  final PrepFilter filter;
  final Widget? header;
  final ValueChanged<PrepFilter>? onOpenGames;
  final VoidCallback? onSources;

  @override
  Widget build(BuildContext context) {
    final gutter = ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w);
    final s = stats;
    final mine = profile.kind == PrepKind.mine;
    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 6.h, gutter, 40.h),
      children: [
        if (header != null) header!,
        Row(
          children: [
            Expanded(
              child: Text(
                'Overall Performance',
                style: AppTypography.textSmBold,
              ),
            ),
            if (profile.accounts.isNotEmpty)
              IconButton(
                tooltip: 'Manage sources',
                onPressed: onSources,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                icon: PrepSourceMarks(
                  sources: profile.accounts.map((a) => a.source),
                  size: 16.sp,
                ),
              ),
          ],
        ),
        SizedBox(height: 12.h),
        _OverallSummary(stats: s, filter: filter, onOpenGames: onOpenGames),
        SizedBox(height: 20.h),
        _DetailsPanel(
          title: 'Performance by colour',
          children: [
            for (final white in [true, false]) ...[
              if (!white) SizedBox(height: 20.h),
              _ColourRow(
                label: mine
                    ? (white ? 'As White' : 'As Black')
                    : (white ? 'Their White' : 'Their Black'),
                tally: white ? s.asWhite : s.asBlack,
                onTap: () => onOpenGames?.call(
                  filter.copyWith(
                    side: white ? PrepSide.white : PrepSide.black,
                  ),
                ),
              ),
            ],
          ],
        ),
        if (s.whiteOpenings.isNotEmpty || s.blackOpenings.isNotEmpty) ...[
          SizedBox(height: 12.h),
          _DetailsPanel(
            title: 'Opening repertoire',
            children: [
              for (final white in [true, false])
                if ((white ? s.whiteOpenings : s.blackOpenings).isNotEmpty) ...[
                  Text(
                    white ? 'As White' : 'As Black',
                    style: AppTypography.textXsMedium.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  _OpeningList(
                    lines: white ? s.whiteOpenings : s.blackOpenings,
                    onTap: (line) => onOpenGames?.call(
                      filter.copyWith(
                        side: white ? PrepSide.white : PrepSide.black,
                        eco: null,
                        opening: line.name,
                      ),
                    ),
                  ),
                ],
            ],
          ),
        ],
        if (s.ratingHistory.length >= 2) ...[
          SizedBox(height: 12.h),
          _DetailsPanel(
            title: 'Rating history',
            children: [PrepRatingHistory(points: s.ratingHistory)],
          ),
        ],
        SizedBox(height: 12.h),
        _DetailsPanel(
          title: 'More statistics',
          children: [
            PrepStatStrip(
              items: [
                ('Peak rating', s.peakRating?.toString() ?? '–'),
                ('Performance', s.performance?.toString() ?? '–'),
              ],
            ),
            if (s.averageOpponent != null) ...[
              SizedBox(height: 12.h),
              Text(
                'Average opponent rating ${s.averageOpponent}',
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
            if (s.opponents.isNotEmpty) ...[
              SizedBox(height: 24.h),
              Text('Most played opponents', style: AppTypography.textSmBold),
              SizedBox(height: 12.h),
              for (final o in s.opponents)
                _LineRow(
                  title: o.name,
                  meta: o.rating?.toString(),
                  tally: o.tally,
                  onTap: () =>
                      onOpenGames?.call(filter.copyWith(opponent: o.name)),
                ),
            ],
            if (s.byYear.length > 1) ...[
              SizedBox(height: 24.h),
              Text('Games by year', style: AppTypography.textSmBold),
              SizedBox(height: 12.h),
              _YearBars(
                years: s.byYear,
                onYear: (year) =>
                    onOpenGames?.call(filter.copyWith(year: year)),
              ),
            ],
            SizedBox(height: 24.h),
            Text('Game length', style: AppTypography.textSmBold),
            SizedBox(height: 12.h),
            _LengthBars(lengths: s.lengths),
            if (s.overall.total < s.games) ...[
              SizedBox(height: 16.h),
              Text(
                '${prepCount(s.games - s.overall.total)} games are excluded from results because they are unfinished or the player name did not match.',
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// A single surface replaces the headline strip and three result cards.
class _OverallSummary extends StatelessWidget {
  const _OverallSummary({
    required this.stats,
    required this.filter,
    this.onOpenGames,
  });
  final PrepStats stats;
  final PrepFilter filter;
  final ValueChanged<PrepFilter>? onOpenGames;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final score = stats.overall.score;
    return Container(
      padding: EdgeInsets.all(16.sp),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _SummaryValue(
                  label: 'Games',
                  value: prepCount(stats.games),
                ),
              ),
              Expanded(
                child: _SummaryValue(
                  label: 'Score',
                  value: score == null ? '–' : '${(score * 100).round()}%',
                  end: true,
                ),
              ),
            ],
          ),
          SizedBox(height: 20.h),
          PrepResultBar(tally: stats.overall, height: 8),
          SizedBox(height: 16.h),
          Row(
            children: [
              for (final outcome in [
                PrepOutcome.win,
                PrepOutcome.draw,
                PrepOutcome.loss,
              ])
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8.br),
                    onTap: () => onOpenGames?.call(
                      filter.copyWith(
                        outcome: filter.outcome == outcome ? null : outcome,
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 4.h),
                      child: Column(
                        children: [
                          Text(
                            prepCount(switch (outcome) {
                              PrepOutcome.win => stats.overall.wins,
                              PrepOutcome.draw => stats.overall.draws,
                              _ => stats.overall.losses,
                            }),
                            style: AppTypography.textLgBold.copyWith(
                              color: switch (outcome) {
                                PrepOutcome.win => colors.accentText,
                                PrepOutcome.draw => colors.textSecondary,
                                _ => colors.danger,
                              },
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            switch (outcome) {
                              PrepOutcome.win => 'Wins',
                              PrepOutcome.draw => 'Draws',
                              _ => 'Losses',
                            },
                            style: AppTypography.textXsRegular.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.label,
    required this.value,
    this.end = false,
  });
  final String label;
  final String value;
  final bool end;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: AppTypography.textXsRegular.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
      SizedBox(height: 4.h),
      Text(
        value,
        style: AppTypography.textXlBold.copyWith(
          color: context.colors.textPrimary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

/// Uses the platform expansion control; details never crowd the first view.
class _DetailsPanel extends StatelessWidget {
  const _DetailsPanel({required this.title, required this.children});
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: PageStorageKey(title),
    title: Text(title, style: AppTypography.textSmMedium),
    backgroundColor: context.colors.surface,
    collapsedBackgroundColor: context.colors.surface,
    textColor: context.colors.textPrimary,
    collapsedTextColor: context.colors.textPrimary,
    iconColor: context.colors.iconSecondary,
    collapsedIconColor: context.colors.iconSecondary,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.br)),
    collapsedShape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12.br),
    ),
    tilePadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 2.h),
    childrenPadding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 16.h),
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ],
  );
}

class _ColourRow extends StatelessWidget {
  const _ColourRow({
    required this.label,
    required this.tally,
    required this.onTap,
  });
  final String label;
  final PrepTally tally;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: AppTypography.textSmMedium)),
            Text(
              tally.score == null ? '–' : '${(tally.score! * 100).round()}%',
              style: AppTypography.textLgBold,
            ),
            SizedBox(width: 8.w),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: context.colors.iconSecondary,
            ),
          ],
        ),
        SizedBox(height: 8.h),
        PrepResultBar(tally: tally, height: 4),
        SizedBox(height: 8.h),
        Wrap(
          spacing: 12.w,
          runSpacing: 4.h,
          children: [
            Text(
              prepGamesLabel(tally.total),
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            PrepTallyText(tally: tally),
          ],
        ),
      ],
    ),
  );
}

class _OpeningList extends StatelessWidget {
  const _OpeningList({required this.lines, this.onTap});
  final List<PrepOpeningLine> lines;
  final ValueChanged<PrepOpeningLine>? onTap;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (final line in lines)
        _LineRow(
          title: line.name,
          meta: line.eco,
          tally: line.tally,
          onTap: onTap == null ? null : () => onTap!(line),
        ),
    ],
  );
}

/// A named row with its game count, score and result bar.
class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.title,
    required this.tally,
    this.meta,
    this.onTap,
  });

  final String title;
  final String? meta;
  final PrepTally tally;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final score = tally.score;
    return InkWell(
      onTap: onTap,
      child: Padding(
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
      ),
    );
  }
}

class _YearBars extends StatelessWidget {
  const _YearBars({required this.years, this.onYear});
  final List<(int, PrepTally)> years;
  final ValueChanged<int>? onYear;

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
              child: InkWell(
                onTap: () => onYear?.call(year),
                child: _Bar(
                  fraction: tally.total / most,
                  tally: tally,
                  label: "'${(year % 100).toString().padLeft(2, '0')}",
                  value: prepCount(tally.total),
                ),
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
                                color: colors.brand,
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
