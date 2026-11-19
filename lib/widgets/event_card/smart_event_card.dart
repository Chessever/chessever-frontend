import 'dart:math' as math;

import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart'
    show SmartEventRequest;
import 'package:chessever2/screens/group_event/smart_event/smart_event_tiers.dart';
import 'package:chessever2/screens/group_event/widget/filter_popup/group_event_filter_provider.dart'
    show EventFormat;
import 'package:chessever2/screens/library/widgets/library_context_menu.dart';
import 'package:chessever2/screens/my_space/actions/space_menu_action.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/widgets/space_edit_fade.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/haptic_feedback_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:chessever2/widgets/card_context_menu.dart';
import 'package:chessever2/widgets/event_card/smart_event_board_window.dart';
import 'package:chessever2/widgets/event_card/smart_event_deck.dart';
import 'package:chessever2/widgets/event_card/smart_event_star.dart';
import 'package:chessever2/widgets/hub_tile.dart' show kHubTileInk;
import 'package:chessever2/widgets/time_control_glyph.dart';
import 'package:dartchess/dartchess.dart' show Square;
import 'package:flutter/material.dart';
import 'package:chessever2/widgets/card_plate_layout.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The time controls a smart event can hold, slow to fast: the builder's
/// order and its glyphs.
const List<EventFormat> _kFormats = [
  EventFormat.standard,
  EventFormat.rapid,
  EventFormat.blitz,
];

/// The grid a row [SmartEventCard] leads ([SmartEventCard.lead]): half
/// cards [column] wide, [gap] apart, each with its plate across its width.
@immutable
class SmartCardLead {
  const SmartCardLead({required this.column, required this.gap});

  /// One half card's width.
  final double column;

  /// Between two half cards of a row.
  final double gap;
}

