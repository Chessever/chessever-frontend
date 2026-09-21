import 'dart:async';
import 'package:chessever2/screens/gamebase/event_view/gamebase_virtual_event_id.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart'
    show standingsSearchQueryProvider;
import 'round_expansion_provider.dart';
import 'match_expansion_provider.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/providers/event_pin_refresh_provider.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/group_event/model/tour_detail_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/game_display_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_priority_matching.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/knockout_stage_round_resolver.dart';
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

@visibleForTesting
bool shouldInitializeGamesScreen({
  required GamesScreenModel? currentScreen,
  required AsyncValue<List<Games>> nextGames,
}) {
  return currentScreen == null && nextGames.hasValue;
}

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
  final pinnedIdSet = args.pinnedIds.toSet();
  sortedGames.sort((a, b) {
    // FIRST PRIORITY: Pinned games (only in non-search mode)
    if (!args.isSearchMode) {
      final aPinned = pinnedIdSet.contains(a.id);
      final bPinned = pinnedIdSet.contains(b.id);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
    }

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

  // 3. Map list metadata; visible cards replay their own board positions.
  final models = <GamesTourModel>[];
  for (final g in sortedGames) {
    try {
      models.add(GamesTourModel.fromGameIndex(g));
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
    Future.microtask(() {
      if (mounted) _initialize();
    });
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
  int _recomputeGeneration = 0;
  int _searchGeneration = 0;
  String? _activeSearchQuery;
  List<Games>? _searchCatalog;
  Future<List<Games>>? _searchCatalogFetch;
  Set<String> _searchTourIds = {};

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
      if (current != null) {
        // Keep the screen model in sync with the persisted preference.
        // The grouped provider does the actual display filtering off
        // gameDisplayMode, so we just need to mirror it onto the model.
        if (mounted) {
          state = state.whenData(
            (value) => value.copyWith(gameDisplayMode: next),
          );
        }
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

      // Loading -> data is an initial result even when the result is empty.
      // Ignoring an empty first result leaves this provider in AsyncLoading
      // forever, so the Games tab never reaches its empty state.
      if (shouldInitializeGamesScreen(
        currentScreen: current,
        nextGames: next,
      )) {
        debugPrint(
          '🎮 GamesTourScreen: Initial data load - triggering recompute with ${nextGames.length} games',
        );
        _recompute();
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
              !haveSameRawGamePriorityInputs(prev, next) ||
              prev.boardNr != next.boardNr ||
              prev.fen != next.fen ||
              prev.pgn != next.pgn ||
              prev.isPgnDeferred != next.isPgnDeferred ||
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

      if (_activeSearchQuery != null) {
        // Refresh matching/status for received rows without dropping results
        // from rounds that have never been mounted.
        final catalog = _searchCatalog;
        if (catalog != null) {
          final byId = {for (final game in catalog) game.id: game};
          for (final game in nextGames) {
            byId[game.id] = game.copyWith(pgn: game.pgn ?? byId[game.id]?.pgn);
          }
          _searchCatalog = byId.values.toList();
          _publishSearchResults();
        }
        return;
      }
      _recompute();
    });

    ref.listen<GamesPinState>(gamesPinprovider(aboutTourModel!.id), (
      previous,
      pins,
    ) {
      final current = state.valueOrNull;
      final allPins = pins.allPins;
      if (current == null || listEquals(current.pinnedGamedIs, allPins)) {
        return;
      }

      // Pin changes do not require reparsing and sorting every game in an
      // isolate. The grouped presentation owns stable priority placement;
      // this model only needs the latest ids for pin icons and navigation.
      if (mounted) {
        state = state.whenData(
          (value) => value.copyWith(pinnedGamedIs: allPins),
        );
      }
    });
  }

  Future<void> _initialize() async {
    if (aboutTourModel == null) return;

    final retainedQuery = ref.read(standingsSearchQueryProvider).trim();
    if (retainedQuery.isNotEmpty) {
      await searchGamesEnhanced(retainedQuery);
      return;
    }

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

    if (_activeSearchQuery != null && isSearchModeOverride != false) {
      final current = state.valueOrNull;
      if (current != null && pinnedIdsOverride != null) {
        state = state.whenData(
          (value) => value.copyWith(pinnedGamedIs: pinnedIdsOverride),
        );
      }
      return;
    }
    int? generation;
    try {
      final gamesAsync = ref.read(gamesTourProvider(aboutTourModel!.id));
      if (gamesAsync.isLoading) {
        return;
      }
      generation = ++_recomputeGeneration;
      final pins = ref.read(gamesPinprovider(aboutTourModel!.id));

      final allGames = gamesAsync.value ?? <Games>[];
      final pinnedIds = pinnedIdsOverride ?? pins.allPins;

      final current = state.valueOrNull;
      final isSearchMode =
          isSearchModeOverride ?? (current?.isSearchMode ?? false);
      final searchQuery =
          isSearchMode ? searchQueryOverride ?? current?.searchQuery : null;

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

      if (!mounted || generation != _recomputeGeneration) return;

      // Read the persisted display mode so it survives notifier recreations
      // (category change, live-tour-id push). `current?.gameDisplayMode` is
      // null on a freshly recreated notifier, which is what produced the
      // "Focus on live games → Show all games" snap-back. The provider is
      // family-keyed by tourId so state can't bleed across tournaments.
      final persistedDisplayMode = ref.read(
        gameDisplayModeProvider(aboutTourModel!.id),
      );

      final latestPinnedIds =
          pinnedIdsOverride ??
          ref.read(gamesPinprovider(aboutTourModel!.id)).allPins;
      state = AsyncValue.data(
        GamesScreenModel(
          gamesTourModels: models,
          // Show pins even in search mode for correct icon state.
          pinnedGamedIs: latestPinnedIds,
          isSearchMode: isSearchMode,
          searchQuery: searchQuery,
          gameDisplayMode: persistedDisplayMode,
        ),
      );
    } catch (e, st) {
      if (mounted &&
          (generation == null || generation == _recomputeGeneration)) {
        state = AsyncValue.error(e, st);
      }
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
    _searchGeneration++;
    _activeSearchQuery = null;
    _searchCatalog = null;
    _searchCatalogFetch = null;
    _searchTourIds = {};
    state = const AsyncLoading();
    ref
        .read(gamesPinprovider(aboutTourModel!.id).notifier)
        .setQueryCatalog(const []);
    final pins = ref.read(gamesPinprovider(aboutTourModel!.id)).allPins;
    _recompute(
      isSearchModeOverride: false,
      searchQueryOverride: null,
      pinnedIdsOverride: pins, // ensure immediate pin state after clearing
    );
  }

  Future<void> unpinAllGames() async {
    if (aboutTourModel == null) return;
    try {
      final pins = ref.read(gamesPinprovider(aboutTourModel!.id).notifier);
      // Manual pins and auto-pins are two separate stores; clearing only one
      // leaves boards pinned after "Unpin all".
      await pins.disableAutoPin();
      await pins.clearManualPins();
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
    _setDisplayMode(GameDisplayMode.showfinishedGame);
  }

  /// Live focus changes order, never query membership.
  Future<void> hideFinishedGames() async {
    _setDisplayMode(GameDisplayMode.hideFinishedGames);
  }

  Future<void> showAllGames() async {
    _setDisplayMode(GameDisplayMode.all);
  }

  void _setDisplayMode(GameDisplayMode mode) {
    if (aboutTourModel == null) return;
    // Grouping applies the mode to every complete round/query result. Keeping
    // the source intact also makes switching back from finished-only lossless.
    ref.read(gameDisplayModeProvider(aboutTourModel!.id).notifier).state = mode;
  }

  List<GamesTourModel> _mapGamesToModels(List<Games> games) {
    if (games.isEmpty) return const <GamesTourModel>[];

    final models = <GamesTourModel>[];
    int skippedCount = 0;
    for (final game in games) {
      try {
        models.add(GamesTourModel.fromGameIndex(game));
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
    query = query.trim();
    if (query.isEmpty) {
      clearSearch();
      return;
    }

    final generation = ++_searchGeneration;
    _recomputeGeneration++; // Invalidate a pre-search isolate result.
    if (_activeSearchQuery != query) {
      ref.read(searchRoundExpansionProvider.notifier).reset();
      ref.read(searchMatchExpansionProvider.notifier).reset();
    }
    _activeSearchQuery = query;
    _searchCatalog = null;
    state = const AsyncLoading<GamesScreenModel>().copyWithPrevious(
      AsyncData(
        GamesScreenModel(
          gamesTourModels: const [],
          pinnedGamedIs: ref.read(gamesPinprovider(aboutTourModel!.id)).allPins,
          isSearchMode: true,
          searchQuery: query,
          gameDisplayMode: ref.read(
            gameDisplayModeProvider(aboutTourModel!.id),
          ),
        ),
      ),
    );
    try {
      // Metadata defines category/stage scope, never loaded game providers.
      final appBar = await _waitForSearchRounds();
      if (!mounted || generation != _searchGeneration) return;
      final tourId = aboutTourModel!.id;
      final tourIds = <String>{
        tourId,
        ...siblingKnockoutStageTourIds(
          rounds: appBar.gamesAppBarModels,
          selectedTourId: tourId,
          knownTourIds:
              ref
                  .read(tourDetailScreenProvider)
                  .valueOrNull
                  ?.tours
                  .map((tour) => tour.tour.id) ??
              const <String>[],
        ),
      };
      if (!setEquals(tourIds, _searchTourIds)) {
        _searchTourIds = tourIds;
        _searchCatalogFetch = null;
      }
      // Share overlapping keystrokes, but always start a fresh backend search
      // after a completed request. The SQLite browsing cache may be stale.
      final fetch = _searchCatalogFetch ??= _fetchSearchCatalog(tourIds);
      try {
        final catalog = await fetch;
        if (!mounted || generation != _searchGeneration) return;
        _searchCatalog = catalog;
        ref.read(gamesPinprovider(tourId).notifier).setQueryCatalog(catalog);
        _publishSearchResults();
      } finally {
        if (identical(_searchCatalogFetch, fetch)) _searchCatalogFetch = null;
      }
    } catch (e, st) {
      if (mounted && generation == _searchGeneration) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<GamesAppBarViewModel> _waitForSearchRounds() =>
      ref.read(gamesAppBarProvider.notifier).waitForRounds();

  Future<List<Games>> _fetchSearchCatalog(Set<String> tourIds) async {
    final repository = ref.read(gameRepositoryProvider);
    final byId = <String, Games>{};
    for (final tourId in tourIds) {
      // Existing paginated Supabase query with result/rating PGN fallbacks.
      // No round, viewport, pin, view-mode or expansion predicate belongs here.
      final games =
          isVirtualGamebaseId(tourId)
              ? await ref.read(completeGamesTourFutureProvider(tourId).future)
              : await repository.getTourGamePreviews(tourId);
      for (final game in games) {
        byId[game.id] = game;
      }
    }
    return byId.values.toList();
  }

  void _publishSearchResults() {
    final query = _activeSearchQuery;
    final catalog = _searchCatalog;
    if (!mounted || query == null || catalog == null) return;
    final result = searchTournamentGameCatalog(catalog, query);
    state = AsyncData(
      GamesScreenModel(
        gamesTourModels: _mapGamesToModels(
          result.results.map((r) => r.game).toList(),
        ),
        pinnedGamedIs: ref.read(gamesPinprovider(aboutTourModel!.id)).allPins,
        isSearchMode: true,
        searchQuery: query,
        gameDisplayMode: ref.read(gameDisplayModeProvider(aboutTourModel!.id)),
      ),
    );
  }

  Future<void> refreshGames() async {
    if (aboutTourModel == null) return;
    final query = _activeSearchQuery;
    if (query != null) {
      _searchCatalogFetch = null;
      await searchGamesEnhanced(query);
      return;
    }
    try {
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
