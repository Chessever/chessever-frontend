import 'package:chessever2/screens/group_event/widget/filter_popup/group_event_filter_provider.dart'
    show EventFormat;
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/widgets/space_glyphs.dart';
import 'package:chessever2/screens/my_space/widgets/space_tile_content.dart'
    show spaceText;
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/game_filter/rating_tier_filter.dart';
import 'package:chessever2/widgets/hub_tile.dart' show kHubTileInk;
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The time controls a smart event can hold, slow to fast: the builder's
/// order and its glyphs.
const List<EventFormat> _kFormats = [
  EventFormat.standard,
  EventFormat.rapid,
  EventFormat.blitz,
];

/// A smart event (the games of every current event that matches a set of
/// criteria) drawn in the Events list's language: the phone event card's
/// surface, radius, padding and lines, so it sits among events as one of
/// them. Where an event keeps its photo, a neutral plate shows the
/// combination the way the builder draws it: the level (its code over its
/// floor, "GM" over "2500+") and the chosen time controls' glyphs under it;
/// with neither picked, the stacked-boards glyph. No hue anywhere: the
/// builder's own monochrome vocabulary.
///
/// Title, then "3 events · Ø 2728", then the builder's one-line summary of
/// the criteria, or the event card's LIVE while a member event is live.
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
    this.spaceDraft,
    this.quiet = false,
    this.formatsAndStates = const <String>{},
    this.summary,
    this.live = false,
    super.key,
  });

  /// Short tier label for the headline, e.g. `GM`, `IM`, or `2500+`.
  final String tierLabel;

  /// The applied game-average floor; 0 when no level is picked.
  final int minElo;

  /// Number of current events folded into this smart event.
  final int liveCount;

  /// Average rating across the gathered events (0 hides the Ø figure).
  final int avgElo;

  final String titleSuffix;

  /// The saved caption ("From your 2500+ filter"): the third line when no
  /// [summary] is given.
  final String? caption;
  final String countSingular;
  final String countPlural;

  /// Not drawn. Smart events used to wear a per-event hue; they now share
  /// the builder's neutral look everywhere. Kept so callers still compile.
  final Color accentColor;
  final VoidCallback? onTap;

  /// When set, a long press lifts the card into the shared focus menu with
  /// Open and the My Space row for this smart event (see
  /// `smartEventSpaceDraft`).
  final SpaceShortcut? spaceDraft;

  /// Kept for callers that asked for a still card; every card is still now.
  final bool quiet;

  /// The criteria's raw formats and statuses (`standard`, `rapid`, `blitz`,
  /// `live`, `completed`): the time-control glyphs on the plate.
  final Set<String> formatsAndStates;

  /// The builder's one-line account of the criteria ("Game average 2500+,
  /// classical, live events"). Falls back to [caption].
  final String? summary;

  /// Whether one of the gathered events is live now: the third line reads
  /// LIVE, as an event card's does.
  final bool live;

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

    final draft = spaceDraft;
    return TappableScale(
        onTap: () {
          HapticFeedbackService.cardTap();
          onTap!();
        },
        child:
            draft == null
                ? card
                : Consumer(
                  child: card,
                  builder:
                      (context, ref, child) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onLongPress:
                            () => showLibraryContextMenu(
                              context: context,
                              previewBuilder: _buildCard,
                              onPreviewTap: onTap,
                              actions: [
                                LibraryMenuAction(
                                  icon: Icons.open_in_new_rounded,
                                  label: 'Open smart event',
                                  onSelected: onTap!,
                                ),
                                spaceMenuAction(
                                  context: context,
                                  ref: ref,
                                  draft: draft,
                                ),
                              ],
                            ),
                        child: child,
                      ),
                ),
    );
  }

  Widget _buildCard(BuildContext context) {
    final colors = context.colors;
    final light = context.isLightTheme;
    final imageW = _imageWidth(context);
    final imageH = imageW * 4 / 5;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8.br),
        // The event card's own treatment: paper lifts with a hairline and
        // a tight shadow, dark stands on its tone.
        border:
            light
                ? Border.all(color: colors.divider.withValues(alpha: 0.4))
                : null,
        boxShadow:
            light
                ? [
                  BoxShadow(
                    color: colors.shadow,
                    blurRadius: 8,
                    offset: const Offset(0, 1),
                  ),
                ]
                : null,
      ),
      padding: EdgeInsets.all(6.sp),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: imageH),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SmartEventPlate(
              width: imageW,
              height: imageH,
              minElo: minElo,
              formatsAndStates: formatsAndStates,
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$tierLabel $titleSuffix'.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.textSmMedium.copyWith(
                      color: colors.textPrimary,
                      fontSize: 14.f,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  _MetaLine(
                    count: liveCount,
                    avgElo: avgElo,
                    countSingular: countSingular,
                    countPlural: countPlural,
                  ),
                  _ThirdLine(
                    live: live,
                    text: summary ?? caption ?? _fallbackCaption,
                  ),
                ],
              ),
            ),
            SizedBox(width: 4.w),
            Icon(
              Icons.chevron_right_rounded,
              size: 20.ic,
              color: colors.iconSecondary,
            ),
            SizedBox(width: 4.w),
          ],
        ),
      ),
    );
  }

  String get _fallbackCaption =>
      minElo > 0 ? 'Every game averaging $minElo+' : 'Games from your filters';
}

