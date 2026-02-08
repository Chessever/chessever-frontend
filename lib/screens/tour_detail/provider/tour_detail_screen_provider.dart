import 'dart:async';

import 'package:chessever2/repository/local_storage/tournament/tour_local_storage.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/interface/itour_detail_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_repo_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tourDetailScreenProvider = StateNotifierProvider<
  _TourDetailScreenNotifier,
  AsyncValue<TourDetailViewModel>
>((ref) {
  final groupBroadcast = ref.watch(selectedBroadcastModelProvider);

  // Handle null case - return a notifier that will show loading/error state
  if (groupBroadcast == null) {
    return _TourDetailScreenNotifier.loading(ref);
  }

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

  // Loading constructor for when broadcast is not yet available
  _TourDetailScreenNotifier.loading(this.ref)
    : groupBroadcast = GroupBroadcast(
        id: '',
        createdAt: DateTime.now(),
        name: '',
        search: [],
      ),
      super(const AsyncValue.loading());

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
      // Check if any new tour IDs appeared that we don't have yet
      final currentTourIds = currentState.tours.map((t) => t.tour.id).toSet();
      final hasNewTours = newLiveTourIds.any((id) => !currentTourIds.contains(id));

      // If new tours appeared, reload everything to fetch them
      if (hasNewTours) {
        debugPrint(
          '🔄 TourDetailScreenNotifier: New tours detected in live_tour_ids! Reloading...',
        );
        loadTourDetails();
        return;
      }

      final now = DateTime.now();
      final updatedTourModels =
          currentState.tours.map((tourModel) {
            final tour = tourModel.tour;

            // Handle tours with empty dates (common for TCEC, CCC, and some imports)
            if (tour.dates.isEmpty) {
              final newRoundStatus = newLiveTourIds.contains(tour.id)
                  ? RoundStatus.live
                  : RoundStatus.completed;
              return TourModel(tour: tour, roundStatus: newRoundStatus);
            }

            final startDate = tour.dates.first;
            final endDate = tour.dates.last;
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

      final selectedTour = await determineSelectedTour(
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
  Future<void> updateSelection(String tourId) async {
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

      // ✅ Save the user's selection for future sessions (ensure persistence before any reloads)
      try {
        await ref
            .read(tourDetailRepoProvider)
            .saveSelectedTourId(
              groupEventId: groupBroadcast.id,
              tourId: tourId,
            );
      } catch (e) {
        logWarning('Failed to persist selected tour: $e');
      }
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
    // Handle tours with empty dates - still show them with a computed status
    // This is common for computer chess events (TCEC, CCC) and some imports
    if (tour.dates.isEmpty) {
      logWarning('Tour ${tour.id} has empty dates, using fallback status');
      // Check if it's live first, otherwise mark as completed (most likely scenario)
      final roundStatus = liveTourIds.contains(tour.id)
          ? RoundStatus.live
          : RoundStatus.completed;
      return TourModel(tour: tour, roundStatus: roundStatus);
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
  Future<Tour> determineSelectedTour(
    List<TourModel> tourModels,
    TourDetailViewModel? currentState,
    List<String> liveTourIds,
  ) async {
    // 1️⃣ If user already selected a tour during this session, keep it.
    final currentSelectedId = currentState?.aboutTourModel.id;
    if (currentSelectedId != null && currentSelectedId.isNotEmpty) {
      final currentModel = findTourModel(tourModels, currentSelectedId);
      if (currentModel != null) {
        return currentModel.tour;
      }
    }

    // 2️⃣ If user previously selected a tour during this session (stored locally)
    final savedTourId = await ref
        .read(tourDetailRepoProvider)
        .getSelectedTourId(groupBroadcast.id);

    if (savedTourId != null) {
      final savedModel = findTourModel(tourModels, savedTourId);
      if (savedModel != null) {
        return savedModel.tour;
      }
    }

    // 3️⃣ Prefer live tours — a tour with active games always takes priority
    final liveModels =
        tourModels
            .where((model) => liveTourIds.contains(model.tour.id))
            .toList();

    if (liveModels.isNotEmpty) {
      // If multiple are live, pick the one that started most recently
      if (liveModels.length > 1) {
        liveModels.sort((a, b) {
          final aDate = a.tour.dates.isNotEmpty ? a.tour.dates.first : DateTime(1970);
          final bDate = b.tour.dates.isNotEmpty ? b.tour.dates.first : DateTime(1970);
          return bDate.compareTo(aDate);
        });
      }
      return liveModels.first.tour;
    }

    // 4️⃣ No live tour — select the tour with the highest avgElo
    final toursWithElo =
        tourModels.where((model) => model.tour.avgElo != null).toList();

    if (toursWithElo.isNotEmpty) {
      toursWithElo.sort((a, b) => b.tour.avgElo!.compareTo(a.tour.avgElo!));
      return toursWithElo.first.tour;
    }

    // 5️⃣ If no live tours, pick most recently completed tour
    final completedTours =
        tourModels
            .where((model) => model.roundStatus == RoundStatus.completed)
            .toList()
          ..sort((a, b) {
            // Handle tours with empty dates (use epoch as fallback)
            final aDate = a.tour.dates.isNotEmpty ? a.tour.dates.last : DateTime(1970);
            final bDate = b.tour.dates.isNotEmpty ? b.tour.dates.last : DateTime(1970);
            return bDate.compareTo(aDate);
          });

    if (completedTours.isNotEmpty) {
      return completedTours.first.tour;
    }

    // 6️⃣ Fallback: first tour
    return tourModels.first.tour;
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
