import 'package:chessever2/repository/local_storage/tournament/tour_local_storage.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/interface/itour_detail_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tourDetailScreenProvider = StateNotifierProvider<
  _TourDetailScreenNotifier,
  AsyncValue<TourDetailViewModel>
>((ref) {
  final groupBroadcast = ref.watch(selectedBroadcastModelProvider)!;

  return _TourDetailScreenNotifier(ref: ref, groupBroadcast: groupBroadcast);
});

class _TourDetailScreenNotifier
    extends StateNotifier<AsyncValue<TourDetailViewModel>>
    implements
        ITourDetailProvider,
        ITourProcessor,
        ITourSelector,
        IViewModelFactory,
        IStateManager,
        ILiveTourListener {
  _TourDetailScreenNotifier({required this.ref, required this.groupBroadcast})
    : super(const AsyncValue.loading()) {
    setupLiveTourIdListener();
    loadTourDetails();
  }

  final Ref ref;
  final GroupBroadcast groupBroadcast;
  List<String> _currentLiveTourIds = [];

  @override
  void setupLiveTourIdListener() {
    ref.listen<AsyncValue<List<String>>>(liveTourIdProvider, (previous, next) {
      next.whenData((newLiveTourIds) {
        if (listsAreEqual(_currentLiveTourIds, newLiveTourIds)) {
          return;
        }

        _currentLiveTourIds = List.from(newLiveTourIds);

        final currentState = state.valueOrNull;
        if (currentState != null) {
          updateStateWithNewLiveTourIds(currentState, newLiveTourIds);
        }
      });
    });
  }

  @override
  bool listsAreEqual(List<String> list1, List<String> list2) {
    if (list1.length != list2.length) return false;
    for (int i = 0; i < list1.length; i++) {
      if (list1[i] != list2[i]) return false;
    }
    return true;
  }

  @override
  void updateStateWithNewLiveTourIds(
    TourDetailViewModel currentState,
    List<String> newLiveTourIds,
  ) {
    try {
      final now = DateTime.now();
      final updatedTourModels =
          currentState.tours.map((tourModel) {
            final tour = tourModel.tour;
            final startDate =
                tour.dates.isNotEmpty ? tour.dates.first : DateTime.now();
            final endDate =
                tour.dates.isNotEmpty ? tour.dates.last : DateTime.now();
            final newRoundStatus = calculateRoundStatus(
              tour.id,
              now,
              startDate,
              endDate,
              newLiveTourIds,
            );

            return TourModel(tour: tour, roundStatus: newRoundStatus);
          }).toList();

      final currentSelectedTourId = currentState.aboutTourModel.id;
      final updatedSelectedTourModel = findTourModel(
        updatedTourModels,
        currentSelectedTourId,
      );

      final selectedTour =
          updatedSelectedTourModel?.tour ??
          findBestTour(updatedTourModels, newLiveTourIds).tour;

      final updatedViewModel = TourDetailViewModel(
        aboutTourModel: AboutTourModel.fromTour(selectedTour),
        liveTourIds: newLiveTourIds,
        tours: updatedTourModels,
      );

      setDataState(updatedViewModel);
    } catch (e, st) {
      setErrorState(e, st);
    }
  }

  @override
  Future<void> loadTourDetails() async {
    try {
      final liveTourIdAsync = ref.read(liveTourIdProvider);
      final liveTourIds = liveTourIdAsync.valueOrNull ?? <String>[];
      _currentLiveTourIds = List.from(liveTourIds);

      final tours = await ref
          .read(tourLocalStorageProvider)
          .getTours(groupBroadcast.id);

      if (tours.isEmpty) {
        setDataState(
          TourDetailViewModel(
            aboutTourModel: AboutTourModel.empty(),
            liveTourIds: liveTourIds,
            tours: [],
          ),
        );
        return;
      }

      final tourModels = await processTours(tours, liveTourIds);

      if (tourModels.isEmpty) {
        setDataState(
          TourDetailViewModel(
            aboutTourModel: AboutTourModel.empty(),
            liveTourIds: liveTourIds,
            tours: [],
          ),
        );
        return;
      }

      final selectedTour = determineSelectedTour(
        tourModels,
        state.valueOrNull,
        liveTourIds,
      );
      final tourDetailViewModel = createViewModel(
        selectedTour,
        tourModels,
        liveTourIds,
      );

      setDataState(tourDetailViewModel);
    } catch (e, st) {
      setErrorState(e, st);
    }
  }

  @override
  void updateSelection(String tourId) {
    final currentState = state.valueOrNull;
    if (currentState == null) {
      logWarning('Cannot update selection: current state is null');
      return;
    }

    try {
      final selectedTourModel = findTourModel(currentState.tours, tourId);
      if (selectedTourModel == null) {
        logWarning('Cannot find tour with ID: $tourId');
        return;
      }
      final updatedViewModel = createViewModelFromExisting(
        currentState,
        selectedTourModel.tour,
        _currentLiveTourIds,
      );
      setDataState(updatedViewModel);
    } catch (e, st) {
      setErrorState(e, st);
    }
  }

  @override
  Future<void> refreshTourDetails() async {
    await loadTourDetails();
  }

  @override
  Future<List<TourModel>> processTours(
    List<Tour> tours,
    List<String> liveTourIds,
  ) async {
    final tourModels = <TourModel>[];
    final now = DateTime.now();

    for (final tour in tours) {
      try {
        final tourModel = processSingleTour(tour, now, liveTourIds);
        if (tourModel != null) {
          tourModels.add(tourModel);
        }
      } catch (e) {
        logWarning('Error processing tour ${tour.id}: $e');
      }
    }

    return tourModels;
  }

  @override
  TourModel? processSingleTour(
    Tour tour,
    DateTime now,
    List<String> liveTourIds,
  ) {
    if (tour.dates.isEmpty) {
      logWarning('Tour ${tour.id} has empty dates, skipping');
      return null;
    }

    final startDate = tour.dates.first;
    final endDate = tour.dates.last;
    final roundStatus = calculateRoundStatus(
      tour.id,
      now,
      startDate,
      endDate,
      liveTourIds,
    );

    return TourModel(tour: tour, roundStatus: roundStatus);
  }

  @override
  RoundStatus calculateRoundStatus(
    String tourId,
    DateTime now,
    DateTime startDate,
    DateTime endDate,
    List<String> liveTourIds,
  ) {
    if (liveTourIds.contains(tourId)) {
      return RoundStatus.live;
    } else if (now.isBefore(startDate)) {
      return RoundStatus.upcoming;
    } else if (now.isAfter(endDate)) {
      return RoundStatus.completed;
    } else {
      return RoundStatus.ongoing;
    }
  }

  @override
  Tour determineSelectedTour(
    List<TourModel> tourModels,
    TourDetailViewModel? currentState,
    List<String> liveTourIds,
  ) {
    if (currentState?.aboutTourModel != null) {
      final validSelectedTour = findTourModel(
        tourModels,
        currentState!.aboutTourModel.id,
      );
      if (validSelectedTour != null) {
        return validSelectedTour.tour;
      }
    }

    final selectedModel = findBestTour(tourModels, liveTourIds);
    return selectedModel.tour;
  }

  @override
  TourModel findBestTour(List<TourModel> tourModels, List<String> liveTourIds) {
    final liveTour =
        tourModels
            .where((model) => liveTourIds.contains(model.tour.id))
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

  @override
  TourModel? findTourModel(List<TourModel> tourModels, String tourId) {
    return tourModels.where((model) => model.tour.id == tourId).firstOrNull;
  }

  @override
  TourDetailViewModel createViewModel(
    Tour selectedTour,
    List<TourModel> tourModels,
    List<String> liveTourIds,
  ) {
    return TourDetailViewModel(
      aboutTourModel: AboutTourModel.fromTour(selectedTour),
      liveTourIds: liveTourIds,
      tours: tourModels,
    );
  }

  @override
  TourDetailViewModel createViewModelFromExisting(
    TourDetailViewModel currentState,
    Tour selectedTour,
    List<String> liveTourIds,
  ) {
    return TourDetailViewModel(
      aboutTourModel: AboutTourModel.fromTour(selectedTour),
      liveTourIds: liveTourIds,
      tours: currentState.tours,
    );
  }

  @override
  void setDataState(TourDetailViewModel viewModel) {
    state = AsyncValue.data(viewModel);
  }

  @override
  void setErrorState(Object error, [StackTrace? stackTrace]) {
    if (mounted) {
      state = AsyncValue.error(
        error is String ? Exception(error) : error,
        stackTrace ?? StackTrace.current,
      );
    }
  }

  @override
  void logWarning(String message) {
    debugPrint('TourDetailScreenNotifier: $message');
  }
}
