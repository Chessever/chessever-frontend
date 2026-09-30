import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/share_card.dart';
import 'package:chessever2/utils/share_card_palette.dart';
import 'package:chessever2/widgets/federation_flag.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:flutter/material.dart';

/// A self-contained, brand-forward image of a player's overall profile, built
/// to be captured with `captureCardPng` and shared to social. It mirrors the
/// About tab of the player profile screen — ratings, win/draw/loss record,
/// color split, recent form and opening repertoire — rather than a single
/// tournament run (that is [PlayerEventShareImageCard]'s job). Height is
/// intrinsic so no section is ever clipped to fit.
///
/// Colours come from the [ShareCardPalette] the capture provides: the dark
/// brand identity, or its paper edition when the app is in light mode.
class PlayerProfileShareImageCard extends StatelessWidget {
  const PlayerProfileShareImageCard({
    super.key,
    required this.width,
    required this.playerName,
    required this.title,
    required this.countryCode,
    required this.fideId,
    required this.photoFuture,
    required this.initials,
    required this.standardRating,
    required this.rapidRating,
    required this.blitzRating,
    required this.analytics,
    this.isMemorial = false,
    this.lifespan,
  });

  final double width;
  final String playerName;
  final String? title;
  final String countryCode;
  final int? fideId;
  final Future<String?>? photoFuture;
  final String initials;
  final int? standardRating;
  final int? rapidRating;
  final int? blitzRating;
  final PlayerAnalytics? analytics;
  final bool isMemorial;
  final String? lifespan;

  static const _padH = 22.0;
  static const footerSlogan = 'Follow Chess Better';

  /// Top openings shown on the card; the About tab list is unbounded but the
  /// shared image must stay social-friendly.
  static const _maxOpenings = 4;

