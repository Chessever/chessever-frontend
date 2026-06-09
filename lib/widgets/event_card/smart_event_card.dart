import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:flutter/material.dart';

Color smartEventAccentColor(String stableKey) {
  return kPrimaryColor;
}

/// Generated level-games card.
///
/// Gathers current games from active broadcasts that match the user's filter,
/// while keeping the For You surface close to the regular event-card anatomy.
class SmartEventCard extends StatelessWidget {
  const SmartEventCard({
    required this.tierLabel,
    required this.minElo,
    required this.liveCount,
    required this.avgElo,
    this.titleSuffix = 'Games',
    this.caption,
    this.countSingular = 'event',
    this.countPlural = 'events',
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
    final card = _buildCard(context);

    if (onTap == null) return card;

    return TappableScale(
      onTap: () {
        HapticFeedbackService.cardTap();
        onTap!();
      },
      child: card,
    );
  }

  Widget _buildCard(BuildContext context) {
    final imageW = _imageWidth(context);
    final imageH = imageW * 4 / 5;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(8.br),
        border:
            context.isLightTheme
                ? Border.all(
                  color: context.colors.divider.withValues(alpha: 0.4),
                )
                : Border.all(
                  color: context.colors.divider.withValues(alpha: 0.4),
                ),
        boxShadow:
            context.isLightTheme
                ? [
                  BoxShadow(
                    color: context.colors.shadow,
                    blurRadius: 8,
                    offset: const Offset(0, 1),
                  ),
                ]
                : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(6.sp),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: imageH),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _LevelEmblem(
                tierLabel: tierLabel,
                width: imageW,
                height: imageH,
                accentColor: accentColor,
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TitleRow(tierLabel: tierLabel, titleSuffix: titleSuffix),
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
                    ),
                  ],
                ),
              ),
              SizedBox(width: 2.w),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: context.colors.textPrimaryMuted,
                size: 16.sp,
                weight: 700,
              ),
              SizedBox(width: 2.w),
            ],
          ),
        ),
      ),
    );
  }
}

/// Headline row: level name.
class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.tierLabel, required this.titleSuffix});

  final String tierLabel;
  final String titleSuffix;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            '$tierLabel $titleSuffix',
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
      ],
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

/// Third line: compact filter context for why this generated card exists.
class _FilterCaption extends StatelessWidget {
  const _FilterCaption({
    required this.minElo,
    required this.caption,
    required this.accentColor,
  });

  final int minElo;
  final String? caption;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      height: 6.h,
      width: 6.w,
      decoration: BoxDecoration(shape: BoxShape.circle, color: accentColor),
    );

    return Row(
      children: [
        dot,
        SizedBox(width: 5.w),
        Flexible(
          child: Text(
            caption ?? 'From your $minElo+ filter',
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

/// The left tile: a restrained level emblem with large, readable letters.
class _LevelEmblem extends StatelessWidget {
  const _LevelEmblem({
    required this.tierLabel,
    required this.width,
    required this.height,
    required this.accentColor,
  });

  final String tierLabel;
  final double width;
  final double height;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colors.surfaceRecessed,
        borderRadius: BorderRadius.circular(6.br),
        border: Border.all(
          color: context.colors.divider.withValues(alpha: 0.5),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 3.w,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(6.br),
                ),
              ),
            ),
          ),
          Center(
            child: Text(
              tierLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.textMdBold.copyWith(
                color: context.colors.textPrimary,
                fontSize: 28.sp,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
