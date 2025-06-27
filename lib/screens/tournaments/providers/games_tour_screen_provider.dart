import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/tournament_detail_view.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gamesTourScreenProvider = StateNotifierProvider.autoDispose<
  GamesTourScreenProvider,
  AsyncValue<List<GamesTourModel>>
>((ref) => GamesTourScreenProvider(ref));

final selectedRoundProvider = StateProvider<GamesTourModel?>((ref) => null);

class GamesTourScreenProvider
    extends StateNotifier<AsyncValue<List<GamesTourModel>>> {
  GamesTourScreenProvider(this.ref) : super(AsyncValue.loading()) {
    _init();
  }

  final Ref ref;

  Future<void> _init() async {
    final aboutTourModel = ref.read(aboutTourModelProvider)!;

    final round = await ref
        .read(roundRepositoryProvider)
        .getRoundsByTourId('5LW5RS0a');
    print(round.map((e) => print(e.toJson())));
    final games = await ref
        .read(gameRepositoryProvider)
        .getGamesByTourId('5LW5RS0a');
    final gamesTourModels = List.generate(
      games.length,
      (index) => GamesTourModel.fromGame(games[index]),
    );

    state = AsyncValue.data(gamesTourModels);
  }
}
