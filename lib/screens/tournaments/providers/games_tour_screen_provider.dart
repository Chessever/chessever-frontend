import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/providers/games_app_bar_provider.dart';
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

  Future<void> _init() async {
    final aboutTourModel = ref.read(aboutTourModelProvider)!;
    final allGames = await ref
        .read(gamesLocalStorage)
        .getGames(aboutTourModel.id);

    if (roundId != null) {
      var games = allGames.where((e) => e.roundId.contains(roundId!)).toList();
      final gamesTourModels = List.generate(
        games.length,
        (index) => GamesTourModel.fromGame(games[index]),
      );
      state = AsyncValue.data(gamesTourModels);
    } else {
      final gamesTourModels = List.generate(
        allGames.length,
        (index) => GamesTourModel.fromGame(allGames[index]),
      );
      state = AsyncValue.data(gamesTourModels);
    }
  }

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
