import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart'
    show discoverySmartEventMembersProvider;
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart'
    show SmartEventRequest, formatOpeningMovePath;
import 'package:chessever2/screens/group_event/smart_event/smart_event_builder_sheet.dart'
    show smartEventBuilderSummary, smartEventCardSummary, watchSmartEventLive;
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart'
    show GroupEventCardModel;
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_tiers.dart';
import 'package:chessever2/utils/eco_openings.dart';
import 'package:chessever2/widgets/event_card/smart_event_board_window.dart';
import 'package:chessever2/widgets/event_card/smart_event_card.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// What a smart event's card says and draws, from its request and the
/// members today's broadcasts give it (null while they load): one rule for
/// every surface that shows one (Search, My Space).
///
/// - An opening never claims a number of events. Membership is read from
///   the event-level criteria (time control, status), which carry no ECO
///   code, so the count would be every current event, not the ones playing
///   this opening. Its card names the codes it covers ("ECO B20-B99"), its
///   plate shows the position, and its last line says what else narrows
///   it, else its moves ([smartEventOpeningCaption]).
/// - A level never claims one either, for the same reason: membership
///   cannot see a game's rating, so Super GM, GM and IM would all print the
///   same count. Its card names its floor ("Game average 2700+") and its
///   last line what else narrows it, else the title ("Super Grandmaster
///   level") ([smartEventLevelCaption]).
/// - Anything else (a time control, a status) counts its events and their
///   average, as an event list would.
@immutable
class SmartEventCardFace {
  const SmartEventCardFace({
    required this.shown,
    required this.count,
    required this.avg,
    required this.summary,
    this.metaText,
    this.deckEvents,
    this.opening,
  });

  /// The request with its members, when they count.
  final SmartEventRequest shown;
  final int count;
  final int avg;
  final String? summary;
  final String? metaText;
  final int? deckEvents;
  final SmartPlateLine? opening;
}

/// [SmartEventCardFace] for [request], with [members] when they are read.
SmartEventCardFace smartEventCardFace(
  SmartEventRequest request,
  List<GroupEventCardModel>? members,
) {
  if (!request.eco.isAll) {
    return SmartEventCardFace(
      shown: request,
      count: 0,
      avg: 0,
      metaText: smartEventOpeningLabel(request.eco),
      // An opening counts no events: one neutral board if it ever falls back
      // to the deck.
      deckEvents: 1,
      summary: smartEventOpeningCaption(request),
      opening: smartPlateLineFor(request),
    );
  }
  final shown = members == null ? request : request.withEvents(members);
  if (request.minElo > 0) {
    return SmartEventCardFace(
      shown: shown,
      count: 0,
      avg: 0,
      metaText: 'Game average ${request.minElo}+',
      summary: smartEventLevelCaption(request),
    );
  }
  final elos = [
    for (final e in shown.events)
      if (e.maxAvgElo > 0) e.maxAvgElo,
  ];
  return SmartEventCardFace(
    shown: shown,
    count: shown.events.length,
    avg: elos.isEmpty
        ? 0
        : (elos.reduce((a, b) => a + b) / elos.length).round(),
    summary: smartEventCardSummary(shown),
  );
}

/// The opening [request] is built on, as its plate draws it; null without
/// one.
SmartPlateLine? smartPlateLineFor(SmartEventRequest request) {
  if (request.eco.isAll) return null;
  return SmartPlateLine(
    ecoCode: request.eco.code,
    moves: request.openingContext?.movePath ?? const <String>[],
  );
}

/// A smart event as My Space draws a saved one, from its [request] alone:
/// the shared [SmartEventCard] with the face [smartEventCardFace] gives it,
/// LIVE while a member is live, its star (the push subscription, Trello
/// #1411) and its long-press (Open, then the My Space row). Any surface that
/// shows a smart event shows this, so it looks and answers the same
/// everywhere.
///
/// A tap opens the smart event. [onTap] replaces that (Search records the
/// pick first, then opens the same screen); the long-press's Open row runs
/// the same path. The card gives its own tap haptic, so a caller adds none.
class SmartEventRequestCard extends ConsumerWidget {
  const SmartEventRequestCard({
    super.key,
    required this.request,
    this.onTap,
    this.stacked = false,
    this.star = true,
    this.showFilters = true,
    this.fillPlate = false,
    this.lead,
  });

