import 'dart:async';

import 'package:chessever2/repository/local_storage/tournament/tour_local_storage.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/live_tour_id_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/interface/itour_detail_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_repo_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_selection_logic.dart';
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
        final normalizedLiveTourIds = _normalizeLiveTourIds(newLiveTourIds);
        if (listsAreEqual(_currentLiveTourIds, normalizedLiveTourIds)) {
          return;
        }

        _currentLiveTourIds = normalizedLiveTourIds;

        final currentState = state.valueOrNull;
        if (currentState != null) {
          updateStateWithNewLiveTourIds(currentState, normalizedLiveTourIds);
        }
      });
    });
  }

  @override
  bool listsAreEqual(List<String> list1, List<String> list2) {
    final normalized1 = _normalizeLiveTourIds(list1);
    final normalized2 = _normalizeLiveTourIds(list2);
    if (normalized1.length != normalized2.length) return false;
    for (var i = 0; i < normalized1.length; i++) {
      if (normalized1[i] != normalized2[i]) return false;
    }
    return true;
  }

  @override
  void updateStateWithNewLiveTourIds(
    TourDetailViewModel currentState,
    List<String> newLiveTourIds,
  ) {
    try {
      final relevantLiveTourIds = _liveTourIdsForTours(
        newLiveTourIds,
        currentState.tours,
      );

      // `live_tour_ids` is global. Ignore IDs from other events, otherwise every
      // settings tick for another live tournament recreates this event view.
      if (listsAreEqual(currentState.liveTourIds, relevantLiveTourIds)) {
        return;
      }

      final now = DateTime.now();
      final updatedTourModels =
          currentState.tours.map((tourModel) {
            final tour = tourModel.tour;

            // Handle tours with empty dates (common for TCEC, CCC, and some imports)
            if (tour.dates.isEmpty) {
              final newRoundStatus =
                  relevantLiveTourIds.contains(tour.id)
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
              relevantLiveTourIds,
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
          findBestTour(updatedTourModels, relevantLiveTourIds).tour;

      final updatedViewModel = TourDetailViewModel(
        aboutTourModel: AboutTourModel.fromTour(selectedTour),
        liveTourIds: relevantLiveTourIds,
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
      final liveTourIds = _normalizeLiveTourIds(
        liveTourIdAsync.valueOrNull ?? <String>[],
      );
      _currentLiveTourIds = liveTourIds;

      final tours = isVirtualGamebaseId(groupBroadcast.id)
          ? await _loadVirtualTours(groupBroadcast.id)
          : await ref
              .read(tourLocalStorageProvider)
              .getTours(groupBroadcast.id);

      if (tours.isEmpty) {
        setDataState(
          TourDetailViewModel(
            aboutTourModel: AboutTourModel.empty(),
            liveTourIds: const <String>[],
            tours: [],
          ),
        );
        return;
      }

      final tourModels = await processTours(tours, liveTourIds);
      final relevantLiveTourIds = _liveTourIdsForTours(liveTourIds, tourModels);

      if (tourModels.isEmpty) {
        setDataState(
          TourDetailViewModel(
            aboutTourModel: AboutTourModel.empty(),
            liveTourIds: const <String>[],
            tours: [],
          ),
        );
        return;
      }

      final selectedTour = await determineSelectedTour(
        tourModels,
        state.valueOrNull,
        relevantLiveTourIds,
      );
      final tourDetailViewModel = createViewModel(
        selectedTour,
        tourModels,
        relevantLiveTourIds,
      );

      setDataState(tourDetailViewModel);
    } catch (e, st) {
      setErrorState(e, st);
    }
  }

  /// Tours for a synthesized gamebase-only event (sentinel broadcast id).
  /// Returns one synthetic tour built from the cached gamebase event view.
  Future<List<Tour>> _loadVirtualTours(String broadcastId) async {
    final eventName = eventNameFromVirtualId(broadcastId);
    if (eventName == null) return const <Tour>[];
    final view = await ref.read(gamebaseEventViewProvider(eventName).future);
    if (view == null) return const <Tour>[];
    return virtualToursFromView(view);
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
        _liveTourIdsForTours(_currentLiveTourIds, currentState.tours),
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
      final roundStatus =
          liveTourIds.contains(tour.id)
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
    return calculateTourRoundStatus(
      tourId: tourId,
      now: now,
      startDate: startDate,
      endDate: endDate,
      liveTourIds: liveTourIds,
    );
  }

  @override
  Future<Tour> determineSelectedTour(
    List<TourModel> tourModels,
    TourDetailViewModel? currentState,
    List<String> liveTourIds,
  ) async {
    final currentSelectedId = currentState?.aboutTourModel.id;

    String? savedTourId;
    try {
      savedTourId = await ref
          .read(tourDetailRepoProvider)
          .getSelectedTourId(groupBroadcast.id);
    } catch (_) {
      savedTourId = null;
    }

    String? activityTourId;
    try {
      activityTourId = await ref
          .read(gameRepositoryProvider)
          .getMostRelevantTourId(
            tourIds: tourModels.map((m) => m.tour.id).toList(),
          );
    } catch (_) {}

    return selectDefaultTour(
      tourModels: tourModels,
      liveTourIds: liveTourIds,
      currentSelectedId: currentSelectedId,
      savedTourId: savedTourId,
      activityTourId: activityTourId,
    );
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
    final tour = findTourById(tourModels, tourId);
    if (tour == null) {
      return null;
    }
    return tourModels.where((model) => model.tour.id == tour.id).firstOrNull;
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

List<String> _normalizeLiveTourIds(Iterable<String> ids) {
  final unique =
      <String>{
        for (final id in ids)
          if (id.trim().isNotEmpty) id.trim(),
      }.toList();
  unique.sort();
  return List<String>.unmodifiable(unique);
}

List<String> _liveTourIdsForTours(
  Iterable<String> liveTourIds,
  Iterable<TourModel> tours,
) {
  final knownTourIds = {for (final tourModel in tours) tourModel.tour.id};
  return _normalizeLiveTourIds(
    liveTourIds.where((id) => knownTourIds.contains(id)),
  );
}
