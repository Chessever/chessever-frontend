import 'dart:math' as math;

import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/screens/chessboard/models/like_tag.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/widgets/chess_progress_bar.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/chess_title_utils.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/png_asset.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/string_utils.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/backfilled_federation_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/widgets/time_control_glyph.dart';

/// Unified game card for library screens.
/// Uses the same design as GamebaseSearchGameCard for consistency.
class LibraryGameCard extends HookConsumerWidget {
  const LibraryGameCard({
    super.key,
    required this.game,
    required this.onTap,
    this.onLongPress,
    this.eventName,
    this.eco,
    this.date,
    this.showRound = true,
    this.tags = const <String>[],
    this.reserveTagSlot = false,
    this.tagCounts,
    this.trailing,
  });

  final GamesTourModel game;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? eventName;
  final String? eco;
  final DateTime? date;
  final bool showRound;
  final List<String> tags;

  /// When true, the tag row keeps its height even with no tags, so every card
  /// in a database list stays the same size. Used by saved-analysis lists
  /// (My Database, My Likes); left false for gamebase/import cards.
  final bool reserveTagSlot;

  /// Optional tag-frequency map (tag label → total games carrying that tag in
  /// the enclosing collection). When provided, the chips render sorted by
  /// count desc — most-used tag leftmost — so the user's dominant categories
  /// surface first. Tie-break follows canonical [kLikeTags] order.
  final Map<String, int>? tagCounts;

  /// A control (e.g. a [CardMoreButton] whose glyph is [trailingGlyphSize])
  /// drawn at the end of the tag slot's last line, in space the footer
  /// already leaves empty. It adds no size and moves nothing: the card lays
  /// out exactly as it does without it. On a card whose chips reach that
  /// corner, or with no tag slot at all, it is left out, and the card's
  /// long-press stays the way in. Hosts pass it with [reserveTagSlot].
  final Widget? trailing;

  /// The [trailing] control's glyph: the size of the footer's time-control
  /// coin, the only other mark on that line.
  static double get trailingGlyphSize => 14.sp;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rawName = eventName ?? game.tourSlug ?? game.tourId;

    // useMemoized: the event-name cleanup (two replaceAll passes + slug→title)
    // is a pure function of rawName, keyed on a value-stable String — so it's
    // computed once and reused across scroll-driven rebuilds / live updates
    // instead of re-running every frame this card rebuilds.
    final displayEventName = useMemoized(() {
      final cleanedName =
          rawName.replaceAll('-', ' ').replaceAll('_', ' ').trim();
      final isGeneric =
          cleanedName.isEmpty ||
          cleanedName.toLowerCase() == 'gamebase' ||
          cleanedName.toLowerCase() == 'search' ||
          cleanedName.toLowerCase() == 'library';
      return isGeneric ? 'Library' : StringUtils.slugToTitle(rawName);
    }, [rawName]);

    final timeControlIcon = _getTimeControlIcon(game, displayEventName);
    final displayEco = eco ?? game.eco ?? ''; // Only ECO code, never round info
    final displayDate = _formatDate(date ?? game.lastMoveTime);

    // useMemoized: tag normalize + count-desc sort (builds a canonical-order
    // map then sorts) recomputed only when the tag list/counts reference
    // changes — no resort when the enclosing list re-renders this card with
    // the same inputs.
    final visibleTags = useMemoized(() {
      final result = normalizeLikeTagLabels(tags).toList();
      final counts = tagCounts;
      if (counts != null && result.length > 1) {
        final canonicalOrder = <String, int>{
          for (var i = 0; i < kLikeTags.length; i++) kLikeTags[i].label: i,
        };
        result.sort((a, b) {
          final cmp = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
          if (cmp != 0) return cmp;
          final ia = canonicalOrder[a] ?? kLikeTags.length;
          final ib = canonicalOrder[b] ?? kLikeTags.length;
          return ia.compareTo(ib);
        });
      }
      return result;
    }, [tags, tagCounts]);

