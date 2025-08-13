import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/tournaments/model/about_tour_model.dart';
import 'package:chessever2/screens/tournaments/model/games_tour_model.dart';
import 'package:chessever2/screens/tournaments/providers/games_app_bar_provider.dart';
import 'package:chessever2/screens/tournaments/providers/pintop_storage.dart';
import 'package:chessever2/screens/tournaments/providers/tour_detail_screen_provider.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Provider to track scroll position for round changes
final roundScrollPositionProvider = StateProvider<int?>((ref) => null);

// Updated provider - no more round filtering, shows all games
final gamesTourScreenProvider = StateNotifierProvider.autoDispose<
  GamesTourScreenProvider,
  AsyncValue<GamesScreenModel>
>((ref) {
  // Watch dependencies and handle loading states properly
  final gamesAppBarAsync = ref.watch(gamesAppBarProvider);
  final tourDetailAsync = ref.watch(tourDetailScreenProvider);

  // Return error state if dependencies have errors
  if (gamesAppBarAsync.hasError || tourDetailAsync.hasError) {
    final error = gamesAppBarAsync.error ?? tourDetailAsync.error;

    throw Exception(error);
  }

  // Get values safely - we still track selected round for scrolling
  final selectedRound = gamesAppBarAsync.valueOrNull?.selectedId;
  final aboutTourModel = tourDetailAsync.valueOrNull?.aboutTourModel;

  // Return error state if required dependencies are missing
  if (aboutTourModel == null) {
    throw Exception(
      'Tour details are not available. Please select a tournament.',
    );
  }

  return GamesTourScreenProvider(
    ref: ref,
    selectedRoundId: selectedRound, // Now used for scrolling, not filtering
    aboutTourModel: aboutTourModel,
  );
});

class GamesTourScreenProvider
    extends StateNotifier<AsyncValue<GamesScreenModel>> {
  GamesTourScreenProvider({
    required this.ref,
    required this.selectedRoundId,
    required this.aboutTourModel,
  }) : super(const AsyncValue.loading()) {
    _init();
  }

  final Ref ref;
  final String? selectedRoundId; // Used for scrolling to round position
  final AboutTourModel aboutTourModel;

  // Cache for reducing redundant operations
  List<Games>? _cachedGames;
  List<String>? _cachedPinnedIds;

  // Search mode tracking
  bool _isSearchMode = false;
  List<Games>? _originalGamesBeforeSearch; // Store original games before search

  Future<void> togglePinGame(String gameId) async {
    try {
      final pinnedStorage = ref.read(pinnedGamesStorageProvider);
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
      // Immediately restore from cached games instead of doing a full refresh
      debugPrint(
        '🔍 Restoring from cached games: ${_originalGamesBeforeSearch!.length} games',
      );
      _isSearchMode = false;
      _updateState(_originalGamesBeforeSearch!);
    } else if (_cachedGames != null) {
      // Fallback: use current cached games
      debugPrint(
        '🔍 Restoring from current cache: ${_cachedGames!.length} games',
      );
      _isSearchMode = false;
      _updateState(_cachedGames!);
    } else {
      // Last resort: refresh from storage
      debugPrint('🔍 No cache available, refreshing from storage');
      _isSearchMode = false;
      refreshGames();
    }
  }

  Future<void> unpinAllGames() async {
    try {
      await ref.read(pinnedGamesStorageProvider).clearAllPinnedGames();

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
      final pinnedIds =
          await ref.read(pinnedGamesStorageProvider).getPinnedGameIds();
      _cachedPinnedIds = pinnedIds;

      // NO MORE FILTERING - Show ALL games from ALL rounds
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
            pinnedGamedIs:
                _isSearchMode ? [] : pinnedIds, // No pins in search mode
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
    // Extract round numbers for proper sorting
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
    // Fallback: try to extract any number from the string
    final numberMatch = RegExp(r'(\d+)').firstMatch(roundId);
    if (numberMatch != null) {
      return int.tryParse(numberMatch.group(1) ?? '0') ?? 0;
    }
    return 0; // Default for non-numeric rounds
  }

  // Find the first game index for a specific round
  int? _findFirstGameIndexForRound(List<GamesTourModel> games, String roundId) {
    for (int i = 0; i < games.length; i++) {
      // You'll need to add roundId to GamesTourModel or access it differently
      // For now, assuming you can access the original game data
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
        aboutTourModel.id,
      );
      await _updateState(allGames);
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> searchGamesEnhanced(String query) async {
    try {
      if (query.isEmpty) {
        // Return to normal state if query is empty
        clearSearch();
        return;
      }

      // Store original games before entering search mode (if not already stored)
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

      // Use the enhanced search with scoring
      final gamesLocalStorageProvider = ref.read(gamesLocalStorage);
      final searchResult = await gamesLocalStorageProvider
          .searchGamesWithScoring(
            tourId: selectedTourId,
            query: query,
          );

      // Extract games from search results (already sorted by score)
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
            pinnedGamedIs: [], // Don't show pins in search results
            scrollToIndex: null, // No scrolling for search results
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
    try {
      // Clear cache to force fresh data
      _cachedGames = null;
      _cachedPinnedIds = null;

      final gamesLocalStorageProvider = ref.read(gamesLocalStorage);
      final allGames = await gamesLocalStorageProvider.refresh(
        aboutTourModel.id,
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
