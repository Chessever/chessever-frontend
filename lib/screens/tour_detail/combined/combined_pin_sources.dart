import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'combined_category.dart';
import 'combined_hall_provider.dart';

/// Pin observers use the same partial snapshots as the Combined hall. They must
/// not reopen full-tour downloads while the hall is still loading round pages.
final pinSourceGamesProvider = Provider.autoDispose
    .family<AsyncValue<List<Games>>, String>((ref, tourId) {
      if (!ref.watch(combinedLiveTourIdsProvider).contains(tourId)) {
        return ref.watch(gamesTourProvider(tourId));
      }
      final key = ref.watch(combinedCategoriesProvider).tourIds.join(',');
      ref.watch(combinedHallProvider(key));
      final hall = ref.read(combinedHallProvider(key).notifier);
      return AsyncData([
        for (final rows in hall.loader.games.values)
          for (final game in rows)
            if (game.tourId == tourId) game,
      ]);
    });

/// Combined collects pins from every real source separately. Looking up a
/// second stage here would eagerly load its knockout state and complete games.
/// Single-category screens retain their existing shared knockout pin behavior.
final pinRelatedStageIdsProvider = Provider.autoDispose
    .family<List<String>, String>((ref, tourId) {
      if (ref.watch(combinedLiveTourIdsProvider).contains(tourId)) {
        return const [];
      }
      return ref.watch(relatedKnockoutStageIdsProvider(tourId));
    });
