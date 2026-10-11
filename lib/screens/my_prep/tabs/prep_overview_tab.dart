import 'dart:math' as math;

import 'package:chessever2/screens/my_prep/models/prep_models.dart';
import 'package:chessever2/screens/my_prep/services/prep_analysis.dart';
import 'package:chessever2/screens/my_prep/services/prep_repository.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_account_switch.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_common.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_filters.dart';
import 'package:chessever2/screens/my_prep/widgets/prep_rating_history.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

/// The player profile's quiet summary, with secondary analysis on demand.
///
/// One list through every state About has, so its identity and heading keep
/// their place while statistics are read, missing or replaced.
class PrepOverviewTab extends StatelessWidget {
  const PrepOverviewTab({
    super.key,
    required this.profile,
    required this.stats,
    required this.filter,
    this.header,
    this.heading,
    this.message,
    this.stale = false,
    this.arriving = false,
    this.shared = 0,
    this.onOpenGames,
    this.onSources,
  });

  final PrepProfile profile;

  /// Null while there are none to show; [message] then takes their place.
  final PrepStats? stats;
  final PrepFilter filter;

  /// Leads the list, inset by its owner.
  final Widget? header;

  /// Stands in for the tab's own heading, where the profile also shows one
  /// over [message].
  final Widget? heading;

  /// What About says while it has no statistics: games being read, none
  /// downloaded, a failure.
  final Widget? message;

  /// Whether [stats] are those of the source read a moment ago. They stay
  /// where they are, faint and out of reach, so nothing moves while the
  /// chosen source's games are read.
  final bool stale;

  /// Whether [stats] have just taken another source's place, and so settle
  /// in from faint rather than appear at once.
  final bool arriving;

  /// Games two of the sources both hold, which [stats] count once.
  final int shared;
  final ValueChanged<PrepFilter>? onOpenGames;
  final VoidCallback? onSources;

  @override
  Widget build(BuildContext context) {
    final gutter = EdgeInsets.symmetric(
      horizontal: ResponsiveHelper.adaptive(phone: 16.w, tablet: 24.w),
    );
    final s = stats;
    return ListView(
      padding: EdgeInsets.only(top: 6.h, bottom: 40.h),
      children: [
        ?header,
        if (heading != null || s != null) ...[
          Padding(
            padding: gutter,
            child:
                heading ??
                PrepPerformanceHeader(profile: profile, onSources: onSources),
          ),
          SizedBox(height: 12.h),
        ],
        if (s == null)
          ?message
        else
          Padding(
            padding: gutter,
            child: _Settling(
              // A new source's statistics are a new arrival, not the old
              // ones changing.
              key: ValueKey(filter.accountKey ?? ''),
              stale: stale,
              arriving: arriving,
              child: _Statistics(
                profile: profile,
                stats: s,
                filter: filter,
                shared: shared,
                onOpenGames: stale ? null : onOpenGames,
              ),
            ),
          ),
      ],
    );
  }
}

/// How statistics read while they are not the chosen source's own: faint
/// enough to recede, clear enough to stay legible.
const double _kFaint = 0.45;

/// Statistics at full strength once they are the chosen source's own. Those
/// of the source before it wait faint and out of reach; those that replace
/// them settle in from the same faintness, so the change is one movement.
class _Settling extends StatelessWidget {
  const _Settling({
    super.key,
    required this.stale,
    required this.arriving,
    required this.child,
  });

  final bool stale;
  final bool arriving;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: stale,
      child: SingleMotionBuilder(
        value: stale ? 1.0 : 0.0,
        from: arriving ? 1.0 : null,
        motion: kPrepToggleMotion,
        active: !MediaQuery.disableAnimationsOf(context),
        child: child,
        builder: (context, t, child) {
          final faint = t.clamp(0.0, 1.0);
          // At rest the statistics are themselves, not a layer around them.
          if (faint < 0.002) return child!;
          return Opacity(opacity: 1 - (1 - _kFaint) * faint, child: child);
        },
      ),
    );
  }
}

/// Everything About knows about one set of games.
class _Statistics extends StatelessWidget {
  const _Statistics({
    required this.profile,
    required this.stats,
    required this.filter,
    this.shared = 0,
    this.onOpenGames,
  });

  final PrepProfile profile;
  final PrepStats stats;
  final PrepFilter filter;
  final int shared;
  final ValueChanged<PrepFilter>? onOpenGames;

