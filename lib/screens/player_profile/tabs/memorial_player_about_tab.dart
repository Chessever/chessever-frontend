import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:chessever2/repository/gamebase/memorial_player_about.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/scroll_to_top_bus.dart';

class MemorialPlayerAboutTab extends ConsumerStatefulWidget {
  const MemorialPlayerAboutTab({
    super.key,
    required this.sourceIdentity,
    required this.playerName,
    required this.playerKey,
  });

  final String sourceIdentity;
  final String playerName;
  final PlayerProfileKey playerKey;

  @override
  ConsumerState<MemorialPlayerAboutTab> createState() =>
      _MemorialPlayerAboutTabState();
}

class _MemorialPlayerAboutTabState extends ConsumerState<MemorialPlayerAboutTab>
    with AutomaticKeepAliveClientMixin, ScrollToTopListenerMixin {
  final ScrollController _scrollController = ScrollController();

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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final overview = ref.watch(
      memorialPlayerOverviewProvider(widget.sourceIdentity),
    );
    final analytics = ref.watch(
      twicPlayerStatsProvider(
        TwicPlayerStatsRequest(
          playerKey: widget.playerKey,
          scope: TwicStatsScope.allGames,
        ),
      ),
    );
    return overview.when(
      data:
          (data) =>
              data == null
                  ? const _AboutStatus(
                    message: 'Historical profile details are unavailable.',
                  )
                  : _AboutContent(
                    controller: _scrollController,
                    overview: data,
                    fallbackName: widget.playerName,
                    analytics: analytics.valueOrNull,
                    analyticsLoading: analytics.isLoading,
                  ),
      loading:
          () => const _AboutStatus(
            message: 'Loading historical profile…',
            loading: true,
          ),
      error:
          (_, _) => const _AboutStatus(
            message: 'Historical profile details are unavailable.',
          ),
    );
  }
}

class _AboutContent extends StatelessWidget {
  const _AboutContent({
    required this.controller,
    required this.overview,
    required this.fallbackName,
    required this.analytics,
    required this.analyticsLoading,
  });

  final ScrollController controller;
  final MemorialPlayerOverview overview;
  final String fallbackName;
  final PlayerAnalytics? analytics;
  final bool analyticsLoading;

  @override
  Widget build(BuildContext context) {
    final player = overview.player;
    final about = overview.about;
    final name = _naturalName(player.name.isEmpty ? fallbackName : player.name);
    final summary =
        about?.summary.isNotEmpty == true
            ? about!.summary
            : <String>[
              _fallbackSummary(
                name: name,
                title: player.title,
                federation: player.fed,
                birthDate: player.birthDate,
                deathDate: player.deathDate,
              ),
            ];
    final highlights = (about?.achievements ?? const [])
        .where((item) => !_isPeakRatingAchievement(item.label))
        .toList(growable: false);
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.0,
      tablet: 32.0,
    );

