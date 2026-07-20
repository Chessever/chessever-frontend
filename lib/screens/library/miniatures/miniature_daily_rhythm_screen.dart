import 'package:chessever2/repository/gamebase/miniatures/miniatures_models.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/number_format_utils.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/skeleton_widget.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';

/// Full drill-down for the About tab's "How many arrive each day" section.
/// Renders the whole fetched daily series (up to 90 days) as a horizontally
/// scrollable bar chart, with a tap-to-inspect selected day.
class MiniatureDailyRhythmScreen extends ConsumerStatefulWidget {
  const MiniatureDailyRhythmScreen({super.key, required this.window});

  final MiniatureGamesWindow window;

  @override
  ConsumerState<MiniatureDailyRhythmScreen> createState() =>
      _MiniatureDailyRhythmScreenState();
}

class _MiniatureDailyRhythmScreenState
    extends ConsumerState<MiniatureDailyRhythmScreen> {
  MiniatureDailyCount? _selectedDay;

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(miniatureStatsProvider(widget.window));
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.w,
      tablet: 24.w,
    );

    Widget content = statsAsync.when(
      loading: () => const _DailyRhythmSkeleton(),
      error:
          (error, _) => _DailyRhythmError(
            onRetry:
                () => ref.invalidate(miniatureStatsProvider(widget.window)),
          ),
      data:
          (stats) => _DailyRhythmBody(
            stats: stats,
            selectedDay: _selectedDay,
            onSelectDay: (day) {
              HapticFeedbackService.selection();
              setState(() => _selectedDay = day);
            },
          ),
    );

    content = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        12.h,
        horizontalPadding,
        32.h,
      ),
      child: content,
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

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        title: Text(
          'Daily rhythm',
          style: AppTypography.textMdMedium.copyWith(
            color: context.colors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(child: content),
    );
  }
}

class _DailyRhythmBody extends StatelessWidget {
  const _DailyRhythmBody({
    required this.stats,
    required this.selectedDay,
    required this.onSelectDay,
  });

  final MiniatureStats stats;
  final MiniatureDailyCount? selectedDay;
  final ValueChanged<MiniatureDailyCount> onSelectDay;

  @override
  Widget build(BuildContext context) {
    if (stats.daily.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 40.h),
        child: Center(
          child: Text(
            'No daily data in this window yet.',
            style: AppTypography.textSmRegular.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ),
      );
    }

    // The API returns newest first; a time series should read left to right.
    final series = stats.daily.reversed.toList(growable: false);
    final busiest = stats.busiestDay;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryLine(stats: stats, days: series.length),
        SizedBox(height: 24.h),
        _DailyBarChart(
          series: series,
          selectedDay: selectedDay,
          onSelectDay: onSelectDay,
        ),
        SizedBox(height: 12.h),
        _SelectedDayLine(day: selectedDay),
        SizedBox(height: 24.h),
        _HighlightsRow(stats: stats, busiest: busiest),
      ],
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.stats, required this.days});

  final MiniatureStats stats;
  final int days;

  @override
  Widget build(BuildContext context) {
    final busiest = stats.busiestDay;
    final parts = <String>[
      'Averaging ${_trimDecimal(stats.perDayAverage)} miniatures a day '
          'over $days ${days == 1 ? 'day' : 'days'}.',
      if (busiest != null)
        '${_formatDayLabel(busiest.date)} was the busiest with '
            '${formatCompactCount(busiest.games)}.',
    ];

    return Text(
      parts.join(' '),
      style: AppTypography.textSmRegular.copyWith(
        color: context.colors.textSecondary,
        height: 1.5,
      ),
    );
  }
}

class _DailyBarChart extends StatelessWidget {
  const _DailyBarChart({
    required this.series,
    required this.selectedDay,
    required this.onSelectDay,
  });

  final List<MiniatureDailyCount> series;
  final MiniatureDailyCount? selectedDay;
  final ValueChanged<MiniatureDailyCount> onSelectDay;

  @override
  Widget build(BuildContext context) {
    final peak = series.fold<int>(
      1,
      (max, day) => day.games > max ? day.games : max,
    );

    return Container(
      padding: EdgeInsets.fromLTRB(12.w, 14.h, 12.w, 10.h),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14.br),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 160.h,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              physics: const BouncingScrollPhysics(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < series.length; i++) ...[
                    if (i > 0) SizedBox(width: 3.w),
                    _DailyBar(
                      day: series[i],
                      peak: peak,
                      isSelected: selectedDay?.date == series[i].date,
                      onTap: () => onSelectDay(series[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(height: 8.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDayLabel(series.first.date),
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textTertiary,
                ),
              ),
              Text(
                _formatDayLabel(series.last.date),
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

class _DailyBar extends StatelessWidget {
  const _DailyBar({
    required this.day,
    required this.peak,
    required this.isSelected,
    required this.onTap,
  });

  final MiniatureDailyCount day;
  final int peak;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 10.w,
        height: double.infinity,
        child: FractionallySizedBox(
          heightFactor: (day.games / peak).clamp(0.03, 1.0),
          alignment: Alignment.bottomCenter,
          child: Container(
            decoration: BoxDecoration(
              color: kPrimaryColor.withValues(alpha: isSelected ? 1.0 : 0.4),
              borderRadius: BorderRadius.vertical(top: Radius.circular(2.br)),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedDayLine extends StatelessWidget {
  const _SelectedDayLine({required this.day});

  final MiniatureDailyCount? day;

  @override
  Widget build(BuildContext context) {
    final selected = day;
    return Text(
      selected == null
          ? 'Tap a bar to see that day\'s count.'
          : '${_formatFullDayLabel(selected.date)}: '
              '${formatCompactCount(selected.games)} '
              '${selected.games == 1 ? 'miniature' : 'miniatures'}.',
      style: AppTypography.textXsMedium.copyWith(
        color:
            selected == null
                ? context.colors.textTertiary
                : context.colors.textPrimary,
      ),
    );
  }
}

class _HighlightsRow extends StatelessWidget {
  const _HighlightsRow({required this.stats, required this.busiest});

  final MiniatureStats stats;
  final MiniatureDailyCount? busiest;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12.br),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Busiest day',
                  style: AppTypography.textXsRegular.copyWith(
                    color: context.colors.textTertiary,
                  ),
                ),
                SizedBox(height: 3.h),
                Text(
                  busiest == null
                      ? 'No data'
                      : '${_formatFullDayLabel(busiest!.date)} · '
                          '${formatCompactCount(busiest!.games)} games',
                  style: AppTypography.textSmMedium.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Days covered',
                style: AppTypography.textXsRegular.copyWith(
                  color: context.colors.textTertiary,
                ),
              ),
              SizedBox(height: 3.h),
              Text(
                '${stats.dailyDays}',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DailyRhythmSkeleton extends StatelessWidget {
  const _DailyRhythmSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SkeletonWidget(
          child: Container(
            height: 36.h,
            width: double.infinity,
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(8.br),
            ),
          ),
        ),
        SizedBox(height: 24.h),
        SkeletonWidget(
          child: Container(
            height: 190.h,
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(14.br),
            ),
          ),
        ),
        SizedBox(height: 24.h),
        SkeletonWidget(
          child: Container(
            height: 64.h,
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(12.br),
            ),
          ),
        ),
      ],
    );
  }
}

class _DailyRhythmError extends StatelessWidget {
  const _DailyRhythmError({required this.onRetry});

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

String _formatFullDayLabel(String isoDate) {
  final parsed = DateTime.tryParse(isoDate);
  if (parsed == null) return isoDate;
  return DateFormat('MMM d, y').format(parsed);
}