/// "3 events · Ø 2728", in the event card's meta ink with its dot.
class _MetaLine extends StatelessWidget {
  const _MetaLine({
    required this.count,
    required this.avgElo,
    required this.countSingular,
    required this.countPlural,
  });

  final int count;
  final int avgElo;
  final String countSingular;
  final String countPlural;

  @override
  Widget build(BuildContext context) {
    final muted = context.colors.textPrimaryMuted;
    return Text.rich(
      TextSpan(
        style: AppTypography.textXsMedium.copyWith(
          color: muted,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        children: [
          TextSpan(text: count == 1 ? '1 $countSingular' : '$count $countPlural'),
          if (avgElo > 0) ...[
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                margin: EdgeInsets.symmetric(horizontal: 4.w),
                height: 6.h,
                width: 6.w,
                decoration: BoxDecoration(shape: BoxShape.circle, color: muted),
              ),
            ),
            TextSpan(text: 'Ø $avgElo'),
          ],
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// The card's third line: the event card's LIVE while a member event is
/// live, else what the smart event gathers, in the builder's words.
class _ThirdLine extends StatelessWidget {
  const _ThirdLine({required this.live, required this.text});

  final bool live;
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = AppTypography.textXxsMedium.copyWith(
      fontSize: 11.f,
      letterSpacing: 0.1,
      color: context.colors.textSecondary,
    );
    return Padding(
      padding: EdgeInsets.only(top: 3.h),
      child: Text(
        live ? 'LIVE' : text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style:
            live
                ? style.copyWith(
                  color: context.colors.accentText,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                )
                : style,
      ),
    );
  }
}

/// The smart event's plate: a neutral panel (the hub tiles' ink in dark, the
/// recessed surface on paper) with a hairline in its own colour, holding the
/// combination as the builder draws it: the level ("GM" over "2500+", or
/// "2700+" alone off the tiers) and under it the chosen time controls'
/// glyphs. With neither, the stacked-boards glyph.
class SmartEventPlate extends StatelessWidget {
  const SmartEventPlate({
    super.key,
    required this.width,
    required this.height,
    required this.minElo,
    this.formatsAndStates = const <String>{},
  });

  final double width;
  final double height;
  final int minElo;
  final Set<String> formatsAndStates;

  /// The level track's code for [minElo] ("GM"), when it is one of its tiers.
  static String? levelCode(int minElo) {
    for (final tier in RatingTierFilter.tiers) {
      if (tier.minRating == minElo) return tier.label;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final light = context.isLightTheme;
    final plate = light ? colors.surfaceRecessed : kHubTileInk;
    final edge = (light ? Colors.black : Colors.white).withValues(alpha: 0.06);
    final glyphs = [
      for (final f in _kFormats)
        if (formatsAndStates.contains(f.name))
          if (TimeControlGlyph.assetForLabel(f.name) case final asset?) asset,
    ];
    final level = minElo > 0;
    final code = level ? levelCode(minElo) : null;
    final glyphSide = 18.w;

    final Widget content;
    if (!level && glyphs.isEmpty) {
      content = SpaceGlyph(
        SpaceGlyphKind.boards,
        size: 40.w,
        ink: colors.iconPrimary,
        background: plate,
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (level) ...[
            if (code != null)
              Text(
                code,
                maxLines: 1,
                style: spaceText(
                  context,
                  size: 15,
                  line: 20,
                  weight: FontWeight.w700,
                ),
              ),
            Text(
              '$minElo+',
              maxLines: 1,
              style:
                  code != null
                      ? spaceText(
                        context,
                        size: 12,
                        line: 16,
                        color: colors.textSecondary,
                        tabular: true,
                      )
                      : spaceText(
                        context,
                        size: 15,
                        line: 20,
                        weight: FontWeight.w700,
                        tabular: true,
                      ),
            ),
          ],
          if (level && glyphs.isNotEmpty) SizedBox(height: 6.w),
          if (glyphs.isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (i, asset) in glyphs.indexed) ...[
                  if (i > 0) SizedBox(width: 6.w),
                  TimeControlGlyph(asset, size: glyphSide),
                ],
              ],
            ),
        ],
      );
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: plate,
        borderRadius: BorderRadius.circular(6.br),
        border: Border.all(color: edge),
      ),
      child: Center(
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.15,
          child: FittedBox(fit: BoxFit.scaleDown, child: content),
        ),
      ),
    );
  }
}
