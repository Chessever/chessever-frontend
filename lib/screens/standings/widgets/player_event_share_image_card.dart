import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
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
/// The palette is hardcoded to the dark brand identity on purpose: the shared
/// image must look the same whether the user is in light or dark mode.
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

  // Deterministic dark brand palette (independent of the active app theme).
  static const _bg = Color(0xFF0A0B0D);
  static const _surface = Color(0xFF15171C); // elevated tiles
  static const _surfaceLow = Color(0xFF101216); // recessed list / rating strip
  static const _hairline = Color(0xFF23262E);
  static const _cyan = kPrimaryColor;
  static const _gold = kLightYellowColor;
  static const _win = kGreenColor2;
  static const _loss = kRedColor;
  static const _textHi = Colors.white;
  static const _textMid = Color(0xFFAEB4BF);
  static const _textLo = Color(0xFF868C97); // ≥4.5:1 on the dark surfaces

  static const _padH = 22.0;

  @override
  Widget build(BuildContext context) {
    // Provide MediaQuery + Material locally so the card survives the
    // off-screen measurement pass of captureFromLongWidget (which only wraps
    // the widget in Directionality), and renders identically on any device.
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
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _padH),
                  child: _buildHeadlineStats(),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _padH),
                  child: _buildRatingStrip(),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _padH),
                  child: _buildGames(),
                ),
                const SizedBox(height: 18),
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Hero: brand mark, event name, player identity, over a cyan glow ────────
  Widget _buildHero() {
    final eventTitle = eventName?.trim();
    final hasEvent = eventTitle != null && eventTitle.isNotEmpty;

    return ClipRect(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.alphaBlend(_cyan.withValues(alpha: 0.13), _bg), _bg],
          ),
        ),
        child: Stack(
          children: [
            // Soft cyan glow bleeding from behind the avatar.
            Positioned(
              left: -60,
              top: 56,
              child: _GlowBlob(color: _cyan, size: 240, opacity: 0.20),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(_padH, 22, _padH, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Brand mark + wordmark
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
                        'PLAYER REPORT',
                        style: AppTypography.textXxsBold.copyWith(
                          color: _textLo,
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
                  // Cyan kicker accent under the event name.
                  Container(
                    width: 38,
                    height: 3,
                    decoration: BoxDecoration(
                      color: _cyan,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 18),
                  _buildPlayerIdentity(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerIdentity() {
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
                          color: _gold,
                          fontSize: 22,
                          height: 1.1,
                          letterSpacing: -0.3,
                        ),
                      ),
                    TextSpan(
                      text: player.name,
                      style: AppTypography.textXlBold.copyWith(
                        color: _textHi,
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
                      '$standardRating FIDE',
                      style: AppTypography.textSmMedium.copyWith(
                        color: _textMid,
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
  Widget _buildHeadlineStats() {
    final scoreText =
        eventScore != null && eventTotalGames != null
            ? formatShareScore(eventScore!, eventTotalGames!)
            : '-';
    final diffText =
        ratingDiff == null
            ? '-'
            : (ratingDiff! >= 0 ? '+$ratingDiff' : '$ratingDiff');
    final diffColor =
        ratingDiff == null ? _textHi : (ratingDiff! >= 0 ? _win : _loss);

    return Container(
      height: 92,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _hairline, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: _HeadlineStat(
              label: 'PERFORMANCE',
              value: performanceRating?.toString() ?? '-',
            ),
          ),
          _statDivider(),
          Expanded(child: _HeadlineStat(label: 'SCORE', value: scoreText)),
          _statDivider(),
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

  Widget _statDivider() => Container(width: 1, height: 42, color: _hairline);

  // ── Rating strip: Classical / Rapid / Blitz, secondary weight ──────────────
  Widget _buildRatingStrip() {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: _surfaceLow,
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
          _segDivider(),
          Expanded(
            child: _RatingSegment(
              icon: PngAsset.rapidIcon,
              label: 'Rapid',
              rating: rapidRating,
            ),
          ),
          _segDivider(),
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

  Widget _segDivider() => Container(width: 1, height: 28, color: _hairline);

  // ── Games: every opponent row, never truncated ────────────────────────────
  Widget _buildGames() {
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
                  color: _textLo,
                  fontSize: 10.5,
                  letterSpacing: 1.4,
                ),
              ),
              const Spacer(),
              Text(
                rows.length == 1 ? '1 game' : '${rows.length} games',
                style: AppTypography.textXxsMedium.copyWith(
                  color: _textLo,
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
            color: _surfaceLow,
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          maxLines: 1,
          style: AppTypography.textXxsBold.copyWith(
            color: PlayerEventShareImageCard._textLo,
            fontSize: 10,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          value,
          maxLines: 1,
          style: AppTypography.displayXsBold.copyWith(
            color: valueColor ?? PlayerEventShareImageCard._textHi,
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Image.asset(icon, width: 17, height: 17),
        const SizedBox(width: 8),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              style: AppTypography.textXxsMedium.copyWith(
                color: PlayerEventShareImageCard._textLo,
                fontSize: 9.5,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              rating?.toString() ?? '-',
              maxLines: 1,
              style: AppTypography.textSmBold.copyWith(
                color: PlayerEventShareImageCard._textHi,
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

  Color get _outcomeColor {
    switch (row.outcome) {
      case PlayerEventGameOutcome.win:
        return PlayerEventShareImageCard._win;
      case PlayerEventGameOutcome.loss:
        return PlayerEventShareImageCard._loss;
      case PlayerEventGameOutcome.draw:
      case PlayerEventGameOutcome.other:
        return PlayerEventShareImageCard._textMid;
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleText = (row.title ?? '').trim();
    final pillColor = _outcomeColor;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border:
            isLast
                ? null
                : const Border(
                  bottom: BorderSide(
                    color: PlayerEventShareImageCard._hairline,
                    width: 0.7,
                  ),
                ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              row.roundLabel ?? '${index + 1}.',
              maxLines: 1,
              style: AppTypography.textSmBold.copyWith(
                color: PlayerEventShareImageCard._textMid,
                fontSize: 13.5,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Piece-colour the player had: white/black ring.
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: row.isWhite ? Colors.white : const Color(0xFF1A1A1C),
              border: Border.all(
                color:
                    row.isWhite
                        ? Colors.transparent
                        : Colors.white.withValues(alpha: 0.45),
                width: 1,
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
                        color: PlayerEventShareImageCard._gold,
                        fontSize: 14.5,
                      ),
                    ),
                  TextSpan(
                    text: row.name,
                    style: AppTypography.textSmBold.copyWith(
                      color: PlayerEventShareImageCard._textHi,
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
              color: PlayerEventShareImageCard._textMid,
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
                  color:
                      row.ratingChange! > 0
                          ? PlayerEventShareImageCard._win
                          : PlayerEventShareImageCard._loss,
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
          const SizedBox(width: 12),
          // Result chip, tinted by outcome.
          Container(
            constraints: const BoxConstraints(minWidth: 34),
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: pillColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              row.result,
              maxLines: 1,
              style: AppTypography.textSmBold.copyWith(
                color: pillColor,
                fontSize: 13.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
