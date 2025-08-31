import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/repository/local_storage/tournament/games/pin_games_local_storage.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Provider to track scroll position for round changes
final roundScrollPositionProvider = StateProvider<int?>((ref) => null);

// Fixed provider with proper null handling and dependency management
final gamesTourScreenProvider = AutoDisposeStateNotifierProvider<
  GamesTourScreenProvider,
  AsyncValue<GamesScreenModel>
>((ref) {
  // Watch tour details first - this is the primary dependency
  final tourDetailAsync = ref.watch(tourDetailScreenProvider);

  // Only proceed if tour details are loaded and valid
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

  // Now watch app bar - it's secondary to tour details
  final gamesAppBarAsync = ref.watch(gamesAppBarProvider);
  final selectedRound = gamesAppBarAsync.valueOrNull?.selectedId;

  // Don't block on app bar loading/errors - games can load without round selection
  return GamesTourScreenProvider(
    ref: ref,
    selectedRoundId: selectedRound,
    aboutTourModel: aboutTourModel,
  );
});

class GamesTourScreenProvider
    extends StateNotifier<AsyncValue<GamesScreenModel>> {
  GamesTourScreenProvider({
    required this.ref,
    required this.selectedRoundId,
    required this.aboutTourModel,
  }) : error = null,
       super(const AsyncValue.loading()) {
    _init();
  }

  // Constructor for loading state
  GamesTourScreenProvider.loading({
    required this.ref,
  }) : selectedRoundId = null,
       aboutTourModel = null,
       error = null,
       super(const AsyncValue.loading());

  // Constructor for error state
  GamesTourScreenProvider.withError({
    required this.ref,
    required Object this.error,
  }) : selectedRoundId = null,
       aboutTourModel = null,
       super(AsyncValue.error(error, StackTrace.current));

  final Ref ref;
  final String? selectedRoundId;
  final AboutTourModel? aboutTourModel;
  final Object? error;

  // Cache for reducing redundant operations
  List<Games>? _cachedGames;
  List<String>? _cachedPinnedIds;

  // Search mode tracking
  bool _isSearchMode = false;
  List<Games>? _originalGamesBeforeSearch;

  Future<void> togglePinGame(String gameId) async {
    // Check if we have the required dependencies
    if (aboutTourModel == null) {
      debugPrint('Cannot toggle pin: tour details not available');
      return;
    }

    try {
      final pinnedStorage = ref.read(pinGameLocalStorage);
      final currentPinnedIds = await pinnedStorage.getPinnedGameIds();

      if (currentPinnedIds.contains(gameId)) {
        await pinnedStorage.removePinnedGameId(gameId);
      } else {
        await pinnedStorage.addPinnedGameId(gameId);
      }

      // Optimized update - only refresh if we have cached games
      if (_cachedGames != null) {
        await _updateState(_cachedGames!);
      } else {
        await _init();
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  void clearSearch() {
    debugPrint('🔍 clearSearch called - resetting to all games');

    if (_isSearchMode && _originalGamesBeforeSearch != null) {
      debugPrint(
        '🔍 Restoring from cached games: ${_originalGamesBeforeSearch!.length} games',
      );
      _isSearchMode = false;
      _updateState(_originalGamesBeforeSearch!);
    } else if (_cachedGames != null) {
      debugPrint(
        '🔍 Restoring from current cache: ${_cachedGames!.length} games',
      );
      _isSearchMode = false;
      _updateState(_cachedGames!);
    } else {
      debugPrint('🔍 No cache available, refreshing from storage');
      _isSearchMode = false;
      refreshGames();
    }
  }

  Future<void> unpinAllGames() async {
    try {
      await ref.read(pinGameLocalStorage).clearAllPinnedGames();

      // Optimized update
      if (_cachedGames != null) {
        await _updateState(_cachedGames!);
      } else {
        await _init();
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> _updateState(List<Games> allGames) async {
    try {
      // Cache the games for optimization
      _cachedGames = allGames;

      // If not in search mode, also update the original games cache
      if (!_isSearchMode) {
        _originalGamesBeforeSearch = List<Games>.from(allGames);
        debugPrint('🔍 Updated original games cache: ${allGames.length} games');
      }

      // Get pinned IDs
      final pinnedIds = await ref.read(pinGameLocalStorage).getPinnedGameIds();
      _cachedPinnedIds = pinnedIds;

      // Sort games by round first, then by other criteria
      final sortedGames = List<Games>.from(allGames);

      sortedGames.sort((a, b) {
        // First priority: Pinned games (but only if not in search mode)
        if (!_isSearchMode) {
          final aPinned = pinnedIds.contains(a.id);
          final bPinned = pinnedIds.contains(b.id);
          if (aPinned && !bPinned) return -1;
          if (!aPinned && bPinned) return 1;
        }

        // Second priority: Sort by round (round1, round2, etc.)
        final roundComparison = _compareRounds(a.roundId, b.roundId);
        if (roundComparison != 0) return roundComparison;

        // Third priority: Sort by board number within same round
        final aBoardNr = a.boardNr;
        final bBoardNr = b.boardNr;

        if (aBoardNr != null && bBoardNr != null) {
          return aBoardNr.compareTo(bBoardNr);
        }
        if (aBoardNr != null && bBoardNr == null) return -1;
        if (aBoardNr == null && bBoardNr != null) return 1;

        return 0;
      });

      // Convert to GamesTourModel with error handling
      final gamesTourModels = <GamesTourModel>[];
      for (final game in sortedGames) {
        try {
          final model = GamesTourModel.fromGame(game);
          gamesTourModels.add(model);
        } catch (e) {
          print('Error converting game ${game.id}: $e');
        }
      }

      // Calculate scroll position for selected round (only if not in search mode)
      int? scrollToIndex;
      if (selectedRoundId != null && !_isSearchMode) {
        scrollToIndex = _findFirstGameIndexForRound(
          gamesTourModels,
          selectedRoundId!,
        );
      }

      if (mounted) {
        // Update scroll position if needed
        if (scrollToIndex != null) {
          ref.read(roundScrollPositionProvider.notifier).state = scrollToIndex;
        }

        state = AsyncValue.data(
          GamesScreenModel(
            gamesTourModels: gamesTourModels,
            pinnedGamedIs: _isSearchMode ? [] : pinnedIds,
            scrollToIndex: scrollToIndex,
          ),
        );

        debugPrint(
          '🔍 State updated with ${gamesTourModels.length} games (search mode: $_isSearchMode)',
        );
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  // Helper method to compare round IDs (round1, round2, etc.)
  int _compareRounds(String roundIdA, String roundIdB) {
    final roundNumberA = _extractRoundNumber(roundIdA);
    final roundNumberB = _extractRoundNumber(roundIdB);
    return roundNumberA.compareTo(roundNumberB);
  }

  // Extract round number from round ID (e.g., "round7" -> 7)
  int _extractRoundNumber(String roundId) {
    final match = RegExp(
      r'round(\d+)',
      caseSensitive: false,
    ).firstMatch(roundId);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '0') ?? 0;
    }
    final numberMatch = RegExp(r'(\d+)').firstMatch(roundId);
    if (numberMatch != null) {
      return int.tryParse(numberMatch.group(1) ?? '0') ?? 0;
    }
    return 0;
  }

  // Find the first game index for a specific round
  int? _findFirstGameIndexForRound(List<GamesTourModel> games, String roundId) {
    for (int i = 0; i < games.length; i++) {
      if (_cachedGames != null) {
        final originalGame = _cachedGames!.firstWhere(
          (game) => game.id == games[i].gameId,
          orElse: () => throw StateError('Game not found'),
        );
        if (originalGame.roundId == roundId) {
          return i;
        }
      }
    }
    return null;
  }

  Future<void> _init() async {
    try {
      final gamesLocalStorageProvider = ref.read(gamesLocalStorage);
      final allGames = await gamesLocalStorageProvider.fetchAndSaveGames(
        aboutTourModel!.id,
      );
      await _updateState(allGames);
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> searchGamesEnhanced(String query) async {
    // Check if we have the required dependencies
    if (aboutTourModel == null) {
      debugPrint('Cannot search: tour details not available');
      return;
    }

    try {
      if (query.isEmpty) {
        clearSearch();
        return;
      }

      // Store original games before entering search mode
      if (!_isSearchMode && _cachedGames != null) {
        _originalGamesBeforeSearch = List<Games>.from(_cachedGames!);
        debugPrint(
          '🔍 Stored original games: ${_originalGamesBeforeSearch!.length} games',
        );
      }

      _isSearchMode = true;

      final selectedTourId = ref.read(selectedTourIdProvider);
      if (selectedTourId == null) {
        throw Exception('No tournament selected');
      }

      final gamesLocalStorageProvider = ref.read(gamesLocalStorage);
      final searchResult = await gamesLocalStorageProvider
          .searchGamesWithScoring(
            tourId: selectedTourId,
            query: query,
          );

      final games = searchResult.results.map((result) => result.game).toList();
      debugPrint('🔍 Search found: ${games.length} games');

      // Convert to GamesTourModel with error handling
      final gamesTourModels = <GamesTourModel>[];
      for (final game in games) {
        try {
          final model = GamesTourModel.fromGame(game);
          gamesTourModels.add(model);
        } catch (e) {
          print('Error converting search result game ${game.id}: $e');
        }
      }

      if (mounted) {
        state = AsyncValue.data(
          GamesScreenModel(
            gamesTourModels: gamesTourModels,
            pinnedGamedIs: [],
            scrollToIndex: null,
          ),
        );
      }
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> refreshGames() async {
    // Check if we have the required dependencies
    if (aboutTourModel == null) {
      debugPrint('Cannot refresh: tour details not available');
      return;
    }

    try {
      // Clear cache to force fresh data
      _cachedGames = null;
      _cachedPinnedIds = null;

      final gamesLocalStorageProvider = ref.read(gamesLocalStorage);
      final allGames = await gamesLocalStorageProvider.refresh(
        aboutTourModel!.id,
      );
      await _updateState(allGames);
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  // Method to scroll to a specific round
  void scrollToRound(String roundId) {
    final currentState = state.valueOrNull;
    if (currentState != null && _cachedGames != null) {
      final scrollToIndex = _findFirstGameIndexForRound(
        currentState.gamesTourModels,
        roundId,
      );
      if (scrollToIndex != null) {
        ref.read(roundScrollPositionProvider.notifier).state = scrollToIndex;
      }
    }
  }

  @override
  void dispose() {
    // Clear all caches on dispose
    _cachedGames = null;
    _cachedPinnedIds = null;
    _originalGamesBeforeSearch = null;
    _isSearchMode = false;
    super.dispose();
  }
}
