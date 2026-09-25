import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/share_card.dart';
import 'package:chessever2/utils/share_card_palette.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:flutter/material.dart';

/// Win / draw / loss of one game from the shared player's perspective.
/// Computed at the call site (where the [GameStatus] is known) so this widget
/// stays decoupled from the game models and can be screenshotted in isolation.
enum PlayerEventGameOutcome { win, draw, loss, other }

/// One opponent row rendered on the shareable player-event card.
class PlayerEventShareGameRow {
  const PlayerEventShareGameRow({
    required this.roundLabel,
    required this.countryCode,
    required this.title,
    required this.name,
    required this.rating,
    required this.ratingChange,
    required this.result,
    required this.outcome,
    required this.isWhite,
  });

  final String? roundLabel;
  final String countryCode;
  final String? title;
  final String name;
  final int rating;
  final double? ratingChange;
  final String result;
  final PlayerEventGameOutcome outcome;
  final bool isWhite;
}

/// A self-contained, brand-forward image of a player's tournament run, built to
/// be captured with `ScreenshotController.captureFromLongWidget` and shared to
/// social. Unlike the live scorecard it is NOT a screenshot of the screen: it
/// is a designed artifact with a ChessEver lockup at the top and bottom, a
/// cyan hero glow behind the player, and the full opponent list. Height is
/// intrinsic (grows with the game count) so no row is ever dropped to fit.
///
/// Colours come from the [ShareCardPalette] the capture provides: the dark
/// brand identity, or its paper edition when the app is in light mode.
class PlayerEventShareImageCard extends StatelessWidget {
  const PlayerEventShareImageCard({
    super.key,
    required this.width,
    required this.player,
    required this.photoFuture,
    required this.initials,
    required this.eventName,
    required this.performanceRating,
    required this.eventScore,
    required this.eventTotalGames,
    required this.ratingDiff,
    required this.standardRating,
    required this.rapidRating,
    required this.blitzRating,
    required this.rows,
  });

  final double width;
  final PlayerStandingModel player;
  final Future<String?>? photoFuture;
  final String initials;
  final String? eventName;
  final int? performanceRating;
  final double? eventScore;
  final int? eventTotalGames;
  final int? ratingDiff;
  final int? standardRating;
  final int? rapidRating;
  final int? blitzRating;
  final List<PlayerEventShareGameRow> rows;

  static const _padH = 22.0;
  static const footerSlogan = 'Follow Chess Better';

  static String formatHeaderRating(int rating) => rating.toString();

