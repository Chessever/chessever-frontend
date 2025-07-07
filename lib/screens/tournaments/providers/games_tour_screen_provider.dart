import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tournaments/providers/pintop_storage.dart';
import 'package:chessever2/screens/tournaments/tournament_detail_view.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gamesTourScreenProvider = StateNotifierProvider.autoDispose<
  GamesTourScreenProvider,
  AsyncValue<List<GamesTourModel>>
>((ref) {
  final selectedRound = ref.watch(gamesAppBarProvider).value?.selectedId;
  return GamesTourScreenProvider(ref: ref, roundId: selectedRound);
});

class GamesTourScreenProvider
    extends StateNotifier<AsyncValue<List<GamesTourModel>>> {
  GamesTourScreenProvider({required this.ref, required this.roundId})
    : super(AsyncValue.loading()) {
    _init();
  }

  final Ref ref;
  final String? roundId;
  final pinnedStorage = PinnedGamesStorage();

  Future<void> togglePinGame(String gameId) async {
    print('Toggle pin called for gameId: $gameId');

    final pinnedIds = await pinnedStorage.getPinnedGameIds();
    print('Currently pinned IDs before toggle: $pinnedIds');

    if (pinnedIds.contains(gameId)) {
      print('Game is already pinned, removing pin for gameId: $gameId');
      await pinnedStorage.removePinnedGameId(gameId);
    } else {
      print('Game is not pinned, adding pin for gameId: $gameId');
      await pinnedStorage.addPinnedGameId(gameId);
    }

    final updatedPinnedIds = await pinnedStorage.getPinnedGameIds();
    print('Pinned IDs after toggle: $updatedPinnedIds');

    print('Refreshing games list...');
    await _init();
    print('Games list refreshed');
  }

  Future<void> unpinAllGames() async {
    print("Unpin All tapped");
    await pinnedStorage.clearAllPinnedGames();
    await _init();
  }

  Future<void> _init() async {
    final aboutTourModel = ref.read(aboutTourModelProvider)!;
    final allGames = await ref
        .read(gamesLocalStorage)
        .getGames(aboutTourModel.id);

    print("All Games:");
    for (final game in allGames) {
      print('''
  ▶ Game ID: ${game.id}
  ▶ Round ID: ${game.roundId}
  
  ▶ fen: ${game.fen}
  
  ''');
    }
    final pinnedIds = await pinnedStorage.getPinnedGameIds();

    final selectedGames =
        roundId != null
            ? allGames.where((e) => e.roundId.contains(roundId!)).toList()
            : allGames;

    // Sort: pinned games on top
    selectedGames.sort((a, b) {
      final aPinned = pinnedIds.contains(a.id);
      final bPinned = pinnedIds.contains(b.id);

      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      return 0;
    });

    final gamesTourModels =
        selectedGames.map((game) => GamesTourModel.fromGame(game)).toList();

    state = AsyncValue.data(gamesTourModels);
  }

  // Future<void> _init() async {
  //   final aboutTourModel = ref.read(aboutTourModelProvider)!;
  //   final allGames = await ref
  //       .read(gamesLocalStorage)
  //       .getGames(aboutTourModel.id);

  //   if (roundId != null) {
  //     var games = allGames.where((e) => e.roundId.contains(roundId!)).toList();
  //     final gamesTourModels = List.generate(
  //       games.length,
  //       (index) => GamesTourModel.fromGame(games[index]),
  //     );
  //     state = AsyncValue.data(gamesTourModels);
  //   } else {
  //     final gamesTourModels = List.generate(
  //       allGames.length,
  //       (index) => GamesTourModel.fromGame(allGames[index]),
  //     );
  //     state = AsyncValue.data(gamesTourModels);
  //   }
  // }

  Future<void> searchGames(String query) async {
    if (query.isNotEmpty && roundId != null) {
      final aboutTourModel = ref.read(aboutTourModelProvider)!;

      final allGames = await ref
          .read(gamesLocalStorage)
          .searchGamesByName(tourId: aboutTourModel.id, query: query);

      var games = allGames.where((e) => e.roundId.contains(roundId!)).toList();
      final gamesTourModels = List.generate(
        games.length,
        (index) => GamesTourModel.fromGame(games[index]),
      );

      state = AsyncValue.data(gamesTourModels);
    }
  }

  Future<void> refreshGames() async {
    final aboutTourModel = ref.read(aboutTourModelProvider)!;

    final allGames = await ref
        .read(gamesLocalStorage)
        .refresh(aboutTourModel.id);

    final games = allGames.where((e) => e.roundId.contains(roundId!)).toList();
    final gamesTourModels = List.generate(
      games.length,
      (index) => GamesTourModel.fromGame(games[index]),
    );

    state = AsyncValue.data(gamesTourModels);
  }
}