  final SmartEventRequest request;

  /// Replaces the default open (push [SmartEventScreen] on [request]).
  final VoidCallback? onTap;

  /// The half-row card: the plate above the words, as My Space sets two
  /// smart events side by side.
  final bool stacked;

  /// The half card's plate across its whole width
  /// ([SmartEventCard.fillPlate]): only where every half card beside it
  /// does the same (Search's grids).
  final bool fillPlate;

  /// The grid of filled half cards this row card leads
  /// ([SmartEventCard.lead]): Search's Super GM over GM and IM.
  final SmartCardLead? lead;

  /// The trailing star. Off where a tap selects rather than opens.
  final bool star;

  /// Whether the smart event it opens offers Filters
  /// ([SmartEventScreen.showFilters]): off on the Search tab.
  final bool showFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Today's broadcasts, read once for every smart event card and filtered
    // per card in memory (My Space's own read). An opening reads none.
    final members = request.eco.isAll
        ? ref
              .watch(discoverySmartEventMembersProvider(request.criteria))
              .valueOrNull
        : null;
    final face = smartEventCardFace(request, members);
    final shown = face.shown;

    void open() {
      final tap = onTap;
      if (tap != null) {
        tap();
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              SmartEventScreen(request: request, showFilters: showFilters),
        ),
      );
    }

    return SmartEventCard(
      key: ValueKey<String>('smart_request_${request.criteriaKey}'),
      quiet: true,
      stacked: stacked,
      fillPlate: fillPlate,
      lead: lead,
      tierLabel: shown.tierLabel,
      minElo: shown.minElo,
      liveCount: face.count,
      deckEvents: face.deckEvents,
      metaText: face.metaText,
      opening: face.opening,
      avgElo: face.avg,
      titleSuffix: shown.titleSuffix,
      caption: shown.caption,
      countSingular: shown.countSingular,
      countPlural: shown.countPlural,
      formatsAndStates: shown.formatsAndStates,
      summary: face.summary,
      live: watchSmartEventLive(ref, shown),
      spaceDraft: smartEventSpaceDraft(request),
      starRequest: star ? shown : null,
      disclosure: star,
      onTap: open,
    );
  }
}

/// A level smart event's last line, under its floor: what narrows it
/// besides the level, in the builder's words ("Rapid, live events"), else
/// the tier's title ("Super Grandmaster level"), never the floor again.
String smartEventLevelCaption(SmartEventRequest request) {
  final criteria = smartEventBuilderSummary(request.criteria.toPopupState());
  if (criteria != null) return criteria;
  final tier = smartTierForFloor(request.minElo);
  return tier == null ? 'Every time control' : '${tier.title} level';
}

/// What an opening smart event covers, in its card's meta line: the ECO
/// range of a family ("ECO B20-B99"), else its one code ("ECO B90").
String smartEventOpeningLabel(GameEcoFilter eco) {
  final code = eco.code;
  final family = EcoOpenings.getFamily(code);
  if (family != null) return 'ECO ${family.rangeLabel}';
  return code == null ? 'ECO' : 'ECO ${code.trim().toUpperCase()}';
}

/// An opening smart event's last line, under the codes it covers: what
/// narrows it besides the opening, in the builder's words ("Game average
/// 2500+, classical"), else the opening's moves ("1. e4 c5"), else what it
/// gathers. Never the codes again: the line above names them.
String smartEventOpeningCaption(SmartEventRequest request) {
  final criteria = smartEventBuilderSummary(
    request.criteria.toPopupState().copyWith(eco: GameEcoFilter.all),
  );
  if (criteria != null) return criteria;
  final moves = request.openingContext?.movePath ?? const <String>[];
  if (moves.isNotEmpty) return formatOpeningMovePath(moves);
  return 'Current games in this opening';
}
