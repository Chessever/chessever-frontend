import 'dart:async';

import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_games_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_display_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_grouped_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_list_presentation_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/match_expansion_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/round_expansion_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// The event Games tab's list controls (Trello #1420): Live first (a floating
// button while something is live) and Collapse all (a row in the event ⋮
// menu). The rules are the same for the single-category list and for
// Combined alike.

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
/// games on screen; with none it stays off and returns
/// [EventLiveFirstPress.nothingLive], for the caller to say so.
EventLiveFirstPress pressEventGamesLiveFirst(EventProviderReader read) {
  if (read(combinedCategorySelectedProvider)) {
    final tourIds = read(combinedCategoriesProvider).tourIds;
    final isOn = combinedLiveGamesFirst(read, tourIds);
    if (!isOn &&
        !_anyLive(
          read(combinedGamesPresentationProvider).gamesByRound.values,
        )) {
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
  if (!isOn && !_anyLive(read(gamesTourGroupedProvider).gamesByRound.values)) {
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

/// Whether a game is in play in the event's Games list (single category or
/// Combined). Live first floats over the list only while this holds (Trello
/// #1420): with nothing live it has nothing to do.
final eventGamesAnyLiveProvider = Provider.autoDispose<bool>((ref) {
  if (ref.watch(combinedCategorySelectedProvider)) {
    return _anyLive(
      ref.watch(combinedGamesPresentationProvider).gamesByRound.values,
    );
  }
  return _anyLive(ref.watch(gamesTourGroupedProvider).gamesByRound.values);
});

/// Live first is on in the event's Games list, the list has loaded, and no
/// game in it is in play. Here Live first hides the finished games, so left
/// on it would keep them hidden behind a button that is no longer shown; the
/// screen turns it off. Never true while the list is still loading, whose
/// empty first frame is not "nothing live".
final eventGamesLiveFirstStrandedProvider = Provider.autoDispose<bool>((ref) {
  if (!ref.watch(eventGamesLiveFirstProvider)) return false;
  final loaded = ref.watch(combinedCategorySelectedProvider)
      ? !ref.watch(
          combinedGamesPresentationProvider.select(
            (presentation) => presentation.source.isLoading,
          ),
        )
      : ref.watch(
          gamesTourScreenProvider.select(
            (screen) => screen.hasValue && !screen.isLoading,
          ),
        );
  return loaded && !ref.watch(eventGamesAnyLiveProvider);
});

bool _anyLive(Iterable<List<GamesTourModel>> rounds) => rounds.any(
  (games) => games.any((game) => GameFilterHelper.isLiveNow(game)),
);

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
/// headers, so folding would change nothing on screen and only resurface
/// once the search is cleared. The team matchup list is the exception; it
/// keeps folding through a search, and so does the button.
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
  if (screen.requireValue.isSearchMode && !_showsTeamMatchups(ref)) {
    return EventGamesSections.none;
  }
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

/// Whether the Games tab paints the team matchup list rather than the board
/// list; the same choice as `GamesTourScreen`, which keeps the board list
/// for knockout stages on tablets.
bool _showsTeamMatchups(Ref ref) {
  if (ref.watch(gamesTourScreenModeProvider).valueOrNull !=
      GamesTourScreenMode.groupEvent) {
    return false;
  }
  final rounds =
      ref.watch(gamesAppBarProvider).valueOrNull?.gamesAppBarModels ??
      const <GamesAppBarModel>[];
  final hasKnockoutStages = rounds.any(
    (round) => round.id.startsWith('$kKnockoutStagePrefix-'),
  );
  return !(hasKnockoutStages && ResponsiveHelper.isTablet);
}

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
