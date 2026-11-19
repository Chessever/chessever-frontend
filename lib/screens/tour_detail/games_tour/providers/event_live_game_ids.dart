import 'package:chessever2/providers/live_game_ids_provider.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_stable_order_provider.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// What an event's Games list counts as in play ("See 3 live") and what its
// Live first lifts: one set, the server's (`get_live_game_ids`: a game in a
// fresh live round, with a move, not finished, not a mirror), limited to the
// boards the list shows and less any it already shows as finished. Until the
// server answers (or on a backend that cannot), the boards' own rows
// ([GameFilterHelper.isInPlay]: ongoing, with a move) stand in for the lift
// and the capsule reads "See live".

/// How often a single-category list asks about the sibling-stage tours it
/// also lists (a knockout whose stages are tours of their own): their games
/// are a stage away from the one in view, so they are asked about at the
/// pace their own status poll runs at.
const Duration kSiblingStageLivePoll = Duration(seconds: 45);

/// The scopes a single-category Games list asks about: [tourId] at the
/// event's pace, and the sibling-stage tours it lists ([siblingTourIds]) at
/// [kSiblingStageLivePoll]. None for no tour.
List<EventLiveGamesScope> eventGamesLiveScopes(
  String? tourId, {
  Iterable<String> siblingTourIds = const <String>[],
}) {
  final main = tourId?.trim() ?? '';
  final siblings = {
    for (final id in siblingTourIds)
      if (id.trim().isNotEmpty && id.trim() != main) id.trim(),
  };
  return [
    if (main.isNotEmpty) EventLiveGamesScope([main]),
    if (siblings.isNotEmpty)
      EventLiveGamesScope(siblings, poll: kSiblingStageLivePoll),
  ];
}

/// The server's live games for [scopes], every one watched: their union,
/// null until each has answered. No scope has nothing in play.
Set<String>? watchEventServerLiveIds(
  T Function<T>(ProviderListenable<T> provider) watch,
  Iterable<EventLiveGamesScope> scopes,
) {
  final answers = [
    for (final scope in scopes) watch(eventLiveGameIdsProvider(scope)),
  ];
  if (answers.isEmpty) return const <String>{};
  if (answers.any((answer) => answer == null)) return null;
  if (answers.length == 1) return answers.single;
  return {for (final answer in answers) ...answer!};
}

/// The boards among [games] in play by [live], the server's answer: in the
/// set and not already shown as finished (the row is newer than the
/// answer). Null while [live] is unknown.
Set<String>? eventLiveIdsAmong(
  Set<String>? live,
  Iterable<GamesTourModel> games,
) {
  if (live == null) return null;
  if (live.isEmpty) return const <String>{};
  return {
    for (final game in games)
      if (live.contains(game.gameId) && !game.effectiveGameStatus.isFinished)
        game.gameId,
  };
}

/// Live first's order for one round of an event: the boards in play by the
/// server's set ([eventLiveIdsAmong]) first, the rest after, each side in
/// its usual order. Until the server answers ([live] null), the boards'
/// own rows decide by the rule the capsule falls back on
/// ([GameFilterHelper.isInPlay]: ongoing, with a move), so a 0-move shell is
/// never lifted and what rises is what made the capsule show.
List<GamesTourModel> eventLiveFocusOrder(
  List<GamesTourModel> games,
  Set<String>? live,
) => applyLiveFocusOrder(
  games: games,
  liveGameIdsAtSnapshot: live == null
      ? {
          for (final game in games)
            if (GameFilterHelper.isInPlay(game)) game.gameId,
        }
      : eventLiveIdsAmong(live, games)!,
);

/// The scope Combined asks about: every category of the event at once,
/// polled at [EventLiveGamesScope.combinedPoll]. Null with no category.
final combinedGamesLiveScopeProvider =
    Provider.autoDispose<EventLiveGamesScope?>((ref) {
      final tourIds = ref.watch(combinedCategoriesProvider).tourIds;
      if (tourIds.isEmpty) return null;
      return EventLiveGamesScope(
        tourIds,
        poll: EventLiveGamesScope.combinedPoll,
      );
    });

/// The games in play in every category Combined lists, by the server. Null
/// until it answers.
final combinedGamesServerLiveIdsProvider = Provider.autoDispose<Set<String>?>((
  ref,
) {
  final scope = ref.watch(combinedGamesLiveScopeProvider);
  return watchEventServerLiveIds(ref.watch, [?scope]);
});
