import 'dart:collection';

import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/repository/local_storage/tournament/games/pin_games_local_storage.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gamesTourScreenProvider = StateNotifierProvider<
  GamesTourScreenProvider,
  AsyncValue<GamesScreenModel>
>((ref) {
  // Watch tour details first - this is the primary dependency
  final tourDetailAsync = ref.watch(tourDetailScreenProvider);
  final showFinishedGames = ref.watch(showFinishedGamesProvider);
  if (tourDetailAsync.isLoading) {
    return GamesTourScreenProvider.loading(ref: ref);
  }

  if (tourDetailAsync.hasError) {
    return GamesTourScreenProvider.withError(
      ref: ref,
      error: tourDetailAsync.error!,
    );
  }

  final aboutTourModel = tourDetailAsync.valueOrNull?.aboutTourModel;

  if (aboutTourModel == null) {
    return GamesTourScreenProvider.loading(ref: ref);
  }

  // The notifier will read games/pins itself and keep state in sync
  return GamesTourScreenProvider(ref: ref, aboutTourModel: aboutTourModel);
});

// Can use this in future to maintain the state across the app
final showFinishedGamesProvider = StateProvider<bool>((ref) => true);
class GamesTourScreenProvider
    extends StateNotifier<AsyncValue<GamesScreenModel>> {
  GamesTourScreenProvider({
    required this.ref,
    required this.aboutTourModel,
    this.error,
  }) : super(const AsyncValue.loading()) {
    _setupListeners();
    _recompute();
  }

  // Constructor for loading state
  GamesTourScreenProvider.loading({required this.ref})
    : aboutTourModel = null,
      error = null,
      super(const AsyncValue.loading());

  // Constructor for error state
  GamesTourScreenProvider.withError({
    required this.ref,
    required Object this.error,
  }) : aboutTourModel = null,
       super(AsyncValue.error(error, StackTrace.current));

  final Ref ref;
  final AboutTourModel? aboutTourModel;
  final Object? error;

  void _setupListeners() {
    if (aboutTourModel == null) return;

    // Recompute or just update pins depending on search mode
    ref.listen<AsyncValue<List<String>>>(gamesPinprovider(aboutTourModel!.id), (
      previous,
      next,
    ) {
      final pins = next.value ?? const <String>[];
      final current = state.valueOrNull;

      // If searching, keep the current search results and only update pins in state
      if (current?.isSearchMode == true) {
        if (mounted) {
          state = AsyncValue.data(current!.copyWith(pinnedGamedIs: pins));
        }
      } else {
        _recompute();
      }
    });

    // Recompute when games list changes (but do not break active search view)
    ref.listen<AsyncValue<List<Games>>>(gamesTourProvider(aboutTourModel!.id), (
      previous,
      next,
    ) {
      final current = state.valueOrNull;

      // Only recompute if the games list actually changed
      final previousGames = previous?.valueOrNull ?? [];
      final nextGames = next.valueOrNull ?? [];

      if (previousGames.length == nextGames.length) {
        // Check if any game data actually changed (more than just clock updates)
        bool significantChange = false;
        for (int i = 0; i < nextGames.length; i++) {
          final prev = i < previousGames.length ? previousGames[i] : null;
          final next = nextGames[i];

          if (prev == null ||
              prev.id != next.id ||
              prev.fen != next.fen ||
              prev.lastMove != next.lastMove ||
              prev.status != next.status) {
            significantChange = true;
            break;
          }
        }

        if (!significantChange) {
          // Only clock/time updates, no need to recompute the entire screen
          print('🔥 GamesTourScreenProvider: Only clock updates, skipping recomputation');
          return;
        }
      }

      print('🔥 GamesTourScreenProvider: Received games update, isSearchMode: ${current?.isSearchMode}');

      // Skip recomputation during search mode to maintain search results
      if (current?.isSearchMode == true) {
        print('🔥 GamesTourScreenProvider: In search mode - skipping recomputation');
        return;
      }

      print('🔥 GamesTourScreenProvider: Full recomputation...');
      _recompute();
    });
  }

  Future<void> _recompute({
    bool? isSearchModeOverride,
    String? searchQueryOverride,
    List<String>? pinnedIdsOverride, // allow optimistic pins
  }) async {
    if (aboutTourModel == null) return;

    try {
      final gamesAsync = ref.read(gamesTourProvider(aboutTourModel!.id));
      final pinsAsync = ref.read(gamesPinprovider(aboutTourModel!.id));

      final allGames = gamesAsync.value ?? <Games>[];
      final pinnedIds =
          pinnedIdsOverride ?? (pinsAsync.value ?? const <String>[]);

      final current = state.valueOrNull;
      final isSearchMode =
          isSearchModeOverride ?? (current?.isSearchMode ?? false);
      final searchQuery = searchQueryOverride ?? current?.searchQuery;

      final sortedGames = List<Games>.from(allGames);
      sortedGames.sort((a, b) {
        if (!isSearchMode) {
          final aPinned = pinnedIds.contains(a.id);
          final bPinned = pinnedIds.contains(b.id);
          if (aPinned && !bPinned) return -1;
          if (!aPinned && bPinned) return 1;
        }

        final roundComparison = _compareRounds(a.roundId, b.roundId);
        if (roundComparison != 0) return roundComparison;

        final aBoard = a.boardNr, bBoard = b.boardNr;
        if (aBoard != null && bBoard != null) return aBoard.compareTo(bBoard);
        if (aBoard != null) return -1;
        if (bBoard != null) return 1;
        return 0;
      });

      final models = <GamesTourModel>[];
      for (final g in sortedGames) {
        try {
          models.add(GamesTourModel.fromGame(g));
        } catch (_) {}
      }

      if (mounted) {
        state = AsyncValue.data(
          GamesScreenModel(
            gamesTourModels: models,
            // Show pins even in search mode for correct icon state.
            pinnedGamedIs: pinnedIds,
            isSearchMode: isSearchMode,
            searchQuery: searchQuery,
          ),
        );
      }
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  // Toggle pin with optimistic UI:
  // - If searching: keep current search results and just update pins in state.
  // - If not searching: recompute full list with optimistic pins.
  Future<void> togglePinGame(String gameId) async {
    if (aboutTourModel == null) return;

    try {
      final pinnedStorage = ref.read(pinGameLocalStorage);

      final currentPinnedIds = List<String>.from(
        ref.read(gamesPinprovider(aboutTourModel!.id)).value ??
            const <String>[],
      );

      if (currentPinnedIds.contains(gameId)) {
        await pinnedStorage.removePinnedGameId(aboutTourModel!.id, gameId);
        currentPinnedIds.remove(gameId);
      } else {
        await pinnedStorage.addPinnedGameId(aboutTourModel!.id, gameId);
        currentPinnedIds.add(gameId);
      }

      final current = state.valueOrNull;
      if (current?.isSearchMode == true) {
        // Stay on search results and just update pin icons immediately
        if (mounted) {
          state = AsyncValue.data(
            current!.copyWith(pinnedGamedIs: currentPinnedIds),
          );
        }
        // Keep providers in sync in background
        ref.invalidate(gamesPinprovider);
        return;
      }

      // Non-search: recompute full list with optimistic pins
      await _recompute(pinnedIdsOverride: currentPinnedIds);
      ref.invalidate(gamesPinprovider);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  void clearSearch() {
    if (aboutTourModel == null) return;
    final pins =
        ref.read(gamesPinprovider(aboutTourModel!.id)).value ??
        const <String>[];
    _recompute(
      isSearchModeOverride: false,
      searchQueryOverride: null,
      pinnedIdsOverride: pins, // ensure immediate pin state after clearing
    );
  }

  Future<void> unpinAllGames() async {
    try {
      await ref.read(pinGameLocalStorage).clearAllPinnedGames();

      // Immediate UI update
      await _recompute(pinnedIdsOverride: const <String>[]);

      // Keep providers in sync
      ref.invalidate(gamesPinprovider);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }
  
  Future<void> toggleFinishedGames( bool showFinishedGame) async{
    //  final currentValue = ref.read(showFinishedGamesProvider);
    // ref.read(showFinishedGamesProvider.notifier).state = !currentValue;
  
  if (showFinishedGame) { // Will be true after toggle
    print("Showing finished games");
    await showFinishedGames();
  } else { // Will be false after toggle
    print("Hiding finished games");
    await hideFinishedGames();
  }
  }

  Future<void> showFinishedGames() async{
    var games = ref.read(gamesTourProvider(aboutTourModel!.id)).value ?? [];
    var pinnedIds =
          ref.read(gamesPinprovider(aboutTourModel!.id)).value ??
          const <String>[];
           state = AsyncValue.data(
          GamesScreenModel(
            gamesTourModels: games.map((g) => GamesTourModel.fromGame(g)).toList(),
            pinnedGamedIs: pinnedIds, 
            isSearchMode: true,
          ),
        );
  }

  Future<void> hideFinishedGames() async{
    var games = ref.read(gamesTourProvider(aboutTourModel!.id)).value ?? [];
    var unfinishedGames = games.where((g) => g.status == '*').toList();
    final pinnedIds =
          ref.read(gamesPinprovider(aboutTourModel!.id)).value ??
          const <String>[];
    state = AsyncValue.data(
          GamesScreenModel(
            gamesTourModels: unfinishedGames.map((g) => GamesTourModel.fromGame(g)).toList(),
            pinnedGamedIs: pinnedIds, 
            isSearchMode: true,
          ),
        );
  }

  Future<void> searchGamesEnhanced(String query) async {
    if (aboutTourModel == null) return;

    try {
      if (query.isEmpty) {
        clearSearch();
        return;
      }

      // Current pins for correct pin UI in search mode
      final pinnedIds =
          ref.read(gamesPinprovider(aboutTourModel!.id)).value ??
          const <String>[];

      final gamesLocal = ref.read(gamesLocalStorage);
      final searchResult = await gamesLocal.searchGamesWithScoring(
        tourId: aboutTourModel!.id,
        query: query,
      );
      final games = searchResult.results.map((r) => r.game).toList();

      final models = <GamesTourModel>[];
      for (final g in games) {
        try {
          models.add(GamesTourModel.fromGame(g));
        } catch (_) {}
      }

      if (mounted) {
        state = AsyncValue.data(
          GamesScreenModel(
            gamesTourModels: models,
            pinnedGamedIs: pinnedIds, // show accurate pins in search
            isSearchMode: true,
            searchQuery: query,
          ),
        );
      }
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  Future<void> refreshGames() async {
    if (aboutTourModel == null) return;
    try {
      clearSearch();
      ref.refresh(gamesTourProvider(aboutTourModel!.id));
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  // Helper method to compare round IDs (round1, round2, etc.)
  int _compareRounds(String roundIdA, String roundIdB) {
    int num(String id) {
      final match =
          RegExp(r'round(\d+)', caseSensitive: false).firstMatch(id) ??
          RegExp(r'(\d+)').firstMatch(id);
      return int.tryParse(match?.group(1) ?? '0') ?? 0;
    }

    return num(roundIdA).compareTo(num(roundIdB));
  }
}
