import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/standings/team_standings_builder.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/widgets/team_crest_avatar.dart';
import 'package:flutter/material.dart';

/// One match row on the shareable team-event card.
class TeamEventShareMatchRow {
  const TeamEventShareMatchRow({
    required this.opponentTeam,
    required this.ourPointsLabel,
    required this.opponentPointsLabel,
    required this.result,
    this.roundLabel,
  });

  final String opponentTeam;
  final String ourPointsLabel;
  final String opponentPointsLabel;
  final TeamMatchResult result;

  /// Numeric round label like `"6."` when available; null for knockout-style.
  final String? roundLabel;
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
  static const _gold = kLightYellowColor;
  static const _padH = 22.0;
  static const footerSlogan = 'Follow Chess Better';

  /// Static MATCHES heading when no row carries a round label; null otherwise
  /// (rows show their own round text, matching the live score card).
  static String? _matchesSectionHeading(List<TeamEventShareMatchRow> matches) {
    for (final m in matches) {
      if (m.roundLabel != null && m.roundLabel!.isNotEmpty) return null;
    }
    return 'MATCHES';
  }

  /// Compact share label: optional title + surname-first name, e.g. "GM Carlsen".
  static String playerShareLabel(PlayerStandingModel player) {
    final name = _presentName(player.name);
    final title = player.title?.trim();
    if (title != null && title.isNotEmpty) return '$title $name';
    return name;
  }

  /// "Carlsen, Magnus" → "Carlsen"; "Magnus Carlsen" → "Carlsen" when multi-word.
  /// Keeps full single-token names as-is. Prefer last-name weight for density.
  static String _presentName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return trimmed;
    if (trimmed.contains(',')) {
      return trimmed.split(',').first.trim();
    }
    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final list = parts.toList();
    if (list.length >= 2) return list.last;
    return trimmed;
  }

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
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _padH),
                  child: _buildStats(),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _padH),
                  child: Text(
                    '${team.matchesWon} W  ·  ${team.matchesDrawn} D  ·  ${team.matchesLost} L'
                    '${averageElo != null ? '  ·  avg elo $averageElo' : ''}',
                    style: AppTypography.textSmMedium.copyWith(color: _textMid),
                  ),
                ),
                if (team.players.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _padH),
                    child: _buildSquad(),
                  ),
                ],
                if (matches.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  // Prefer per-row round labels when available; else static MATCHES.
                  if (_matchesSectionHeading(matches) case final heading?) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: _padH),
                      child: Text(
                        heading,
                        style: AppTypography.textXsMedium.copyWith(
                          color: _textLo,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _padH),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(12),
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
                const SizedBox(height: 18),
                Container(
                  color: const Color(0xFF07080B),
                  padding: const EdgeInsets.symmetric(
                    horizontal: _padH,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      _logoBadge(28),
                      const SizedBox(width: 10),
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

  /// Dense two-column squad grid: title + surname · rating.
  Widget _buildSquad() {
    final players = List<PlayerStandingModel>.from(team.players)
      ..sort((a, b) {
        if (b.score != a.score) return b.score.compareTo(a.score);
        return a.name.compareTo(b.name);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SQUAD',
          style: AppTypography.textXsMedium.copyWith(
            color: _textLo,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _hairline),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final gap = 8.0;
              final colW = (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: 5,
                children: [
                  for (final p in players)
                    SizedBox(
                      width: colW,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  if (p.title != null &&
                                      p.title!.trim().isNotEmpty)
                                    TextSpan(
                                      text: '${p.title!.trim()} ',
                                      style: AppTypography.textXsMedium
                                          .copyWith(
                                            color: _gold,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  TextSpan(
                                    text: _presentName(p.name),
                                    style: AppTypography.textXsMedium.copyWith(
                                      color: _textHi,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (p.score > 0) ...[
                            const SizedBox(width: 4),
                            Text(
                              '${p.score}',
                              style: AppTypography.textXsMedium.copyWith(
                                color: _textMid,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
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
              _logoBadge(26),
              const SizedBox(width: 9),
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
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: AppTypography.textMdBold.copyWith(color: _textHi),
            ),
            const SizedBox(height: 2),
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
    final round = row.roundLabel?.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          if (round != null && round.isNotEmpty) ...[
            SizedBox(
              width: 24,
              child: Text(
                round,
                maxLines: 1,
                style: AppTypography.textXsBold.copyWith(
                  color: TeamEventShareImageCard._textMid,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              teamName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textXsMedium.copyWith(
                color: TeamEventShareImageCard._textHi,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  row.ourPointsLabel,
                  style: AppTypography.textXsBold.copyWith(
                    color: _sideColor(true),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '–',
                    style: AppTypography.textXsMedium.copyWith(
                      color: TeamEventShareImageCard._textLo,
                    ),
                  ),
                ),
                Text(
                  row.opponentPointsLabel,
                  style: AppTypography.textXsBold.copyWith(
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
              style: AppTypography.textXsMedium.copyWith(
                color: TeamEventShareImageCard._textMid,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
