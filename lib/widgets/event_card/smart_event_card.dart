import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

Color smartEventAccentColor(String stableKey) {
  const palette = <Color>[
    kPrimaryColor,
    Color(0xFF38BDF8),
    Color(0xFFA3E635),
    Color(0xFFF97316),
    Color(0xFFF472B6),
    Color(0xFF22C55E),
  ];
  final hash = stableKey.codeUnits.fold<int>(
    0,
    (value, unit) => (value * 31 + unit) & 0x7fffffff,
  );
  return palette[hash % palette.length];
}

/// The "Convergence" smart-event card.
///
/// A synthetic event that gathers the most interesting live games from every
/// ongoing broadcast into one place — so the user never has to hop between
/// tournaments. It mirrors the real [EventCard] silhouette (same size, same
/// image-left + title + meta anatomy) so it sits natively in the For-You feed,
/// but the rectangle is fractured into primary-tinted facets and self-brands as
/// SMART so it reads instantly as the special, filter-driven card.
///
/// It is shown only when an ELO/tier filter is applied, pinned top-most.
class SmartEventCard extends StatelessWidget {
  const SmartEventCard({
    required this.tierLabel,
    required this.minElo,
    required this.liveCount,
    required this.avgElo,
    this.titleSuffix = 'Live Games',
    this.caption,
    this.countSingular = 'live event',
    this.countPlural = 'live events',
    this.accentColor = kPrimaryColor,
    this.onTap,
    super.key,
  });

  /// Short tier label for the headline, e.g. `GM`, `IM`, or `2500+`.
  final String tierLabel;

  /// The applied ELO floor (drives the "from your … filter" caption).
  final int minElo;

  /// Number of currently live/ongoing events folded into this smart event.
  final int liveCount;

  /// Average rating across the gathered events (0 hides the Ø chip).
  final int avgElo;

  final String titleSuffix;
  final String? caption;
  final String countSingular;
  final String countPlural;
  final Color accentColor;
  final VoidCallback? onTap;

  static double _imageWidth(BuildContext context) {
    double w = 108.w;
    if (MediaQuery.sizeOf(context).width < 360) {
      w = w.clamp(70.0, 90.0);
    }
    return w;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final card = _buildCard(context, reduceMotion);

    if (onTap == null) return _entrance(card, reduceMotion);

    return _entrance(
      TappableScale(
        onTap: () {
          HapticFeedbackService.cardTap();
          onTap!();
        },
        child: card,
      ),
      reduceMotion,
    );
  }

  // One-shot reveal so the card lands gracefully when the filter is applied.
  Widget _entrance(Widget child, bool reduceMotion) {
    if (reduceMotion) return child;
    return child
        .animate()
        .fadeIn(duration: 320.ms, curve: Curves.easeOutQuart)
        .slideY(
          begin: -0.06,
          end: 0,
          duration: 360.ms,
          curve: Curves.easeOutQuart,
        )
        .scaleXY(
          begin: 0.985,
          end: 1,
          duration: 360.ms,
          curve: Curves.easeOutQuart,
        );
  }

  Widget _buildCard(BuildContext context, bool reduceMotion) {
    final imageW = _imageWidth(context);
    final imageH = imageW * 4 / 5;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8.br),
        // A primary-tinted border + soft primary glow distinguishes the smart
        // card from the plain divider/shadow of a normal event card.
        border: Border.all(
          color: accentColor.withValues(
            alpha: context.isLightTheme ? 0.45 : 0.35,
          ),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.18),
            blurRadius: 16,
            spreadRadius: -4,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Faceted "convergence" background — the rectangle split into pieces.
          Positioned.fill(
            child: CustomPaint(
              painter: _FacetBackgroundPainter(
                isLight: context.isLightTheme,
                accentColor: accentColor,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(6.sp),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: imageH),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _MosaicEmblem(
                    width: imageW,
                    height: imageH,
                    reduceMotion: reduceMotion,
                    accentColor: accentColor,
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TitleRow(
                          tierLabel: tierLabel,
                          titleSuffix: titleSuffix,
                          accentColor: accentColor,
                        ),
                        SizedBox(height: 4.h),
                        _MetaLine(
                          liveCount: liveCount,
                          avgElo: avgElo,
                          countSingular: countSingular,
                          countPlural: countPlural,
                        ),
                        SizedBox(height: 3.h),
                        _FilterCaption(
                          minElo: minElo,
                          caption: caption,
                          accentColor: accentColor,
                          reduceMotion: reduceMotion,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 2.w),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: accentColor.withValues(alpha: 0.85),
                    size: 16.sp,
                    weight: 700,
                  ),
                  SizedBox(width: 2.w),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Headline row: smart name + the SMART brand pill.
class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.tierLabel,
    required this.titleSuffix,
    required this.accentColor,
  });

