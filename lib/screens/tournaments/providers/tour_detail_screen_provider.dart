import 'package:chessever2/repository/local_storage/tournament/tour_local_storage.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/screens/tournaments/model/about_tour_model.dart';
import 'package:chessever2/screens/tournaments/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tournaments/providers/live_tour_id_provider.dart';
import 'package:chessever2/screens/tournaments/tournament_detail_view.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tourDetailScreenProvider = StateNotifierProvider.autoDispose<
  TourDetailScreenProvider,
  AsyncValue<TourDetailViewModel>
>((ref) {
  final groupBroadcast = ref.watch(selectedBroadcastModelProvider)!;
  var liveTourId = <String>[];
  ref
      .watch(liveTourIdProvider)
      .when(
        data: (data) {
          liveTourId = data;
        },
        error: (e, _) {},
        loading: () {},
      );
  return TourDetailScreenProvider(
    ref: ref,
    groupBroadcast: groupBroadcast,
    liveTourId: liveTourId,
  );
});

class TourDetailScreenProvider
    extends StateNotifier<AsyncValue<TourDetailViewModel>> {
  TourDetailScreenProvider({
    required this.ref,
    required this.groupBroadcast,
    required this.liveTourId,
  }) : super(const AsyncValue.loading()) {
    loadTourDetails();
  }

  final Ref ref;
  final GroupBroadcast groupBroadcast;
  final List<String> liveTourId;

  Future<void> loadTourDetails() async {
    try {
      final tours = await ref
          .read(tourLocalStorageProvider)
          .getToursBasedOnGroupId(groupBroadcast.id);

      if (tours.isEmpty) return;

      var selectedTourId = tours.first.id;
      var selectedTour = tours.first;
      for (var a = 0; a < tours.length; a++) {
        if (liveTourId.contains(tours[a].id)) {
          selectedTourId = tours[a].id;
          selectedTour = tours[a];
          break;
        }
      }

      final tourEventCardModel = TourDetailViewModel(
        aboutTourModel: AboutTourModel.fromTour(selectedTour),
        liveTourIds: liveTourId,
        selectedTourId: selectedTourId,
        tours: tours,
      );

      state = AsyncValue.data(tourEventCardModel);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  void updateSelection(String tourId) {
    final currentState = state.value!;
    final selectedTour = currentState.tours.firstWhere((e) => e.id == tourId);
    final tourEventCardModel = TourDetailViewModel(
      aboutTourModel: AboutTourModel.fromTour(selectedTour),
      liveTourIds: liveTourId,
      selectedTourId: selectedTour.id,
      tours: currentState.tours,
    );
    state = AsyncValue.data(tourEventCardModel);
  }
}
