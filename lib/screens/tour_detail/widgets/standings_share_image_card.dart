import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/share_card.dart';
import 'package:chessever2/utils/share_card_palette.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:flutter/material.dart';

/// Maximum standings rows rendered on the shareable card. Long open events run
/// to hundreds of players; a leaderboard image stays legible and X/Twitter-sized
/// when capped, with a "+N more" line pointing back to the app for the tail.
const int kStandingsShareRowLimit = 16;

/// A self-contained, brand-forward leaderboard image of a tournament's
/// standings, built to be captured off-screen (see `captureCardPng`) and shared
/// to social. Colours come from the capture's [ShareCardPalette]: the dark
/// brand identity, or its paper edition when the app is in light mode. Height
/// is intrinsic (grows with the row count up to [kStandingsShareRowLimit]).
class StandingsShareImageCard extends StatelessWidget {
  const StandingsShareImageCard({
    super.key,
    required this.width,
    required this.eventName,
    required this.standings,
  });

  final double width;
  final String? eventName;
  final List<PlayerStandingModel> standings;

  static const _padH = 22.0;

  /// Footer tagline: the one [kShareFooterSlogan] every share card uses
  /// (standings, team standings, bracket, player, profile, team event).
  static const footerSlogan = kShareFooterSlogan;

  @override
  Widget build(BuildContext context) {
    final rows =
        standings.length > kStandingsShareRowLimit
            ? standings.sublist(0, kStandingsShareRowLimit)
            : standings;
    final remaining = standings.length - rows.length;
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
                _buildHeader(p),
                Padding(
                  padding: const EdgeInsets.fromLTRB(_padH, 6, _padH, 18),
                  child: _buildTable(rows, remaining, p),
                ),
                _buildFooter(p),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ShareCardPalette p) {
    final title = eventName?.trim();
    final hasEvent = title != null && title.isNotEmpty;

    return DecoratedBox(
      // Paper keeps a flat header; dark washes it with cyan.
      decoration:
          p.heroTint > 0
              ? BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.alphaBlend(
                      p.accentFill.withValues(alpha: p.heroTint),
                      p.bg,
                    ),
                    p.bg,
                  ],
                ),
              )
              : const BoxDecoration(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_padH, 22, _padH, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _logoBadge(26, p),
                const SizedBox(width: 9),
                Text(
                  'ChessEver',
                  style: AppTypography.textSmBold.copyWith(
                    color: p.textHi,
                    fontSize: 15,
                    letterSpacing: 0.2,
                  ),
                ),
                const Spacer(),
                Text(
                  'STANDINGS',
                  style: AppTypography.textXxsBold.copyWith(
                    color: p.textLo,
                    fontSize: 10,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              hasEvent ? title : 'Tournament',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textXlBold.copyWith(
                color: p.textHi,
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
                color: p.accentFill,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(
    List<PlayerStandingModel> rows,
    int remaining,
    ShareCardPalette p,
  ) {
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
                  color: p.textLo,
                  fontSize: 10.5,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              Text(
                rows.length == 1 ? '1 player' : '${rows.length} players',
                style: AppTypography.textXxsMedium.copyWith(
                  color: p.textLo,
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            color: p.surfaceLow,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  _StandingRow(
                    rank: rows[i].overallRank ?? (i + 1),
                    player: rows[i],
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
                color: p.textLo,
                fontSize: 11.5,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFooter(ShareCardPalette p) {
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.hairline, width: 1)),
      ),
      padding: const EdgeInsets.fromLTRB(_padH, 15, _padH, 16),
      child: Row(
        children: [
          _logoBadge(30, p),
          const SizedBox(width: 11),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ChessEver',
                style: AppTypography.textSmBold.copyWith(
                  color: p.textHi,
                  fontSize: 14.5,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                footerSlogan,
                style: AppTypography.textXxsMedium.copyWith(
                  color: p.textLo,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            'chessever.com',
            style: AppTypography.textXsBold.copyWith(
              color: p.accentInk,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
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
}

class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.rank,
    required this.player,
    required this.isLast,
  });

  final int rank;
  final PlayerStandingModel player;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final titleText = (player.title ?? '').trim();
    final countryCode = player.countryCode.trim();
    final matchScore = player.matchScore?.trim();
    final isTopThree = rank <= 3;
    final p = ShareCardPalette.of(context);

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border:
            isLast
                ? null
                : Border(bottom: BorderSide(color: p.hairline, width: 0.7)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '$rank',
              maxLines: 1,
              style: AppTypography.textSmBold.copyWith(
                color: isTopThree ? p.gold : p.textMid,
                fontSize: 15,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (countryCode.isNotEmpty) ...[
            FederationFlag(
              federation: countryCode,
              height: 14,
              width: 20,
              borderRadius: BorderRadius.circular(3),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  if (titleText.isNotEmpty)
                    TextSpan(
                      text: '$titleText ',
                      style: AppTypography.textSmBold.copyWith(
                        color: p.gold,
                        fontSize: 14.5,
                      ),
                    ),
                  TextSpan(
                    text: player.name,
                    style: AppTypography.textSmBold.copyWith(
                      color: p.textHi,
                      fontSize: 14.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (player.scoreChange != 0) ...[
            const SizedBox(width: 8),
            Text(
              player.scoreChange > 0
                  ? '+${player.scoreChange}'
                  : '${player.scoreChange}',
              style: AppTypography.textXxsBold.copyWith(
                color: player.scoreChange > 0 ? p.win : p.loss,
                fontSize: 11,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          const SizedBox(width: 12),
          Text(
            matchScore != null && matchScore.isNotEmpty
                ? matchScore
                : '${player.score}',
            style: AppTypography.textMdBold.copyWith(
              color: p.textHi,
              fontSize: 16,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
