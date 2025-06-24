import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/tournament_detail_view.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gamesTourScreenProvider = StateNotifierProvider.autoDispose<
  GamesTourScreenProvider,
  AsyncValue<List<GamesTourModel>>
>((ref) => GamesTourScreenProvider(ref));

class GamesTourScreenProvider
    extends StateNotifier<AsyncValue<List<GamesTourModel>>> {
  GamesTourScreenProvider(this.ref) : super(AsyncValue.loading()) {
    _init();
  }

  final Ref ref;

  Future<void> _init() async {
    final aboutTourModel = ref.read(aboutTourModelProvider)!;
    final games = await ref
        .read(gameRepositoryProvider)
        .getGamesByTourId(aboutTourModel.id);
    final gamesTourModels = List.generate(
      games.length,
      (index) => GamesTourModel.fromGames(games[index]),
    );
    state = AsyncValue.data(gamesTourModels);
  }
}
