import 'package:chessever2/repository/supabase/round/round_repository.dart';
import 'package:chessever2/screens/games_tour/providers/games_tour_scroll_state_provider.dart';
import 'package:chessever2/screens/group_event/model/games_app_bar_view_model.dart';
import 'package:chessever2/screens/group_event/providers/live_rounds_id_provider.dart';
import 'package:chessever2/screens/group_event/providers/tour_detail_screen_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Stores the currently selected round ID and whether the user has selected it
final userSelectedRoundProvider =
    StateProvider<({String id, bool userSelected})?>((ref) => null);

// Fixed provider with proper null handling
final gamesAppBarProvider = AutoDisposeStateNotifierProvider<
  GamesAppBarNotifier,
  AsyncValue<GamesAppBarViewModel>
>((ref) {
  final tourId = ref.watch(selectedTourIdProvider); // Use watch instead of read

  // Return loading state if tourId is null instead of throwing
  if (tourId == null) {
    return GamesAppBarNotifier.withoutTourId(ref: ref);
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

  // Constructor for when tourId is not available
  GamesAppBarNotifier.withoutTourId({
    required this.ref,
  }) : tourId = null,
       liveRounds = <String>[],
       super(const AsyncValue.loading()) {
    // Wait for tourId to become available
    _waitForTourId();
  }

  final Ref ref;
  final String? tourId;
  final List<String> liveRounds;

  // Cache for optimization
  List<GamesAppBarModel>? _cachedRounds;
  String? _lastTourId;

  Future<void> _waitForTourId() async {
    // Listen for changes to selectedTourIdProvider
    ref.listen<String?>(selectedTourIdProvider, (previous, next) {
      if (next != null && mounted) {
        // Tournament ID is now available, recreate the provider
        // This will trigger a rebuild of the dependent widgets
        ref.invalidateSelf();
      }
    });

    // Set initial empty state
    if (mounted) {
      state = AsyncValue.data(
        GamesAppBarViewModel(
          gamesAppBarModels: [],
          selectedId: '',
          userSelectedId: false,
        ),
      );
    }
  }

  Future<void> _init() async {
    if (tourId == null) {
      await _waitForTourId();
      return;
    }

    try {
      List<GamesAppBarModel> gamesAppBarModels;

      if (_cachedRounds != null && _lastTourId == tourId) {
        gamesAppBarModels = _cachedRounds!;
      } else {
        final roundRepository = ref.read(roundRepositoryProvider);
        final rounds = await roundRepository.getRoundsByTourId(tourId!);

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

        _cachedRounds = gamesAppBarModels;
        _lastTourId = tourId;
      }

      String selectedId = '';
      bool userSelectedId = false;

      if (gamesAppBarModels.isNotEmpty) {
        final userSelection = ref.read(userSelectedRoundProvider);

        if (userSelection != null &&
            userSelection.userSelected &&
            gamesAppBarModels.any((model) => model.id == userSelection.id)) {
          selectedId = userSelection.id;
          userSelectedId = true;
        } else {
          GamesAppBarModel? liveRound;
          for (var model in gamesAppBarModels) {
            if (liveRounds.contains(model.id)) {
              liveRound = model;
              break;
            }
          }

          if (liveRound != null) {
            selectedId = liveRound.id;
            print("Selected live round: $selectedId");
          } else {
            final roundRepository = ref.read(roundRepositoryProvider);
            final latestRound = await roundRepository.getLatestRoundByLastMove(
              tourId!,
            );

            if (latestRound != null) {
              selectedId = latestRound.id;
              print(
                " Latest round with non-null last_move selected: $selectedId",
              );
            } else {
              selectedId = gamesAppBarModels.last.id;
              print(
                "No live or non-null-move round found, fallback to newest: $selectedId",
              );
            }
          }
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

  // FIXED: Enhanced selectNewRound method with better state management
  void selectNewRound(GamesAppBarModel gamesAppBarModel) {
    try {
      debugPrint('🎯 User selected round: ${gamesAppBarModel.id}');

      // Always mark as user selected and persist
      ref.read(userSelectedRoundProvider.notifier).state = (
        id: gamesAppBarModel.id,
        userSelected: true,
      );

      // Update state immediately with userSelectedId = true
      final currentState = state.valueOrNull;
      if (currentState != null) {
        state = AsyncValue.data(
          GamesAppBarViewModel(
            gamesAppBarModels: currentState.gamesAppBarModels,
            selectedId: gamesAppBarModel.id,
            userSelectedId: true, // CRITICAL: Mark as user-initiated
          ),
        );

        debugPrint(
          '🎯 Provider state updated with userSelectedId=true for round: ${gamesAppBarModel.id}',
        );
      }

      // Clear any scroll state that might interfere
      ref.read(scrollStateProvider.notifier).setUserScrolling(false);
      ref.read(scrollStateProvider.notifier).setScrolling(false);
    } catch (e, st) {
      debugPrint('❌ Error in selectNewRound: $e');
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  // Method to refresh rounds if needed
  Future<void> refreshRounds() async {
    if (tourId == null) {
      debugPrint('Cannot refresh rounds: Tournament ID not available');
      return;
    }

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

  // FIXED: Enhanced selectNewRoundSilently method
  void selectNewRoundSilently(GamesAppBarModel gamesAppBarModel) {
    try {
      debugPrint(
        '🔄 Silent selection called for round: ${gamesAppBarModel.id}',
      );

      // Update state without marking as user selected (keep existing userSelectedId)
      final currentState = state.valueOrNull;
      if (currentState != null) {
        state = AsyncValue.data(
          GamesAppBarViewModel(
            gamesAppBarModels: currentState.gamesAppBarModels,
            selectedId: gamesAppBarModel.id,
            userSelectedId: false, // CRITICAL: Keep as false for silent updates
          ),
        );

        debugPrint(
          '✅ Provider state updated silently to: ${gamesAppBarModel.id}',
        );
      }
    } catch (e, st) {
      debugPrint('❌ Error in selectNewRoundSilently: $e');
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }
}
