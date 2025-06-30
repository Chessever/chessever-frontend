import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/tournament_detail_view.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gamesTourScreenProvider = StateNotifierProvider.family.autoDispose<
  GamesTourScreenProvider,
  AsyncValue<List<GamesTourModel>>,
  String
>((ref, roundId) {
  return GamesTourScreenProvider(ref: ref, roundId: roundId);
});

class GamesTourScreenProvider
    extends StateNotifier<AsyncValue<List<GamesTourModel>>> {
  GamesTourScreenProvider({required this.ref, required this.roundId})
    : super(AsyncValue.loading()) {
    _init();
  }

  final Ref ref;
  final String roundId;

  Future<void> _init() async {
    final aboutTourModel = ref.read(aboutTourModelProvider)!;

    final allGames = await ref.read(gamesLocalStorage).getGames('5LW5RS0a');

    final games =
        allGames.where((e) => e.roundId.contains(roundId)).toList();
    final gamesTourModels = List.generate(
      games.length,
      (index) => GamesTourModel.fromGame(games[index]),
    );

    state = AsyncValue.data(gamesTourModels);
  }

  Future<void> searchGames(String query) async {
    final aboutTourModel = ref.read(aboutTourModelProvider)!;

    final allGames = await ref
        .read(gamesLocalStorage)
        .searchGamesByName(tourId: '5LW5RS0a', query: query);

    final games = allGames.where((e) => e.roundId.contains(roundId)).toList();
    final gamesTourModels = List.generate(
      games.length,
      (index) => GamesTourModel.fromGame(games[index]),
    );

    state = AsyncValue.data(gamesTourModels);
  }

  Future<void> refreshGames() async {
    final aboutTourModel = ref.read(aboutTourModelProvider)!;

    final allGames = await ref.read(gamesLocalStorage).refresh('5LW5RS0a');

    final games = allGames.where((e) => e.roundId.contains(roundId)).toList();
    final gamesTourModels = List.generate(
      games.length,
      (index) => GamesTourModel.fromGame(games[index]),
    );

    state = AsyncValue.data(gamesTourModels);
  }
}
