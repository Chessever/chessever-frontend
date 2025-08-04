import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/screens/tournaments/model/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tournaments/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tournaments/providers/tour_detail_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gamesAppBarProvider = AutoDisposeStateNotifierProvider<
  GamesAppBarNotifier,
  AsyncValue<GamesAppBarViewModel>
>((ref) {
  final tourId = ref.watch(selectedTourIdProvider)!;
  var liveRounds = <String>[];
  ref
      .watch(liveRoundsIdProvider)
      .when(
        data: (data) {
          liveRounds = data;
        },
        error: (e, _) {},
        loading: () {},
      );
  return GamesAppBarNotifier(ref: ref, tourId: tourId, liveRounds: liveRounds);
});

class GamesAppBarNotifier
    extends StateNotifier<AsyncValue<GamesAppBarViewModel>> {
  GamesAppBarNotifier({
    required this.ref,
    required this.tourId,
    required this.liveRounds,
  }) : super(AsyncValue.loading()) {
    _init();
  }

  final Ref ref;
  final String tourId;
  final List<String> liveRounds;

  Future<void> _init() async {
    try {
      final rounds = await ref
          .read(roundRepositoryProvider)
          .getRoundsByTourId(tourId);
      final gamesAppBarModels =
          rounds
              .map((round) => GamesAppBarModel.fromRound(round, liveRounds))
              .toList();
      var selectedId = gamesAppBarModels.first.id;
      for (var a = 0; a < gamesAppBarModels.length; a++) {
        if (liveRounds.contains(gamesAppBarModels[a].id)) {
          selectedId = gamesAppBarModels[a].id;
          break;
        }
      }
      state = AsyncValue.data(
        GamesAppBarViewModel(
          gamesAppBarModels: gamesAppBarModels,
          selectedId: selectedId,
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
