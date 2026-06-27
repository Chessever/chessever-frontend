import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:flutter/material.dart';

@visibleForTesting
bool playerEventShareShouldShowFooter(int rowCount) => rowCount <= 11;

@visibleForTesting
double playerEventShareRowHeight(int rowCount) =>
    rowCount >= 13
        ? 47.0
        : rowCount >= 11
        ? 50.0
        : 54.0;

class PlayerEventShareGameRow {
  const PlayerEventShareGameRow({
    required this.roundLabel,
    required this.countryCode,
    required this.title,
    required this.name,
    required this.rating,
    required this.ratingChange,
    required this.result,
    required this.isWhite,
  });

  final String? roundLabel;
  final String countryCode;
  final String? title;
  final String name;
  final int rating;
  final double? ratingChange;
  final String result;
  final bool isWhite;
}

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

  static const _background = Color(0xFF0B0B0E);
  static const _surface = Color(0xFF18191D);
  static const _topSurface = Color(0xFF12161B);
  static const _divider = Color(0xFF2B2D31);
  static const _muted = Color(0xFFBABCC5);

  @override
  Widget build(BuildContext context) {
    final showFooter = playerEventShareShouldShowFooter(rows.length);
    final rowHeight = playerEventShareRowHeight(rows.length);
    final ratingAreaHeight = rows.length >= 13 ? 118.0 : 128.0;
    final statsHeight = rows.length >= 13 ? 76.0 : 86.0;
    final rowsHeight = rows.length * rowHeight;
    final footerHeight = showFooter ? 28.0 : 8.0;
    final totalHeight =
        48.0 +
        58.0 +
        12.0 +
        ratingAreaHeight +
        12.0 +
        statsHeight +
        12.0 +
        rowsHeight +
        footerHeight;

    return MediaQuery(
      data: MediaQueryData(
        size: Size(width, totalHeight),
        padding: EdgeInsets.zero,
      ),
      child: Material(
        color: _background,
        child: SizedBox(
          width: width,
          height: totalHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildEventStrip(),
              _buildPlayerHeader(context),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildRatingsRow(context, ratingAreaHeight),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildStatsRow(context, statsHeight),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildGamesList(context, rowHeight),
              ),
              if (showFooter)
                Expanded(
                  child: Center(
                    child: Text(
                      'ChessEver · Follow Chess Better',
                      style: AppTypography.textXsMedium.copyWith(
                        color: _muted.withValues(alpha: 0.6),
                        fontSize: 11,
                      ),
                    ),
                  ),
                )
              else
                const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEventStrip() {
    final title = eventName?.trim();
    return Container(
      height: 48,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      color: const Color(0xFF07080B),
      child: Text(
        title == null || title.isEmpty ? 'ChessEver Event' : title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: AppTypography.textSmBold.copyWith(color: _muted, fontSize: 14),
      ),
    );
  }

  Widget _buildPlayerHeader(BuildContext context) {
    final titleText = (player.title ?? '').trim();
    final countryCode = player.countryCode.trim();
    return Container(
      height: 58,
      color: _topSurface,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          if (countryCode.isNotEmpty)
            FederationFlag(
              federation: countryCode,
              height: 16,
              width: 22,
              borderRadius: BorderRadius.circular(2),
            ),
          if (countryCode.isNotEmpty) const SizedBox(width: 10),
          Expanded(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  if (titleText.isNotEmpty)
                    TextSpan(
                      text: '$titleText ',
                      style: AppTypography.textMdBold.copyWith(
                        color: kLightYellowColor,
                        fontSize: 20,
                      ),
                    ),
                  TextSpan(
                    text: player.name,
                    style: AppTypography.textMdBold.copyWith(
                      color: Colors.white,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingsRow(BuildContext context, double height) {
    return SizedBox(
      height: height,
      child: Row(
        children: [
          SizedBox(
            width: height,
            child: FutureBuilder<String?>(
              future: photoFuture,
              builder: (context, snapshot) {
                return PlayerInitialsAvatar(
                  photoUrl: snapshot.data,
                  initials: initials,
                  size: height,
                  borderRadius: 12,
                  title: player.title,
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ShareRatingTile(
              label: 'Classical',
              icon: PngAsset.classicalIcon,
              rating: standardRating,
              height: height,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ShareRatingTile(
              label: 'Rapid',
              icon: PngAsset.rapidIcon,
              rating: rapidRating,
              height: height,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ShareRatingTile(
              label: 'Blitz',
              icon: PngAsset.blitzIcon,
              rating: blitzRating,
              height: height,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context, double height) {
    final scoreText =
        eventScore != null && eventTotalGames != null
            ? _formatScore(eventScore!, eventTotalGames!)
            : '-';
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ShareStat(
            label: 'Performance',
            value: performanceRating?.toString() ?? '-',
          ),
          _ShareStat(label: 'Score', value: scoreText),
          _ShareStat(
            label: 'Rating',
            value:
                ratingDiff == null
                    ? '-'
                    : (ratingDiff! >= 0 ? '+$ratingDiff' : '$ratingDiff'),
            valueColor:
                ratingDiff == null
                    ? Colors.white
                    : ratingDiff! >= 0
                    ? context.colors.brand
                    : kRedColor,
          ),
        ],
      ),
    );
  }

  Widget _buildGamesList(BuildContext context, double rowHeight) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: const Color(0xFF161719),
        child: Column(
          children: [
            for (final entry in rows.asMap().entries)
              _ShareGameRow(
                row: entry.value,
                index: entry.key,
                height: rowHeight,
                isLast: entry.key == rows.length - 1,
              ),
          ],
        ),
      ),
    );
  }

  static String _formatScore(double score, int totalGames) {
    final scoreStr =
        score == score.truncate()
            ? score.truncate().toString()
            : score.toString();
    return '$scoreStr/$totalGames';
  }
}

class _ShareRatingTile extends StatelessWidget {
  const _ShareRatingTile({
    required this.label,
    required this.icon,
    required this.rating,
    required this.height,
  });

  final String label;
  final String icon;
  final int? rating;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: PlayerEventShareImageCard._surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(icon, width: 18, height: 18),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.textXsMedium.copyWith(
              color: PlayerEventShareImageCard._muted,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            rating?.toString() ?? '-',
            style: AppTypography.textMdBold.copyWith(
              color: Colors.white,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareStat extends StatelessWidget {
  const _ShareStat({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.textXsMedium.copyWith(
            color: PlayerEventShareImageCard._muted,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: AppTypography.textLgBold.copyWith(
            color: valueColor ?? Colors.white,
            fontSize: 21,
          ),
        ),
      ],
    );
  }
}

class _ShareGameRow extends StatelessWidget {
  const _ShareGameRow({
    required this.row,
    required this.index,
    required this.height,
    required this.isLast,
  });

  final PlayerEventShareGameRow row;
  final int index;
  final double height;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final nameFontSize = height <= 48 ? 14.2 : 15.2;
    final titleText = (row.title ?? '').trim();
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border:
            isLast
                ? null
                : const Border(
                  bottom: BorderSide(
                    color: PlayerEventShareImageCard._divider,
                    width: 0.7,
                  ),
                ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              row.roundLabel ?? '${index + 1}.',
              style: AppTypography.textMdBold.copyWith(
                color: Colors.white,
                fontSize: nameFontSize,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (row.countryCode.trim().isNotEmpty)
            FederationFlag(
              federation: row.countryCode,
              height: 14,
              width: 20,
              borderRadius: BorderRadius.circular(2),
            ),
          if (row.countryCode.trim().isNotEmpty) const SizedBox(width: 9),
          Expanded(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  if (titleText.isNotEmpty)
                    TextSpan(
                      text: '$titleText ',
                      style: AppTypography.textMdBold.copyWith(
                        color: kLightYellowColor,
                        fontSize: nameFontSize,
                      ),
                    ),
                  TextSpan(
                    text: row.name,
                    style: AppTypography.textMdBold.copyWith(
                      color: Colors.white,
                      fontSize: nameFontSize,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            row.rating.toString(),
            style: AppTypography.textMdMedium.copyWith(
              color: Colors.white,
              fontSize: 15,
            ),
          ),
          if (row.ratingChange != null && row.ratingChange != 0.0) ...[
            const SizedBox(width: 4),
            Text(
              row.ratingChange! > 0
                  ? '+${row.ratingChange!.toStringAsFixed(0)}'
                  : row.ratingChange!.toStringAsFixed(0),
              style: AppTypography.textXsMedium.copyWith(
                color: row.ratingChange! > 0 ? context.colors.brand : kRedColor,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(width: 12),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: row.isWhite ? Colors.white : Colors.black,
              shape: BoxShape.circle,
              border:
                  row.isWhite
                      ? null
                      : Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                        width: 1.1,
                      ),
            ),
            child: Center(
              child: Text(
                row.result,
                textAlign: TextAlign.center,
                style: AppTypography.textMdBold.copyWith(
                  color: row.isWhite ? Colors.black : Colors.white,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
