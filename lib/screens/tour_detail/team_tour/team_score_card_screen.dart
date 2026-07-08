import 'package:chessever2/screens/standings/team_standings_builder.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_tour_screen_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart' show kGreenColor, kRedColor;
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/team_crest_avatar.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Team score card — the team analogue of [ScoreCardScreen]. Shows the team's
/// crest, its collected score (match points / board points / rank) and its
/// round-by-round matches versus the other teams. Layout intentionally mirrors
/// the player score card so the two feel familiar.
class TeamScoreCardScreen extends ConsumerWidget {
  const TeamScoreCardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(selectedTeamProvider);
    if (team == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final matches = ref.watch(teamMatchesProvider);

    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 20.sp,
      tablet: 24.sp,
    );
    final avatarSize = ResponsiveHelper.isTablet ? 120.sp : 90.w;
    final avatarGap = ResponsiveHelper.adaptive(phone: 10.w, tablet: 16.sp);
    final boxGap = ResponsiveHelper.adaptive(phone: 6.w, tablet: 10.sp);

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.contentMaxWidth,
            ),
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  backgroundColor: context.colors.background,
                  elevation: 0,
                  centerTitle: false,
                  leading: IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios_new_outlined,
                      color: context.colors.textPrimary,
                      size: 22.ic,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  title: Text(
                    team.teamName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textMdBold.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 10.h),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TeamCrestAvatar(
                              teamName: team.teamName,
                              size: avatarSize,
                              borderRadius: 12.br,
                            ),
                            SizedBox(width: avatarGap),
                            Expanded(
                              child: IntrinsicHeight(
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _TeamStatBox(
                                        label: 'Match Pts',
                                        value: '${team.matchPoints}',
                                        height: avatarSize,
                                      ),
                                    ),
                                    SizedBox(width: boxGap),
                                    Expanded(
                                      child: _TeamStatBox(
                                        label: 'Board Pts',
                                        value: team.gamePointsLabel,
                                        height: avatarSize,
                                      ),
                                    ),
                                    SizedBox(width: boxGap),
                                    Expanded(
                                      child: _TeamStatBox(
                                        label: 'Rank',
                                        value: '#${team.rank}',
                                        height: avatarSize,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12.h),
                        Text(
                          'Played ${team.matchesWon + team.matchesDrawn + team.matchesLost} · ${team.recordLabel} (W-D-L)',
                          style: AppTypography.textSmMedium.copyWith(
                            color: context.colors.textSecondary,
                          ),
                        ),
                        SizedBox(height: 14.h),
                        Text(
                          'Matches',
                          style: AppTypography.textXsMedium.copyWith(
                            color: context.colors.textTertiary,
                          ),
                        ),
                        SizedBox(height: 8.h),
                      ],
                    ),
                  ),
                ),
                if (matches.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                        vertical: 24.h,
                      ),
                      child: Text(
                        'No matches played yet',
                        style: AppTypography.textSmMedium.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final match = matches[index];
                      return Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        child: _TeamMatchCard(
                          index: index,
                          match: match,
                          isFirst: index == 0,
                          isLast: index == matches.length - 1,
                        ),
                      );
                    }, childCount: matches.length),
                  ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 24.h + MediaQuery.of(context).padding.bottom,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamStatBox extends StatelessWidget {
  final String label;
  final String value;
  final double height;

  const _TeamStatBox({
    required this.label,
    required this.value,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.isTablet ? 6.sp : 3.sp,
        vertical: ResponsiveHelper.isTablet ? 12.sp : 8.sp,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8.br),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.textXsMedium.copyWith(
              color: context.colors.textPrimaryMuted,
              fontSize: ResponsiveHelper.isTablet ? 12.sp : 10.sp,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: ResponsiveHelper.isTablet ? 6.h : 4.h),
          Text(
            value,
            style:
                ResponsiveHelper.isTablet
                    ? AppTypography.textLgBold.copyWith(
                      color: context.colors.textPrimary,
                    )
                    : AppTypography.textMdBold.copyWith(
                      color: context.colors.textPrimary,
                    ),
          ),
        ],
      ),
    );
  }
}

/// A single opponent-team match row, styled like [ScoreboardCardWidget].
class _TeamMatchCard extends StatelessWidget {
  final int index;
  final TeamMatch match;
  final bool isFirst;
  final bool isLast;

  const _TeamMatchCard({
    required this.index,
    required this.match,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    BorderRadius? borderRadius;
    if (isFirst) {
      borderRadius = BorderRadius.only(
        topLeft: Radius.circular(8.br),
        topRight: Radius.circular(8.br),
      );
    } else if (isLast) {
      borderRadius = BorderRadius.only(
        bottomLeft: Radius.circular(8.br),
        bottomRight: Radius.circular(8.br),
      );
    }

    return Container(
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 12.sp),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: borderRadius,
        border:
            isLast
                ? null
                : Border(
                  bottom: BorderSide(
                    color: context.colors.textPrimary.withValues(alpha: 0.08),
                    width: 0.7,
                  ),
                ),
      ),
      child: Row(
        children: [
          Text(
            match.roundLabel,
            style: AppTypography.textMdBold.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          SizedBox(width: 10.w),
          TeamCrestAvatar(
            teamName: match.opponentTeam,
            size: 28.w,
            borderRadius: 6.br,
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              match.opponentTeam,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textMdBold.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),
          SizedBox(width: 12.w),
          Text(
            match.scoreLabel,
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
          SizedBox(width: 12.w),
          _ResultTag(result: match.result),
        ],
      ),
    );
  }
}

class _ResultTag extends StatelessWidget {
  final TeamMatchResult result;

  const _ResultTag({required this.result});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (result) {
      TeamMatchResult.win => ('W', kGreenColor),
      TeamMatchResult.loss => ('L', kRedColor),
      TeamMatchResult.draw => ('D', context.colors.textSecondary),
      TeamMatchResult.ongoing => ('·', context.colors.textTertiary),
    };
    return Container(
      width: 24.w,
      height: 24.w,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(
        label,
        style: AppTypography.textXsMedium.copyWith(color: color),
      ),
    );
  }
}