    return ListView(
      controller: controller,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        18,
        horizontalPadding,
        32,
      ),
      children: [
        if (analytics != null || analyticsLoading) ...[
          _PerformanceSummary(analytics: analytics, loading: analyticsLoading),
          const SizedBox(height: 14),
        ],
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Life & career',
                style: AppTypography.textLgBold.copyWith(
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 28,
                runSpacing: 18,
                children: [
                  _LifeFact(
                    label: 'Born',
                    value: formatMemorialProfileDate(player.birthDate),
                    detail: about?.birthPlace,
                  ),
                  _LifeFact(
                    label: 'Died',
                    value: formatMemorialProfileDate(player.deathDate),
                    detail: about?.deathPlace,
                  ),
                  if (player.ratingClassical > 0)
                    _LifeFact(
                      label: 'Peak classical',
                      value: player.ratingClassical.toString(),
                    ),
                ],
              ),
              const SizedBox(height: 28),
              for (var index = 0; index < summary.length; index++) ...[
                Text(
                  summary[index],
                  style: AppTypography.textSmRegular.copyWith(
                    color: context.colors.textSecondary,
                    height: 1.65,
                  ),
                ),
                if (index != summary.length - 1) const SizedBox(height: 12),
              ],
              if (highlights.isNotEmpty) ...[
                const SizedBox(height: 30),
                Text(
                  'Career highlights',
                  style: AppTypography.textMdBold.copyWith(
                    color: context.colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 14),
                for (final highlight in highlights)
                  _CareerHighlight(highlight: highlight),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PerformanceSummary extends StatelessWidget {
  const _PerformanceSummary({required this.analytics, required this.loading});

  final PlayerAnalytics? analytics;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final value = analytics;
    if (value == null && loading) {
      return Container(
        height: 104,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 1.5),
        ),
      );
    }
    if (value == null) return const SizedBox.shrink();

    final stats = value.resultStats;
    final topOpening =
        value.openingStats.isEmpty ? null : value.openingStats.first;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chess record',
            style: AppTypography.textLgBold.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 28,
            runSpacing: 18,
            children: [
              _LifeFact(label: 'Games', value: stats.totalGames.toString()),
              _LifeFact(label: 'Wins', value: stats.wins.toString()),
              _LifeFact(label: 'Draws', value: stats.draws.toString()),
              _LifeFact(label: 'Losses', value: stats.losses.toString()),
              if (value.avgOpponentRating > 0)
                _LifeFact(
                  label: 'Average opponent',
                  value: value.avgOpponentRating.toString(),
                ),
              if (topOpening != null)
                _LifeFact(
                  label: 'Most played opening',
                  value: topOpening.eco,
                  detail: topOpening.openingName,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LifeFact extends StatelessWidget {
  const _LifeFact({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 96).clamp(126.0, 220.0);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.textXsMedium.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: AppTypography.textSmBold.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          if (detail?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(
              detail!,
              style: AppTypography.textXsRegular.copyWith(
                color: context.colors.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CareerHighlight extends StatelessWidget {
  const _CareerHighlight({required this.highlight});

  final MemorialPlayerAchievement highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 62,
            child: Text(
              highlight.year,
              style: AppTypography.textXsBold.copyWith(
                color: context.colors.titleAccent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Text(
              highlight.label,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutStatus extends StatelessWidget {
  const _AboutStatus({required this.message, this.loading = false});

  final String message;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Text(
              message,
              style: AppTypography.textSmRegular.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String formatMemorialProfileDate(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return 'Unknown';
  final match = RegExp(r'^(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?$').firstMatch(raw);
  if (match == null) return raw;
  final year = int.tryParse(match.group(1) ?? '');
  final month = int.tryParse(match.group(2) ?? '');
  final day = int.tryParse(match.group(3) ?? '');
  if (year == null) return raw;
  if (month == null) return year.toString();
  const months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  if (month < 1 || month > 12) return raw;
  if (day == null) return '${months[month - 1]} $year';
  return '${months[month - 1]} $day, $year';
}

String _naturalName(String value) {
  final parts = value.split(',');
  if (parts.length < 2) return value.trim();
  return '${parts.skip(1).join(' ').trim()} ${parts.first.trim()}'.trim();
}

String _fallbackSummary({
  required String name,
  required String? title,
  required String federation,
  required String? birthDate,
  required String? deathDate,
}) {
  final titleText = title?.trim().isNotEmpty == true ? ' ${title!.trim()}' : '';
  final federationText =
      federation.trim().isEmpty ? '' : ' who represented ${federation.trim()}';
  return '$name was a$titleText chess player$federationText. ChessEver’s reviewed historical record lists ${formatMemorialProfileDate(birthDate)} – ${formatMemorialProfileDate(deathDate)}.';
}

bool _isPeakRatingAchievement(String label) {
  return RegExp(
    r'^(?:Peak\b.*\brating\b|Reached a peak\b.*\brating\b)',
    caseSensitive: false,
  ).hasMatch(label);
}