    final footerPadding = EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h);

    return TappableScale(
      onTap: () {
        HapticFeedbackService.cardTap();
        onTap();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress:
            onLongPress != null
                ? () {
                  HapticFeedbackService.buttonPress();
                  onLongPress!();
                }
                : null,
        child: Container(
          decoration: BoxDecoration(
            color: context.isLightTheme
                ? context.colors.surface
                : context.colors.surfaceRecessed,
            borderRadius: BorderRadius.circular(12.br),
          ),
          child: Column(
            children: [
              // Top section - light background with player info
              Container(
                padding: EdgeInsets.fromLTRB(14.w, 10.h, 14.w, 10.h),
                decoration: BoxDecoration(
                  color: context.isLightTheme
                      ? context.colors.surfaceRecessed
                      : null,
                  gradient: context.isLightTheme
                      ? null
                      : const LinearGradient(
                          begin: Alignment(-1.0, 0.26),
                          end: Alignment(1.0, -0.26),
                          colors: [Color(0xFFDDDDE0), Color(0xFFADAEB3)],
                        ),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(12.br),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _PlayerInfo(
                        name: game.whitePlayer.name,
                        title: ChessTitleUtils.normalize(
                          game.whitePlayer.title,
                        ),
                        rating:
                            game.whitePlayer.rating > 0
                                ? game.whitePlayer.displayRating
                                : '',
                        federation: game.whitePlayer.countryCode,
                        fideId: game.whitePlayer.fideId,
                        alignment: CrossAxisAlignment.start,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10.w),
                      child: _ResultOrEvalBar(game: game, ref: ref),
                    ),
                    Expanded(
                      child: _PlayerInfo(
                        name: game.blackPlayer.name,
                        title: ChessTitleUtils.normalize(
                          game.blackPlayer.title,
                        ),
                        rating:
                            game.blackPlayer.rating > 0
                                ? game.blackPlayer.displayRating
                                : '',
                        federation: game.blackPlayer.countryCode,
                        fideId: game.blackPlayer.fideId,
                        alignment: CrossAxisAlignment.end,
                      ),
                    ),
                  ],
                ),
              ),
              // Bottom section - dark background with event info
              Container(
                padding: footerPadding,
                decoration: BoxDecoration(
                  color: context.colors.surface,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(12.br),
                  ),
                ),
                child: _withTrailing(
                  padding: footerPadding,
                  hasTagSlot: reserveTagSlot || visibleTags.isNotEmpty,
                  footer: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Left: time control icon + event name
                          // Paper swaps in the ink twins of the white coins.
                          Image.asset(
                            TimeControlGlyph.resolve(
                              timeControlIcon,
                              light: context.isLightTheme,
                            ),
                            width: 14.sp,
                            height: 14.sp,
                          ),
                          SizedBox(width: 4.w),
                          Expanded(
                            child: Text(
                              displayEventName,
                              style: AppTypography.textXsRegular.copyWith(
                                color: context.colors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // ECO code (only if available)
                          if (showRound && displayEco.isNotEmpty) ...[
                            SizedBox(width: 8.w),
                            Text(
                              displayEco,
                              style: AppTypography.textXsRegular.copyWith(
                                color: context.colors.textPrimary,
                              ),
                            ),
                          ],
                          // Date (always right-most)
                          if (displayDate.isNotEmpty) ...[
                            SizedBox(width: 8.w),
                            Text(
                              displayDate,
                              style: AppTypography.textXsRegular.copyWith(
                                color: context.colors.textPrimary,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (reserveTagSlot || visibleTags.isNotEmpty) ...[
                        SizedBox(height: 6.h),
                        if (visibleTags.isNotEmpty)
                          _LibraryTagChips(tags: visibleTags)
                        else
                          // No tags: keep a single chip-row of height so cards
                          // stay uniformly sized across the list.
                          SizedBox(height: 22.h),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [footer] as it is, with [trailing] laid over the end of its tag slot.
  /// With no tag slot there is no empty room for it, so it is left out.
  Widget _withTrailing({
    required Widget footer,
    required EdgeInsets padding,
    required bool hasTagSlot,
  }) {
    final end = trailing;
    if (end == null || !hasTagSlot) return footer;
    return _FooterTrailing(
      glyph: trailingGlyphSize,
      endInset: padding.right,
      bottomInset: padding.bottom,
      // The Wrap's run spacing, the narrower of the gaps above a last line.
      lineGap: 5.h,
      footer: footer,
      trailing: end,
    );
  }

  /// Get time control icon from game data
  /// Primary source: timeControl field from group_broadcasts table (via tours join)
  /// Fallback: event name keywords (e.g., "Tata Steel Blitz")
  /// NOTE: Do NOT use remaining clock time - it's unreliable (a classical game
  /// with 5 minutes left would be wrongly classified as blitz)
  String _getTimeControlIcon(GamesTourModel game, String eventName) {
    // Primary: use the actual time_control from group_broadcasts
    if (game.timeControl != null && game.timeControl!.isNotEmpty) {
      switch (game.timeControl!.toLowerCase()) {
        case 'standard':
        case 'classical':
          return PngAsset.classicalIcon;
        case 'rapid':
          return PngAsset.rapidIcon;
        case 'blitz':
        case 'bullet':
          return PngAsset.blitzIcon;
      }
    }

    // Fallback: check event name for keywords
    final event = eventName.toLowerCase();
    if (event.contains('blitz') || event.contains('bullet')) {
      return PngAsset.blitzIcon;
    }
    if (event.contains('titled')) return PngAsset.blitzIcon;
    if (event.contains('speed chess')) return PngAsset.blitzIcon;
    if (event.contains('rapid')) return PngAsset.rapidIcon;

    // Default to classical for standard/unknown events
    return PngAsset.classicalIcon;
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

/// Readable tag presentation for library cards.
///
/// Tags are sorted before this widget, then rendered as normal chips in a
/// wrapping row so every persisted label remains visible instead of collapsing
/// secondary tags into unlabeled slivers.
class _LibraryTagChips extends StatelessWidget {
  const _LibraryTagChips({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 5.w,
      runSpacing: 5.h,
      children: [for (final tag in tags) _LibraryTagChip(label: tag)],
    );
  }
}

class _LibraryTagChip extends StatelessWidget {
  const _LibraryTagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tag = likeTagByLabel(label);
    final color = tag?.color ?? context.colors.textSecondary;

    return Container(
      constraints: BoxConstraints(maxWidth: 160.w),
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999.br),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.textXsMedium.copyWith(
          color: context.colors.textPrimary,
          fontSize: 10.sp,
        ),
      ),
    );
  }
}

/// The trailing control's target, the platform minimum (as [CardMoreButton]).
const double _kTrailingTarget = 44;

/// Lays a card's [LibraryGameCard.trailing] over the end of the footer's
/// last line (the tag slot), in space the footer already leaves empty.
///
/// The footer lays out exactly as it would alone: this adds no size and
/// moves nothing. The control's target is a [_kTrailingTarget]-wide band at
/// the footer's right edge, from just above that line to the card's bottom.
/// On a card whose last line of chips reaches into that band the control is
/// left out altogether (not painted, hit or announced), so it never sits on
/// a chip.
class _FooterTrailing extends MultiChildRenderObjectWidget {
  _FooterTrailing({
    required Widget footer,
    required Widget trailing,
    required this.glyph,
    required this.endInset,
    required this.bottomInset,
    required this.lineGap,
  }) : super(children: [footer, trailing]);

  /// The control's glyph size.
  final double glyph;

  /// The footer's padding right of and below the footer column. The target
  /// and the press disc reach into it, never past the card's edge.
  final double endInset;
  final double bottomInset;

  /// Empty space above the last line that the target may take.
  final double lineGap;

  @override
  _RenderFooterTrailing createRenderObject(BuildContext context) =>
      _RenderFooterTrailing(glyph, endInset, bottomInset, lineGap);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderFooterTrailing renderObject,
  ) {
    renderObject
      ..glyph = glyph
      ..endInset = endInset
      ..bottomInset = bottomInset
      ..lineGap = lineGap;
  }
}

class _FooterTrailingParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderFooterTrailing extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FooterTrailingParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FooterTrailingParentData> {
  _RenderFooterTrailing(
    this._glyph,
    this._endInset,
    this._bottomInset,
    this._lineGap,
  );

  double _glyph;
  set glyph(double value) {
    if (value == _glyph) return;
    _glyph = value;
    markNeedsLayout();
  }

  double _endInset;
  set endInset(double value) {
    if (value == _endInset) return;
    _endInset = value;
    markNeedsLayout();
  }

  double _bottomInset;
  set bottomInset(double value) {
    if (value == _bottomInset) return;
    _bottomInset = value;
    markNeedsLayout();
  }

  double _lineGap;
  set lineGap(double value) {
    if (value == _lineGap) return;
    _lineGap = value;
    markNeedsLayout();
  }

  /// Whether this card has room for the control.
  bool _shows = false;

  /// Where a press lands on the control, in this box's coordinates. It
  /// reaches into the footer's padding, past this box.
  Rect _target = Rect.zero;

  RenderBox get _footer => firstChild!;
  RenderBox get _trailing => lastChild!;

  Offset _offsetOf(RenderBox child) =>
      (child.parentData! as _FooterTrailingParentData).offset;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FooterTrailingParentData) {
      child.parentData = _FooterTrailingParentData();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _footer.getMinIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _footer.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _footer.getMinIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _footer.getMaxIntrinsicHeight(width);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _footer.getDistanceToActualBaseline(baseline);

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _footer.getDryLayout(constraints);

  /// The footer's last line in this box's coordinates, as wide as what sits
  /// on it: the last run of chips, or the reserved empty slot (no width).
  /// The tag slot is the footer column's last child.
  static Rect? _lastLine(RenderBox footer) {
    if (footer is! RenderFlex) return null;
    final slot = footer.lastChild;
    if (slot == null || !slot.hasSize) return null;
    final at = (slot.parentData! as FlexParentData).offset;
    if (slot is RenderWrap && slot.firstChild != null) {
      Rect? line;
      for (var chip = slot.firstChild; chip != null;) {
        final rect = (chip.parentData! as WrapParentData).offset & chip.size;
        // A chip lower than the line so far starts the next run.
        line = line == null || rect.top > line.top + 0.5
            ? rect
            : line.expandToInclude(rect);
        chip = slot.childAfter(chip);
      }
      return line!.shift(at);
    }
    return Rect.fromLTWH(at.dx, at.dy, 0, slot.size.height);
  }

  @override
  void performLayout() {
    _footer.layout(constraints, parentUsesSize: true);
    size = _footer.size;
    // The dots end on the footer's text edge, so the press disc can reach
    // into the padding past them; it stops a quarter of it short of the
    // card's edge. A line is never less than 22 tall, which leaves the disc
    // more room below than that.
    final disc = 2 * (_endInset * 0.75 + _glyph / 3);
    _trailing.layout(BoxConstraints.tight(Size.square(disc)));
  }

  /// Puts the control on the footer's last line as it is laid out now. Done
  /// at paint rather than in [performLayout], which may not read the chips
  /// below the footer column; paint runs after any layout beneath this box.
  void _place() {
    final line = _lastLine(_footer);
    if (line == null) {
      _setShows(false);
      return;
    }
    final trailing = _trailing;
    // Centred on the line, with the three dots (the middle two thirds of
    // the glyph) ending on the footer's text edge, level with the date.
    final center = Offset(size.width - _glyph / 3, line.center.dy);
    (trailing.parentData! as _FooterTrailingParentData).offset =
        center - trailing.size.center(Offset.zero);

    final right = size.width + _endInset;
    _target = Rect.fromLTRB(
      right - _kTrailingTarget,
      math.max(0, line.top - _lineGap),
      right,
      size.height + _bottomInset,
    );
    _setShows(line.right <= _target.left);
  }

  void _setShows(bool value) {
    if (value == _shows) return;
    _shows = value;
    markNeedsSemanticsUpdate();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.paintChild(_footer, offset);
    _place();
    if (_shows) {
      final trailing = _trailing;
      context.paintChild(trailing, offset + _offsetOf(trailing));
    }
  }

  // The target reaches past this box into the footer's padding, so it is
  // tried ahead of the usual bounds check.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_shows && _target.contains(position)) {
      final trailing = _trailing;
      final hit = result.addWithPaintOffset(
        offset: _offsetOf(trailing),
        position: position,
        // A press anywhere in the target is a press on the control.
        hitTest: (result, _) => trailing.hitTest(
          result,
          position: trailing.size.center(Offset.zero),
        ),
      );
      if (hit) {
        result.add(BoxHitTestEntry(this, position));
        return true;
      }
    }
    return super.hitTest(result, position: position);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      _footer.hitTest(result, position: position);

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    visitor(_footer);
    if (_shows) visitor(_trailing);
  }
}

class _PlayerInfo extends StatelessWidget {
  const _PlayerInfo({
    required this.name,
    required this.title,
    required this.rating,
    required this.alignment,
    required this.federation,
    required this.fideId,
  });

  final String name;
  final String title;
  final String rating;
  final CrossAxisAlignment alignment;
  final String federation;
  final int? fideId;

  @override
  Widget build(BuildContext context) {
    final rank = [
      if (title.isNotEmpty) title,
      if (rating.isNotEmpty) rating,
    ].join(' ');

    // Imported PGNs often omit [WhiteFed]/[BlackFed] but include FideId tags,
    // so BackfilledFederationFlag resolves the country via Supabase's
    // chess_players lookup. If no real country is available, the flag widget
    // renders nothing rather than a generic placeholder.
    final flag = BackfilledFederationFlag(
      federation: federation,
      fideId: fideId,
      width: 14.sp,
      height: 10.sp,
      borderRadius: BorderRadius.circular(2.br),
    );

    return Column(
      crossAxisAlignment: alignment,
      children: [
        Row(
          mainAxisAlignment:
              alignment == CrossAxisAlignment.end
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
          children: [
            if (alignment != CrossAxisAlignment.end) ...[
              flag,
              SizedBox(width: 6.w),
            ],
            Flexible(
              child: Text(
                name,
                style: AppTypography.textSmMedium.copyWith(
                  color: const Color(0xFF0E1A1C),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign:
                    alignment == CrossAxisAlignment.end
                        ? TextAlign.right
                        : TextAlign.left,
              ),
            ),
            if (alignment == CrossAxisAlignment.end) ...[
              SizedBox(width: 6.w),
              flag,
            ],
          ],
        ),
        SizedBox(height: 2.h),
        Text(
          rank,
          style: AppTypography.textXsRegular.copyWith(
            color: const Color(0xFF4A5259),
            fontSize: 12.sp,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign:
              alignment == CrossAxisAlignment.end
                  ? TextAlign.right
                  : TextAlign.left,
        ),
      ],
    );
  }
}

/// Result score display: "½ - ½", "1 - 0", "0 - 1"
/// Uses larger dash (18sp semibold) with smaller scores (12sp medium) per CSS spec.
class _GameResultScore extends StatelessWidget {
  const _GameResultScore({required this.status});

  final GameStatus status;

  @override
  Widget build(BuildContext context) {
    final (left, right) = switch (status) {
      GameStatus.whiteWins => ('1', '0'),
      GameStatus.blackWins => ('0', '1'),
      GameStatus.draw => ('½', '½'),
      _ => ('*', '*'),
    };

    final scoreStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 12.sp,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.005 * 12,
      color: const Color(0xFF000000),
    );

    final dashStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 18.sp,
      fontWeight: FontWeight.w600,
      height: 26 / 18,
      letterSpacing: 0.001 * 18,
      color: const Color(0xFF000000),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(left, style: scoreStyle),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.w),
          child: Text('-', style: dashStyle),
        ),
        Text(right, style: scoreStyle),
      ],
    );
  }
}

/// Shows either eval bar for ongoing games or result text for finished games.
/// Mirrors the behavior of _CenterContent in game_card.dart.
class _ResultOrEvalBar extends StatelessWidget {
  const _ResultOrEvalBar({required this.game, required this.ref});

  final GamesTourModel game;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    // Use effectiveGameStatus to handle DB update lag
    final effectiveStatus = game.effectiveGameStatus;

    // If game is not ongoing, show result score
    if (effectiveStatus != GameStatus.ongoing) {
      return _GameResultScore(status: effectiveStatus);
    }

    // Check if engine gauge is enabled in settings
    final showEngineGauge = ref.watch(
      engineSettingsProviderNew.select(
        (state) => state.valueOrNull?.shouldShowEngineGaugeInGrid ?? true,
      ),
    );

    // If engine gauge is disabled, show "LIVE" indicator
    if (!showEngineGauge) {
      return Text(
        'LIVE',
        style: AppTypography.textSmMedium.copyWith(
          color: context.colors.accentText,
          fontSize: 12.sp,
        ),
      );
    }

    // Show the eval progress bar for ongoing games
    return ChessProgressBar(gamesTourModel: game);
  }
}
