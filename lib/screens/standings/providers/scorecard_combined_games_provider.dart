import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/round/round.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_category.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_games_provider.dart';
import 'package:chessever2/screens/tour_detail/combined/combined_round_sections.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A direct Home player tap bypasses board navigation and must resolve the
/// saved Combined selection from the tapped game's event, not the last route.
final homeScorecardCombinedCategoriesProvider = FutureProvider.autoDispose
    .family<CombinedCategories, String>((ref, tourId) async {
      final events = ref.watch(groupBroadcastRepositoryProvider);
      final tours = ref.watch(tourRepositoryProvider);
      final prefs = ref.watch(combinedCategoryPrefsProvider.notifier);
      final mapping = await events.getTourToGroupBroadcastMapping([tourId]);
      final groupId = mapping[tourId];
      if (groupId == null) return CombinedCategories.none;
      await prefs.ensureLoaded(groupId);
      if (!prefs.isSelected(groupId)) return CombinedCategories.none;
      final eventTours = await tours.getTourByGroupId(groupId);
      final categories = CombinedCategories.fromTours([
        for (final tour in eventTours)
          TourModel(tour: tour, roundStatus: RoundStatus.ongoing),
      ]);
      return categories.canCombine ? categories : CombinedCategories.none;
    });

typedef CombinedScorecardGames = ({
  List<GamesTourModel> games,
  Map<String, String> stageLabels,
  Map<String, String> roundNames,
  bool complete,
  bool loading,
});

/// Uses complete, unfiltered catalogs, not search results or preview boards.
final combinedScorecardGamesProvider = Provider.autoDispose
    .family<CombinedScorecardGames, CombinedCategories>((ref, categories) {
      final gamesByTour = <String, List<GamesTourModel>>{};
      var complete = true;
      var pending = false;
      for (final category in categories.items) {
        final id = category.tourId;
        final full = ref.watch(completeGamesTourProvider(id));
        final models = ref.watch(combinedTourGamesProvider(id));
        final value = models.valueOrNull;
        if (!full.hasValue || value == null) {
          complete = false;
          pending |= !full.hasError && !models.hasError;
          continue;
        }
        gamesByTour[id] = value;
      }
      final rounds = ref.watch(
        combinedRoundsProvider(combinedRoundsKey(categories.tourIds)),
      );
      return assembleCombinedScorecardGames(
        categories: categories,
        gamesByTour: gamesByTour,
        roundsByTour: rounds.valueOrNull ?? const {},
        complete: complete && rounds.hasValue,
        loading: pending || (!rounds.hasValue && rounds.isLoading),
      );
    });

CombinedScorecardGames assembleCombinedScorecardGames({
  required CombinedCategories categories,
  required Map<String, List<GamesTourModel>> gamesByTour,
  required Map<String, List<Round>> roundsByTour,
  required bool complete,
  required bool loading,
}) {
  final mirrors = findMirrorTourIds(
    tourIds: categories.tourIds,
    gamesByTourId: gamesByTour,
    roundsByTourId: roundsByTour,
  );
  final labels = {
    for (final item in categories.items)
      if (!mirrors.contains(item.tourId)) item.tourId: item.label,
  };
  return (
    games: [for (final id in labels.keys) ...?gamesByTour[id]],
    stageLabels: labels,
    roundNames: {
      for (final id in labels.keys)
        for (final round in roundsByTour[id] ?? const <Round>[])
          round.id: round.name,
    },
    complete: complete,
    loading: loading,
  );
}

/// Combined scores must never take a stage's weighted standings total.
bool useScorecardSourceScore({
  required bool combined,
  required int sourcePlayed,
  required int finishedGames,
  required double? sourceScore,
}) => !combined && sourcePlayed >= finishedGames && sourceScore != null;