  bool get _hasStats => (analytics?.resultStats.totalGames ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    // Provide MediaQuery + Material locally so the card survives the
    // off-screen measurement pass of the capture (which only wraps the widget
    // in Directionality), and renders identically on any device.
    final openings = _topOpenings();
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
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _padH),
                  child: _buildRatingStrip(p),
                ),
                if (_hasStats) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _padH),
                    child: _buildHeadlineStats(p),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _padH),
                    child: _buildResults(p),
                  ),
                  if (analytics!.recentForm.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: _padH),
                      child: _buildForm(p),
                    ),
                  ],
                  if (openings.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: _padH),
                      child: _buildOpenings(openings, p),
                    ),
                  ],
                ],
                const SizedBox(height: 18),
                _buildFooter(p),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<OpeningStatistic> _topOpenings() {
    final stats = analytics?.openingStats;
    if (stats == null || stats.isEmpty) return const [];
    // Never fall back to the unknown-ECO buckets: a share image reading
    // "Unknown — 661 games" is worse than one opening row fewer.
    final named = stats.where((s) => s.hasRealEcoCode).toList(growable: false);
    final sorted = [...named]..sort((a, b) => b.count.compareTo(a.count));
    return sorted.take(_maxOpenings).toList(growable: false);
  }

  // ── Hero: brand mark + player identity ────────────────────────────────────
  Widget _buildHero(ShareCardPalette p) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_padH, 22, _padH, 20),
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
                  color: p.textHi,
                  fontSize: 15,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              Text(
                isMemorial ? 'Memorial profile' : 'Player profile',
                style: AppTypography.textXsMedium.copyWith(
                  color: p.textLo,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _buildPlayerIdentity(p),
        ],
      ),
    );
  }

  Widget _buildPlayerIdentity(ShareCardPalette p) {
    final titleText = (title ?? '').trim();
    final country = countryCode.trim();
    final countryName =
        country.isNotEmpty ? CountryUtils.getCountryName(country) : '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 84,
          height: 84,
          child: FutureBuilder<String?>(
            future: photoFuture,
            builder: (context, snapshot) {
              return PlayerInitialsAvatar(
                photoUrl: snapshot.data,
                initials: initials,
                size: 84,
                borderRadius: 16,
                title: title,
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
                      text: playerName,
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
                  if (country.isNotEmpty) ...[
                    FederationFlag(
                      federation: country,
                      height: 14,
                      width: 20,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        countryName.isNotEmpty ? countryName : country,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.textSmMedium.copyWith(
                          color: p.textMid,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (fideId != null) ...[
                const SizedBox(height: 6),
                Text(
                  '${isMemorial ? 'Historical FIDE ID' : 'FIDE ID'} $fideId',
                  style: AppTypography.textXxsMedium.copyWith(
                    color: p.textLo,
                    fontSize: 11,
                    letterSpacing: 0.4,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              if (lifespan?.trim().isNotEmpty == true) ...[
                const SizedBox(height: 5),
                Text(
                  lifespan!.trim(),
                  style: AppTypography.textXxsMedium.copyWith(
                    color: p.textLo,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ── Rating strip: Classical / Rapid / Blitz ────────────────────────────────
  Widget _buildRatingStrip(ShareCardPalette p) {
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        border: _tileEdge(p),
      ),
      child: Row(
        children: [
          Expanded(
            child: _RatingSegment(
              icon: PngAsset.classicalIcon,
              label: isMemorial ? 'Peak classical' : 'Classical',
              rating: standardRating,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _RatingSegment(
              icon: PngAsset.rapidIcon,
              label: isMemorial ? 'Peak rapid' : 'Rapid',
              rating: rapidRating,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _RatingSegment(
              icon: PngAsset.blitzIcon,
              label: isMemorial ? 'Peak blitz' : 'Blitz',
              rating: blitzRating,
            ),
          ),
        ],
      ),
    );
  }

  // ── Headline stats: Win rate / Games / Avg opponent ────────────────────────
  /// Light only: a white tile on paper needs an edge; dark separates by tone.
  static Border? _tileEdge(ShareCardPalette p) =>
      p.tileEdge == null ? null : Border.all(color: p.tileEdge!);

  Widget _buildHeadlineStats(ShareCardPalette p) {
    final stats = analytics!.resultStats;
    final winRateText = '${(stats.winRate * 100).toStringAsFixed(1)}%';
    final avgOpponent = analytics!.avgOpponentRating;

    return Container(
      height: 92,
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: _tileEdge(p),
      ),
      child: Row(
        children: [
          Expanded(
            child: _HeadlineStat(
              label: 'Win rate',
              value: winRateText,
              valueColor: p.win,
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _HeadlineStat(label: 'Games', value: '${stats.totalGames}'),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _HeadlineStat(
              label: 'Avg opponent',
              value: avgOpponent > 0 ? '$avgOpponent' : '-',
            ),
          ),
        ],
      ),
    );
  }

  // ── Results: W/D/L ratio bar + counts + colour split ───────────────────────
  Widget _buildResults(ShareCardPalette p) {
    final stats = analytics!.resultStats;
    final colors = analytics!.colorStats;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('Record', p),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            color: p.surfaceLow,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // W/D/L ratio bar, mirroring the About tab's Overall Performance.
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 8,
                  child: Row(
                    children: [
                      if (stats.wins > 0)
                        Expanded(
                          flex: stats.wins,
                          child: Container(color: p.win),
                        ),
                      if (stats.draws > 0)
                        Expanded(
                          flex: stats.draws,
                          child: Container(color: p.draw),
                        ),
                      if (stats.losses > 0)
                        Expanded(
                          flex: stats.losses,
                          child: Container(color: p.loss),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _resultCount('W', stats.wins, p.win, p),
                  _resultCount('D', stats.draws, p.draw, p),
                  _resultCount('L', stats.losses, p.loss, p),
                ],
              ),
              const SizedBox(height: 12),
              Container(height: 1, color: p.hairline),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ColorScore(
                      label: 'White',
                      isWhite: true,
                      games: colors.whiteGames,
                      score: colors.whiteScore,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ColorScore(
                      label: 'Black',
                      isWhite: false,
                      games: colors.blackGames,
                      score: colors.blackScore,
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

  Widget _resultCount(
    String letter,
    int count,
    Color color,
    ShareCardPalette p,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$count',
          style: AppTypography.textSmBold.copyWith(
            color: color,
            fontSize: 15,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 4),
        Text(
          letter,
          style: AppTypography.textXxsBold.copyWith(
            // A step quieter than its count in dark; on paper the faded
            // signal colour would fall under AA, so it keeps full strength.
            color: p.isLight ? color : color.withValues(alpha: 0.75),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  // ── Form: last N results as coloured dots ──────────────────────────────────
  Widget _buildForm(ShareCardPalette p) {
    final form = analytics!.recentForm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('Recent form', p),
        const SizedBox(height: 8),
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: p.surfaceLow,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              for (var i = 0; i < form.length; i++) ...[
                if (i > 0) const SizedBox(width: 7),
                _FormDot(result: form[i]),
              ],
              const Spacer(),
              Text(
                'last ${form.length}',
                style: AppTypography.textXxsMedium.copyWith(
                  color: p.textLo,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Openings: most played, with per-opening score ──────────────────────────
  Widget _buildOpenings(List<OpeningStatistic> openings, ShareCardPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('Most played openings', p),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            color: p.surfaceLow,
            child: Column(
              children: [
                for (var i = 0; i < openings.length; i++)
                  _OpeningRow(
                    stat: openings[i],
                    isLast: i == openings.length - 1,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text, ShareCardPalette p) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: AppTypography.textXsBold.copyWith(color: p.textLo, fontSize: 11),
      ),
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
          _logoBadge(30),
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

  Widget _logoBadge(double size) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Image.asset(
        PngAsset.newAppLogo,
        width: size,
        height: size,
        fit: BoxFit.cover,
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
          ),
        ),
        const SizedBox(height: 7),
        Text(
          value,
          maxLines: 1,
          style: AppTypography.displayXsBold.copyWith(
            color: valueColor ?? p.textHi,
            fontSize: 24,
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

class _ColorScore extends StatelessWidget {
  const _ColorScore({
    required this.label,
    required this.isWhite,
    required this.games,
    required this.score,
  });

  final String label;

  /// The side the disc stands for.
  final bool isWhite;
  final int games;
  final double score;

  @override
  Widget build(BuildContext context) {
    final p = ShareCardPalette.of(context);
    final scoreText = games > 0 ? '${(score * 100).toStringAsFixed(0)}%' : '-';
    final edge = isWhite ? p.pieceWhiteEdge : p.pieceBlackEdge;
    return Row(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isWhite ? p.pieceWhite : p.pieceBlack,
            border: edge == null ? null : Border.all(color: edge, width: 1.1),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label · $games games',
              maxLines: 1,
              style: AppTypography.textXxsMedium.copyWith(
                color: p.textLo,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              scoreText,
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

class _FormDot extends StatelessWidget {
  const _FormDot({required this.result});

  /// 1.0 win, 0.5 draw, 0.0 loss — same encoding as [PlayerAnalytics.recentForm].
  final double result;

  @override
  Widget build(BuildContext context) {
    final p = ShareCardPalette.of(context);
    final color =
        result >= 1.0
            ? p.win
            : result >= 0.5
            ? p.draw
            : p.loss;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.9),
      ),
    );
  }
}

class _OpeningRow extends StatelessWidget {
  const _OpeningRow({required this.stat, required this.isLast});

  final OpeningStatistic stat;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final p = ShareCardPalette.of(context);
    final name = (stat.openingName ?? '').trim();
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border:
            isLast
                ? null
                : Border(bottom: BorderSide(color: p.hairline, width: 0.7)),
      ),
      child: Row(
        children: [
          // The 34x22 slot holds the column in both editions; only dark
          // fills it (paper leaves the code bare, no chip around metadata).
          Container(
            width: 34,
            height: 22,
            alignment: Alignment.center,
            decoration:
                p.ecoTileAlpha > 0
                    ? BoxDecoration(
                      color: p.accentFill.withValues(alpha: p.ecoTileAlpha),
                      borderRadius: BorderRadius.circular(6),
                    )
                    : null,
            child: Text(
              stat.eco,
              maxLines: 1,
              style: AppTypography.textXxsBold.copyWith(
                color: p.accentInk,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name.isNotEmpty ? name : 'Opening',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textSmBold.copyWith(
                color: p.textHi,
                fontSize: 13.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            stat.count == 1 ? '1 game' : '${stat.count} games',
            style: AppTypography.textXxsMedium.copyWith(
              color: p.textLo,
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 38,
            child: Text(
              '${(stat.score * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: AppTypography.textSmBold.copyWith(
                color: p.textMid,
                fontSize: 13,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
