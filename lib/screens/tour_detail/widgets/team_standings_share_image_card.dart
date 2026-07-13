import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/widgets/team_crest_avatar.dart';
import 'package:flutter/material.dart';

/// Maximum team rows rendered on the shareable card. Mirrors
/// [kStandingsShareRowLimit] for the individual standings card — a leaderboard
/// image stays legible and X/Twitter-sized when capped, with a "+N more" line
/// pointing back to the app for the tail.
const int kTeamStandingsShareRowLimit = 12;

/// A self-contained, brand-forward leaderboard image of a team event's team
/// standings, built to be captured off-screen (see `captureCardPng`) and shared
/// to social. Deterministic dark palette (independent of the active theme) so
/// the shared image looks identical in light or dark mode. Height is intrinsic
/// (grows with the row count up to [kTeamStandingsShareRowLimit]).
///
/// This is the team-event sibling of [StandingsShareImageCard]: same header /
/// footer chrome, but each row is a team (crest, name, W-D-L record) with match
/// points (MP) as the headline score and board points (BP) as the tiebreak.
class TeamStandingsShareImageCard extends StatelessWidget {
  const TeamStandingsShareImageCard({
    super.key,
    required this.width,
    required this.eventName,
    required this.standings,
  });

  final double width;
  final String? eventName;
  final List<TeamStandingModel> standings;

  // Deterministic dark brand palette (matches StandingsShareImageCard).
  static const _bg = Color(0xFF0A0B0D);
  static const _surfaceLow = Color(0xFF101216);
  static const _hairline = Color(0xFF23262E);
  static const _cyan = kPrimaryColor;
  static const _gold = kLightYellowColor;
  static const _textHi = Colors.white;
  static const _textMid = Color(0xFFAEB4BF);
  static const _textLo = Color(0xFF868C97);

  static const _padH = 22.0;

  @override
  Widget build(BuildContext context) {
    final rows =
        standings.length > kTeamStandingsShareRowLimit
            ? standings.sublist(0, kTeamStandingsShareRowLimit)
            : standings;
    final remaining = standings.length - rows.length;

    return MediaQuery(
      data: const MediaQueryData(devicePixelRatio: 3.0),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          color: _bg,
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(_padH, 6, _padH, 18),
                  child: _buildTable(rows, remaining),
                ),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final title = eventName?.trim();
    final hasEvent = title != null && title.isNotEmpty;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.alphaBlend(_cyan.withValues(alpha: 0.13), _bg), _bg],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_padH, 22, _padH, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _logoBadge(26),
                const SizedBox(width: 9),
                Text(
                  'ChessEver',
                  style: AppTypography.textSmBold.copyWith(
                    color: _textHi,
                    fontSize: 15,
                    letterSpacing: 0.2,
                  ),
                ),
                const Spacer(),
                Text(
                  'TEAM STANDINGS',
                  style: AppTypography.textXxsBold.copyWith(
                    color: _textLo,
                    fontSize: 10,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              hasEvent ? title : 'Team Tournament',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textXlBold.copyWith(
                color: _textHi,
                fontSize: 21,
                height: 1.15,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 38,
              height: 3,
              decoration: BoxDecoration(
                color: _cyan,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(List<TeamStandingModel> rows, int remaining) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
          child: Row(
            children: [
              Text(
                'RANK',
                style: AppTypography.textXxsBold.copyWith(
                  color: _textLo,
                  fontSize: 10.5,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              // Column legend: MP = match points, BP = board points.
              Text(
                'MP  ·  BP',
                style: AppTypography.textXxsBold.copyWith(
                  color: _textLo,
                  fontSize: 10.5,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            color: _surfaceLow,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  _TeamStandingRow(
                    rank: rows[i].rank > 0 ? rows[i].rank : (i + 1),
                    team: rows[i],
                    isLast: i == rows.length - 1 && remaining <= 0,
                  ),
              ],
            ),
          ),
        ),
        if (remaining > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10, left: 4),
            child: Text(
              '+$remaining more on ChessEver',
              style: AppTypography.textXxsMedium.copyWith(
                color: _textLo,
                fontSize: 11.5,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFooter() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _hairline, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(_padH, 15, _padH, 16),
      child: Row(
        children: [
          _logoBadge(30),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ChessEver',
                style: AppTypography.textSmBold.copyWith(
                  color: _textHi,
                  fontSize: 14.5,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                'Follow live chess',
                style: AppTypography.textXxsMedium.copyWith(
                  color: _textLo,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            'chessever.com',
            style: AppTypography.textXsBold.copyWith(
              color: _cyan,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoBadge(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: _cyan.withValues(alpha: 0.35),
            blurRadius: 14,
            spreadRadius: -4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: Image.asset(
          PngAsset.newAppLogo,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _TeamStandingRow extends StatelessWidget {
  const _TeamStandingRow({
    required this.rank,
    required this.team,
    required this.isLast,
  });

  final int rank;
  final TeamStandingModel team;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final isTopThree = rank <= 3;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border:
            isLast
                ? null
                : const Border(
                  bottom: BorderSide(
                    color: TeamStandingsShareImageCard._hairline,
                    width: 0.7,
                  ),
                ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '$rank',
              maxLines: 1,
              style: AppTypography.textSmBold.copyWith(
                color:
                    isTopThree
                        ? TeamStandingsShareImageCard._gold
                        : TeamStandingsShareImageCard._textMid,
                fontSize: 15,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          TeamCrestAvatar(teamName: team.teamName, size: 26, borderRadius: 7),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  team.teamName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.textSmBold.copyWith(
                    color: TeamStandingsShareImageCard._textHi,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${team.matchesWon}W  ${team.matchesDrawn}D  ${team.matchesLost}L',
                  maxLines: 1,
                  style: AppTypography.textXxsMedium.copyWith(
                    color: TeamStandingsShareImageCard._textLo,
                    fontSize: 10.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Board points (tiebreak) — muted.
          SizedBox(
            width: 34,
            child: Text(
              team.gamePointsLabel,
              textAlign: TextAlign.right,
              style: AppTypography.textSmMedium.copyWith(
                color: TeamStandingsShareImageCard._textMid,
                fontSize: 13,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Match points (headline score).
          SizedBox(
            width: 26,
            child: Text(
              '${team.matchPoints}',
              textAlign: TextAlign.right,
              style: AppTypography.textMdBold.copyWith(
                color: TeamStandingsShareImageCard._textHi,
                fontSize: 16,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
