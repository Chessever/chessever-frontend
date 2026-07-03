import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/country_utils.dart';
import 'package:chessever2/utils/png_asset.dart';
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
/// The palette is hardcoded to the dark brand identity on purpose: the shared
/// image must look the same whether the user is in light or dark mode.
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

  // Deterministic dark brand palette (independent of the active app theme).
  static const _bg = Color(0xFF0A0B0D);
  static const _surface = Color(0xFF15171C); // elevated tiles
  static const _surfaceLow = Color(0xFF101216); // recessed list / rating strip
  static const _hairline = Color(0xFF23262E);
  static const _cyan = kPrimaryColor;
  static const _gold = kLightYellowColor;
  static const _win = kGreenColor2;
  static const _loss = kRedColor;
  static const _draw = Color(0xFF868C97);
  static const _textHi = Colors.white;
  static const _textMid = Color(0xFFAEB4BF);
  static const _textLo = Color(0xFF868C97); // ≥4.5:1 on the dark surfaces

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
                  child: _buildRatingStrip(),
                ),
                if (_hasStats) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _padH),
                    child: _buildHeadlineStats(),
                  ),
                  const SizedBox(height: 18),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _padH),
                    child: _buildResults(),
                  ),
                  if (analytics!.recentForm.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: _padH),
                      child: _buildForm(),
                    ),
                  ],
                  if (openings.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: _padH),
                      child: _buildOpenings(openings),
                    ),
                  ],
                ],
                const SizedBox(height: 18),
                _buildFooter(),
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
    final named =
        stats.where((s) => s.eco != 'Unknown').toList(growable: false);
    final pool = named.isNotEmpty ? named : stats;
    final sorted = [...pool]..sort((a, b) => b.count.compareTo(a.count));
    return sorted.take(_maxOpenings).toList(growable: false);
  }

  // ── Hero: brand mark + player identity over a cyan glow ────────────────────
  Widget _buildHero() {
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
              top: 40,
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
                        'PLAYER PROFILE',
                        style: AppTypography.textXxsBold.copyWith(
                          color: _textLo,
                          fontSize: 10,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildPlayerIdentity(),
                  const SizedBox(height: 14),
                  // Cyan kicker accent under the identity block.
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
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerIdentity() {
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
                      text: playerName,
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
                          color: _textMid,
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
                  'FIDE ID $fideId',
                  style: AppTypography.textXxsMedium.copyWith(
                    color: _textLo,
                    fontSize: 11,
                    letterSpacing: 0.4,
                    fontFeatures: const [FontFeature.tabularFigures()],
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
  Widget _buildRatingStrip() {
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _hairline, width: 1),
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

  Widget _segDivider() => Container(width: 1, height: 30, color: _hairline);

  // ── Headline stats: Win rate / Games / Avg opponent ────────────────────────
  Widget _buildHeadlineStats() {
    final stats = analytics!.resultStats;
    final winRateText = '${(stats.winRate * 100).toStringAsFixed(1)}%';
    final avgOpponent = analytics!.avgOpponentRating;

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
              label: 'WIN RATE',
              value: winRateText,
              valueColor: _win,
            ),
          ),
          _statDivider(),
          Expanded(
            child: _HeadlineStat(label: 'GAMES', value: '${stats.totalGames}'),
          ),
          _statDivider(),
          Expanded(
            child: _HeadlineStat(
              label: 'AVG OPPONENT',
              value: avgOpponent > 0 ? '$avgOpponent' : '-',
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() => Container(width: 1, height: 42, color: _hairline);

  // ── Results: W/D/L ratio bar + counts + colour split ───────────────────────
  Widget _buildResults() {
    final stats = analytics!.resultStats;
    final colors = analytics!.colorStats;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('RECORD'),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            color: _surfaceLow,
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
                          child: Container(color: _win),
                        ),
                      if (stats.draws > 0)
                        Expanded(
                          flex: stats.draws,
                          child: Container(color: _draw),
                        ),
                      if (stats.losses > 0)
                        Expanded(
                          flex: stats.losses,
                          child: Container(color: _loss),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _resultCount('W', stats.wins, _win),
                  _resultCount('D', stats.draws, _draw),
                  _resultCount('L', stats.losses, _loss),
                ],
              ),
              const SizedBox(height: 12),
              Container(height: 1, color: _hairline),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ColorScore(
                      label: 'White',
                      pieceColor: Colors.white,
                      games: colors.whiteGames,
                      score: colors.whiteScore,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ColorScore(
                      label: 'Black',
                      pieceColor: Colors.black,
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

  Widget _resultCount(String letter, int count, Color color) {
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
            color: color.withValues(alpha: 0.75),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  // ── Form: last N results as coloured dots ──────────────────────────────────
  Widget _buildForm() {
    final form = analytics!.recentForm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('RECENT FORM'),
        const SizedBox(height: 8),
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: _surfaceLow,
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
                  color: _textLo,
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
  Widget _buildOpenings(List<OpeningStatistic> openings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('MOST PLAYED OPENINGS'),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            color: _surfaceLow,
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

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: AppTypography.textXxsBold.copyWith(
          color: _textLo,
          fontSize: 10.5,
          letterSpacing: 1.4,
        ),
      ),
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
                footerSlogan,
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
            color: PlayerProfileShareImageCard._textLo,
            fontSize: 10,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          value,
          maxLines: 1,
          style: AppTypography.displayXsBold.copyWith(
            color: valueColor ?? PlayerProfileShareImageCard._textHi,
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
                color: PlayerProfileShareImageCard._textLo,
                fontSize: 9.5,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              rating?.toString() ?? '-',
              maxLines: 1,
              style: AppTypography.textSmBold.copyWith(
                color: PlayerProfileShareImageCard._textHi,
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
    required this.pieceColor,
    required this.games,
    required this.score,
  });

  final String label;
  final Color pieceColor;
  final int games;
  final double score;

  @override
  Widget build(BuildContext context) {
    final scoreText = games > 0 ? '${(score * 100).toStringAsFixed(0)}%' : '-';
    return Row(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: pieceColor,
            border:
                pieceColor == Colors.black
                    ? Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 1.1,
                    )
                    : null,
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
                color: PlayerProfileShareImageCard._textLo,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              scoreText,
              maxLines: 1,
              style: AppTypography.textSmBold.copyWith(
                color: PlayerProfileShareImageCard._textHi,
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
    final color =
        result >= 1.0
            ? PlayerProfileShareImageCard._win
            : result >= 0.5
            ? PlayerProfileShareImageCard._draw
            : PlayerProfileShareImageCard._loss;
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
    final name = (stat.openingName ?? '').trim();
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border:
            isLast
                ? null
                : const Border(
                  bottom: BorderSide(
                    color: PlayerProfileShareImageCard._hairline,
                    width: 0.7,
                  ),
                ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: PlayerProfileShareImageCard._cyan.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              stat.eco,
              maxLines: 1,
              style: AppTypography.textXxsBold.copyWith(
                color: PlayerProfileShareImageCard._cyan,
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
                color: PlayerProfileShareImageCard._textHi,
                fontSize: 13.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            stat.count == 1 ? '1 game' : '${stat.count} games',
            style: AppTypography.textXxsMedium.copyWith(
              color: PlayerProfileShareImageCard._textLo,
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
                color: PlayerProfileShareImageCard._textMid,
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
