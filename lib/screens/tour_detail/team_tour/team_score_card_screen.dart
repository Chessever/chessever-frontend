import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/team_tour/widgets/team_player_chip.dart';
import 'package:chessever2/screens/tour_detail/team_tour/widgets/team_round_group.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart' show kGreenColor2, kRedColor;
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/team_crest_avatar.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const Color _drawGrey = Color(0xFF9AA0A6);

/// Team score card — the team analogue of the individual score card. Keeps the
/// same structure (avatar + stat boxes, then a list of result rows) but for a
/// team: crest, collected score, and the round-by-round matchups vs the other
/// teams with W/D/L colour induction and per-board circles that open the game.
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
                    child: _TeamHeader(team: team),
                  ),
                ),
                if (team.players.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        18.h,
                        horizontalPadding,
                        10.h,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TEAM',
                            style: AppTypography.textXsMedium.copyWith(
                              color: context.colors.textTertiary,
                              letterSpacing: 1.2,
                            ),
                          ),
                          SizedBox(height: 10.h),
                          TeamPlayerChipsGrid(players: team.players),
                        ],
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      18.h,
                      horizontalPadding,
                      10.h,
                    ),
                    child: Text(
                      'MATCHES',
                      style: AppTypography.textXsMedium.copyWith(
                        color: context.colors.textTertiary,
                        letterSpacing: 1.2,
                      ),
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
                      return Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                        ),
                        child: TeamRoundGroup(
                          match: matches[index],
                          teamName: team.teamName,
                          index: index,
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

class _TeamHeader extends StatelessWidget {
  final TeamStandingModel team;

  const _TeamHeader({required this.team});

  @override
  Widget build(BuildContext context) {
    final avatarSize = ResponsiveHelper.isTablet ? 120.sp : 90.w;
    final gap = ResponsiveHelper.adaptive(phone: 10.w, tablet: 16.sp);
    final boxGap = ResponsiveHelper.adaptive(phone: 6.w, tablet: 10.sp);

    return Column(
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
            SizedBox(width: gap),
            Expanded(
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: _StatBox(
                        label: 'Team Pts',
                        value: '${team.matchPoints}',
                        height: avatarSize,
                      ),
                    ),
                    SizedBox(width: boxGap),
                    Expanded(
                      child: _StatBox(
                        label: 'Board Pts',
                        value: team.gamePointsLabel,
                        height: avatarSize,
                      ),
                    ),
                    SizedBox(width: boxGap),
                    Expanded(
                      child: _StatBox(
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
        _RecordLine(
          won: team.matchesWon,
          drawn: team.matchesDrawn,
          lost: team.matchesLost,
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final double height;

  const _StatBox({
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
          SizedBox(height: ResponsiveHelper.isTablet ? 6.h : 4.h),
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
        ],
      ),
    );
  }
}

class _RecordLine extends StatelessWidget {
  final int won;
  final int drawn;
  final int lost;

  const _RecordLine({
    required this.won,
    required this.drawn,
    required this.lost,
  });

  @override
  Widget build(BuildContext context) {
    TextSpan seg(String v, Color color) => TextSpan(
      text: v,
      style: AppTypography.textSmMedium.copyWith(color: color),
    );
    final dim = AppTypography.textSmMedium.copyWith(
      color: context.colors.textTertiary,
    );
    return RichText(
      text: TextSpan(
        style: dim,
        children: [
          seg('$won W', kGreenColor2),
          const TextSpan(text: '   ·   '),
          seg('$drawn D', _drawGrey),
          const TextSpan(text: '   ·   '),
          seg('$lost L', kRedColor),
        ],
      ),
    );
  }
}
