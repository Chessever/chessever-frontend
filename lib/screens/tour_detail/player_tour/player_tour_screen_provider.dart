import 'package:chessever2/repository/local_storage/tournament/tour_local_storage.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
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
      // 🧩 Step 1: Get tournament players from local storage
      final allTours = await ref
          .read(tourLocalStorageProvider)
          .getTours(groupBroadcastId);

      final selectedTours = allTours.where((e) => e.id == tourId).toList();
      var tournamentPlayers = <TournamentPlayer>[];

      for (final tour in selectedTours) {
        tournamentPlayers.addAll(tour.players);
      }

      // Remove duplicates safely
      tournamentPlayers = tournamentPlayers.toSet().toList();

      final gamesScreenData = ref.read(gamesTourScreenProvider);
      final allGames = gamesScreenData.value?.gamesTourModels ?? [];

      for (int i = 0; i < tournamentPlayers.length; i++) {
        final player = tournamentPlayers[i];

        GamesTourModel? relatedGame;
        try {
          relatedGame = allGames.firstWhere((g) {
            final playerName = player.name.trim().toLowerCase();
            final whiteGamePlayerName = g.whitePlayer.name.toLowerCase();
            final blackGamePlayerName = g.blackPlayer.name.toLowerCase();
            return isSamePlayer(playerName, whiteGamePlayerName) ||
                isSamePlayer(playerName, blackGamePlayerName);
          });
        } catch (e, _) {
          relatedGame = null;
        }

        if (relatedGame == null) continue;

        // Find the correct player card (white or black)
        final card =
            relatedGame.whitePlayer.name.trim().toLowerCase() ==
                    player.name.trim().toLowerCase()
                ? relatedGame.whitePlayer
                : relatedGame.blackPlayer;

        // Update only missing/null fields
        tournamentPlayers[i] = player.copyWith(
          federation:
              (player.federation != null &&
                      player.federation!.trim().isNotEmpty)
                  ? player.federation
                  : (card.federation.trim().isNotEmpty
                      ? card.federation
                      : player.federation),
          title:
              (player.title != null && player.title!.trim().isNotEmpty)
                  ? player.title
                  : (card.title.trim().isNotEmpty ? card.title : player.title),
          rating:
              (player.rating != null && player.rating! > 0)
                  ? player.rating
                  : (card.rating > 0 ? card.rating : player.rating),
          fideId:
              (player.fideId != null && player.fideId! > 0)
                  ? player.fideId
                  : card.fideId ?? player.fideId,
        );
      }

      // 🧩 Step 4: Calculate scores and games played
      for (int i = 0; i < tournamentPlayers.length; i++) {
        final player = tournamentPlayers[i];

        final playerGames =
            allGames
                .where(
                  (game) =>
                      game.whitePlayer.name.trim().toLowerCase() ==
                          player.name.trim().toLowerCase() ||
                      game.blackPlayer.name.trim().toLowerCase() ==
                          player.name.trim().toLowerCase(),
                )
                .toList();

        double calculatedScore = 0.0;
        int gamesPlayed = 0;

        for (final game in playerGames) {
          // Skip ongoing/unknown games
          if (game.gameStatus == GameStatus.ongoing ||
              game.gameStatus == GameStatus.unknown)
            continue;

          gamesPlayed++;
          final isWhite =
              game.whitePlayer.name.trim().toLowerCase() ==
              player.name.trim().toLowerCase();

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

        // Update player with new score and games played
        tournamentPlayers[i] = player.copyWith(
          score: calculatedScore,
          played: gamesPlayed,
        );
      }

      // 🧩 Step 5: Sort players by score (desc) and games played (desc)
      tournamentPlayers.sort((a, b) {
        final aScore = double.tryParse(a.scoreString) ?? a.score ?? 0.0;
        final bScore = double.tryParse(b.scoreString) ?? b.score ?? 0.0;

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

  bool isSamePlayer(String? name1, String? name2) {
    if (name1 == null || name2 == null) return false;

    String normalize(String name) => name
        .toLowerCase()
        .replaceAll(',', '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .join(' ');

    final n1 = normalize(name1);
    final n2 = normalize(name2);

    if (n1 == n2) return true;

    // Handle "First Last" vs "Last First"
    final parts1 = n1.split(' ');
    final parts2 = n2.split(' ');

    if (parts1.length == 2 && parts2.length == 2) {
      return (parts1[0] == parts2[1] && parts1[1] == parts2[0]);
    }

    return false;
  }
}

final tournamentFavoritePlayersProvider =
    FutureProvider<List<PlayerStandingModel>>((ref) async {
      final favoritesService = ref.read(favoriteStandingsPlayerService);
      return await favoritesService.getFavoritePlayers();
    });
