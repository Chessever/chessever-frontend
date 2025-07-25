import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/providers/pintop_storage.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final countrymanGamesTourScreenProvider = StateNotifierProvider.autoDispose<
  CountrymanGamesTourScreenProvider,
  AsyncValue<GamesScreenModel>
>((ref) {
  final selectedCountry = ref.read(countryDropdownProvider).value?.countryCode;

  return CountrymanGamesTourScreenProvider(
    ref: ref,
    currentCountry: selectedCountry,
  );
});

class CountrymanGamesTourScreenProvider
    extends StateNotifier<AsyncValue<GamesScreenModel>> {
  CountrymanGamesTourScreenProvider({
    required this.ref,
    required this.currentCountry,
  }) : super(AsyncValue.loading()) {
    _init();
  }

  final Ref ref;
  final String? currentCountry;

  Future<void> _init() async {
    final initialGames = await ref
        .read(gamesLocalStorage)
        .getCountrymanGames('USA'); // or currentCountry ?? 'USA'

    final pinnedIds =
        await ref.read(pinnedGamesStorageProvider).getPinnedGameIds();

    // Sort initial games: pinned on top
    initialGames.sort((a, b) {
      final aPinned = pinnedIds.contains(a.id);
      final bPinned = pinnedIds.contains(b.id);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      return 0;
    });

    final gamesTourModels =
        initialGames.map((game) => GamesTourModel.fromGame(game)).toList();

    state = AsyncValue.data(
      GamesScreenModel(
        gamesTourModels: gamesTourModels,
        pinnedGamedIs: pinnedIds,
      ),
    );

    /// ✅ Listen for full isolate-parsed games
    ref.listen<List<Games>>(fullGamesProvider, (previous, next) async {
      if (next.length > initialGames.length) {
        final pinnedIds =
            await ref.read(pinnedGamesStorageProvider).getPinnedGameIds();

        final sortedGames = [...next]..sort((a, b) {
          final aPinned = pinnedIds.contains(a.id);
          final bPinned = pinnedIds.contains(b.id);
          if (aPinned && !bPinned) return -1;
          if (!aPinned && bPinned) return 1;
          return 0;
        });

        final updatedModels =
            sortedGames.map((game) => GamesTourModel.fromGame(game)).toList();

        state = AsyncValue.data(
          GamesScreenModel(
            gamesTourModels: updatedModels,
            pinnedGamedIs: pinnedIds,
          ),
        );
      }
    });
  }

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

  // TODO(dev): Not implemented yet, only returns a default all games list
  Future<void> searchGames(String query) async {
    if (query.isNotEmpty && currentCountry != null) {
      final allGames = await ref
          .read(gamesLocalStorage)
          .getCountrymanGames('USA');

      var games = allGames;

      final gamesTourModels = List.generate(
        games.length,
        (index) => GamesTourModel.fromGame(games[index]),
      );

      state = AsyncValue.data(
        GamesScreenModel(gamesTourModels: gamesTourModels, pinnedGamedIs: []),
      );
    }
  }

  Future<void> refreshGames() async {
    await _init();
  }
}
