import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/team_standing_model.dart';
import 'package:chessever2/screens/standings/team_standings_builder.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/share_card.dart';
import 'package:chessever2/utils/share_card_palette.dart';
import 'package:chessever2/widgets/team_country_code.dart';
import 'package:chessever2/widgets/team_crest_avatar.dart';
import 'package:country_flags/country_flags.dart'
    show CountryFlag, FlagCode, ImageTheme, RoundedRectangle;
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

/// Branded share image for a team scorecard. Colours come from the capture's
/// [ShareCardPalette]: dark brand identity, or paper when the app is light.
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

  /// A raised tile: tone alone in dark, plus an edge on paper.
  static BoxDecoration _tile(ShareCardPalette p, {double radius = 12}) =>
      BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: p.tileEdge ?? p.hairline),
      );

  @override
  Widget build(BuildContext context) {
    final p = ShareCardPalette.of(context);
    return MediaQuery(
      data: const MediaQueryData(devicePixelRatio: 3.0),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          color: p.bg,
          child: SizedBox(
            width: width,
            child: ShareCardColumn(
              children: [
                _buildHero(p),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _padH),
                  child: _buildStats(p),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _padH),
                  // Avg Elo already has its own stat tile above.
                  child: Text(
                    '${team.matchesWon} W  ·  ${team.matchesDrawn} D  ·  ${team.matchesLost} L',
                    style: AppTypography.textSmMedium.copyWith(
                      color: p.textMid,
                    ),
                  ),
                ),
                if (team.players.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _padH),
                    child: _buildSquad(p),
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
                          color: p.textLo,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _padH),
                    child: Container(
                      decoration: _tile(p),
                      child: Column(
                        children: [
                          for (var i = 0; i < matches.length; i++) ...[
                            if (i > 0)
                              Divider(height: 1, color: p.hairline),
                            _MatchRow(row: matches[i]),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Container(
                  color: p.band,
                  padding: const EdgeInsets.symmetric(
                    horizontal: _padH,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      _logoBadge(28, p),
                      const SizedBox(width: 10),
                      Text(
                        'ChessEver',
                        style: AppTypography.textSmBold.copyWith(
                          color: p.textHi,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        footerSlogan,
                        style: AppTypography.textXsMedium.copyWith(
                          color: p.textLo,
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
  Widget _buildSquad(ShareCardPalette p) {
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
            color: p.textLo,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: _tile(p),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final gap = 8.0;
              final colW = (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: 5,
                children: [
                  for (final player in players)
                    SizedBox(
                      width: colW,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  if (player.title != null &&
                                      player.title!.trim().isNotEmpty)
                                    TextSpan(
                                      text: '${player.title!.trim()} ',
                                      style: AppTypography.textXsMedium
                                          .copyWith(
                                            color: p.gold,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  TextSpan(
                                    text: _presentName(player.name),
                                    style: AppTypography.textXsMedium.copyWith(
                                      color: p.textHi,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (player.score > 0) ...[
                            const SizedBox(width: 4),
                            Text(
                              '${player.score}',
                              style: AppTypography.textXsMedium.copyWith(
                                color: p.textMid,
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

  Widget _logoBadge(double size, ShareCardPalette p) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow:
            p.logoGlow
                ? [
                  BoxShadow(
                    color: p.accentFill.withValues(alpha: 0.35),
                    blurRadius: 14,
                    spreadRadius: -4,
                  ),
                ]
                : null,
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

  /// The 84dp hero crest. Country teams draw the vector flag: the raster flag
  /// [TeamCrestAvatar] uses is ~100px wide and blurs when upscaled to 252px at
  /// the capture's 3x. Same size, radius and cover crop, so the slot is
  /// unchanged; anything without a vector flag keeps the regular crest.
  Widget _buildCrest() {
    const size = 84.0;
    const radius = 16.0;
    final iso2 = resolveTeamCountryCode(team.teamName);
    if (iso2 != null && FlagCode.fromCountryCode(iso2) != null) {
      return CountryFlag.fromCountryCode(
        iso2,
        theme: const ImageTheme(
          width: size,
          height: size,
          shape: RoundedRectangle(radius),
        ),
      );
    }
    return TeamCrestAvatar(
      teamName: team.teamName,
      size: size,
      borderRadius: radius,
    );
  }

  Widget _buildHero(ShareCardPalette p) {
    final crest = _buildCrest();
    // Flat in both editions: a tinted hero ended in a hard seam on the page.
    return Padding(
      padding: const EdgeInsets.fromLTRB(_padH, 28, _padH, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _logoBadge(26, p),
              const SizedBox(width: 9),
              Text(
                'ChessEver',
                style: AppTypography.textMdBold.copyWith(color: p.textHi),
              ),
              const Spacer(),
              Text(
                'TEAM REPORT',
                style: AppTypography.textXsMedium.copyWith(
                  color: p.textLo,
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
              style: AppTypography.textMdBold.copyWith(color: p.textHi),
            ),
            const SizedBox(height: 6),
            Container(
              width: 36,
              height: 3,
              decoration: BoxDecoration(
                color: p.accentFill,
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
                      style: AppTypography.textLgBold.copyWith(
                        color: p.textHi,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      team.rank > 0 ? 'Rank #${team.rank}' : 'Team scorecard',
                      style: AppTypography.textSmMedium.copyWith(
                        color: p.textMid,
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

  Widget _buildStats(ShareCardPalette p) {
    Widget tile(String label, String value) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(10),
          // Paper only: a white tile needs an edge; dark separates by tone.
          border:
              p.tileEdge == null ? null : Border.all(color: p.tileEdge!),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: AppTypography.textMdBold.copyWith(color: p.textHi),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTypography.textXsMedium.copyWith(color: p.textLo),
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
          averageElo != null ? averageElo.toString() : '-',
        ),
      ],
    );
  }
}

/// One match line: `1.  2.5 – 1.5  Norway`. The card is already about this
/// team, so only the opponent is named; our score reads first, on our side.
class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.row});

  final TeamEventShareMatchRow row;

  /// Every score pill shares this width (wider scores still grow) so opponent
  /// names start on one edge down the list instead of trailing each score.
  static const _scoreSlotWidth = 72.0;

  Color _sideColor(bool ours, ShareCardPalette p) {
    switch (row.result) {
      case TeamMatchResult.win:
        return ours ? p.accentInk : p.loss;
      case TeamMatchResult.loss:
        return ours ? p.loss : p.accentInk;
      case TeamMatchResult.draw:
        return p.textHi;
      case TeamMatchResult.ongoing:
        return p.pending;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ShareCardPalette.of(context);
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
                  color: p.textMid,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Container(
            constraints: const BoxConstraints(minWidth: _scoreSlotWidth),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: p.wash,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  row.ourPointsLabel,
                  style: AppTypography.textXsBold.copyWith(
                    color: _sideColor(true, p),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '–',
                    style: AppTypography.textXsMedium.copyWith(
                      color: p.textLo,
                    ),
                  ),
                ),
                Text(
                  row.opponentPointsLabel,
                  style: AppTypography.textXsBold.copyWith(
                    color: _sideColor(false, p),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              row.opponentTeam,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textXsMedium.copyWith(
                color: p.textHi,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
