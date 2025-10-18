import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/standings/providers/player_utils_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_screen_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/repository/local_storage/favorite/favourate_standings_player_services.dart';

// Provider for the standings state
final playerTourScreenProvider = StateNotifierProvider<
  _PlayerTourScreenController,
  AsyncValue<List<PlayerStandingModel>>
>((ref) {
  final groupBroadcastId = ref.watch(selectedBroadcastModelProvider)!.id;
  final aboutTourModel =
      ref.watch(tourDetailScreenProvider).value?.aboutTourModel;

  final gamesTourScreen = ref.watch(gamesTourScreenProvider);

  if (gamesTourScreen.isLoading ||
      gamesTourScreen.hasError ||
      aboutTourModel == null) {
    return _PlayerTourScreenController.loading(ref, '', '');
  }

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
    loadPlayers();
  }

  _PlayerTourScreenController.loading(
    this.ref,
    this.tourId,
    this.groupBroadcastId,
  ) : super(AsyncValue.loading());

  final Ref ref;
  final String tourId;
  final String groupBroadcastId;
  Future<void> loadPlayers() async {
    try {
      // 🧩 Step 1: Load tournament players from local storage
      final allTours = ref.read(tourDetailScreenProvider).value!.tours;

      final selectedTours = allTours.where((e) => e.tour.id == tourId).toList();
      var tournamentPlayers = <TournamentPlayer>[];

      for (final tour in selectedTours) {
        tournamentPlayers.addAll(tour.tour.players);
      }

      // Remove duplicates by name + fideId (safe deduplication)
      final seen = <String>{};
      tournamentPlayers =
          tournamentPlayers.where((p) {
            final key = '${p.name.trim().toLowerCase()}-${p.fideId ?? 0}';
            if (seen.contains(key)) return false;
            seen.add(key);
            return true;
          }).toList();

      // 🧩 Step 2: Load all games for this tournament
      final gamesScreenData = ref.read(gamesTourScreenProvider);
      final allGames = gamesScreenData.value?.gamesTourModels ?? [];

      // 🧩 Step 3: Enrich player info (federation, title, rating, fideId)
      for (int i = 0; i < tournamentPlayers.length; i++) {
        final player = tournamentPlayers[i];

        GamesTourModel? relatedGame;
        try {
          relatedGame = allGames.firstWhere((g) {
            final playerName = player.name.trim().toLowerCase();
            final whiteName = g.whitePlayer.name.toLowerCase();
            final blackName = g.blackPlayer.name.toLowerCase();
            return ref
                    .read(playerUtilsProvider)
                    .isSamePlayer(playerName, whiteName) ||
                ref
                    .read(playerUtilsProvider)
                    .isSamePlayer(playerName, blackName);
          });
        } catch (_) {
          relatedGame = null;
        }

        if (relatedGame == null) continue;

        final isWhite = ref
            .read(playerUtilsProvider)
            .isSamePlayer(
              player.name.trim().toLowerCase(),
              relatedGame.whitePlayer.name.toLowerCase(),
            );
        final card =
            isWhite ? relatedGame.whitePlayer : relatedGame.blackPlayer;

        tournamentPlayers[i] = player.copyWith(
          federation:
              (player.federation?.trim().isNotEmpty ?? false)
                  ? player.federation
                  : (card.federation.trim().isNotEmpty
                      ? card.federation
                      : player.federation),
          title:
              (player.title?.trim().isNotEmpty ?? false)
                  ? player.title
                  : (card.title.trim().isNotEmpty ? card.title : player.title),
          rating:
              (player.rating != null && player.rating! > 0)
                  ? player.rating
                  : (card.rating > 0 ? card.rating : player.rating),
          fideId:
              (player.fideId != null && player.fideId! > 0)
                  ? player.fideId
                  : (card.fideId ?? player.fideId),
        );
      }

      // 🧩 Step 4: Calculate score and games played
      for (int i = 0; i < tournamentPlayers.length; i++) {
        final player = tournamentPlayers[i];

        final playerGames =
            allGames.where((game) {
              final playerName = player.name.trim().toLowerCase();
              return ref
                      .read(playerUtilsProvider)
                      .isSamePlayer(
                        playerName,
                        game.whitePlayer.name.toLowerCase(),
                      ) ||
                  ref
                      .read(playerUtilsProvider)
                      .isSamePlayer(
                        playerName,
                        game.blackPlayer.name.toLowerCase(),
                      );
            }).toList();

        double calculatedScore = 0.0;
        int gamesPlayed = 0;

        for (final game in playerGames) {
          // Skip ongoing or unknown games
          if (game.gameStatus == GameStatus.ongoing ||
              game.gameStatus == GameStatus.unknown) {
            continue;
          }

          gamesPlayed++;
          final isWhite = ref
              .read(playerUtilsProvider)
              .isSamePlayer(
                player.name.trim().toLowerCase(),
                game.whitePlayer.name.toLowerCase(),
              );

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

        tournamentPlayers[i] = player.copyWith(
          score: calculatedScore,
          played: gamesPlayed,
        );
      }

      // 🧩 Step 5: Sort by score (desc), then by games played (desc)
      tournamentPlayers.sort((a, b) {
        final aScore = a.score ?? double.tryParse(a.scoreString) ?? 0.0;
        final bScore = b.score ?? double.tryParse(b.scoreString) ?? 0.0;

        if (bScore != aScore) return bScore.compareTo(aScore);
        return b.played.compareTo(a.played);
      });

      // 🧩 Step 6: Update provider state
      final standings =
          tournamentPlayers
              .map((e) => PlayerStandingModel.fromPlayer(e))
              .toList();

      state = AsyncValue.data(standings);
    } catch (e, _) {
      state = const AsyncValue.data([]);
    }
  }
}

final tournamentFavoritePlayersProvider =
    FutureProvider<List<PlayerStandingModel>>((ref) async {
      final favoritesService = ref.read(favoriteStandingsPlayerService);
      return await favoritesService.getFavoritePlayers();
    });