  @override
  Widget build(BuildContext context) {
    final p = ShareCardPalette.of(context);
    // Provide MediaQuery + Material locally so the card survives the
    // off-screen measurement pass of captureFromLongWidget (which only wraps
    // the widget in Directionality), and renders identically on any device.
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
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _padH),
                  child: _buildHeadlineStats(p),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _padH),
                  child: _buildRatingStrip(p),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _padH),
                  child: _buildGames(p),
                ),
                const SizedBox(height: 18),
                _buildFooter(p),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Hero: brand mark, event name, player identity, over a cyan glow ────────
  Widget _buildHero(ShareCardPalette p) {
    final eventTitle = eventName?.trim();
    final hasEvent = eventTitle != null && eventTitle.isNotEmpty;

    return ClipRect(
      child: DecoratedBox(
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
        child: Stack(
          children: [
            // Soft cyan glow bleeding from behind the avatar (dark only).
            if (p.glowOpacity > 0)
              Positioned(
                left: -60,
                top: 56,
                child: _GlowBlob(
                  color: p.accentFill,
                  size: 240,
                  opacity: p.glowOpacity,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(_padH, 22, _padH, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Brand mark + wordmark
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
                        'PLAYER REPORT',
                        style: AppTypography.textXxsBold.copyWith(
                          color: p.textLo,
                          fontSize: 10,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Event name (the headline at the top, per the brief)
                  Text(
                    hasEvent ? eventTitle : 'Tournament',
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
                  // Cyan kicker accent under the event name.
                  Container(
                    width: 38,
                    height: 3,
                    decoration: BoxDecoration(
                      color: p.accentFill,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _buildPlayerIdentity(p),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerIdentity(ShareCardPalette p) {
    final titleText = (player.title ?? '').trim();
    final countryCode = player.countryCode.trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 76,
          height: 76,
          child: FutureBuilder<String?>(
            future: photoFuture,
            builder: (context, snapshot) {
              return PlayerInitialsAvatar(
                photoUrl: snapshot.data,
                initials: initials,
                size: 76,
                borderRadius: 16,
                title: player.title,
              );
            },
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              RichText(
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  children: [
                    if (titleText.isNotEmpty)
                      TextSpan(
                        text: '$titleText ',
                        style: AppTypography.textXlBold.copyWith(
                          color: p.gold,
                          fontSize: 22,
                          height: 1.1,
                          letterSpacing: -0.3,
                        ),
                      ),
                    TextSpan(
                      text: player.name,
                      style: AppTypography.textXlBold.copyWith(
                        color: p.textHi,
                        fontSize: 22,
                        height: 1.1,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (countryCode.isNotEmpty) ...[
                    FederationFlag(
                      federation: countryCode,
                      height: 14,
                      width: 20,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (standardRating != null)
                    Text(
                      formatHeaderRating(standardRating!),
                      style: AppTypography.textSmMedium.copyWith(
                        color: p.textMid,
                        fontSize: 13,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Headline stats: Performance / Score / Rating, divided not boxed ────────
  Widget _buildHeadlineStats(ShareCardPalette p) {
    final scoreText =
        eventScore != null && eventTotalGames != null
            ? formatShareScore(eventScore!, eventTotalGames!)
            : '-';
    final diffText =
        ratingDiff == null
            ? '-'
            : (ratingDiff! >= 0 ? '+$ratingDiff' : '$ratingDiff');
    final diffColor =
        ratingDiff == null ? p.textHi : (ratingDiff! >= 0 ? p.win : p.loss);

    return Container(
      height: 92,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.tileEdge ?? p.hairline, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: _HeadlineStat(
              label: 'PERFORMANCE',
              value: performanceRating?.toString() ?? '-',
            ),
          ),
          _statDivider(p),
          Expanded(child: _HeadlineStat(label: 'SCORE', value: scoreText)),
          _statDivider(p),
          Expanded(
            child: _HeadlineStat(
              label: 'RATING',
              value: diffText,
              valueColor: diffColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDivider(ShareCardPalette p) =>
      Container(width: 1, height: 42, color: p.hairline);

  // ── Rating strip: Classical / Rapid / Blitz, secondary weight ──────────────
  Widget _buildRatingStrip(ShareCardPalette p) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: p.surfaceLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _RatingSegment(
              icon: PngAsset.classicalIcon,
              label: 'Classical',
              rating: standardRating,
            ),
          ),
          _segDivider(p),
          Expanded(
            child: _RatingSegment(
              icon: PngAsset.rapidIcon,
              label: 'Rapid',
              rating: rapidRating,
            ),
          ),
          _segDivider(p),
          Expanded(
            child: _RatingSegment(
              icon: PngAsset.blitzIcon,
              label: 'Blitz',
              rating: blitzRating,
            ),
          ),
        ],
      ),
    );
  }

  Widget _segDivider(ShareCardPalette p) =>
      Container(width: 1, height: 28, color: p.hairline);

  // ── Games: every opponent row, never truncated ────────────────────────────
  Widget _buildGames(ShareCardPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Text(
                'RESULTS',
                style: AppTypography.textXxsBold.copyWith(
                  color: p.textLo,
                  fontSize: 10.5,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              Text(
                rows.length == 1 ? '1 game' : '${rows.length} games',
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
                  _ShareGameRow(
                    row: rows[i],
                    index: i,
                    isLast: i == rows.length - 1,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Footer: persistent ChessEver lockup + attribution ──────────────────────
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
                PlayerEventShareImageCard.footerSlogan,
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

  /// Formats an event score as e.g. `9/11` or `8.5/11`.
  @visibleForTesting
  static String formatShareScore(double score, int totalGames) {
    final scoreStr =
        score == score.truncate()
            ? score.truncate().toString()
            : score.toString();
    return '$scoreStr/$totalGames';
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({
    required this.color,
    required this.size,
    required this.opacity,
  });

  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeadlineStat extends StatelessWidget {
  const _HeadlineStat({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final p = ShareCardPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          maxLines: 1,
          style: AppTypography.textXxsBold.copyWith(
            color: p.textLo,
            fontSize: 10,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          value,
          maxLines: 1,
          style: AppTypography.displayXsBold.copyWith(
            color: valueColor ?? p.textHi,
            fontSize: 26,
            height: 1.0,
            letterSpacing: -0.5,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _RatingSegment extends StatelessWidget {
  const _RatingSegment({
    required this.icon,
    required this.label,
    required this.rating,
  });

  final String icon;
  final String label;
  final int? rating;

  @override
  Widget build(BuildContext context) {
    final p = ShareCardPalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        shareTimeControlIcon(icon, p),
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              style: AppTypography.textXxsMedium.copyWith(
                color: p.textLo,
                fontSize: 9.5,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              rating?.toString() ?? '-',
              maxLines: 1,
              style: AppTypography.textSmBold.copyWith(
                color: p.textHi,
                fontSize: 15,
                height: 1.05,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ShareGameRow extends StatelessWidget {
  const _ShareGameRow({
    required this.row,
    required this.index,
    required this.isLast,
  });

  final PlayerEventShareGameRow row;
  final int index;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final p = ShareCardPalette.of(context);
    final titleText = (row.title ?? '').trim();

    return Container(
      height: 48,
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
            width: 24,
            child: Text(
              row.roundLabel ?? '${index + 1}.',
              maxLines: 1,
              style: AppTypography.textSmBold.copyWith(
                color: p.textMid,
                fontSize: 13.5,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (row.countryCode.trim().isNotEmpty) ...[
            FederationFlag(
              federation: row.countryCode,
              height: 13,
              width: 19,
              borderRadius: BorderRadius.circular(2),
            ),
            const SizedBox(width: 9),
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
                    text: row.name,
                    style: AppTypography.textSmBold.copyWith(
                      color: p.textHi,
                      fontSize: 14.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            row.rating.toString(),
            style: AppTypography.textSmMedium.copyWith(
              color: p.textMid,
              fontSize: 13.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (row.ratingChange != null && row.ratingChange != 0.0) ...[
            const SizedBox(width: 5),
            SizedBox(
              width: 30,
              child: Text(
                row.ratingChange! > 0
                    ? '+${row.ratingChange!.toStringAsFixed(0)}'
                    : row.ratingChange!.toStringAsFixed(0),
                style: AppTypography.textXxsBold.copyWith(
                  color: row.ratingChange! > 0 ? p.win : p.loss,
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
          const SizedBox(width: 12),
          // Result on a white/black piece-colour circle (mirrors the live
          // scorecard): the circle fill conveys the side the player had, the
          // inverted text the score. The disc that matches the page gets an
          // edge so it never melts into it.
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: row.isWhite ? p.pieceWhite : p.pieceBlack,
              border: switch (row.isWhite
                  ? p.pieceWhiteEdge
                  : p.pieceBlackEdge) {
                final edge? => Border.all(color: edge, width: 1.1),
                null => null,
              },
            ),
            child: Text(
              row.result,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: AppTypography.textSmBold.copyWith(
                color: row.isWhite ? p.pieceBlack : p.pieceWhite,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
