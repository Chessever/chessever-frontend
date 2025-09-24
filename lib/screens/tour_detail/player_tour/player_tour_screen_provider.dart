import 'package:chessever2/repository/local_storage/tournament/tour_local_storage.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../repository/local_storage/favorite/favourate_standings_player_services.dart';

// Provider for the standings state
final playerTourScreenProvider = StateNotifierProvider<
  _PlayerTourScreenController,
  AsyncValue<List<PlayerStandingModel>>
>((ref) {
  final groupBroadcastId = ref.watch(selectedBroadcastModelProvider)!.id;
  final aboutTourModel =
      ref.watch(tourDetailScreenProvider).value!.aboutTourModel;
  return _PlayerTourScreenController(
    ref: ref,
    tourId: aboutTourModel.id,
    groupBroadcastId: groupBroadcastId,
  );
});

class _PlayerTourScreenController
    extends StateNotifier<AsyncValue<List<PlayerStandingModel>>> {
  _PlayerTourScreenController({
    required this.ref,
    required this.tourId,
    required this.groupBroadcastId,
  }) : super(AsyncValue.loading()) {
    // Initialize with test data
    loadPlayers();
  }

  final Ref ref;
  final String tourId;
  final String groupBroadcastId;

  Future<void> loadPlayers() async {
    try {
      // Get tournament players from local storage
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

      // Get all games for this tournament from Supabase (same as score card screen)
      final gamesScreenData = ref.read(gamesTourScreenProvider);
      final allGames = gamesScreenData.value?.gamesTourModels ?? [];

      // Calculate scores from actual games for each player
      for (int i = 0; i < tournamentPlayer.length; i++) {
        final player = tournamentPlayer[i];
        final playerGames = allGames.where((game) =>
            game.whitePlayer.name == player.name ||
            game.blackPlayer.name == player.name).toList();

        double calculatedScore = 0.0;
        int gamesPlayed = 0;

        for (final game in playerGames) {
          // Skip ongoing games
          if (game.gameStatus == GameStatus.ongoing || game.gameStatus == GameStatus.unknown) {
            continue;
          }

          gamesPlayed++;
          final isWhite = game.whitePlayer.name == player.name;

          // Calculate score using w:1, d:0.5, l:0 system
          switch (game.gameStatus) {
            case GameStatus.whiteWins:
              if (isWhite) calculatedScore += 1.0;
              break;
            case GameStatus.blackWins:
              if (!isWhite) calculatedScore += 1.0;
              break;
            case GameStatus.draw:
              calculatedScore += 0.5;
              break;
            default:
              break;
          }
        }

        // Update player with calculated score
        tournamentPlayer[i] = player.copyWith(
          score: calculatedScore,
          played: gamesPlayed,
        );
      }

      // Sort by total score (highest first), then by number of games played
      tournamentPlayer.sort((a, b) {
        final aScore = a.score ?? 0.0;
        final bScore = b.score ?? 0.0;

        // Primary sort: total score (highest first)
        if (bScore != aScore) {
          return bScore.compareTo(aScore);
        }

        // Secondary sort: number of games played if scores are equal
        return b.played.compareTo(a.played);
      });

      state = AsyncValue.data(
        tournamentPlayer.map((e) => PlayerStandingModel.fromPlayer(e)).toList(),
      );
    } catch (e, _) {
      state = AsyncValue.data([]);
    }
  }
}

final tournamentFavoritePlayersProvider = FutureProvider<List<PlayerStandingModel>>((
  ref,
) async {
  final favoritesService = ref.read(favoriteStandingsPlayerService);
  return await favoritesService.getFavoritePlayers();
});

final isTournamentPlayerFavoriteProvider = FutureProvider.family<bool, String>((
  ref,
  playerName,
) async {
  final favoritesService = ref.read(favoriteStandingsPlayerService);
  return await favoritesService.isFavorite(playerName);
});