  final String tierLabel;
  final String titleSuffix;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            '$tierLabel · $titleSuffix',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.textSmMedium.copyWith(
              color: context.colors.textPrimary,
              fontSize: 14.sp,
              height: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        SizedBox(width: 6.w),
        _SmartPill(accentColor: accentColor),
      ],
    );
  }
}

/// Solid-primary SMART badge with a spark glyph.
class _SmartPill extends StatelessWidget {
  const _SmartPill({required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: accentColor,
        borderRadius: BorderRadius.circular(5.br),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 10.sp, color: kBlackColor),
          SizedBox(width: 3.w),
          Text(
            'SMART',
            style: AppTypography.textXxsBold.copyWith(
              color: kBlackColor,
              fontSize: 9.sp,
              letterSpacing: 0.6,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Meta line mirroring the real card's `count · Ø elo` rhythm.
class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.liveCount,
    required this.avgElo,
    required this.countSingular,
    required this.countPlural,
  });

  final int liveCount;
  final int avgElo;
  final String countSingular;
  final String countPlural;

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.textPrimaryMuted;
    final spans = <InlineSpan>[
      TextSpan(
        text: liveCount == 1 ? '1 $countSingular' : '$liveCount $countPlural',
      ),
    ];
    if (avgElo > 0) {
      spans.add(_dot(muted));
      spans.add(TextSpan(text: 'Ø $avgElo'));
    }

    return Text.rich(
      TextSpan(
        style: AppTypography.textXsMedium.copyWith(color: muted),
        children: spans,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  InlineSpan _dot(Color color) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 4.w),
        height: 6.h,
        width: 6.w,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

/// Third line: a pulsing live dot + the filter-bound caption, so it is obvious
/// this card only exists because a filter is applied.
class _FilterCaption extends StatelessWidget {
  const _FilterCaption({
    required this.minElo,
    required this.caption,
    required this.accentColor,
    required this.reduceMotion,
  });

  final int minElo;
  final String? caption;
  final Color accentColor;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      height: 6.h,
      width: 6.w,
      decoration: BoxDecoration(shape: BoxShape.circle, color: accentColor),
    );

    return Row(
      children: [
        reduceMotion
            ? dot
            : dot
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fadeIn(duration: 700.ms, curve: Curves.easeOut)
                .scaleXY(begin: 0.7, end: 1.15, duration: 700.ms),
        SizedBox(width: 5.w),
        Flexible(
          child: Text(
            caption ?? 'Gathered from your $minElo+ filter',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.textXxsMedium.copyWith(
              color: accentColor.withValues(alpha: 0.95),
              fontSize: 11.sp,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ],
    );
  }
}

/// The left tile: a faceted mosaic emblem with a "stacked events" hint and a
/// central spark — the visual metaphor for many broadcasts folding into one.
class _MosaicEmblem extends StatelessWidget {
  const _MosaicEmblem({
    required this.width,
    required this.height,
    required this.reduceMotion,
    required this.accentColor,
  });

  final double width;
  final double height;
  final bool reduceMotion;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final spark = Icon(Icons.auto_awesome, size: 22.sp, color: Colors.white);

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // "Stacked events" hint: two faint offset outlines peeking behind the
          // tile, reading as a pile of tournaments collapsed into one.
          Positioned(top: -3, right: -3, child: _stackGhost(width, height)),
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6.br),
              child: CustomPaint(
                painter: _MosaicTilePainter(accentColor: accentColor),
                child: Center(
                  child:
                      reduceMotion
                          ? spark
                          : spark
                              .animate(onPlay: (c) => c.repeat(reverse: true))
                              .fadeIn(duration: 1200.ms)
                              .then()
                              .shimmer(
                                duration: 1600.ms,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stackGhost(double w, double h) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6.br),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
    );
  }
}

/// Paints the card's fractured "convergence" background: slanted facets tinted
/// with the primary color at stepped alphas, separated by hairline seams.
class _FacetBackgroundPainter extends CustomPainter {
  _FacetBackgroundPainter({required this.isLight, required this.accentColor});

  final bool isLight;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Slanted band cut points: top-edge x → bottom-edge x. Each band is a
    // quadrilateral; alphas step up toward the trailing edge for directional
    // light, so the rectangle reads as separate shards converging.
    final cuts = <List<double>>[
      [0.0, 0.0, 0.30, 0.14, 0.05],
      [0.30, 0.14, 0.55, 0.40, 0.085],
      [0.55, 0.40, 0.80, 0.66, 0.055],
      [0.80, 0.66, 1.0, 1.0, 0.11],
    ];

    for (final c in cuts) {
      final path =
          Path()
            ..moveTo(c[0] * w, 0)
            ..lineTo(c[2] * w, 0)
            ..lineTo(c[3] * w, h)
            ..lineTo(c[1] * w, h)
            ..close();
      canvas.drawPath(
        path,
        Paint()..color = accentColor.withValues(alpha: c[4]),
      );
    }

    // Brighter top-right corner facet for a premium catch-light.
    final corner =
        Path()
          ..moveTo(0.62 * w, 0)
          ..lineTo(w, 0)
          ..lineTo(w, 0.45 * h)
          ..close();
    canvas.drawPath(
      corner,
      Paint()..color = accentColor.withValues(alpha: 0.10),
    );

    // Hairline seams along the band boundaries.
    final seam =
        Paint()
          ..color = accentColor.withValues(alpha: isLight ? 0.16 : 0.12)
          ..strokeWidth = 1
          ..style = PaintingStyle.stroke;
    for (final c in cuts.sublist(1)) {
      canvas.drawLine(Offset(c[0] * w, 0), Offset(c[1] * w, h), seam);
    }
  }

  @override
  bool shouldRepaint(covariant _FacetBackgroundPainter oldDelegate) =>
      oldDelegate.isLight != isLight || oldDelegate.accentColor != accentColor;
}

/// Paints the left emblem tile: a dark base broken into a diamond mosaic of
/// primary facets — a stylized, abstracted "board of boards".
class _MosaicTilePainter extends CustomPainter {
  const _MosaicTilePainter({required this.accentColor});

  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Dark recessed base.
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF12202B),
    );

    // Diamond mosaic: a 4×3 lattice of diamonds, alternating primary alphas.
    const cols = 4;
    const rows = 3;
    final cw = w / cols;
    final ch = h / rows;
    for (var r = 0; r < rows; r++) {
      for (var col = 0; col < cols; col++) {
        final cx = (col + 0.5) * cw;
        final cy = (r + 0.5) * ch;
        final alpha =
            ((col + r) % 3 == 0)
                ? 0.30
                : ((col + r) % 3 == 1)
                ? 0.16
                : 0.07;
        final diamond =
            Path()
              ..moveTo(cx, cy - ch * 0.5)
              ..lineTo(cx + cw * 0.5, cy)
              ..lineTo(cx, cy + ch * 0.5)
              ..lineTo(cx - cw * 0.5, cy)
              ..close();
        canvas.drawPath(
          diamond,
          Paint()..color = accentColor.withValues(alpha: alpha),
        );
      }
    }

    // Soft top-left catch-light.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: 0.10), Colors.transparent],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _MosaicTilePainter oldDelegate) =>
      oldDelegate.accentColor != accentColor;
}
