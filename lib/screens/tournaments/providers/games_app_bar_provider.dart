import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/screens/tournaments/model/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tournaments/providers/tour_detail_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gamesAppBarProvider = AutoDisposeStateNotifierProvider<
  GamesAppBarNotifier,
  AsyncValue<GamesAppBarViewModel>
>((ref) {
  final tourId = ref.watch(tourDetailScreenProvider).value!.selectedTourId;
  return GamesAppBarNotifier(ref: ref, tourId: tourId);
});

class GamesAppBarNotifier
    extends StateNotifier<AsyncValue<GamesAppBarViewModel>> {
  GamesAppBarNotifier({required this.ref, required this.tourId})
    : super(AsyncValue.loading()) {
    _init();
  }

  final Ref ref;
  final String tourId;

  Future<void> _init() async {
    try {
      final rounds = await ref
          .read(roundRepositoryProvider)
          .getRoundsByTourId(tourId);
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

  void selectNewRound(GamesAppBarModel gamesAppBarModel) {
    state = AsyncValue.data(
      GamesAppBarViewModel(
        gamesAppBarModels: state.value!.gamesAppBarModels,
        selectedId: gamesAppBarModel.id,
      ),
    );
  }
}
