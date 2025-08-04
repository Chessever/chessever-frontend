import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tournaments/model/about_tour_model.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tournaments/providers/pintop_storage.dart';
import 'package:chessever2/screens/tournaments/providers/tour_detail_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gamesTourScreenProvider = StateNotifierProvider.autoDispose<
    GamesTourScreenProvider,
    AsyncValue<GamesScreenModel>
>((ref) {
  final selectedRound = ref.watch(gamesAppBarProvider).value?.selectedId;
  final aboutTourModel =
      ref.watch(tourDetailScreenProvider).value!.aboutTourModel;
  return GamesTourScreenProvider(
    ref: ref,
    roundId: selectedRound,
    aboutTourModel: aboutTourModel,
  );
});

class GamesTourScreenProvider
    extends StateNotifier<AsyncValue<GamesScreenModel>> {
  GamesTourScreenProvider({
    required this.ref,
    required this.roundId,
    required this.aboutTourModel,
  }) : super(AsyncValue.loading()) {
    _init();
  }

  final Ref ref;
  final String? roundId;
  final AboutTourModel aboutTourModel;

  Future<void> togglePinGame(String gameId) async {
    print('Toggle pin called for gameId: $gameId');

    final pinnedIds =
    await ref.read(pinnedGamesStorageProvider).getPinnedGameIds();
    print('Currently pinned IDs before toggle: $pinnedIds');

    if (pinnedIds.contains(gameId)) {
      print('Game is already pinned, removing pin for gameId: $gameId');
      await ref.read(pinnedGamesStorageProvider).removePinnedGameId(gameId);
    } else {
      print('Game is not pinned, adding pin for gameId: $gameId');
      await ref.read(pinnedGamesStorageProvider).addPinnedGameId(gameId);
    }

    final updatedPinnedIds =
    await ref.read(pinnedGamesStorageProvider).getPinnedGameIds();
    print('Pinned IDs after toggle: $updatedPinnedIds');

    print('Refreshing games list...');
    await _init();
    print('Games list refreshed');
  }

  Future<void> unpinAllGames() async {
    print("Unpin All tapped");
    await ref.read(pinnedGamesStorageProvider).clearAllPinnedGames();
    await _init();
  }

  Future<void> _updateState(List<Games> allGames) async {
    final pinnedIds = await ref.read(pinnedGamesStorageProvider).getPinnedGameIds();
    final selectedGames = roundId != null
        ? allGames.where((e) => e.roundId.contains(roundId!)).toList()
        : allGames;

    selectedGames.sort((a, b) {
      final aPinned = pinnedIds.contains(a.id);
      final bPinned = pinnedIds.contains(b.id);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      if (a.boardNr != null && b.boardNr != null) return a.boardNr!.compareTo(b.boardNr!);
      if (a.boardNr != null && b.boardNr == null) return -1;
      if (a.boardNr == null && b.boardNr != null) return 1;
      return 0;
    });

    state = AsyncValue.data(GamesScreenModel(
      gamesTourModels: selectedGames.map((game) => GamesTourModel.fromGame(game)).toList(),
      pinnedGamedIs: pinnedIds,
    ));
  }

  Future<void> _init() async {
    final allGames = await ref.read(gamesLocalStorage).fetchAndSaveGames(aboutTourModel.id);
    await _updateState(allGames);
  }

  Future<void> searchGames(String query) async {
    if (query.isNotEmpty && roundId != null) {
      final selectedTourId = ref.watch(selectedTourIdProvider)!;
      final allGames = await ref.read(gamesLocalStorage).searchGamesByName(tourId: selectedTourId, query: query);
      var games = allGames.where((e) => e.roundId.contains(roundId!)).toList();
      final gamesTourModels = List.generate(games.length, (index) => GamesTourModel.fromGame(games[index]));

      state = AsyncValue.data(GamesScreenModel(gamesTourModels: gamesTourModels, pinnedGamedIs: []));
    }
  }

  Future<void> refreshGames() async {
    final allGames = await ref.read(gamesLocalStorage).refresh(aboutTourModel.id);
    await _updateState(allGames);
  }
}