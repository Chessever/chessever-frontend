import 'package:chessever2/repository/local_storage/tournament/tour_local_storage.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tournaments/providers/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tournaments/tournament_detail_screen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../services/favourate_standings_player_services.dart';

// Provider for the standings state
final standingScreenProvider = StateNotifierProvider<
  StandingScreenNotifier,
  AsyncValue<List<PlayerStandingModel>>
>((ref) {
  final groupBroadcastId = ref.watch(selectedBroadcastModelProvider)!.id;
  final aboutTourModel =
      ref.watch(tourDetailScreenProvider).value!.aboutTourModel;
  return StandingScreenNotifier(
    ref: ref,
    tourId: aboutTourModel.id,
    groupBroadcastId: groupBroadcastId,
  );
});

class StandingScreenNotifier
    extends StateNotifier<AsyncValue<List<PlayerStandingModel>>> {
  StandingScreenNotifier({
    required this.ref,
    required this.tourId,
    required this.groupBroadcastId,
  }) : super(AsyncValue.loading()) {
    // Initialize with test data
    loadStandings();
  }

  final Ref ref;
  final String tourId;
  final String groupBroadcastId;

  Future<void> loadStandings() async {
    try {
      final allTours = await ref
          .read(tourLocalStorageProvider)
          .getTours(groupBroadcastId);
      final selectedTour = allTours.where((e) => e.id == tourId).toList();

      var tournamentPlayer = <TournamentPlayer>[];

      for (var a = 0; a < selectedTour.length; a++) {
        for (var b = 0; b < selectedTour[a].players.length; b++) {
          tournamentPlayer.add(selectedTour[a].players[b]);
        }
      }

      tournamentPlayer = tournamentPlayer.toSet().toList();

      tournamentPlayer.sort((a, b) {
        final aRating = a.score == null ? 0 : (a.score! / a.played);
        final bRating = b.score == null ? 0 : (b.score! / b.played);

        if (bRating == aRating) {
          return b.played.compareTo(a.played);
        }

        return bRating.compareTo(aRating); // Descending order (highest first)
      });

      state = AsyncValue.data(
        tournamentPlayer.map((e) => PlayerStandingModel.fromPlayer(e)).toList(),
      );
    } catch (e, _) {
      state = AsyncValue.data([]);
    }
  }
}

final favoritesServiceProvider = Provider<FavourateStandingsPlayerServices>((
  ref,
) {
  return FavourateStandingsPlayerServices();
});

final favoritePlayersProvider = FutureProvider<List<PlayerStandingModel>>((
  ref,
) async {
  final favoritesService = ref.read(favoritesServiceProvider);
  return await favoritesService.getFavoritePlayers();
});

final isPlayerFavoriteProvider = FutureProvider.family<bool, String>((
  ref,
  playerName,
) async {
  final favoritesService = ref.read(favoritesServiceProvider);
  return await favoritesService.isFavorite(playerName);
});
