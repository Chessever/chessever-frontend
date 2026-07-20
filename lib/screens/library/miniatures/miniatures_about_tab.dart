import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/library/miniatures/miniature_daily_rhythm_screen.dart';
import 'package:chessever2/screens/library/miniatures/miniature_game_launcher.dart';
import 'package:chessever2/screens/library/miniatures/miniature_hall_of_fame_screen.dart';
import 'package:chessever2/screens/library/miniatures/miniature_openings_detail_screen.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_mode_provider.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// ECO volume letters spelled out, so the opening breakdown reads as chess
/// rather than as database codes.
const Map<String, String> _ecoCategoryNames = {
  'A': 'Flank & irregular openings',
  'B': 'Semi-open games (Sicilian, Caro-Kann…)',
  'C': 'Open games & the French',
  'D': 'Closed & semi-closed games',
  'E': 'Indian defences',
};

const Map<String, String> _timeControlNames = {
  'CLASSICAL': 'Classical',
  'RAPID': 'Rapid',
  'BLITZ': 'Blitz',
};

/// Explains what a miniature is, then a compact dashboard of live aggregates
/// with three "explore" cards that drill into a full-screen view each:
/// openings, daily rhythm, and the hall of fame of shortest/strongest games.
class MiniaturesAboutTab extends ConsumerStatefulWidget {
  const MiniaturesAboutTab({super.key});

  @override
  ConsumerState<MiniaturesAboutTab> createState() => _MiniaturesAboutTabState();
}

class _MiniaturesAboutTabState extends ConsumerState<MiniaturesAboutTab>
    with AutomaticKeepAliveClientMixin, ScrollToTopListenerMixin {
  final ScrollController _scrollController = ScrollController();
  MiniatureGamesWindow _window = MiniatureGamesWindow.all;

  /// Latched true the first time this tab becomes the selected one.
  bool _activated = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void onScrollToTopRequested() {
    animateScrollControllerToTop(_scrollController);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _openMiniature(GamebaseMiniature miniature) {
    final games = <GamesTourModel>[miniature.toGamesTourModel()];
    return openMiniatureGame(
      context: context,
      ref: ref,
      games: games,
      index: 0,
    );
  }

  void _openOpenings() {
    HapticFeedbackService.buttonPress();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MiniatureOpeningsDetailScreen(window: _window),
      ),
    );
  }

  void _openDailyRhythm() {
    HapticFeedbackService.buttonPress();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MiniatureDailyRhythmScreen(window: _window),
      ),
    );
  }

  void _openHallOfFame() {
    HapticFeedbackService.buttonPress();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MiniatureHallOfFameScreen(window: _window),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Stats are not fetched until the tab is first opened, but once they are
    // the watch stays put so switching tabs does not auto-dispose and refetch.
    _activated |=
        ref.watch(selectedMiniaturesModeProvider) == MiniaturesScreenMode.about;
    if (!_activated) return const SizedBox.shrink();

    final statsAsync = ref.watch(miniatureStatsProvider(_window));
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );

    Widget content = ListView(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        12.h,
        horizontalPadding,
        32.h,
      ),
      children: [
        const _WhatIsAMiniature(),
        SizedBox(height: 20.h),
        SegmentedSwitcher(
          options: const ['Today', 'This week', 'All time'],
          currentSelection: MiniatureGamesWindow.values.indexOf(_window),
          onSelectionChanged: (index) {
            HapticFeedbackService.selection();
            setState(() => _window = MiniatureGamesWindow.values[index]);
          },
        ),
        SizedBox(height: 20.h),
        statsAsync.when(
          loading: () => const _AboutSkeleton(),
          error:
              (error, _) => _AboutError(
                onRetry: () => ref.invalidate(miniatureStatsProvider(_window)),
              ),
          data:
              (stats) => _StatsBody(
                stats: stats,
                onOpenGame: _openMiniature,
                onOpenOpenings: _openOpenings,
                onOpenDailyRhythm: _openDailyRhythm,
                onOpenHallOfFame: _openHallOfFame,
              ),
        ),
      ],
    );

    if (ResponsiveHelper.isTablet) {
      content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.contentMaxWidth,
          ),
          child: content,
        ),
      );
    }

    return content;
  }
}

class _WhatIsAMiniature extends StatelessWidget {
  const _WhatIsAMiniature();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.sp),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14.br),
        border: Border.all(
          color: context.colors.textPrimary.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'A miniature is a game that ends early and ends badly.',
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
              height: 1.35,
            ),
          ),
          SizedBox(height: 10.h),
          Text(
            'An opening goes wrong, a piece hangs, a king gets caught in the '
            'centre, and the game is over before it really began.',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textSecondary,
              height: 1.5,
            ),
          ),
          SizedBox(height: 14.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: const [
              _RuleChip('3–25 moves'),
              _RuleChip('Decisive only, no draws'),
              _RuleChip('Mate or a confirmed winning position'),
            ],
          ),
        ],
      ),
    );
  }
}