/// A smart event (the games of every current event that matches a set of
/// criteria) drawn in the Events list's language: the phone event card's
/// surface, radius, padding and lines, so it sits among events as one of
/// them. Where an event keeps its photo, the plate is a window onto a real
/// board ([SmartEventPlate]): an opening's position, a level's piece, or,
/// for a time control alone, the stacked-boards mark.
///
/// Title, then "3 events · Ø 2728" (or [metaText]), then the builder's
/// one-line summary of the criteria, or the event card's LIVE while a
/// member event is live.
///
/// The half card ([stacked]) keeps the event card's 108 plate, so a pair in
/// My Space lines up whatever sits beside it. With [fillPlate] (Search's
/// grids, where every half card is a smart event) it lays its plate across
/// the card's whole width, in whole squares. Either way its title ends in
/// the star, clear of the board.
///
/// It handles like an event card: a tap presses it ([TappableScale]) with the
/// card-tap haptic, and with a [spaceDraft] a hold lifts it into the shared
/// focus menu ([CardContextMenu]), from the side the finger pressed and with
/// the card itself hidden under its lifted copy.
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
    this.disclosure = true,
    this.starRequest,
    this.stacked = false,
    this.editing = false,
    this.deckEvents,
    this.metaText,
    this.opening,
    this.fillPlate = false,
    this.lead,
    super.key,
  });

  /// Short tier label for the headline, e.g. `GM`, `IM`, or `2500+`.
  final String tierLabel;

  /// The applied game-average floor; 0 when no level is picked.
  final int minElo;

  /// Number of current events folded into this smart event.
  final int liveCount;

  /// The plate's deck thickness: [liveCount] by default. A smart event that
  /// cannot count its events (an opening) gives a neutral one, so its plate
  /// never claims a crowd it does not have.
  final int? deckEvents;

  /// Replaces the count line ("3 events · Ø 2728") with what the smart event
  /// covers when it is not a number of events (an opening's "ECO B20-B99",
  /// a level's "Game average 2700+").
  final String? metaText;

  /// The opening the smart event is built on: its plate shows the position
  /// its line reaches.
  final SmartPlateLine? opening;

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

  /// When set (with [onTap]), a long press lifts the card into the shared
  /// focus menu with "Open smart event" and the My Space row for this smart
  /// event (see `smartEventSpaceDraft`).
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

  /// The trailing "open" chevron. Off where a tap selects instead of opens
  /// (My Space's Edit mode).
  final bool disclosure;

  /// When set, the card ends in this smart event's star instead of the
  /// chevron, as an event card does in the Events lists. The star is the
  /// smart event's push subscription (Trello #1411), so the menu has no
  /// notifications row of its own. My Space sets it (Trello #1225).
  final SmartEventRequest? starRequest;
  final bool stacked;

  /// The half card's plate fills the card's width instead of the event
  /// card's 108. Only where every half card beside it fills its own
  /// (Search's grids): next to an event, a Library row or a collection (My
  /// Space) the taller plate would leave the pair's bottoms out of line.
  final bool fillPlate;

  /// The row card leading a grid of [fillPlate] half cards (Search's Super
  /// GM over GM and IM): its plate is theirs, over the first column, and its
  /// words and star stand where the second column's do. Without it the row
  /// card keeps the event card's 108 plate, and the card meant to lead
  /// would draw the smallest board of its section.
  final SmartCardLead? lead;

  /// The card's inner padding, round the plate and the words.
  static double get _padding => 6.sp;

  /// The half card's inset round its words ([CardPlateLayout]'s).
  static double get _wordsInset => 6.sp;

  /// The star's (or the chevron's) full target, its 20pt glyph centred.
  static const double _target = 44.0;

  /// From the card's inner edge in to the star glyph's near side, plus a
  /// hair of air: where a title ending in the star stops.
  static double get _glyphReach => _target / 2 + 10.w + 4.w;

  /// The paper card's hairline; dark stands on its tone.
  static Border? _border(BuildContext context) => context.isLightTheme
      ? Border.all(color: context.colors.divider.withValues(alpha: 0.4))
      : null;

  static double _borderWidth(BuildContext context) =>
      (_border(context)?.dimensions.horizontal ?? 0) / 2;

  /// The plate width of a [fillPlate] half card [cardWidth] wide.
  static double _filledPlateWidth(BuildContext context, double cardWidth) =>
      math.max(0.0, cardWidth - 2 * _padding - 2 * _borderWidth(context));

  /// My Space's Edit, where a tap selects the card: the star keeps its place
  /// (the card never reflows) but fades out and takes no taps
  /// ([SpaceEditFade]). [disclosure] off instead leaves the trailing slot
  /// empty.
  final bool editing;

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
    final open = onTap;
    if (open == null) return card;

    final draft = spaceDraft;
    // The hold sits inside the press, as on an event card: the menu measures
    // the card as painted, mid-press, and the copy lifts from that size.
    return TappableScale(
      onTap: () {
        HapticFeedbackService.cardTap();
        open();
      },
      child: draft == null
          ? card
          : Consumer(
              child: card,
              builder: (context, ref, child) => CardContextMenu(
                // The copy is the card as drawn, inert in the menu.
                previewBuilder: _buildCard,
                onPreviewTap: open,
                actions: (menuContext) => [
                  LibraryMenuAction(
                    icon: Icons.open_in_new_rounded,
                    label: spaceOpenLabel(SpaceShortcutKind.smartEvent),
                    onSelected: open,
                  ),
                  spaceMenuAction(context: menuContext, ref: ref, draft: draft),
                ],
                child: child!,
              ),
            ),
    );
  }

  /// The plate, [width] x [height]: the same plate in the row and the half
  /// card.
  Widget _plate(double width, double height) => SmartEventPlate(
    width: width,
    height: height,
    minElo: minElo,
    formatsAndStates: formatsAndStates,
    events: deckEvents ?? liveCount,
    opening: opening,
    seed: smartDeckSeed([
      tierLabel,
      titleSuffix,
      minElo,
      ...formatsAndStates.toList()..sort(),
    ]),
  );

  /// Title, meta line and third line. [titleEnd] keeps the title clear of
  /// a trailing control laid over its row (the half card's star).
  Widget _details(BuildContext context, {double titleEnd = 0}) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(right: titleEnd),
          child: CardPlateTitle(
            stacked: stacked,
            child: Text(
              '$tierLabel $titleSuffix'.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _titleStyle(context),
            ),
          ),
        ),
        SizedBox(height: 4.h),
        if (metaText case final meta?)
          Text(
            meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.textXsMedium.copyWith(
              color: colors.textPrimaryMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          )
        else
          _MetaLine(
            count: liveCount,
            avgElo: avgElo,
            countSingular: countSingular,
            countPlural: countPlural,
          ),
        _ThirdLine(live: live, text: summary ?? caption ?? _fallbackCaption),
      ],
    );
  }

  TextStyle _titleStyle(BuildContext context) => AppTypography.textSmMedium
      .copyWith(color: context.colors.textPrimary, fontSize: 14.f, height: 1.2);

  /// The title's first line, as laid out: what the star centres on.
  double _titleLine(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14.f) *
      (_titleStyle(context).height ?? 1.2);

  /// The star or the chevron in its full target, ending the title of a
  /// filled half card or a lead card; null where neither is drawn.
  Widget? _titleEnd(BuildContext context) {
    if (starRequest case final request?) {
      return SpaceEditFade(
        hidden: editing,
        child: SmartEventStar(request: request),
      );
    }
    if (!disclosure) return null;
    return SizedBox.square(
      dimension: _target,
      child: Center(
        child: Icon(
          Icons.chevron_right_rounded,
          size: 20.ic,
          color: context.colors.iconSecondary,
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    final colors = context.colors;
    final light = context.isLightTheme;
    // The event card's 108 plate, in the row and in the half card alike
    // (CardPlateLayout), unless the row card leads a grid of filled ones.
    final lead = stacked ? null : this.lead;
    final imageW = lead != null
        ? _filledPlateWidth(context, lead.column)
        : _imageWidth(context);
    final imageH = imageW * kSmartPlateRanks / kSmartPlateFiles;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8.br),
        // The event card's own treatment: paper lifts with a hairline and
        // a tight shadow, dark stands on its tone.
        border: _border(context),
        boxShadow: light
            ? [
                BoxShadow(
                  color: colors.shadow,
                  blurRadius: 8,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      padding: EdgeInsets.all(_padding),
      child: stacked
          ? _buildStacked(context, imageW, imageH)
          : lead != null
          ? _buildLead(context, lead, imageW, imageH)
          : ConstrainedBox(
              constraints: BoxConstraints(minHeight: imageH),
              child: CardPlateLayout(
                plate: _plate(imageW, imageH),
                details: _details(context),
                trailing: starRequest != null
                    ? SpaceEditFade(
                        hidden: editing,
                        child: SmartEventStar(request: starRequest!),
                      )
                    : disclosure
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: 4.w),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 20.ic,
                            color: colors.iconSecondary,
                          ),
                          SizedBox(width: 4.w),
                        ],
                      )
                    : null,
              ),
            ),
    );
  }

  /// The half card: the plate on top, then the words, the star or chevron
  /// at the title's end in its full 44pt target, clear of the board (a
  /// piece can stand in the plate's corner). [CardPlateLayout]'s stacked
  /// gap and inset, so the words and the card's height are a half card's.
  ///
  /// The plate is the event card's [plateW] x [plateH] centred on top (My
  /// Space: every half card beside it draws that plate, so the pair's rows
  /// line up), or with [fillPlate] the whole width in whole squares (the
  /// 5:4 of five files by four ranks; Search, where only filled half cards
  /// stand beside it).
  Widget _buildStacked(BuildContext context, double plateW, double plateH) {
    final gap = 10.sp;
    final inset = _wordsInset;
    // The star's 44pt target, its 20pt glyph centred: the title stops short
    // of the glyph, with a hair of air.
    const target = _target;
    final glyphReach = _glyphReach;
    final line = _titleLine(context);
    final trailing = _titleEnd(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (fillPlate)
          // AspectRatio answers its height from the width alone, so the
          // card can still be measured without laying out the board.
          AspectRatio(
            aspectRatio: kSmartPlateFiles / kSmartPlateRanks,
            child: LayoutBuilder(
              builder: (context, box) => _plate(box.maxWidth, box.maxHeight),
            ),
          )
        else
          Align(alignment: Alignment.topCenter, child: _plate(plateW, plateH)),
        Stack(
          // On a small phone the target reaches a point or two into the gap
          // above; it is drawn whole, centred on the title all the same.
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(inset, gap + inset, inset, inset),
              child: _details(
                context,
                titleEnd: trailing == null
                    ? 0
                    : math.max(0.0, glyphReach - inset),
              ),
            ),
            if (trailing != null)
              Positioned(
                // Centred on the title's first line.
                top: gap + inset + line / 2 - target / 2,
                right: 0,
                child: trailing,
              ),
          ],
        ),
      ],
    );
  }

  /// The row card leading a grid of filled half cards ([lead]): the plate,
  /// the half cards' own, over the first column; the words and the star
  /// where the second column's stand, so title, star and lines sit on the
  /// grid of the cards under it. The words centre on the plate; the star
  /// centres on the title's first line, as on a half card, its whole
  /// target inside the card.
  Widget _buildLead(
    BuildContext context,
    SmartCardLead lead,
    double plateW,
    double plateH,
  ) {
    final border = _borderWidth(context);
    // From the plate's edge to where the second column's words start: the
    // grid's gap, the two cards' padding and hairlines, the words' inset.
    final toWords = lead.gap + 2 * _padding + 2 * border + _wordsInset;
    final line = _titleLine(context);
    final trailing = _titleEnd(context);
    // Room above and below the words for the star's target, centred on
    // the title's first line; the words stay centred on the plate.
    final lift = trailing == null ? 0.0 : math.max(0.0, _target / 2 - line / 2);
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: plateH),
      child: Row(
        children: [
          _plate(plateW, plateH),
          SizedBox(width: toWords),
          Expanded(
            child: Stack(
              children: [
                // The second column's words end their inset short of the
                // card's inner edge, where the star's target ends.
                Padding(
                  padding: EdgeInsets.fromLTRB(0, lift, _wordsInset, lift),
                  child: _details(
                    context,
                    titleEnd: trailing == null
                        ? 0
                        : math.max(0.0, _glyphReach - _wordsInset),
                  ),
                ),
                if (trailing != null)
                  Positioned(
                    top: lift + line / 2 - _target / 2,
                    right: 0,
                    child: trailing,
                  ),
              ],
            ),
          ),
        ],
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
          TextSpan(
            text: count == 1 ? '1 $countSingular' : '$count $countPlural',
          ),
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
        style: live
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

/// The smart event's plate: a window onto a real board, cut on square
/// lines ([SmartEventBoardWindow]), in the plate's own quiet squares with
/// one tonal mark. What it shows, first that applies:
///
/// 1. an opening ([opening]): the position its line reaches, the move that
///    defines it marked on both squares, framed where the line played;
/// 2. a level ([minElo]): its piece of the title ladder (Super GM the king,
///    GM the queen, IM the rook, FM the bishop, CM the knight) alone on its
///    home square, the square marked, ranks 1-3 of one board;
/// 3. else the stacked-boards deck ([SmartEventDeck]), the fastest time
///    control's glyph on its front board.
///
/// A window with a level or time controls to state ends in a band one
/// square tall, a board's coordinate margin: the floor ("2700+") on the
/// left, the time controls' glyphs on the right.
class SmartEventPlate extends StatelessWidget {
  const SmartEventPlate({
    super.key,
    required this.width,
    required this.height,
    required this.minElo,
    this.formatsAndStates = const <String>{},
    this.events = 2,
    this.seed = 0,
    this.opening,
  });

  final double width;
  final double height;
  final int minElo;
  final Set<String> formatsAndStates;

  /// How many events the smart event gathers: the deck's thickness.
  final int events;

  /// Deals the deck (see [smartDeckSeed]).
  final int seed;

  /// The opening the plate shows, when the smart event is built on one.
  final SmartPlateLine? opening;

  @override
  Widget build(BuildContext context) {
    final glyphs = [
      for (final f in _kFormats)
        if (formatsAndStates.contains(f.name))
          if (TimeControlGlyph.assetForLabel(f.name) case final asset?) asset,
    ];
    final level = minElo > 0;
    final band = level || glyphs.isNotEmpty;
    final square = math.min(
      width / kSmartPlateFiles,
      height / kSmartPlateRanks,
    );
    final windowRanks = band ? kSmartPlateRanks - 1 : kSmartPlateRanks;

    Widget board(String fen, SmartBoardWindow window, Set<Square> marks) {
      final palette = SmartPlatePalette.of(context);
      return SizedBox(
        width: width,
        height: height,
        child: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6.br),
            child: ColoredBox(
              color: palette.ink,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SmartEventBoardWindow(
                    square: square,
                    fen: fen,
                    window: window,
                    marks: marks,
                  ),
                  if (band)
                    SmartPlateBand(
                      square: square,
                      width: square * kSmartPlateFiles,
                      floor: level ? minElo : null,
                      glyphs: glyphs,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (opening case final line?) {
      if (resolveSmartPlateLine(line) case final position?) {
        final move = position.lastMove;
        return board(position.fen, position.window(ranks: windowRanks), {
          move.from,
          move.to,
        });
      }
    }
    if (level) {
      final tier = smartTierAtOrBelow(minElo);
      if (tier != null) {
        return board(
          smartTierPlateFen(tier),
          smartBoardWindowAround(tier.home, ranks: windowRanks),
          {tier.home},
        );
      }
      // A floor under every tier: an empty crop of the board, its floor in
      // the band.
      return board(
        '8/8/8/8/8/8/8/8 w - - 0 1',
        smartBoardWindowAround(Square.d1, ranks: windowRanks),
        const {},
      );
    }
    return _deck(context);
  }

  /// The deck on the plate's neutral panel, with a hairline in the panel's
  /// own colour.
  Widget _deck(BuildContext context) {
    final colors = context.colors;
    final light = context.isLightTheme;
    final plate = light ? colors.surfaceRecessed : kHubTileInk;
    final edge = (light ? Colors.black : Colors.white).withValues(alpha: 0.06);
    final side = math.min(width * 0.86, height * 0.84);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: plate,
        borderRadius: BorderRadius.circular(6.br),
        border: Border.all(color: edge),
      ),
      child: Center(
        child: SmartEventDeck(
          size: side,
          ink: colors.iconPrimary,
          background: plate,
          seed: seed,
          behind: events.clamp(1, 3),
          pace: smartDeckPace(formatsAndStates),
          glyph: smartDeckGlyph(formatsAndStates),
        ),
      ),
    );
  }
}
