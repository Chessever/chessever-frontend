import 'package:chessever2/repository/local_storage/tournament/tour_local_storage.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/screens/tournaments/model/about_tour_model.dart';
import 'package:chessever2/screens/tournaments/model/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tournaments/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tournaments/providers/live_tour_id_provider.dart';
import 'package:chessever2/screens/tournaments/tournament_detail_screen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final selectedTourIdProvider = StateProvider<String?>((ref) => null);

// Optimized provider with better null safety and error handling
final tourDetailScreenProvider = StateNotifierProvider.autoDispose<
  TourDetailScreenProvider,
  AsyncValue<TourDetailViewModel>
>((ref) {
  final groupBroadcast = ref.read(selectedBroadcastModelProvider);

  // Null safety check for groupBroadcast
  if (groupBroadcast == null) {
    throw Exception('Group broadcast is not available');
  }

  // Get live tour IDs with fallback
  final liveTourIdAsync = ref.watch(liveTourIdProvider);
  final liveTourId = liveTourIdAsync.valueOrNull ?? <String>[];

  return TourDetailScreenProvider(
    ref: ref,
    groupBroadcast: groupBroadcast,
    liveTourId: liveTourId,
  );
});

// Error provider for when dependencies are not available
class _ErrorTourDetailScreenProvider
    extends StateNotifier<AsyncValue<TourDetailViewModel>> {
  _ErrorTourDetailScreenProvider(String errorMessage)
    : super(AsyncValue.error(Exception(errorMessage), StackTrace.current));
}

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

  // Cache for optimization
  List<Tour>? _cachedTours;
  String? _lastGroupId;

  Future<void> loadTourDetails() async {
    try {
      // Use cache if same group ID
      List<Tour> tours;

      if (_cachedTours != null && _lastGroupId == groupBroadcast.id) {
        tours = _cachedTours!;
      } else {
        final tourLocalStorage = ref.read(tourLocalStorageProvider);
        tours = await tourLocalStorage.getToursBasedOnGroupId(
          groupBroadcast.id,
        );

        // Cache the results
        _cachedTours = tours;
        _lastGroupId = groupBroadcast.id;
      }

      if (tours.isEmpty) {
        if (mounted) {
          state = AsyncValue.error(
            Exception('No tournaments found for this group'),
            StackTrace.current,
          );
        }
        return;
      }

      final now = DateTime.now();

      // Process tour models with better error handling
      final tourModels = <TourModel>[];

      for (final tour in tours) {
        try {
          // Skip tours with empty dates but log it
          if (tour.dates.isEmpty) {
            print('Warning: Tour ${tour.id} has empty dates, skipping');
            continue;
          }

          final startDate = tour.dates.first;
          final endDate = tour.dates.last;

          RoundStatus roundStatus;

          if (liveTourId.contains(tour.id)) {
            roundStatus = RoundStatus.live;
          } else if (now.isBefore(startDate)) {
            roundStatus = RoundStatus.upcoming;
          } else if (now.isAfter(endDate)) {
            roundStatus = RoundStatus.completed;
          } else {
            roundStatus = RoundStatus.ongoing;
          }

          tourModels.add(
            TourModel(
              tour: tour,
              roundStatus: roundStatus,
            ),
          );
        } catch (e) {
          print('Error processing tour ${tour.id}: $e');
          // Continue with other tours
        }
      }

      if (tourModels.isEmpty) {
        if (mounted) {
          state = AsyncValue.error(
            Exception('No valid tournaments found'),
            StackTrace.current,
          );
        }
        return;
      }

      // Determine selected tour with better logic
      String selectedTourId;
      Tour selectedTour;

      // Check if a tour is already selected and valid
      final currentSelectedId = ref.read(selectedTourIdProvider);
      final validSelectedTour =
          tourModels
              .where((model) => model.tour.id == currentSelectedId)
              .firstOrNull;

      if (validSelectedTour != null) {
        selectedTourId = validSelectedTour.tour.id;
        selectedTour = validSelectedTour.tour;
      } else {
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

        final selectedModel =
            liveTour ?? ongoingTour ?? upcomingTour ?? tourModels.first;

        selectedTourId = selectedModel.tour.id;
        selectedTour = selectedModel.tour;

        // Update the selected tour ID
        ref.read(selectedTourIdProvider.notifier).state = selectedTourId;
      }

      final tourDetailViewModel = TourDetailViewModel(
        aboutTourModel: AboutTourModel.fromTour(selectedTour),
        liveTourIds: liveTourId,
        tours: tourModels,
      );

      if (mounted) {
        state = AsyncValue.data(tourDetailViewModel);
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  void updateSelection(String tourId) {
    try {
      // Safely get current state
      final currentState = state.valueOrNull;
      if (currentState == null) {
        print('Cannot update selection: current state is null');
        return;
      }

      // Find the selected tour
      final selectedTourModel =
          currentState.tours
              .where((model) => model.tour.id == tourId)
              .firstOrNull;

      if (selectedTourModel == null) {
        print('Cannot find tour with ID: $tourId');
        return;
      }

      // Update selected tour ID
      ref.read(selectedTourIdProvider.notifier).state = tourId;

      // Create new view model
      final updatedViewModel = TourDetailViewModel(
        aboutTourModel: AboutTourModel.fromTour(selectedTourModel.tour),
        liveTourIds: liveTourId,
        tours: currentState.tours,
      );

      if (mounted) {
        state = AsyncValue.data(updatedViewModel);
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  // Method to refresh tour details
  Future<void> refreshTourDetails() async {
    try {
      // Clear cache to force fresh data
      _cachedTours = null;
      _lastGroupId = null;

      await loadTourDetails();
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  @override
  void dispose() {
    // Clear cache on dispose
    _cachedTours = null;
    _lastGroupId = null;
    super.dispose();
  }
}
