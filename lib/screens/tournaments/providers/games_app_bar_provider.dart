import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/screens/tournaments/model/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tournaments/tournament_detail_view.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gamesAppBarProvider = AutoDisposeStateNotifierProvider<
  GamesAppBarNotifier,
  AsyncValue<GamesAppBarViewModel>
>((ref) => GamesAppBarNotifier(ref));

class GamesAppBarNotifier
    extends StateNotifier<AsyncValue<GamesAppBarViewModel>> {
  GamesAppBarNotifier(this.ref) : super(AsyncValue.loading()) {
    _init();
  }

  final Ref ref;

  Future<void> _init() async {
    try {
      final aboutTourModel = ref.read(aboutTourModelProvider)!;
      final rounds = await ref
          .read(roundRepositoryProvider)
          .getRoundsByTourId(aboutTourModel.id);
      final gamesAppBarModels =
          rounds.map((round) => GamesAppBarModel.fromRound(round)).toList();
      state = AsyncValue.data(
        GamesAppBarViewModel(
          gamesAppBarModels: gamesAppBarModels,
          selectedId: gamesAppBarModels.first.id,
        ),
      );
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void selectNewRound(GamesAppBarModel gamesAppBarModel){
    state = AsyncValue.data(
      GamesAppBarViewModel(
        gamesAppBarModels: state.value!.gamesAppBarModels,
        selectedId: gamesAppBarModel.id,
      ),
    );
  }
}
