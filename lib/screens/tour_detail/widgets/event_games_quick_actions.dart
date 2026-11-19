import 'dart:async';

import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_games_provider.dart';
import 'package:chessever2/providers/live_game_ids_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_live_game_ids.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_display_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_list_presentation_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/match_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_expansion_provider.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:flutter/widgets.dart' show BuildContext, ModalRoute;
import 'package:hooks_riverpod/hooks_riverpod.dart';

// The event Games tab's list controls (Trello #1420): Live first (a floating
// capsule while something is live or while it is on; it reorders, never
// hides, so it reads `LiveFirstMode.reorder`) and Collapse all (a row in the
// event ⋮ menu). The rules are the same for the single-category list and
// for Combined alike.

/// `ref.read` of a widget or a [ProviderContainer].
typedef EventProviderReader = T Function<T>(ProviderListenable<T> provider);

/// Accessible name of the fold button while any section is open.
const String kCollapseAllRoundsLabel = 'Collapse all rounds';

/// Accessible name of the fold button once every section is folded.
const String kExpandAllRoundsLabel = 'Expand all rounds';

/// Whether Live first is on in the event's Games list.
///
/// Single category: the screen model's display mode. Combined: on only while
/// every merged category has it on, read from the same per-category setting.
final eventGamesLiveFirstProvider = Provider.autoDispose<bool>((ref) {
  if (ref.watch(combinedCategorySelectedProvider)) {
    return combinedLiveGamesFirst(
      ref.watch,
      ref.watch(combinedCategoriesProvider).tourIds,
    );
  }
  return ref.watch(
        gamesTourScreenProvider.select(
          (screen) => screen.valueOrNull?.gameDisplayMode,
        ),
      ) ==
      GameDisplayMode.hideFinishedGames;
});

/// What happened when Live first was pressed.
enum EventLiveFirstPress { turnedOn, turnedOff, nothingLive }

/// Presses Live first in the event's Games list.
///
/// Turning it off always works. Turning it on needs a game in play among the
/// games on screen ([eventGamesAnyLiveProvider]: the server's count once it
/// has answered); with none it stays off and returns
/// [EventLiveFirstPress.nothingLive], for the caller to say so.
EventLiveFirstPress pressEventGamesLiveFirst(EventProviderReader read) {
  if (read(combinedCategorySelectedProvider)) {
    final tourIds = read(combinedCategoriesProvider).tourIds;
    final isOn = combinedLiveGamesFirst(read, tourIds);
    if (!isOn && !read(eventGamesAnyLiveProvider)) {
      return EventLiveFirstPress.nothingLive;
    }
    final next = isOn ? GameDisplayMode.all : GameDisplayMode.hideFinishedGames;
    for (final tourId in tourIds) {
      read(gameDisplayModeProvider(tourId).notifier).state = next;
    }
    return isOn ? EventLiveFirstPress.turnedOff : EventLiveFirstPress.turnedOn;
  }

  final screen = read(gamesTourScreenProvider).valueOrNull;
  final isOn = screen?.gameDisplayMode == GameDisplayMode.hideFinishedGames;
  if (!isOn && !read(eventGamesAnyLiveProvider)) {
    return EventLiveFirstPress.nothingLive;
  }
  // Switching the order rebuilds the screen model from every game, which
  // ends a search. The field still shows the query, so run it again in the
  // new order instead of leaving the hits replaced by the whole event.
  final query = screen?.isSearchMode == true
      ? (screen?.searchQuery ?? '').trim()
      : '';
  final notifier = read(gamesTourScreenProvider.notifier);
  unawaited(() async {
    if (isOn) {
      await notifier.showAllGames();
    } else {
      await notifier.hideFinishedGames();
    }
    if (query.isNotEmpty) await notifier.searchGamesEnhanced(query);
  }());
  return isOn ? EventLiveFirstPress.turnedOff : EventLiveFirstPress.turnedOn;
}

/// The games in play in the event's Games list (single category or
/// Combined, every category): the server's set (`get_live_game_ids`)
/// limited to the boards the list shows, less any it already shows as
/// finished. The same set Live first lifts, so the count and the lift
/// agree. Null until the server answers (or on a backend that cannot).
final eventGamesLiveIdsProvider = Provider.autoDispose<Set<String>?>((ref) {
  if (ref.watch(combinedCategorySelectedProvider)) {
    final live = ref.watch(combinedGamesServerLiveIdsProvider);
    return eventLiveIdsAmong(live, [
      for (final games
          in ref.watch(combinedGamesPresentationProvider).gamesByRound.values)
        ...games,
    ]);
  }
  final grouped = ref.watch(gamesTourGroupedProvider);
  final live = watchEventServerLiveIds(ref.watch, grouped.liveScopes);
  return eventLiveIdsAmong(live, [
    for (final games in grouped.gamesByRound.values) ...games,
  ]);
});

