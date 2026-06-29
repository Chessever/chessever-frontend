import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/providers/event_pin_refresh_provider.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/repository/local_storage/tournament/games/pin_games_local_storage.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_display_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_tournament_state_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final gamesTourScreenProvider = StateNotifierProvider<
  GamesTourScreenProvider,
  AsyncValue<GamesScreenModel>
>((ref) {
  // Only the selected tournament identity should recreate this notifier.
  // Live-tour/status updates are handled elsewhere and should not flash the
  // Games tab back through loading.
  final tourDetailAsync = ref.watch(
    tourDetailScreenProvider.select(_GamesTourDetailSlice.from),
  );
  // unused: final showFinishedGames = ref.watch(showFinishedGamesProvider);

  if (tourDetailAsync.isLoading) {
    return GamesTourScreenProvider.loading(ref: ref);
  }

  if (tourDetailAsync.hasError) {
    return GamesTourScreenProvider.withError(
      ref: ref,
      error: tourDetailAsync.error!,
    );
  }

  final aboutTourModel = tourDetailAsync.aboutTourModel;

  if (aboutTourModel == null) {
    return GamesTourScreenProvider.loading(ref: ref);
  }

  // The notifier will read games/pins itself and keep state in sync
  return GamesTourScreenProvider(ref: ref, aboutTourModel: aboutTourModel);
});

// Can use this in future to maintain the state across the app
final showFinishedGamesProvider = StateProvider<bool>((ref) => true);

class _GamesProcessingArgs {
  final List<Games> games;
  final List<String> pinnedIds;
  final bool isSearchMode;

  _GamesProcessingArgs({
    required this.games,
    required this.pinnedIds,
    required this.isSearchMode,
  });
}

