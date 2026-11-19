import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart'
    show discoverySmartEventMembersProvider;
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart'
    show SmartEventRequest, formatOpeningMovePath;
import 'package:chessever2/screens/group_event/smart_event/smart_event_builder_sheet.dart'
    show smartEventBuilderSummary, smartEventCardSummary, watchSmartEventLive;
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/utils/eco_openings.dart';
import 'package:chessever2/widgets/event_card/smart_event_card.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A smart event as My Space draws a saved one, from its [request] alone:
/// the shared [SmartEventCard] with the members today's broadcasts give it,
/// the builder's one-line summary, LIVE while a member is live, its star
/// (the push subscription, Trello #1411) and its long-press (Open, then the
/// My Space row). Any surface that shows a smart event shows this, so it
/// looks and answers the same everywhere.
///
/// A tap opens the smart event. [onTap] replaces that (Search records the
/// pick first, then opens the same screen); the long-press's Open row runs
/// the same path. The card gives its own tap haptic, so a caller adds none.
///
/// An opening never claims a number of events. Membership is read from the
/// event-level criteria (time control, status), which carry no ECO code, so
/// the count would be every current event, not the ones playing this
/// opening. Its card names the codes it covers instead ("ECO B20-B99", "ECO
/// B90"), its plate wears the thinnest deck, the same for every opening, and
/// its last line says what else narrows it, else its moves
/// ([smartEventOpeningCaption]), never its codes a second time.
class SmartEventRequestCard extends ConsumerWidget {
  const SmartEventRequestCard({
    super.key,
    required this.request,
    this.onTap,
    this.stacked = false,
    this.star = true,
  });

  final SmartEventRequest request;

  /// Replaces the default open (push [SmartEventScreen] on [request]).
  final VoidCallback? onTap;

  /// The half-row card: the plate above the words, as My Space sets two
  /// smart events side by side.
  final bool stacked;

  /// The trailing star. Off where a tap selects rather than opens.
  final bool star;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SmartEventRequest shown;
    var count = 0;
    var singular = 'event';
    var plural = 'events';
    var avg = 0;
    String? opening;
    if (!request.eco.isAll) {
      shown = request;
      opening = smartEventOpeningLabel(request.eco);
    } else {
      // Today's broadcasts, read once for every smart event card and
      // filtered per card in memory (My Space's own read).
      final members = ref
          .watch(discoverySmartEventMembersProvider(request.criteria))
          .valueOrNull;
      shown = members == null ? request : request.withEvents(members);
      final elos = [
        for (final e in shown.events)
          if (e.maxAvgElo > 0) e.maxAvgElo,
      ];
      if (elos.isNotEmpty) {
        avg = (elos.reduce((a, b) => a + b) / elos.length).round();
      }
      count = shown.events.length;
      singular = shown.countSingular;
      plural = shown.countPlural;
    }

    void open() {
      final tap = onTap;
      if (tap != null) {
        tap();
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SmartEventScreen(request: request),
        ),
      );
    }

    return SmartEventCard(
      key: ValueKey<String>('smart_request_${request.criteriaKey}'),
      quiet: true,
      stacked: stacked,
      tierLabel: shown.tierLabel,
      minElo: shown.minElo,
      liveCount: count,
      // An opening counts no events: one neutral board, and its codes.
      deckEvents: opening == null ? null : 1,
      metaText: opening,
      avgElo: avg,
      titleSuffix: shown.titleSuffix,
      caption: shown.caption,
      countSingular: singular,
      countPlural: plural,
      formatsAndStates: shown.formatsAndStates,
      summary: opening == null
          ? smartEventCardSummary(shown)
          : smartEventOpeningCaption(request),
      live: watchSmartEventLive(ref, shown),
      spaceDraft: smartEventSpaceDraft(request),
      starRequest: star ? shown : null,
      disclosure: star,
      onTap: open,
    );
  }
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