/// Whether a game is in play in the event's Games list (single category or
/// Combined). Live first floats over the list only while this holds (Trello
/// #1420): with nothing live it has nothing to do. Until the server answers,
/// the boards' own status decides, so a backend that cannot say keeps the
/// capsule (with no number).
final eventGamesAnyLiveProvider = Provider.autoDispose<bool>((ref) {
  final live = ref.watch(eventGamesLiveIdsProvider);
  if (live != null) return live.isNotEmpty;
  if (ref.watch(combinedCategorySelectedProvider)) {
    return _anyLive(
      ref.watch(combinedGamesPresentationProvider).gamesByRound.values,
    );
  }
  return _anyLive(ref.watch(gamesTourGroupedProvider).gamesByRound.values);
});

/// How many games are in play in the event's Games list (single category or
/// Combined, every category), each board once however many sections list
/// it: the count Live first shows ("See 3 live"). Null while unknown ("See
/// live").
final eventGamesLiveCountProvider = Provider.autoDispose<int?>(
  (ref) => ref.watch(eventGamesLiveIdsProvider)?.length,
);

bool _anyLive(Iterable<List<GamesTourModel>> rounds) => rounds.any(
  (games) => games.any((game) => GameFilterHelper.isInPlay(game)),
);

/// The event Games list's live-game polls that are running (the floating
/// buttons' count keeps them alive): only what already runs, nothing is
/// started from here.
List<LiveGameIdsNotifier> _runningEventLivePolls(WidgetRef ref) {
  final List<EventLiveGamesScope> scopes;
  if (ref.read(combinedCategorySelectedProvider)) {
    scopes = ref.exists(combinedGamesLiveScopeProvider)
        ? [?ref.read(combinedGamesLiveScopeProvider)]
        : const <EventLiveGamesScope>[];
  } else {
    scopes = ref.exists(gamesTourGroupedProvider)
        ? ref.read(gamesTourGroupedProvider).liveScopes
        : const <EventLiveGamesScope>[];
  }
  return [
    for (final scope in scopes)
      if (ref.exists(eventLiveGameIdsProvider(scope)))
        ref.read(eventLiveGameIdsProvider(scope).notifier),
  ];
}

/// Pauses the event Games list's live-game polls while the list is out of
/// view, another tab in front of it ([gamesInView] false) or a route (a
/// board) over the page, and resumes them as it comes back
/// ([LiveGameIdsNotifier.visible]). With Live first on, the Games list keeps
/// them running from its kept-alive tab, so without this they would poll
/// every 5 s under Standings, and under a board opened from it.
///
/// Call from the build of the event's floating buttons, on every tab: they
/// rebuild as the tab changes and as the page is covered or uncovered. A
/// poll Live first starts later in the same frame (a category picked from
/// another tab) is paused once the frame is done.
void syncEventGamesLiveIdsVisibility(
  BuildContext context,
  WidgetRef ref, {
  required bool gamesInView,
}) {
  final visible = gamesInView && (ModalRoute.isCurrentOf(context) ?? true);
  _setEventLivePollsVisible(ref, visible);
  final scheduled = _eventLivePollsHiddenAfterFrame[context] != null;
  if (visible) {
    // A pause still due from earlier in this frame no longer holds.
    if (scheduled) _eventLivePollsHiddenAfterFrame[context] = false;
    return;
  }
  // One check per frame, with the buttons' latest wish.
  _eventLivePollsHiddenAfterFrame[context] = true;
  if (scheduled) return;
  SchedulerBinding.instance.addPostFrameCallback((_) {
    final hidden = _eventLivePollsHiddenAfterFrame[context] ?? false;
    _eventLivePollsHiddenAfterFrame[context] = null;
    if (hidden && context.mounted) _setEventLivePollsVisible(ref, false);
  });
}

/// The buttons whose end-of-frame pause is pending: true while the list is
/// still out of view by their latest build.
final Expando<bool> _eventLivePollsHiddenAfterFrame = Expando<bool>(
  'eventLivePollsHiddenAfterFrame',
);

void _setEventLivePollsVisible(WidgetRef ref, bool visible) {
  for (final poll in _runningEventLivePolls(ref)) {
    if (poll.visible != visible) poll.visible = visible;
  }
}

/// Asks the server again for the event Games list's games in play: a pull
/// to refresh takes the count along with the boards.
Future<void> refreshEventGamesLiveIds(WidgetRef ref) => Future.wait<void>([
  for (final poll in _runningEventLivePolls(ref)) poll.refresh(),
]);

/// The round (and knockout match) sections Collapse all acts on.
@immutable
class EventGamesSections {
  const EventGamesSections({
    required this.roundIds,
    this.matchKeys = const <String>[],
    required this.foldRoundIds,
    this.foldMatchKeys = const <String>[],
  });

  /// The sections in the list, which decide whether everything is folded.
  final List<String> roundIds;
  final List<String> matchKeys;

