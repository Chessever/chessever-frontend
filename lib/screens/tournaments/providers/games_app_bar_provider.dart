import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/screens/tournaments/model/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tournaments/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/tournaments/providers/tour_detail_screen_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Stores the currently selected round ID and whether the user has selected it
final userSelectedRoundProvider =
    StateProvider<({String id, bool userSelected})?>((ref) => null);

// Optimized provider with better error handling and null safety
final gamesAppBarProvider = AutoDisposeStateNotifierProvider<
  GamesAppBarNotifier,
  AsyncValue<GamesAppBarViewModel>
>((ref) {
  final tourId = ref.read(selectedTourIdProvider);

  // Null safety check for tourId
  if (tourId == null) {
    throw Exception('Tournament ID not available');
  }

  // Get live rounds with fallback
  final liveRoundsAsync = ref.watch(liveRoundsIdProvider);
  final liveRounds = liveRoundsAsync.valueOrNull ?? <String>[];

  return GamesAppBarNotifier(
    ref: ref,
    tourId: tourId,
    liveRounds: liveRounds,
  );
});

class GamesAppBarNotifier
    extends StateNotifier<AsyncValue<GamesAppBarViewModel>> {
  GamesAppBarNotifier({
    required this.ref,
    required this.tourId,
    required this.liveRounds,
  }) : super(const AsyncValue.loading()) {
    _init();
  }

  final Ref ref;
  final String tourId;
  final List<String> liveRounds;

  // Cache for optimization
  List<GamesAppBarModel>? _cachedRounds;
  String? _lastTourId;

  Future<void> _init() async {
    try {
      // Use cache if same tour ID
      List<GamesAppBarModel> gamesAppBarModels;

      if (_cachedRounds != null && _lastTourId == tourId) {
        gamesAppBarModels = _cachedRounds!;
      } else {
        final roundRepository = ref.read(roundRepositoryProvider);
        final rounds = await roundRepository.getRoundsByTourId(tourId);

        if (rounds.isEmpty) {
          if (mounted) {
            state = AsyncValue.data(
              GamesAppBarViewModel(
                gamesAppBarModels: [],
                selectedId: '',
                userSelectedId: false,
              ),
            );
          }
          return;
        }

        gamesAppBarModels =
            rounds
                .map((round) => GamesAppBarModel.fromRound(round, liveRounds))
                .toList();

        // Cache the results
        _cachedRounds = gamesAppBarModels;
        _lastTourId = tourId;
      }

      // Determine selected round with better logic
      String selectedId = '';
      bool userSelectedId = false;

      if (gamesAppBarModels.isNotEmpty) {
        // Default to first round
        selectedId = gamesAppBarModels.first.id;

        // Check if user had previously selected a round for this tour
        final userSelection = ref.read(userSelectedRoundProvider);
        if (userSelection != null &&
            userSelection.userSelected &&
            gamesAppBarModels.any((model) => model.id == userSelection.id)) {
          selectedId = userSelection.id;
          userSelectedId = true;
        } else {
          // Auto-select a live round if available and no user selection
          final liveRound = gamesAppBarModels.firstWhere(
            (model) => liveRounds.contains(model.id),
            orElse: () => gamesAppBarModels.first,
          );
          selectedId = liveRound.id;
        }
      }

      if (mounted) {
        state = AsyncValue.data(
          GamesAppBarViewModel(
            gamesAppBarModels: gamesAppBarModels,
            selectedId: selectedId,
            userSelectedId: userSelectedId,
          ),
        );
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  void selectNewRound(GamesAppBarModel gamesAppBarModel) {
    try {
      // Persist user selection
      ref.read(userSelectedRoundProvider.notifier).state = (
        id: gamesAppBarModel.id,
        userSelected: true,
      );

      // Safely update local state
      final currentState = state.valueOrNull;
      if (currentState != null) {
        state = AsyncValue.data(
          GamesAppBarViewModel(
            gamesAppBarModels: currentState.gamesAppBarModels,
            selectedId: gamesAppBarModel.id,
            userSelectedId: true,
          ),
        );
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  // Method to refresh rounds if needed
  Future<void> refreshRounds() async {
    try {
      // Clear cache to force fresh data
      _cachedRounds = null;
      _lastTourId = null;

      await _init();
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  @override
  void dispose() {
    // Clear cache on dispose
    _cachedRounds = null;
    _lastTourId = null;
    super.dispose();
  }
}