  /// The source every rating figure is on the scale of, named as far as the
  /// profile needs: its site, and its username where the profile holds two
  /// of that site.
  String? get _scale {
    final account = profile.accounts
        .where(
          (a) =>
              stats.ratingPath?.endsWith(PrepRepository.gamesFileName(a)) ??
              false,
        )
        .firstOrNull;
    if (account == null) return stats.ratingSource?.label;
    return profile.accounts.where((a) => a.source == account.source).length > 1
        ? '${account.source.label} · ${prepAccountName(account)}'
        : account.source.label;
  }

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final mine = profile.kind == PrepKind.mine;
    final scale = _scale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OverallSummary(stats: s, filter: filter, onOpenGames: onOpenGames),
        // Why every source together is fewer games than the sources' own
        // counts add up to.
        if (shared > 0) ...[
          SizedBox(height: 8.h),
          Text(
            shared == 1
                ? '1 game is in two sources and is counted once.'
                : '${prepCount(shared)} games are in two sources and are '
                      'counted once.',
            key: const ValueKey('prep_shared_games'),
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
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
                games: white ? s.whiteGames : s.blackGames,
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
                        eco: line.eco,
                        opening: null,
                      ),
                    ),
                  ),
                ],
            ],
          ),
        ],
        if (s.clocks.isNotEmpty) ...[
          SizedBox(height: 12.h),
          _DetailsPanel(
            title: 'Time controls',
            children: [
              _ClockShare(
                clocks: s.clocks,
                source: filter.source,
                onTap: (speed) => onOpenGames?.call(filter.withSpeed(speed)),
              ),
            ],
          ),
        ],
        if (s.ratingHistory.length >= 2) ...[
          SizedBox(height: 12.h),
          _DetailsPanel(
            // Whose rating it is, wherever the profile has more than one.
            title: [
              'Rating history',
              if (profile.accounts.length > 1) ?scale,
              ?s.ratingSpeed?.labelFor(s.ratingSource),
            ].join(' · '),
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
                ('Rating now', s.currentRating?.toString() ?? '–'),
                ('Performance', s.performance?.toString() ?? '–'),
              ],
            ),
            // Several sources are several rating scales: these follow one.
            if (s.accounts > 1 && scale != null) ...[
              SizedBox(height: 8.h),
              Text(
                'Rating figures are from $scale games only: rating scales '
                'differ between sources.',
                key: const ValueKey('prep_rating_scale'),
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
            if (s.decisiveRate case final rate?) ...[
              SizedBox(height: 12.h),
              Text(
                '${prepCount(s.decisive)} decisive games · ${(rate * 100).round()}% decisive',
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
            if (s.averageOpponent != null) ...[
              SizedBox(height: s.decisiveRate == null ? 12.h : 4.h),
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
                  meta: o.rating == null ? null : 'avg ${o.rating}',
                  tally: o.tally,
                  games: o.games,
                  onTap: () =>
                      onOpenGames?.call(filter.copyWith(opponent: o.name)),
                ),
            ],
            if (s.byYear.length > 1) ...[
              SizedBox(height: 24.h),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Games by year',
                      style: AppTypography.textSmBold,
                    ),
                  ),
                  Text(
                    '${prepCount(s.byYear.fold(0, (n, y) => n + y.total))} total',
                    style: AppTypography.textXsRegular.copyWith(
                      color: context.colors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
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

/// About's heading. A profile with several sources also carries the switch
/// between reading them together and reading one alone, and names the choice.
class PrepPerformanceHeader extends StatelessWidget {
  const PrepPerformanceHeader({
    super.key,
    required this.profile,
    this.accountKey,
    this.onAccount,
    this.onSources,
    this.progress,
  });

  final PrepProfile profile;
  final String? accountKey;
  final ValueChanged<String?>? onAccount;
  final VoidCallback? onSources;

  /// What reading the chosen source's games is doing, said in place of its
  /// name until they are read.
  final String? progress;

  static const _title = 'Overall Performance';

  @override
  Widget build(BuildContext context) {
    final onAccount = this.onAccount;
    if (onAccount == null || profile.accounts.length < 2) {
      return Row(
        children: [
          Expanded(child: Text(_title, style: AppTypography.textSmBold)),
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
      );
    }
    // Same order as the My Games source list.
    final accounts = [
      for (final source in PrepSource.values)
        ...profile.accounts.where((a) => a.source == source),
    ];
    final chosen = accounts.where((a) => a.key == accountKey).firstOrNull;
    final caption = AppTypography.textXsRegular.copyWith(
      color: context.colors.textSecondary,
    );
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_title, style: AppTypography.textSmBold),
        if (progress case final reading?)
          PrepShimmerText(
            reading,
            key: const ValueKey('prep_switch_progress'),
            style: caption.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          )
        else
          Text(
            chosen == null
                ? 'Combined · ${accounts.length} sources'
                : '${chosen.source.label} · ${prepAccountName(chosen)}',
            key: const ValueKey('prep_switch_caption'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: caption,
          ),
      ],
    );
    final choice = PrepAccountSwitch(
      accounts: accounts,
      selectedKey: chosen?.key,
      onSelected: onAccount,
    );
    return LayoutBuilder(
      builder: (context, box) {
        final title = TextPainter(
          text: TextSpan(text: _title, style: AppTypography.textSmBold),
          textDirection: TextDirection.ltr,
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final titleWidth = title.width;
        title.dispose();
        // Decided by the title alone, so choosing a source with a longer
        // name never moves the switch to another line.
        final beside =
            titleWidth + 12.w + PrepAccountSwitch.widthOf(context, accounts) <=
            box.maxWidth;
        if (beside) {
          return Row(
            children: [
              Expanded(child: heading),
              SizedBox(width: 12.w),
              choice,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading,
            SizedBox(height: 4.h),
            // More sources than the line holds scroll under the heading,
            // running off the screen's edge rather than being cut at the
            // margin.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: choice,
            ),
          ],
        );
      },
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
                  label: 'Games analyzed',
                  value: prepCount(stats.overall.total),
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
    required this.games,
    required this.onTap,
  });
  final String label;
  final PrepTally tally;

  /// Every game with the colour: what a tap lists, unfinished ones too.
  final int games;
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
              prepGamesLabel(games),
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
          games: line.games,
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
    required this.games,
    this.meta,
    this.onTap,
  });

  final String title;
  final String? meta;
  final PrepTally tally;

  /// Every game in the row: what a tap lists, unfinished ones too.
  final int games;
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
                  '${prepCount(games)} · ${score == null ? '–' : '${(score * 100).round()}%'}',
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
  final List<PrepYearLine> years;
  final ValueChanged<int>? onYear;

  /// How many years fit before the row scrolls.
  static const _fit = 10;

  @override
  Widget build(BuildContext context) {
    final most = years.fold<int>(1, (m, y) => math.max(m, y.total));
    Widget bar(PrepYearLine y) => InkWell(
      onTap: () => onYear?.call(y.year),
      child: _Bar(
        fraction: y.total / most,
        tally: y.tally,
        rest: y.total - y.tally.total,
        label: "'${(y.year % 100).toString().padLeft(2, '0')}",
        value: prepCount(y.total),
      ),
    );
    return SizedBox(
      height: 120.h,
      child: years.length <= _fit
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [for (final y in years) Expanded(child: bar(y))],
            )
          // Every year is kept; the newest stay in view and the rest scroll.
          : LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final y in years)
                      SizedBox(
                        width: constraints.maxWidth / _fit,
                        height: 120.h,
                        child: bar(y),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// How the games divide by clock. A row opens its games.
class _ClockShare extends StatelessWidget {
  const _ClockShare({required this.clocks, required this.onTap, this.source});
  final List<(PrepTimeControl?, int)> clocks;
  final PrepSource? source;
  final ValueChanged<PrepTimeControl> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final total = clocks.fold<int>(0, (n, c) => n + c.$2);
    return Column(
      children: [
        for (final (speed, count) in clocks)
          InkWell(
            onTap: speed == null ? null : () => onTap(speed),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      speed?.labelFor(source) ?? 'Unknown',
                      style: AppTypography.textSmMedium.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '${prepCount(count)} · ${(count * 100 / total).round()}%',
                    style: AppTypography.textXsMedium.copyWith(
                      color: colors.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: speed == null
                        ? Colors.transparent
                        : colors.iconSecondary,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _LengthBars extends StatelessWidget {
  const _LengthBars({required this.lengths});
  final List<int> lengths;

  static const _labels = PrepStats.lengthLabels;

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
    this.rest = 0,
  });

  final double fraction;
  final String label;
  final String value;
  final PrepTally? tally;

  /// Games without a result, drawn above the results as their own segment.
  final int rest;

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
                child: t == null || t.total + rest == 0
                    ? ColoredBox(
                        color: colors.textPrimary.withValues(alpha: 0.35),
                        child: const SizedBox.expand(),
                      )
                    : Column(
                        children: [
                          if (rest > 0)
                            Expanded(
                              flex: rest,
                              child: ColoredBox(
                                color: colors.textPrimary.withValues(
                                  alpha: 0.18,
                                ),
                                child: const SizedBox.expand(),
                              ),
                            ),
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
