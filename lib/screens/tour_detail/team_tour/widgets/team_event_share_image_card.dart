import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/standings/team_standings_builder.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/team_crest_avatar.dart';
import 'package:flutter/material.dart';

/// One match row on the shareable team-event card.
class TeamEventShareMatchRow {
  const TeamEventShareMatchRow({
    required this.opponentTeam,
    required this.ourPointsLabel,
    required this.opponentPointsLabel,
    required this.result,
  });

  final String opponentTeam;
  final String ourPointsLabel;
  final String opponentPointsLabel;
  final TeamMatchResult result;
}

/// Branded share image for a team scorecard (dark palette, independent of app theme).
class TeamEventShareImageCard extends StatelessWidget {
  const TeamEventShareImageCard({
    super.key,
    required this.width,
    required this.team,
    required this.eventName,
    required this.matches,
    this.averageElo,
  });

  final double width;
  final TeamStandingModel team;
  final String? eventName;
  final List<TeamEventShareMatchRow> matches;

  /// Mean roster Elo for the event time control (standard / rapid / blitz).
  final int? averageElo;

  static const _bg = Color(0xFF0A0B0D);
  static const _surface = Color(0xFF15171C);
  static const _hairline = Color(0xFF23262E);
  static const _cyan = kPrimaryColor;
  static const _loss = kRedColor;
  static const _draw = Color(0xFF9AA0A6);
  static const _textHi = Colors.white;
  static const _textMid = Color(0xFFAEB4BF);
  static const _textLo = Color(0xFF868C97);
  static const _padH = 22.0;
  static const footerSlogan = 'Follow Chess Better';

  @override
  Widget build(BuildContext context) {
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
                _buildHero(),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _padH),
                  child: _buildStats(),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _padH),
                  child: Text(
                    '${team.matchesWon} W  ·  ${team.matchesDrawn} D  ·  ${team.matchesLost} L'
                    '${averageElo != null ? '  ·  avg elo $averageElo' : ''}',
                    style: AppTypography.textSmMedium.copyWith(color: _textMid),
                  ),
                ),
                if (matches.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _padH),
                    child: Text(
                      'MATCHES',
                      style: AppTypography.textXsMedium.copyWith(
                        color: _textLo,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _padH),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _hairline),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < matches.length; i++) ...[
                            if (i > 0)
                              const Divider(height: 1, color: _hairline),
                            _MatchRow(
                              teamName: team.teamName,
                              row: matches[i],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 22),
                Container(
                  color: const Color(0xFF07080B),
                  padding: const EdgeInsets.symmetric(
                    horizontal: _padH,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Text(
                        'ChessEver',
                        style: AppTypography.textSmBold.copyWith(
                          color: _textHi,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        footerSlogan,
                        style: AppTypography.textXsMedium.copyWith(
                          color: _textLo,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    final crest = TeamCrestAvatar(
      teamName: team.teamName,
      size: 84,
      borderRadius: 16,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(_padH, 28, _padH, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E1A22), Color(0xFF0A0B0D)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ChessEver',
                style: AppTypography.textMdBold.copyWith(color: _textHi),
              ),
              const Spacer(),
              Text(
                'TEAM REPORT',
                style: AppTypography.textXsMedium.copyWith(
                  color: _textLo,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (eventName != null && eventName!.trim().isNotEmpty) ...[
            Text(
              eventName!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textMdBold.copyWith(color: _textHi),
            ),
            const SizedBox(height: 6),
            Container(
              width: 36,
              height: 3,
              decoration: BoxDecoration(
                color: _cyan,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              crest,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      team.teamName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.textLgBold.copyWith(color: _textHi),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      team.rank > 0 ? 'Rank #${team.rank}' : 'Team scorecard',
                      style: AppTypography.textSmMedium.copyWith(
                        color: _textMid,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStats() {
    Widget tile(String label, String value) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: AppTypography.textLgBold.copyWith(color: _textHi),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTypography.textXsMedium.copyWith(color: _textLo),
            ),
          ],
        ),
      ),
    );

    return Row(
      children: [
        tile('Team Pts', '${team.matchPoints}'),
        const SizedBox(width: 8),
        tile('Board Pts', team.gamePointsLabel),
        const SizedBox(width: 8),
        tile(
          'Avg Elo',
          averageElo != null ? averageElo.toString() : '—',
        ),
      ],
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.teamName, required this.row});

  final String teamName;
  final TeamEventShareMatchRow row;

  Color _sideColor(bool ours) {
    switch (row.result) {
      case TeamMatchResult.win:
        return ours ? TeamEventShareImageCard._cyan : TeamEventShareImageCard._loss;
      case TeamMatchResult.loss:
        return ours ? TeamEventShareImageCard._loss : TeamEventShareImageCard._cyan;
      case TeamMatchResult.draw:
        return TeamEventShareImageCard._textHi;
      case TeamMatchResult.ongoing:
        return TeamEventShareImageCard._draw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              teamName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textSmMedium.copyWith(
                color: TeamEventShareImageCard._textHi,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  row.ourPointsLabel,
                  style: AppTypography.textSmBold.copyWith(
                    color: _sideColor(true),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Text(
                    '–',
                    style: AppTypography.textSmMedium.copyWith(
                      color: TeamEventShareImageCard._textLo,
                    ),
                  ),
                ),
                Text(
                  row.opponentPointsLabel,
                  style: AppTypography.textSmBold.copyWith(
                    color: _sideColor(false),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              row.opponentTeam,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: AppTypography.textSmMedium.copyWith(
                color: TeamEventShareImageCard._textMid,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