// Top-level worker function for isolate
List<GamesTourModel> _processGamesWorker(_GamesProcessingArgs args) {
  // 1. Pre-parse numbers to avoid repeated regex operations during sort
  final gameInfo = <String, (int, int)>{};

  // Helper to extract numbers (copied here to be accessible in isolate)
  int extractRound(String roundSlug) {
    final match =
        RegExp(r'round-?(\d+)', caseSensitive: false).firstMatch(roundSlug) ??
        RegExp(r'(\d+)').firstMatch(roundSlug);
    return int.tryParse(match?.group(1) ?? '0') ?? 0;
  }

  int extractGame(String roundSlug) {
    final match = RegExp(
      r'game-?(\d+)',
      caseSensitive: false,
    ).firstMatch(roundSlug);
    return int.tryParse(match?.group(1) ?? '0') ?? 0;
  }

  for (final game in args.games) {
    gameInfo[game.id] = (
      extractRound(game.roundSlug),
      extractGame(game.roundSlug),
    );
  }

  // 2. Sort games
  final sortedGames = List<Games>.from(args.games);
  sortedGames.sort((a, b) {
    // FIRST PRIORITY: Pinned games (only in non-search mode)
    if (!args.isSearchMode) {
      final aPinned = args.pinnedIds.contains(a.id);
      final bPinned = args.pinnedIds.contains(b.id);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
    }

    final aLive = GameStatus.fromString(a.status).isOngoing;
    final bLive = GameStatus.fromString(b.status).isOngoing;
    if (aLive && !bLive) return -1;
    if (!aLive && bLive) return 1;

    final (roundA, gameA) = gameInfo[a.id] ?? (0, 0);
    final (roundB, gameB) = gameInfo[b.id] ?? (0, 0);

    // Second, sort by round number DESCENDING
    if (roundA != roundB) return roundB.compareTo(roundA);

    // Within same round, sort by game number DESCENDING
    if (gameA != gameB) return gameB.compareTo(gameA);

    // Finally, sort by board number ASCENDING
    final aBoard = a.boardNr, bBoard = b.boardNr;
    if (aBoard != null && bBoard != null) return aBoard.compareTo(bBoard);
    if (aBoard != null) return -1;
    if (bBoard != null) return 1;
    return 0;
  });

  // 3. Map to models (heavy PGN parsing happens here inside fromGame)
  final models = <GamesTourModel>[];
  for (final g in sortedGames) {
    try {
      models.add(GamesTourModel.fromGame(g));
    } catch (e) {
      // In isolate we can't use debugPrint, so we just skip invalid games
      // The main thread will see a slightly shorter list
    }
  }
  return models;
}

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
    // The display-mode provider lives outside this notifier so it survives
    // recreations triggered by tourDetailScreenProvider (category change,
    // live tour ID pushes). Republish state when it changes externally —
    // e.g. after the notifier is rebuilt and reads the persisted value.
    ref.listen<GameDisplayMode>(gameDisplayModeProvider(aboutTourModel!.id), (
      previous,
      next,
    ) {
      if (previous == next) return;
      final current = state.valueOrNull;
      if (current != null && !current.isSearchMode) {
        // Keep the screen model in sync with the persisted preference.
        // The grouped provider does the actual display filtering off
        // gameDisplayMode, so we just need to mirror it onto the model.
        if (mounted) {
          state = AsyncValue.data(current.copyWith(gameDisplayMode: next));
        }
      }
    });

    // Recompute when games list changes (but do not break active search view)
    ref.listen<AsyncValue<List<Games>>>(gamesTourProvider(aboutTourModel!.id), (
      previous,
      next,
    ) async {
      final current = state.valueOrNull;

      // Only recompute if the games list actually changed
      final previousGames = previous?.valueOrNull ?? [];
      final nextGames = next.valueOrNull ?? [];

      // ALWAYS recompute if we don't have any model data yet
      // This ensures we don't miss the initial load
      final needsInitialData =
          current == null || current.gamesTourModels.isEmpty;
      if (needsInitialData && nextGames.isNotEmpty) {
        debugPrint(
          '🎮 GamesTourScreen: Initial data load - triggering recompute with ${nextGames.length} games',
        );
        _recompute();
        await ref
            .read(gamesPinprovider(aboutTourModel!.id).notifier)
            .computeAutoPins();
        return;
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

      // During search mode or filter mode, we need to re-apply the filter
      // when significant game changes occur (like status changes)
      if (current?.isSearchMode == true) {
        // If this is a filter mode (not text search), re-apply the filter
        final displayMode = current?.gameDisplayMode;
        if (displayMode != null && displayMode != GameDisplayMode.all) {
          // Check if any game status changed (finished/started)
          bool statusChanged = false;
          for (
            int i = 0;
            i < nextGames.length && i < previousGames.length;
            i++
          ) {
            if (previousGames[i].status != nextGames[i].status) {
              statusChanged = true;
              break;
            }
          }

          if (statusChanged) {
            debugPrint(
              '🎮 GamesTourScreen: Game status changed during filter mode - re-applying filter',
            );
            // Re-apply the current filter
            if (displayMode == GameDisplayMode.hideFinishedGames) {
              hideFinishedGames();
            } else if (displayMode == GameDisplayMode.showfinishedGame) {
              showFinishedGames();
            }
          }
        }
        // For text search mode, keep the current search results
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
      // Games not ready yet - the listener will trigger _recompute when they load.
      // But to be safe, schedule an immediate recompute attempt after a short delay
      // in case the listener doesn't fire due to timing issues.
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && state.valueOrNull == null) {
          _recompute();
        }
      });
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

      // Check if there are any live games
      final hasLiveGames = allGames.any((g) => g.status == "*");

      debugPrint(
        '🎮 GamesTourScreen: Total games: ${allGames.length}, Live games: ${allGames.where((g) => g.status == "*").length}',
      );
      if (allGames.where((g) => g.status == "*").isNotEmpty) {
        debugPrint(
          '🎮 GamesTourScreen: Live game rounds: ${allGames.where((g) => g.status == "*").map((g) => g.roundSlug).join(", ")}',
        );
      }

      // Find the upcoming round if no live games exist
      int? upcomingRoundNumber;
      if (!hasLiveGames && allGames.isNotEmpty) {
        // Find the highest round number with all games finished
        final roundNumbers =
            gameInfo.values.map((info) => info.$1).toSet().toList()..sort();
        if (roundNumbers.isNotEmpty) {
          final maxRound = roundNumbers.last;
          // The upcoming round is the next one
          upcomingRoundNumber = maxRound + 1;

          // Check if this round actually exists in our games
          final upcomingRoundExists = allGames.any((g) {
            final roundNum = gameInfo[g.id]?.$1 ?? 0;
            return roundNum == upcomingRoundNumber;
          });

          if (!upcomingRoundExists) {
            upcomingRoundNumber = null; // No upcoming round available
          }
        }
      }

      // Offload heavy sorting and mapping to background isolate
      final models = await compute(
        _processGamesWorker,
        _GamesProcessingArgs(
          games: allGames,
          pinnedIds: pinnedIds,
          isSearchMode: isSearchMode,
        ),
      );

      // Read the persisted display mode so it survives notifier recreations
      // (category change, live-tour-id push). `current?.gameDisplayMode` is
      // null on a freshly recreated notifier, which is what produced the
      // "Focus on live games → Show all games" snap-back. The provider is
      // family-keyed by tourId so state can't bleed across tournaments.
      final persistedDisplayMode = ref.read(
        gameDisplayModeProvider(aboutTourModel!.id),
      );

      if (mounted) {
        state = AsyncValue.data(
          GamesScreenModel(
            gamesTourModels: models,
            // Show pins even in search mode for correct icon state.
            pinnedGamedIs: pinnedIds,
            isSearchMode: isSearchMode,
            searchQuery: searchQuery,
            gameDisplayMode: persistedDisplayMode,
          ),
        );
      }
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  Future<void> togglePinGame(
    String gameId, {
    required String sourceTourId,
  }) async {
    await ref
        .read(gamesPinprovider(aboutTourModel!.id).notifier)
        .togglePin(gameId: gameId, sourceTourId: sourceTourId);
    bumpEventPinRefreshSignal(
      ref,
      ref.read(selectedBroadcastModelProvider)?.id,
    );
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

  Future<void> enableAutoPin() async {
    if (aboutTourModel == null) return;
    try {
      await ref
          .read(gamesPinprovider(aboutTourModel!.id).notifier)
          .enableAutoPin();
      // Immediate UI update with new pins
      final pins = ref.read(gamesPinprovider(aboutTourModel!.id)).allPins;
      await _recompute(pinnedIdsOverride: pins);
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  Future<void> disableAutoPin() async {
    if (aboutTourModel == null) return;
    try {
      await ref
          .read(gamesPinprovider(aboutTourModel!.id).notifier)
          .disableAutoPin();
      // Immediate UI update with updated pins (manual pins only)
      final pins = ref.read(gamesPinprovider(aboutTourModel!.id)).allPins;
      await _recompute(pinnedIdsOverride: pins);
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
    if (aboutTourModel == null) return;

    final pinnedIds = ref.read(gamesPinprovider(aboutTourModel!.id)).allPins;
    final allGames = _collectGamesAcrossVisibleStages();
    final finishedGames = allGames.where((g) => g.status != '*').toList();
    final sortedGames = _sortGamesForFilters(finishedGames, pinnedIds);
    final models = _mapGamesToModels(sortedGames);

    ref.read(gameDisplayModeProvider(aboutTourModel!.id).notifier).state =
        GameDisplayMode.showfinishedGame;

    state = AsyncValue.data(
      GamesScreenModel(
        gamesTourModels: models,
        pinnedGamedIs: pinnedIds,
        isSearchMode: false,
        gameDisplayMode: GameDisplayMode.showfinishedGame,
      ),
    );
  }

  Future<void> hideFinishedGames() async {
    if (aboutTourModel == null) return;

    final pinnedIds = ref.read(gamesPinprovider(aboutTourModel!.id)).allPins;
    final allGames = _collectGamesAcrossVisibleStages();
    final unfinishedGames = allGames.where((g) => g.status == '*').toList();
    final sortedGames = _sortGamesForFilters(unfinishedGames, pinnedIds);
    final models = _mapGamesToModels(sortedGames);

    ref.read(gameDisplayModeProvider(aboutTourModel!.id).notifier).state =
        GameDisplayMode.hideFinishedGames;

    state = AsyncValue.data(
      GamesScreenModel(
        gamesTourModels: models,
        pinnedGamedIs: pinnedIds,
        isSearchMode: false,
        gameDisplayMode: GameDisplayMode.hideFinishedGames,
      ),
    );
  }

  Future<void> showAllGames() async {
    if (aboutTourModel == null) return;

    final pinnedIds = ref.read(gamesPinprovider(aboutTourModel!.id)).allPins;
    final allGames = _collectGamesAcrossVisibleStages();
    final sortedGames = _sortGamesForFilters(allGames, pinnedIds);
    final models = _mapGamesToModels(sortedGames);

    ref.read(gameDisplayModeProvider(aboutTourModel!.id).notifier).state =
        GameDisplayMode.all;

    state = AsyncValue.data(
      GamesScreenModel(
        gamesTourModels: models,
        pinnedGamedIs: pinnedIds,
        isSearchMode: false,
        gameDisplayMode: GameDisplayMode.all,
      ),
    );
  }

  List<Games> _collectGamesAcrossVisibleStages() {
    if (aboutTourModel == null) {
      return const <Games>[];
    }

    final baseGames =
        ref.read(gamesTourProvider(aboutTourModel!.id)).value ??
        const <Games>[];
    final gamesAppBar = ref.read(gamesAppBarProvider);

    if (!gamesAppBar.hasValue) {
      return baseGames;
    }

    final rounds =
        gamesAppBar.value?.gamesAppBarModels ?? const <GamesAppBarModel>[];
    final stageTourIds =
        rounds
            .where((round) => round.id.startsWith('$kKnockoutStagePrefix-'))
            .map((round) => round.id.replaceFirst('$kKnockoutStagePrefix-', ''))
            .where((id) => id.isNotEmpty)
            .toSet();

    if (stageTourIds.isEmpty) {
      return baseGames;
    }

    final aggregatedGames = <Games>[];
    final seenGameIds = <String>{};

    void addGames(List<Games> games) {
      for (final game in games) {
        if (seenGameIds.add(game.id)) {
          aggregatedGames.add(game);
        }
      }
    }

    addGames(baseGames);

    for (final stageTourId in stageTourIds) {
      if (stageTourId == aboutTourModel!.id) continue;
      final stageGames = ref.read(gamesTourProvider(stageTourId)).value;
      if (stageGames != null && stageGames.isNotEmpty) {
        addGames(stageGames);
      }
    }

    return aggregatedGames.isEmpty ? baseGames : aggregatedGames;
  }

  List<Games> _sortGamesForFilters(List<Games> games, List<String> pinnedIds) {
    if (games.isEmpty) return const <Games>[];

    final gameInfo = <String, (int, int)>{};
    for (final game in games) {
      gameInfo[game.id] = (
        _extractRoundNumber(game.roundSlug),
        _extractGameNumber(game.roundSlug),
      );
    }

    final sortedGames = List<Games>.from(games);
    sortedGames.sort((a, b) {
      final aPinned = pinnedIds.contains(a.id);
      final bPinned = pinnedIds.contains(b.id);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;

      final aLive = GameStatus.fromString(a.status).isOngoing;
      final bLive = GameStatus.fromString(b.status).isOngoing;
      if (aLive && !bLive) return -1;
      if (!aLive && bLive) return 1;

      final (roundA, gameA) = gameInfo[a.id] ?? (0, 0);
      final (roundB, gameB) = gameInfo[b.id] ?? (0, 0);

      if (roundA != roundB) return roundB.compareTo(roundA);
      if (gameA != gameB) return gameB.compareTo(gameA);

      final aBoard = a.boardNr, bBoard = b.boardNr;
      if (aBoard != null && bBoard != null) return aBoard.compareTo(bBoard);
      if (aBoard != null) return -1;
      if (bBoard != null) return 1;
      return 0;
    });

    return sortedGames;
  }

  List<GamesTourModel> _mapGamesToModels(List<Games> games) {
    if (games.isEmpty) return const <GamesTourModel>[];

    final models = <GamesTourModel>[];
    int skippedCount = 0;
    for (final game in games) {
      try {
        models.add(GamesTourModel.fromGame(game));
      } catch (e) {
        skippedCount++;
        debugPrint(
          '⚠️ _mapGamesToModels: Failed to parse game ${game.id} (${game.name ?? 'unnamed'}): $e',
        );
      }
    }
    if (skippedCount > 0) {
      debugPrint(
        '⚠️ _mapGamesToModels: Skipped $skippedCount games due to parsing errors',
      );
    }
    return models;
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

      // Search in main tournament
      final mainSearchResult = await gamesLocal.searchGamesWithScoring(
        tourId: aboutTourModel!.id,
        query: query,
      );
      final allResults = <GameSearchResult>[...mainSearchResult.results];

      // Check if this is a multi-stage knockout tournament and search all stages
      final gamesAppBar = ref.read(gamesAppBarProvider);
      if (gamesAppBar.hasValue) {
        final rounds = gamesAppBar.value?.gamesAppBarModels ?? [];
        final stageTourIds =
            rounds
                .where((r) => r.id.startsWith('$kKnockoutStagePrefix-'))
                .map((r) => r.id.replaceFirst('$kKnockoutStagePrefix-', ''))
                .where(
                  (id) => id != aboutTourModel!.id,
                ) // Don't search main tour twice
                .toSet()
                .toList();

        // Search each stage
        for (final stageTourId in stageTourIds) {
          try {
            final stageSearchResult = await gamesLocal.searchGamesWithScoring(
              tourId: stageTourId,
              query: query,
            );
            allResults.addAll(stageSearchResult.results);
          } catch (e) {
            debugPrint('Error searching stage $stageTourId: $e');
          }
        }
      }

      final games = allResults.map((r) => r.game).toList();

      final models = <GamesTourModel>[];
      for (final g in games) {
        try {
          models.add(GamesTourModel.fromGame(g));
        } catch (_) {}
      }

      debugPrint(
        '🔍 Search completed: Found ${models.length} games across all stages for query "$query"',
      );

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
      await ref
          .read(gamesTourProvider(aboutTourModel!.id).notifier)
          .refreshGames();
      await _recompute();
    } catch (e, st) {
      if (mounted) state = AsyncValue.error(e, st);
    }
  }

  // Helper method to extract round number from round slug.
  // Named knockout stages get high numbers so they sort after numbered rounds.
  int _extractRoundNumber(String roundSlug) {
    final slug = roundSlug.toLowerCase();
    if (slug.contains('final') &&
        !slug.contains('quarter') &&
        !slug.contains('semi')) {
      return 10000;
    }
    if (slug.contains('semifinal') || slug.contains('semi-final')) {
      return 9000;
    }
    if (slug.contains('quarterfinal') || slug.contains('quarter-final')) {
      return 8000;
    }
    final match =
        RegExp(r'round-?(\d+)', caseSensitive: false).firstMatch(roundSlug) ??
        RegExp(r'(\d+)').firstMatch(roundSlug);
    return int.tryParse(match?.group(1) ?? '0') ?? 0;
  }

  // Helper method to extract game number from round slug (e.g., "round-6--game-2" -> 2)
  int _extractGameNumber(String roundSlug) {
    final match = RegExp(
      r'game-?(\d+)',
      caseSensitive: false,
    ).firstMatch(roundSlug);
    return int.tryParse(match?.group(1) ?? '0') ?? 0;
  }
}

class _GamesTourDetailSlice {
  const _GamesTourDetailSlice({
    required this.isLoading,
    required this.error,
    required this.aboutTourModel,
  });

  factory _GamesTourDetailSlice.from(AsyncValue<TourDetailViewModel> value) {
    return _GamesTourDetailSlice(
      isLoading: value.isLoading,
      error: value.error,
      aboutTourModel: value.valueOrNull?.aboutTourModel,
    );
  }

  final bool isLoading;
  final Object? error;
  final AboutTourModel? aboutTourModel;

  bool get hasError => error != null;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _GamesTourDetailSlice &&
            other.isLoading == isLoading &&
            other.error == error &&
            other.aboutTourModel == aboutTourModel;
  }

  @override
  int get hashCode => Object.hash(isLoading, error, aboutTourModel);
}
