import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/standings/team_standings_builder.dart';
import 'package:chessever2/screens/tour_detail/team_tour/team_tour_screen_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart' show kGreenColor2, kRedColor;
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/team_crest_avatar.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _drawColor = Color(0xFFEAB308); // amber

Color _resultColor(BuildContext context, TeamMatchResult r) => switch (r) {
  TeamMatchResult.win => kGreenColor2,
  TeamMatchResult.draw => _drawColor,
  TeamMatchResult.loss => kRedColor,
  TeamMatchResult.ongoing => context.colors.textTertiary,
};

String _resultLetter(TeamMatchResult r) => switch (r) {
  TeamMatchResult.win => 'W',
  TeamMatchResult.draw => 'D',
  TeamMatchResult.loss => 'L',
  TeamMatchResult.ongoing => '·',
};

/// Team score card — the team analogue of the player [ScoreCardScreen]. A
/// crest-tinted hero (rank, form guide, collected score) over the team's
/// round-by-round matches, each expanded to its board games, with W/D/L
/// color-coded throughout.
class TeamScoreCardScreen extends ConsumerWidget {
  const TeamScoreCardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(selectedTeamProvider);
    if (team == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final matches = ref.watch(teamMatchesProvider);
    final accent = TeamCrestAvatar.colorFor(team.teamName);
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 16.sp,
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
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      8.h,
                      horizontalPadding,
                      4.h,
                    ),
                    child: _TeamHero(team: team, matches: matches, accent: accent),
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
                        padding: EdgeInsets.fromLTRB(
                          horizontalPadding,
                          0,
                          horizontalPadding,
                          10.h,
                        ),
                        child: _MatchCard(
                          match: matches[index],
                          accent: accent,
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

class _TeamHero extends StatelessWidget {
  final TeamStandingModel team;
  final List<TeamMatch> matches;
  final Color accent;

  const _TeamHero({
    required this.team,
    required this.matches,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final played = team.matchesWon + team.matchesDrawn + team.matchesLost;
    // Form guide: completed results, oldest → newest, capped to the last 8.
    final form =
        matches
            .where((m) => m.result != TeamMatchResult.ongoing)
            .map((m) => m.result)
            .toList();
    final recent = form.length > 8 ? form.sublist(form.length - 8) : form;

    return Container(
      padding: EdgeInsets.all(16.sp),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.24),
            accent.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16.br),
        border: Border.all(color: accent.withValues(alpha: 0.30), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TeamCrestAvatar(
                teamName: team.teamName,
                size: 60.w,
                borderRadius: 14.br,
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      team.teamName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.textLgBold.copyWith(
                        color: context.colors.textPrimary,
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: 6.h),
                    Row(
                      children: [
                        _RankChip(rank: team.rank, accent: accent),
                        SizedBox(width: 8.w),
                        Text(
                          '$played ${played == 1 ? 'match' : 'matches'}',
                          style: AppTypography.textXsMedium.copyWith(
                            color: context.colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (recent.isNotEmpty) ...[
            SizedBox(height: 14.h),
            Row(
              children: [
                Text(
                  'FORM',
                  style: AppTypography.textXsMedium.copyWith(
                    color: context.colors.textTertiary,
                    letterSpacing: 1.0,
                  ),
                ),
                SizedBox(width: 8.w),
                for (final r in recent) ...[
                  _FormDot(color: _resultColor(context, r)),
                  SizedBox(width: 4.w),
                ],
              ],
            ),
          ],
          SizedBox(height: 16.h),
          Row(
            children: [
              _HeroStat(
                label: 'Match Pts',
                value: '${team.matchPoints}',
                emphasis: accent,
              ),
              _HeroDivider(),
              _HeroStat(label: 'Board Pts', value: team.gamePointsLabel),
              _HeroDivider(),
              _HeroRecord(
                won: team.matchesWon,
                drawn: team.matchesDrawn,
                lost: team.matchesLost,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RankChip extends StatelessWidget {
  final int rank;
  final Color accent;

  const _RankChip({required this.rank, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(6.br),
        border: Border.all(color: accent.withValues(alpha: 0.45), width: 1),
      ),
      child: Text(
        '#$rank',
        style: AppTypography.textXsMedium.copyWith(
          color: context.colors.textPrimary,
        ),
      ),
    );
  }
}

class _FormDot extends StatelessWidget {
  final Color color;
  const _FormDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10.w,
      height: 10.w,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _HeroDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 30.h,
      margin: EdgeInsets.symmetric(horizontal: 12.w),
      color: context.colors.textPrimary.withValues(alpha: 0.10),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? emphasis;

  const _HeroStat({required this.label, required this.value, this.emphasis});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: AppTypography.textLgBold.copyWith(
              color: emphasis ?? context.colors.textPrimary,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            label,
            style: AppTypography.textXsMedium.copyWith(
              color: context.colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroRecord extends StatelessWidget {
  final int won;
  final int drawn;
  final int lost;

  const _HeroRecord({
    required this.won,
    required this.drawn,
    required this.lost,
  });

  @override
  Widget build(BuildContext context) {
    Widget cell(int v, Color color) => Column(
      children: [
        Text(
          '$v',
          style: AppTypography.textMdBold.copyWith(color: color),
        ),
      ],
    );

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              cell(won, kGreenColor2),
              SizedBox(width: 6.w),
              cell(drawn, _drawColor),
              SizedBox(width: 6.w),
              cell(lost, kRedColor),
            ],
          ),
          SizedBox(height: 2.h),
          Text(
            'W · D · L',
            style: AppTypography.textXsMedium.copyWith(
              color: context.colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchCard extends StatelessWidget {
  final TeamMatch match;
  final Color accent;

  const _MatchCard({required this.match, required this.accent});

  @override
  Widget build(BuildContext context) {
    final resultColor = _resultColor(context, match.result);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12.br),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4.w, color: resultColor),
            Expanded(
              child: Container(
                color: context.colors.surface,
                padding: EdgeInsets.all(12.sp),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Round + opponent + result
                    Row(
                      children: [
                        _RoundPill(label: 'Round ${_roundNumber(match)}'),
                        SizedBox(width: 8.w),
                        TeamCrestAvatar(
                          teamName: match.opponentTeam,
                          size: 24.w,
                          borderRadius: 5.br,
                        ),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Text(
                            match.opponentTeam,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.textSmBold.copyWith(
                              color: context.colors.textPrimary,
                            ),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        _ResultBadge(result: match.result),
                      ],
                    ),
                    SizedBox(height: 10.h),
                    // Board-point split + share bar
                    Row(
                      children: [
                        Text(
                          match.scoreLabel,
                          style: AppTypography.textMdBold.copyWith(
                            color: context.colors.textPrimary,
                          ),
                        ),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: _ShareBar(
                            ourPoints: match.ourPoints,
                            opponentPoints: match.opponentPoints,
                            ourColor: resultColor,
                          ),
                        ),
                      ],
                    ),
                    if (match.boardGames.isNotEmpty) ...[
                      SizedBox(height: 10.h),
                      Divider(
                        height: 1,
                        color: context.colors.textPrimary.withValues(
                          alpha: 0.06,
                        ),
                      ),
                      SizedBox(height: 6.h),
                      for (final b in match.boardGames)
                        _BoardRow(board: b),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _roundNumber(TeamMatch m) => m.roundLabel.replaceAll('.', '');
}

class _RoundPill extends StatelessWidget {
  final String label;
  const _RoundPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: context.colors.surfaceRecessed,
        borderRadius: BorderRadius.circular(6.br),
      ),
      child: Text(
        label,
        style: AppTypography.textXsMedium.copyWith(
          color: context.colors.textSecondary,
        ),
      ),
    );
  }
}

class _ResultBadge extends StatelessWidget {
  final TeamMatchResult result;
  const _ResultBadge({required this.result});

  @override
  Widget build(BuildContext context) {
    final color = _resultColor(context, result);
    return Container(
      width: 24.w,
      height: 24.w,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.55), width: 1),
      ),
      child: Text(
        _resultLetter(result),
        style: AppTypography.textXsMedium.copyWith(color: color),
      ),
    );
  }
}

class _ShareBar extends StatelessWidget {
  final double ourPoints;
  final double opponentPoints;
  final Color ourColor;

  const _ShareBar({
    required this.ourPoints,
    required this.opponentPoints,
    required this.ourColor,
  });

  @override
  Widget build(BuildContext context) {
    final total = ourPoints + opponentPoints;
    final ourFlex = total > 0 ? (ourPoints / total * 1000).round() : 500;
    final oppFlex = 1000 - ourFlex;
    return ClipRRect(
      borderRadius: BorderRadius.circular(3.br),
      child: SizedBox(
        height: 6.h,
        child: Row(
          children: [
            if (ourFlex > 0)
              Expanded(flex: ourFlex, child: ColoredBox(color: ourColor)),
            if (oppFlex > 0)
              Expanded(
                flex: oppFlex,
                child: ColoredBox(
                  color: context.colors.textPrimary.withValues(alpha: 0.12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BoardRow extends StatelessWidget {
  final TeamBoardGame board;
  const _BoardRow({required this.board});

  @override
  Widget build(BuildContext context) {
    final color = _resultColor(context, board.result);
    final oppLabel = [
      if (board.opponentTitle != null) board.opponentTitle,
      board.opponentName,
    ].join(' ');

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5.h),
      child: Row(
        children: [
          SizedBox(
            width: 20.w,
            child: Text(
              board.boardNr?.toString() ?? '',
              style: AppTypography.textXsMedium.copyWith(
                color: context.colors.textTertiary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              board.ourName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textSmMedium.copyWith(
                color: context.colors.textPrimary,
              ),
            ),
          ),
          SizedBox(width: 6.w),
          _BoardResultGlyph(result: board.result, color: color),
          SizedBox(width: 6.w),
          Expanded(
            child: Text(
              oppLabel,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

class _BoardResultGlyph extends StatelessWidget {
  final TeamMatchResult result;
  final Color color;

  const _BoardResultGlyph({required this.result, required this.color});

  @override
  Widget build(BuildContext context) {
    final label = switch (result) {
      TeamMatchResult.win => '1',
      TeamMatchResult.draw => '½',
      TeamMatchResult.loss => '0',
      TeamMatchResult.ongoing => '·',
    };
    return Container(
      width: 20.w,
      height: 20.w,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5.br),
      ),
      child: Text(
        label,
        style: AppTypography.textXsMedium.copyWith(color: color),
      ),
    );
  }
}
