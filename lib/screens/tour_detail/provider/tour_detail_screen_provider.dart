import 'package:chessever2/repository/local_storage/tournament/tour_local_storage.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/interface/itour_detail_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// State providers
final selectedTourIdProvider = StateProvider<String?>((ref) => null);

final tourDetailScreenProvider = StateNotifierProvider.autoDispose<
  TourDetailScreenNotifier,
  AsyncValue<TourDetailViewModel>
>((ref) {
  final groupBroadcast = ref.read(selectedBroadcastModelProvider)!;
  final liveTourIdAsync = ref.watch(liveTourIdProvider);
  final liveTourId = liveTourIdAsync.valueOrNull ?? <String>[];

  return TourDetailScreenNotifier(
    ref: ref,
    groupBroadcast: groupBroadcast,
    liveTourId: liveTourId,
  );
});

// Main provider implementation
class TourDetailScreenNotifier
    extends StateNotifier<AsyncValue<TourDetailViewModel>>
    implements ITourDetailProvider {
  TourDetailScreenNotifier({
    required this.ref,
    required this.groupBroadcast,
    required this.liveTourId,
  }) : super(const AsyncValue.loading()) {
    _initialize();
  }

  final Ref ref;
  final GroupBroadcast groupBroadcast;
  final List<String> liveTourId;

  // Private initialization method
  void _initialize() {
    loadTourDetails();
  }

  @override
  @override
  Future<void> loadTourDetails() async {
    if (!mounted) return;

    try {
      final tours = await ref
          .read(tourLocalStorageProvider)
          .getTours(groupBroadcast.id);

      if (tours.isEmpty) {
        _setDataState(
          TourDetailViewModel(
            aboutTourModel: AboutTourModel.empty(),
            liveTourIds: liveTourId,
            tours: [],
          ),
        );
        return;
      }

      final tourModels = await _processTours(tours);

      if (tourModels.isEmpty) {
        _setDataState(
          TourDetailViewModel(
            aboutTourModel: AboutTourModel.empty(),
            liveTourIds: liveTourId,
            tours: [],
          ),
        );
        return;
      }

      final selectedTour = _determineSelectedTour(tourModels);
      final tourDetailViewModel = _createViewModel(selectedTour, tourModels);

      _setDataState(tourDetailViewModel);
    } catch (e, st) {
      _setErrorState(e, st);
    }
  }

  @override
  void updateSelection(String tourId) {
    final currentState = state.valueOrNull;
    if (currentState == null) {
      _logWarning('Cannot update selection: current state is null');
      return;
    }

    try {
      final selectedTourModel = _findTourModel(currentState.tours, tourId);
      if (selectedTourModel == null) {
        _logWarning('Cannot find tour with ID: $tourId');
        return;
      }

      _updateSelectedTourId(tourId);
      final updatedViewModel = _createViewModelFromExisting(
        currentState,
        selectedTourModel.tour,
      );
      _setDataState(updatedViewModel);
    } catch (e, st) {
      _setErrorState(e, st);
    }
  }

  @override
  Future<void> refreshTourDetails() async {
    await loadTourDetails();
  }

  // Private helper methods
  Future<List<TourModel>> _processTours(List<Tour> tours) async {
    final tourModels = <TourModel>[];
    final now = DateTime.now();

    for (final tour in tours) {
      try {
        final tourModel = _processSingleTour(tour, now);
        if (tourModel != null) {
          tourModels.add(tourModel);
        }
      } catch (e) {
        _logWarning('Error processing tour ${tour.id}: $e');
      }
    }

    return tourModels;
  }

  TourModel? _processSingleTour(Tour tour, DateTime now) {
    if (tour.dates.isEmpty) {
      _logWarning('Tour ${tour.id} has empty dates, skipping');
      return null;
    }

    final startDate = tour.dates.first;
    final endDate = tour.dates.last;
    final roundStatus = _calculateRoundStatus(tour.id, now, startDate, endDate);

    return TourModel(
      tour: tour,
      roundStatus: roundStatus,
    );
  }

  RoundStatus _calculateRoundStatus(
    String tourId,
    DateTime now,
    DateTime startDate,
    DateTime endDate,
  ) {
    if (liveTourId.contains(tourId)) {
      return RoundStatus.live;
    } else if (now.isBefore(startDate)) {
      return RoundStatus.upcoming;
    } else if (now.isAfter(endDate)) {
      return RoundStatus.completed;
    } else {
      return RoundStatus.ongoing;
    }
  }

  Tour _determineSelectedTour(List<TourModel> tourModels) {
    final currentSelectedId = ref.read(selectedTourIdProvider);

    // Check if current selection is still valid
    if (currentSelectedId != null) {
      final validSelectedTour = _findTourModel(tourModels, currentSelectedId);
      if (validSelectedTour != null) {
        return validSelectedTour.tour;
      }
    }

    // Find best tour based on priority
    final selectedModel = _findBestTour(tourModels);
    _updateSelectedTourId(selectedModel.tour.id);

    return selectedModel.tour;
  }

  TourModel _findBestTour(List<TourModel> tourModels) {
    // Priority: live tours > ongoing > upcoming > completed
    final liveTour =
        tourModels
            .where((model) => liveTourId.contains(model.tour.id))
            .firstOrNull;

    final ongoingTour =
        tourModels
            .where((model) => model.roundStatus == RoundStatus.ongoing)
            .firstOrNull;

    final upcomingTour =
        tourModels
            .where((model) => model.roundStatus == RoundStatus.upcoming)
            .firstOrNull;

    return liveTour ?? ongoingTour ?? upcomingTour ?? tourModels.first;
  }

  TourModel? _findTourModel(List<TourModel> tourModels, String tourId) {
    return tourModels.where((model) => model.tour.id == tourId).firstOrNull;
  }

  TourDetailViewModel _createViewModel(
    Tour selectedTour,
    List<TourModel> tourModels,
  ) {
    return TourDetailViewModel(
      aboutTourModel: AboutTourModel.fromTour(selectedTour),
      liveTourIds: liveTourId,
      tours: tourModels,
    );
  }

  TourDetailViewModel _createViewModelFromExisting(
    TourDetailViewModel currentState,
    Tour selectedTour,
  ) {
    return TourDetailViewModel(
      aboutTourModel: AboutTourModel.fromTour(selectedTour),
      liveTourIds: liveTourId,
      tours: currentState.tours,
    );
  }

  void _updateSelectedTourId(String tourId) {
    ref.read(selectedTourIdProvider.notifier).state = tourId;
  }

  void _setDataState(TourDetailViewModel viewModel) {
    if (mounted) {
      state = AsyncValue.data(viewModel);
    }
  }

  void _setErrorState(Object error, [StackTrace? stackTrace]) {
    if (mounted) {
      state = AsyncValue.error(
        error is String ? Exception(error) : error,
        stackTrace ?? StackTrace.current,
      );
    }
  }

  void _logWarning(String message) {
    print('TourDetailScreenNotifier: $message');
  }
}
