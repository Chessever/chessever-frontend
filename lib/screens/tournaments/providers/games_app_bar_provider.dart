import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/screens/tournaments/model/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tournaments/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tournaments/providers/tour_detail_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Stores the currently selected round ID and whether the user has selected it
final userSelectedRoundProvider =
    StateProvider<({String id, bool userSelected})?>((ref) => null);

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

      // Default to first round
      String selectedId = gamesAppBarModels.first.id;
      bool userSelectedId = false;

      // Check if user had previously selected a round
      final userSelection = ref.read(userSelectedRoundProvider);
      if (userSelection != null && userSelection.userSelected) {
        selectedId = userSelection.id;
        userSelectedId = true;
      } else {
        // Auto-select a live round if available
        for (final model in gamesAppBarModels) {
          if (liveRounds.contains(model.id)) {
            selectedId = model.id;
            break;
          }
        }
      }

      state = AsyncValue.data(
        GamesAppBarViewModel(
          gamesAppBarModels: gamesAppBarModels,
          selectedId: selectedId,
          userSelectedId: userSelectedId,
        ),
      );
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  void selectNewRound(GamesAppBarModel gamesAppBarModel) {
    // Persist user selection
    ref.read(userSelectedRoundProvider.notifier).state = (
      id: gamesAppBarModel.id,
      userSelected: true,
    );

    // Update local state
    state = AsyncValue.data(
      GamesAppBarViewModel(
        gamesAppBarModels: state.value!.gamesAppBarModels,
        selectedId: gamesAppBarModel.id,
        userSelectedId: true,
      ),
    );
  }
}