  /// The sections the button folds or opens: every round with games plus
  /// every round in [roundIds] in the single-category list, the same cards
  /// as [roundIds] in Combined. Always covers [roundIds].
  final List<String> foldRoundIds;
  final List<String> foldMatchKeys;

  /// No sections: the list is loading or empty.
  static const none = EventGamesSections(
    roundIds: <String>[],
    foldRoundIds: <String>[],
  );

  bool get isEmpty => roundIds.isEmpty && matchKeys.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is EventGamesSections &&
      listEquals(other.roundIds, roundIds) &&
      listEquals(other.matchKeys, matchKeys) &&
      listEquals(other.foldRoundIds, foldRoundIds) &&
      listEquals(other.foldMatchKeys, foldMatchKeys);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(roundIds),
    Object.hashAll(matchKeys),
    Object.hashAll(foldRoundIds),
    Object.hashAll(foldMatchKeys),
  );
}

/// The Games list's foldable sections, kept current as rounds and games land.
///
/// None during a search: the list then shows every hit open under inert
/// headers (the board list and the team matchup list alike), so folding
/// would change nothing on screen and only resurface once the search is
/// cleared.
final eventGamesSectionsProvider = Provider.autoDispose<EventGamesSections>((
  ref,
) {
  if (ref.watch(combinedCategorySelectedProvider)) {
    final presentation = ref.watch(combinedGamesPresentationProvider);
    if (presentation.isSearchMode) return EventGamesSections.none;
    final roundIds = presentation.roundIds;
    return EventGamesSections(roundIds: roundIds, foldRoundIds: roundIds);
  }
  // Nothing to fold until the event's games are in; the list shows its
  // loading state meanwhile.
  final screen = ref.watch(gamesTourScreenProvider);
  if (!screen.hasValue) {
    return EventGamesSections.none;
  }
  if (screen.requireValue.isSearchMode) return EventGamesSections.none;
  final roundIds = [
    for (final round in ref.watch(gamesTourDisplayRoundsProvider)) round.id,
  ];
  // The app bar's helpers read the games and the round list; watching both
  // recomputes the sections whenever either changes.
  ref.watch(gamesAppBarProvider);
  final appBar = ref.watch(gamesAppBarProvider.notifier);
  // Every round with games, and every round on screen: a Lichess pairings
  // card (the next round's boards while the backend sync lags) is shown
  // without having games of its own in the app bar's count. Folding fewer
  // rounds than the list checks would leave Collapse all unable to finish.
  final foldRoundIds = {
    ...appBar.getAllRoundIdsWithGames(),
    ...roundIds,
  }.toList(growable: false);
  return EventGamesSections(
    roundIds: roundIds,
    matchKeys: appBar.getVisibleMatchKeys(roundIds),
    foldRoundIds: foldRoundIds,
    foldMatchKeys: appBar.getVisibleMatchKeys(foldRoundIds),
  );
});

/// Whether every round and knockout match in the list is folded. An empty
/// list is not: there is nothing to open.
bool areAllVisibleSectionsCollapsed({
  required Iterable<String> visibleRoundIds,
  required Iterable<String> visibleMatchKeys,
  required Map<String, bool> roundExpansionState,
  required Map<String, bool> matchExpansionState,
}) {
  final rounds = visibleRoundIds.toList(growable: false);
  final matches = visibleMatchKeys.toList(growable: false);

  if (rounds.isEmpty && matches.isEmpty) {
    return false;
  }

  final areRoundsCollapsed = rounds.every(
    (id) => !(roundExpansionState[id] ?? true),
  );
  final areMatchesCollapsed = matches.every(
    (key) => !resolveMatchExpansionState(matchExpansionState, key),
  );

  return areRoundsCollapsed && areMatchesCollapsed;
}

/// Whether [sections] are all folded in the current expansion state.
bool eventGamesSectionsCollapsed(
  EventProviderReader read,
  EventGamesSections sections,
) => areAllVisibleSectionsCollapsed(
  visibleRoundIds: sections.roundIds,
  visibleMatchKeys: sections.matchKeys,
  roundExpansionState: read(roundExpansionProvider),
  matchExpansionState: read(matchExpansionProvider),
);

/// Folds every section of the Games list, or opens them all once everything
/// is folded.
void toggleEventGamesSections(EventProviderReader read) {
  final sections = read(eventGamesSectionsProvider);
  final rounds = read(roundExpansionProvider.notifier);
  final matches = read(matchExpansionProvider.notifier);
  if (eventGamesSectionsCollapsed(read, sections)) {
    rounds.expandAll(sections.foldRoundIds);
    if (sections.foldMatchKeys.isNotEmpty) matches.expandAll();
  } else {
    rounds.collapseAll(sections.foldRoundIds);
    if (sections.foldMatchKeys.isNotEmpty) {
      matches.collapseAll(sections.foldMatchKeys);
    }
  }
}
