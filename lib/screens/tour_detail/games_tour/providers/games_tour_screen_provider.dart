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
    _initialize();
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

  Future<void> _setupListeners() async {
    // Recompute when games list changes (but do not break active search view)
    ref.listen<AsyncValue<List<Games>>>(gamesTourProvider(aboutTourModel!.id), (
      previous,
      next,
    ) async {
      final current = state.valueOrNull;

      // Only recompute if the games list actually changed
      final previousGames = previous?.valueOrNull ?? [];
      final nextGames = next.valueOrNull ?? [];

      if (next.hasValue) {
        ref.refresh(gamesPinprovider(aboutTourModel!.id));
      }

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
          return;
        }
      }

      // Skip recomputation during search mode to maintain search results
      if (current?.isSearchMode == true) {
        return;
      }
      _recompute();
      await ref
          .read(gamesPinprovider(aboutTourModel!.id).notifier)
          .computeAutoPins();
    });

    ref.listen<GamesPinState>(gamesPinprovider(aboutTourModel!.id), (
      previous,
      pins,
    ) {
      final current = state.valueOrNull;

      // If searching, keep the current search results and only update pins in state
      if (current?.isSearchMode ?? false) {
        if (mounted) {
          state = AsyncValue.data(
            current!.copyWith(pinnedGamedIs: pins.allPins),
          );
        }
      } else {
        if (previous?.allPins != pins.allPins) {
          _recompute();
        }
      }
    });
  }

  Future<void> _initialize() async {
    if (aboutTourModel == null) return;

    // Wait until gamesTourProvider emits a value
    final games = ref.read(gamesTourProvider(aboutTourModel!.id));

    if (games.isLoading || games.hasError || games.value == null) {
      return;
    }

    await _recompute();
  }

  Future<void> _recompute({
    bool? isSearchModeOverride,
    String? searchQueryOverride,
    List<String>? pinnedIdsOverride, // allow optimistic pins
  }) async {
    if (aboutTourModel == null) return;

    try {
      final gamesAsync = ref.read(gamesTourProvider(aboutTourModel!.id));
       if (gamesAsync.isLoading) {
      return; 
    }
      final pins = ref.read(gamesPinprovider(aboutTourModel!.id));

      final allGames = gamesAsync.value ?? <Games>[];
      final pinnedIds = pinnedIdsOverride ?? pins.allPins;

      final current = state.valueOrNull;
      final isSearchMode =
          isSearchModeOverride ?? (current?.isSearchMode ?? false);
      final searchQuery = searchQueryOverride ?? current?.searchQuery;

      // Pre-parse numbers to avoid repeated regex operations
      final gameInfo = <String, (int, int)>{};
      for (final game in allGames) {
        final roundNum = _extractRoundNumber(game.roundSlug);
        final gameNum = _extractGameNumber(game.roundSlug);
        gameInfo[game.id] = (roundNum, gameNum);
      }

      final sortedGames = List<Games>.from(allGames);
      sortedGames.sort((a, b) {
        if (!isSearchMode) {
          final aPinned = pinnedIds.contains(a.id);
          final bPinned = pinnedIds.contains(b.id);
          if (aPinned && !bPinned) return -1;
          if (!aPinned && bPinned) return 1;
        }

        // Use pre-parsed values for performance
        final (roundA, gameA) = gameInfo[a.id] ?? (0, 0);
        final (roundB, gameB) = gameInfo[b.id] ?? (0, 0);

        // First, sort by round number DESCENDING (to match the round list order)
        if (roundA != roundB) return roundB.compareTo(roundA);

        // Within same round, sort by game number DESCENDING (Game 2 before Game 1)
        if (gameA != gameB) return gameB.compareTo(gameA);

        // Finally, sort by board number ASCENDING
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
            gameDisplayMode: current?.gameDisplayMode ?? GameDisplayMode.all,
          ),
        );
      }
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  Future<void> togglePinGame(String gameId) async {
    await ref
        .read(gamesPinprovider(aboutTourModel!.id).notifier)
        .togglePin(gameId);
  }

  void clearSearch() {
    if (aboutTourModel == null) return;
    final pins = ref.read(gamesPinprovider(aboutTourModel!.id)).allPins;
    _recompute(
      isSearchModeOverride: false,
      searchQueryOverride: null,
      pinnedIdsOverride: pins, // ensure immediate pin state after clearing
    );
  }

  Future<void> unpinAllGames() async {
    try {
      await Future.wait([
        ref.read(pinGameLocalStorage).clearAllPinnedGames(),
        ref
            .read(gamesPinprovider(aboutTourModel!.id).notifier)
            .disableAutoPin(),
      ]);
      // Immediate UI update
      await _recompute(pinnedIdsOverride: const <String>[]);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  Future<void> toggleFinishedGames() async {
    final currentMode = state.valueOrNull?.gameDisplayMode;

    if (currentMode != null) {
      if (currentMode == GameDisplayMode.all) {
        await hideFinishedGames();
      } else if (currentMode == GameDisplayMode.hideFinishedGames) {
        await showFinishedGames();
      } else if (currentMode == GameDisplayMode.showfinishedGame) {
        await showAllGames();
      } else {
        await showAllGames();
      }
    }
  }

  String getTitle() {
    final currentMode = state.valueOrNull?.gameDisplayMode;

    if (currentMode != null) {
      if (currentMode == GameDisplayMode.all) {
        return 'Hide Finished Games';
      } else if (currentMode == GameDisplayMode.hideFinishedGames) {
        return 'Show Finished Games';
      } else if (currentMode == GameDisplayMode.showfinishedGame) {
        return 'Show All Games';
      } else {
        return 'Show All Games';
      }
    }
    return 'Show All Games';
  }

  Future<void> showFinishedGames() async {
    var games = ref.read(gamesTourProvider(aboutTourModel!.id)).value ?? [];
    var pinnedIds = ref.read(gamesPinprovider(aboutTourModel!.id)).allPins;
    var finishedGames = games.where((g) => g.status != '*').toList();

    // Pre-parse for performance
    final gameInfo = <String, (int, int)>{};
    for (final game in finishedGames) {
      gameInfo[game.id] = (_extractRoundNumber(game.roundSlug), _extractGameNumber(game.roundSlug));
    }

    final sortedGames = List<Games>.from(finishedGames);
    sortedGames.sort((a, b) {
      final aPinned = pinnedIds.contains(a.id);
      final bPinned = pinnedIds.contains(b.id);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;

      final (roundA, gameA) = gameInfo[a.id] ?? (0, 0);
      final (roundB, gameB) = gameInfo[b.id] ?? (0, 0);

      // Sort by round DESCENDING (to match the round list order)
      if (roundA != roundB) return roundB.compareTo(roundA);

      // Within same round, sort by game DESCENDING (Game 2 before Game 1)
      if (gameA != gameB) return gameB.compareTo(gameA);

      final aBoard = a.boardNr, bBoard = b.boardNr;
      if (aBoard != null && bBoard != null) return aBoard.compareTo(bBoard);
      if (aBoard != null) return -1;
      if (bBoard != null) return 1;
      return 0;
    });

    state = AsyncValue.data(
      GamesScreenModel(
        gamesTourModels:
            sortedGames.map((g) => GamesTourModel.fromGame(g)).toList(),
        pinnedGamedIs: pinnedIds,
        isSearchMode: true,
        gameDisplayMode: GameDisplayMode.showfinishedGame,
      ),
    );
  }

  Future<void> hideFinishedGames() async {
    var games = ref.read(gamesTourProvider(aboutTourModel!.id)).value ?? [];
    var unfinishedGames = games.where((g) => g.status == '*').toList();
    final pinnedIds = ref.read(gamesPinprovider(aboutTourModel!.id)).allPins;

    // Pre-parse for performance
    final gameInfo = <String, (int, int)>{};
    for (final game in unfinishedGames) {
      gameInfo[game.id] = (_extractRoundNumber(game.roundSlug), _extractGameNumber(game.roundSlug));
    }

    final sortedGames = List<Games>.from(unfinishedGames);
    sortedGames.sort((a, b) {
      final aPinned = pinnedIds.contains(a.id);
      final bPinned = pinnedIds.contains(b.id);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;

      final (roundA, gameA) = gameInfo[a.id] ?? (0, 0);
      final (roundB, gameB) = gameInfo[b.id] ?? (0, 0);

      // Sort by round DESCENDING (to match the round list order)
      if (roundA != roundB) return roundB.compareTo(roundA);

      // Within same round, sort by game DESCENDING (Game 2 before Game 1)
      if (gameA != gameB) return gameB.compareTo(gameA);

      final aBoard = a.boardNr, bBoard = b.boardNr;
      if (aBoard != null && bBoard != null) return aBoard.compareTo(bBoard);
      if (aBoard != null) return -1;
      if (bBoard != null) return 1;
      return 0;
    });
    state = AsyncValue.data(
      GamesScreenModel(
        gamesTourModels:
            sortedGames.map((g) => GamesTourModel.fromGame(g)).toList(),
        pinnedGamedIs: pinnedIds,
        isSearchMode: true,
        gameDisplayMode: GameDisplayMode.hideFinishedGames,
      ),
    );
  }

  Future<void> showAllGames() async {
    var games = ref.read(gamesTourProvider(aboutTourModel!.id)).value ?? [];
    final pinnedIds = ref.read(gamesPinprovider(aboutTourModel!.id)).allPins;

    // Pre-parse for performance
    final gameInfo = <String, (int, int)>{};
    for (final game in games) {
      gameInfo[game.id] = (_extractRoundNumber(game.roundSlug), _extractGameNumber(game.roundSlug));
    }

    final sortedGames = List<Games>.from(games);
    sortedGames.sort((a, b) {
      final aPinned = pinnedIds.contains(a.id);
      final bPinned = pinnedIds.contains(b.id);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;

      final (roundA, gameA) = gameInfo[a.id] ?? (0, 0);
      final (roundB, gameB) = gameInfo[b.id] ?? (0, 0);

      // Sort by round DESCENDING (to match the round list order)
      if (roundA != roundB) return roundB.compareTo(roundA);

      // Within same round, sort by game DESCENDING (Game 2 before Game 1)
      if (gameA != gameB) return gameB.compareTo(gameA);

      final aBoard = a.boardNr, bBoard = b.boardNr;
      if (aBoard != null && bBoard != null) return aBoard.compareTo(bBoard);
      if (aBoard != null) return -1;
      if (bBoard != null) return 1;
      return 0;
    });
    state = AsyncValue.data(
      GamesScreenModel(
        gamesTourModels:
            sortedGames.map((g) => GamesTourModel.fromGame(g)).toList(),
        pinnedGamedIs: pinnedIds,
        isSearchMode: true,
        gameDisplayMode: GameDisplayMode.hideFinishedGames,
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
      final pinnedIds = ref.read(gamesPinprovider(aboutTourModel!.id)).allPins;

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
            gameDisplayMode:
                state.valueOrNull?.gameDisplayMode ?? GameDisplayMode.all,
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

  // Helper method to extract round number from round slug
  int _extractRoundNumber(String roundSlug) {
    final match = RegExp(r'round-?(\d+)', caseSensitive: false).firstMatch(roundSlug) ??
                  RegExp(r'(\d+)').firstMatch(roundSlug);
    return int.tryParse(match?.group(1) ?? '0') ?? 0;
  }

  // Helper method to extract game number from round slug (e.g., "round-6--game-2" -> 2)
  int _extractGameNumber(String roundSlug) {
    final match = RegExp(r'game-?(\d+)', caseSensitive: false).firstMatch(roundSlug);
    return int.tryParse(match?.group(1) ?? '0') ?? 0;
  }
}