class _RuleChip extends StatelessWidget {
  const _RuleChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: context.colors.surfaceRecessed,
        borderRadius: BorderRadius.circular(8.br),
      ),
      child: Text(
        label,
        style: AppTypography.textXsMedium.copyWith(
          color: context.colors.textPrimary,
        ),
      ),
    );
  }
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({
    required this.stats,
    required this.onOpenGame,
    required this.onOpenOpenings,
    required this.onOpenDailyRhythm,
    required this.onOpenHallOfFame,
  });

  final MiniatureStats stats;
  final Future<void> Function(GamebaseMiniature) onOpenGame;
  final VoidCallback onOpenOpenings;
  final VoidCallback onOpenDailyRhythm;
  final VoidCallback onOpenHallOfFame;

  @override
  Widget build(BuildContext context) {
    if (stats.total == 0) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 40.h),
        child: Center(
          child: Text(
            'No miniatures in this window yet.',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeadlineNumbers(stats: stats),
        SizedBox(height: 24.h),
        _ColourSplit(stats: stats),
        if (stats.daily.length >= 2) ...[
          SizedBox(height: 24.h),
          _DailyRhythm(stats: stats, onSeeAll: onOpenDailyRhythm),
        ],
        if (stats.byEcoCategory.isNotEmpty) ...[
          SizedBox(height: 24.h),
          _EcoBreakdown(stats: stats),
        ],
        if (stats.byOpening.isNotEmpty) ...[
          SizedBox(height: 24.h),
          _OpeningsPreview(stats: stats, onSeeAll: onOpenOpenings),
        ],
        if (stats.byTimeControl.isNotEmpty) ...[
          SizedBox(height: 24.h),
          _TimeControlSplit(stats: stats),
        ],
        if (stats.shortestGames.isNotEmpty ||
            stats.topRatedGames.isNotEmpty) ...[
          SizedBox(height: 24.h),
          _HallOfFamePreview(
            stats: stats,
            onOpenGame: onOpenGame,
            onSeeAll: onOpenHallOfFame,
          ),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.caption, this.onSeeAll});

  final String title;
  final String? caption;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTypography.textMdMedium.copyWith(
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (onSeeAll != null)
              GestureDetector(
                onTap: onSeeAll,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'See all',
                      style: AppTypography.textXsMedium.copyWith(
                        color: kPrimaryColor,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 16.sp,
                      color: kPrimaryColor,
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (caption != null) ...[
          SizedBox(height: 6.h),
          Text(
            caption!,
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textSecondary,
              height: 1.45,
            ),
          ),
        ],
        SizedBox(height: 12.h),
      ],
    );
  }
}

class _HeadlineNumbers extends StatelessWidget {
  const _HeadlineNumbers({required this.stats});

  final MiniatureStats stats;

  @override
  Widget build(BuildContext context) {
    final ratedNote =
        (stats.ratedSampleSize ?? 0) > 0 && stats.ratedSampleSize! < stats.total
            ? 'rated · ${formatCompactCount(stats.ratedSampleSize!)} sample'
            : 'average rating';

    return _StatRow(
      children: [
        _BigStat(value: formatCompactCount(stats.total), label: 'miniatures'),
        _BigStat(
          value: _trimDecimal(stats.avgMoves),
          label: 'moves on average',
        ),
        _BigStat(
          // Unrated events are common in the imported data, so this is blank
          // rather than a misleading zero when nothing in the window is rated.
          value: stats.avgRating > 0 ? '${stats.avgRating}' : '—',
          label: ratedNote,
        ),
      ],
    );
  }
}

/// Lays stat tiles on one shared baseline. Without the intrinsic height a
/// two-line label in one tile leaves its neighbours short and centred, which
/// reads as a broken grid.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(width: 12.w),
            Expanded(child: children[i]),
          ],
        ],
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: AppTypography.textLgMedium.copyWith(
                color: context.colors.textPrimary,
                fontSize: 24.sp,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            label,
            style: AppTypography.textXsRegular.copyWith(
              color: context.colors.textSecondary,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _ColourSplit extends StatelessWidget {
  const _ColourSplit({required this.stats});

  final MiniatureStats stats;

  @override
  Widget build(BuildContext context) {
    final whiteFlex = stats.whiteWins.clamp(1, 1 << 30);
    final blackFlex = stats.blackWins.clamp(1, 1 << 30);
    final leader = stats.whiteWinRate >= stats.blackWinRate ? 'White' : 'Black';
    final leadRate =
        stats.whiteWinRate >= stats.blackWinRate
            ? stats.whiteWinRate
            : stats.blackWinRate;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: 'Who wins the short games',
          caption: '$leader takes ${_trimDecimal(leadRate)}% of them.',
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(6.br),
          child: SizedBox(
            height: 12.h,
            child: Row(
              children: [
                Expanded(
                  flex: whiteFlex,
                  child: const ColoredBox(color: kMoveStatWhiteColor),
                ),
                Expanded(
                  flex: blackFlex,
                  child: const ColoredBox(color: kMoveStatBlackColor),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 10.h),
        Row(
          children: [
            Expanded(
              child: _ColourLegend(
                colour: kMoveStatWhiteColor,
                label: 'White wins',
                value:
                    '${formatCompactCount(stats.whiteWins)} · ${_trimDecimal(stats.whiteWinRate)}%',
              ),
            ),
            Expanded(
              child: _ColourLegend(
                colour: kMoveStatBlackColor,
                label: 'Black wins',
                value:
                    '${formatCompactCount(stats.blackWins)} · ${_trimDecimal(stats.blackWinRate)}%',
                alignEnd: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ColourLegend extends StatelessWidget {
  const _ColourLegend({
    required this.colour,
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final Color colour;
  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final swatch = Container(
      width: 8.w,
      height: 8.w,
      decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
    );

    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment:
              alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!alignEnd) ...[swatch, SizedBox(width: 6.w)],
            Text(
              label,
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            if (alignEnd) ...[SizedBox(width: 6.w), swatch],
          ],
        ),
        SizedBox(height: 2.h),
        Text(
          value,
          style: AppTypography.textSmMedium.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _DailyRhythm extends StatelessWidget {
  const _DailyRhythm({required this.stats, required this.onSeeAll});

  final MiniatureStats stats;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    // The API returns newest first; a time series should read left to right.
    // The preview only ever shows the most recent two weeks — the full range
    // (up to 90 days) lives behind "See all".
    final series = stats.daily.reversed
        .toList(growable: false)
        .skip((stats.daily.length - 14).clamp(0, stats.daily.length))
        .toList(growable: false);
    final peak = series.fold<int>(
      1,
      (max, day) => day.games > max ? day.games : max,
    );
    final busiest = stats.busiestDay;

    return GestureDetector(
      onTap: onSeeAll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle(
            title: 'How many arrive each day',
            caption: [
              'About ${_trimDecimal(stats.perDayAverage)} a day.',
              if (busiest != null)
                'Busiest was ${_formatDayLabel(busiest.date)} with '
                    '${formatCompactCount(busiest.games)}.',
            ].join(' '),
            onSeeAll: onSeeAll,
          ),
          SizedBox(
            height: 72.h,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < series.length; i++) ...[
                  if (i > 0) SizedBox(width: 2.w),
                  Expanded(
                    child: FractionallySizedBox(
                      heightFactor: (series[i].games / peak).clamp(0.04, 1.0),
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        decoration: BoxDecoration(
                          color: kPrimaryColor.withValues(
                            alpha: series[i].games == peak ? 0.95 : 0.45,
                          ),
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(3.br),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(height: 8.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                series.isEmpty ? '' : _formatDayLabel(series.first.date),
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textTertiary,
                ),
              ),
              Text(
                series.isEmpty ? '' : _formatDayLabel(series.last.date),
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EcoBreakdown extends StatelessWidget {
  const _EcoBreakdown({required this.stats});

  final MiniatureStats stats;

  @override
  Widget build(BuildContext context) {
    final peak = stats.byEcoCategory.fold<int>(
      1,
      (max, bucket) => bucket.games > max ? bucket.games : max,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: 'Where they come from',
          caption:
              'Grouped by ECO volume, with how often White lands the blow.',
        ),
        for (final bucket in stats.byEcoCategory)
          Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 18.w,
                      child: Text(
                        bucket.value ?? '–',
                        style: AppTypography.textSmMedium.copyWith(
                          color: kPrimaryColor,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _ecoCategoryNames[bucket.value] ?? 'Unclassified',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.textXsRegular.copyWith(
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    Text(
                      '${formatCompactCount(bucket.games)} · '
                      '${_trimDecimal(bucket.whiteWinRate)}% W',
                      style: AppTypography.textXsRegular.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6.h),
                _ProportionBar(fraction: bucket.games / peak),
              ],
            ),
          ),
      ],
    );
  }
}

class _ProportionBar extends StatelessWidget {
  const _ProportionBar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3.br),
      child: SizedBox(
        height: 6.h,
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: context.colors.surfaceRecessed),
            ),
            FractionallySizedBox(
              widthFactor: fraction.clamp(0.02, 1.0),
              heightFactor: 1,
              alignment: Alignment.centerLeft,
              child: ColoredBox(color: kPrimaryColor.withValues(alpha: 0.75)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Top 3 openings only — the full ranked list (up to 50) lives in
/// [MiniatureOpeningsDetailScreen], reachable from "See all".
class _OpeningsPreview extends StatelessWidget {
  const _OpeningsPreview({required this.stats, required this.onSeeAll});

  final MiniatureStats stats;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final top = stats.byOpening.take(3).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: 'Openings that keep producing them',
          caption: '${formatCompactCount(stats.byOpening.length)} tracked.',
          onSeeAll: onSeeAll,
        ),
        GestureDetector(
          onTap: onSeeAll,
          child: Container(
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(12.br),
            ),
            child: Column(
              children: [
                for (var i = 0; i < top.length; i++)
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12.w,
                      vertical: 10.h,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 34.w,
                          child: Text(
                            top[i].eco ?? '–',
                            style: AppTypography.textXsMedium.copyWith(
                              color: kPrimaryColor,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            top[i].displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.textXsRegular.copyWith(
                              color: context.colors.textPrimary,
                            ),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          '${formatCompactCount(top[i].games)} · '
                          '${_trimDecimal(top[i].avgMoves)} mv',
                          style: AppTypography.textXsRegular.copyWith(
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TimeControlSplit extends StatelessWidget {
  const _TimeControlSplit({required this.stats});

  final MiniatureStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(title: 'By time control'),
        _StatRow(
          children: [
            for (final bucket in stats.byTimeControl)
              _BigStat(
                value: formatCompactCount(bucket.games),
                label:
                    _timeControlNames[bucket.value] ??
                    (bucket.value ?? 'Other'),
              ),
          ],
        ),
      ],
    );
  }
}

/// Two games only — the full hall of fame (up to 20 each side of
/// shortest/strongest) lives in [MiniatureHallOfFameScreen].
class _HallOfFamePreview extends StatelessWidget {
  const _HallOfFamePreview({
    required this.stats,
    required this.onOpenGame,
    required this.onSeeAll,
  });

  final MiniatureStats stats;
  final Future<void> Function(GamebaseMiniature) onOpenGame;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final games =
        stats.shortestGames.isNotEmpty
            ? stats.shortestGames.take(2).toList(growable: false)
            : stats.topRatedGames.take(2).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          title: 'Hall of fame',
          caption: 'The quickest collapses and the strongest company.',
          onSeeAll: onSeeAll,
        ),
        for (final game in games)
          Padding(
            padding: EdgeInsets.only(bottom: 8.h),
            child: _NotableGameRow(game: game, onTap: () => onOpenGame(game)),
          ),
      ],
    );
  }
}

class _NotableGameRow extends StatelessWidget {
  const _NotableGameRow({required this.game, required this.onTap});

  final GamebaseMiniature game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final whiteWins = game.result == 'W';
    final winner = (whiteWins ? game.whiteName : game.blackName) ?? 'Unknown';
    final loser = (whiteWins ? game.blackName : game.whiteName) ?? 'Unknown';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.br),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(12.br),
        ),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${game.finalMoveNumber}',
                  style: AppTypography.textMdMedium.copyWith(
                    color: kPrimaryColor,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  'moves',
                  style: AppTypography.textXsRegular.copyWith(
                    color: context.colors.textTertiary,
                    fontSize: 9.sp,
                  ),
                ),
              ],
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$winner beat $loser',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textSmMedium.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 3.h),
                  Text(
                    _subtitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textXsRegular.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            Icon(
              Icons.chevron_right_rounded,
              size: 20.sp,
              color: context.colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[];
    final opening = game.openingDisplayName ?? game.eco;
    if (opening != null && opening.isNotEmpty) parts.add(opening);
    if (game.avgRating != null && game.avgRating! > 0) {
      parts.add('avg ${game.avgRating}');
    }
    if (game.date != null) {
      parts.add(DateFormat('MMM y').format(game.date!.toUtc()));
    }
    return parts.join(' · ');
  }
}

class _AboutSkeleton extends StatelessWidget {
  const _AboutSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        4,
        (index) => Padding(
          padding: EdgeInsets.only(bottom: 16.h),
          child: SkeletonWidget(
            child: Container(
              height: index == 0 ? 84.h : 120.h,
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(12.br),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AboutError extends StatelessWidget {
  const _AboutError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 40.h),
      child: Column(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 36.sp,
            color: context.colors.textSecondary,
          ),
          SizedBox(height: 14.h),
          Text(
            'Could not load the numbers',
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          SizedBox(height: 16.h),
          GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: context.colors.surfaceRecessed,
                borderRadius: BorderRadius.circular(10.br),
              ),
              child: Text(
                'Retry',
                style: AppTypography.textXsMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `20.0` reads as noise next to `20.2`, so whole numbers drop the decimal.
String _trimDecimal(double value) {
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toStringAsFixed(1);
}

String _formatDayLabel(String isoDate) {
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  return DateFormat('MMM d').format(parsed);
}
