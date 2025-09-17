import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/repository/local_storage/tournament/games/pin_games_local_storage.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Updated provider with better null safety
final gamesTourScreenProvider = StateNotifierProvider<
  GamesTourScreenProvider,
  AsyncValue<GamesScreenModel>
>((ref) {
  // Watch tour details first - this is the primary dependency
  final tourDetailAsync = ref.watch(tourDetailScreenProvider);

  // Only proceed if tour details are loaded and valid
  if (tourDetailAsync.isLoading) {
    return GamesTourScreenProvider.loading(
      ref: ref,
      allGames: [],
      pinndedIds: [],
    );
  }

  if (tourDetailAsync.hasError) {
    return GamesTourScreenProvider.withError(
      ref: ref,
      error: tourDetailAsync.error!,
      allGames: [],
      pinndedIds: [],
    );
  }

  final aboutTourModel = tourDetailAsync.valueOrNull?.aboutTourModel;

  if (aboutTourModel == null) {
    return GamesTourScreenProvider.loading(
      ref: ref,
      allGames: [],
      pinndedIds: [],
    );
  }

  final gamesAsync = ref.watch(gamesTourProvider(aboutTourModel.id));

  if (gamesAsync.isLoading) {
    return GamesTourScreenProvider.loading(
      ref: ref,
      allGames: [],
      pinndedIds: [],
    );
  }

  if (gamesAsync.hasError) {
    return GamesTourScreenProvider.withError(
      ref: ref,
      error: gamesAsync.error!,
      allGames: [],
      pinndedIds: [],
    );
  }

  final games = gamesAsync.valueOrNull ?? [];
  final pinnedIds = ref.watch(gamesPinprovider(aboutTourModel.id)).value ?? [];

  return GamesTourScreenProvider(
    ref: ref,
    aboutTourModel: aboutTourModel,
    allGames: games,
    pinndedIds: pinnedIds,
  );
});

class GamesTourScreenProvider
    extends StateNotifier<AsyncValue<GamesScreenModel>> {
  GamesTourScreenProvider({
    required this.ref,
    required this.aboutTourModel,
    required this.allGames,
    required this.pinndedIds,
  }) : error = null,
       super(const AsyncValue.loading()) {
    _setupListeners();
    _init();
  }

  // Constructor for loading state
  GamesTourScreenProvider.loading({
    required this.ref,
    required this.allGames,
    required this.pinndedIds,
  }) : aboutTourModel = null,
       error = null,
       _selectedRoundId = null,
       super(const AsyncValue.loading());

  // Constructor for error state
  GamesTourScreenProvider.withError({
    required this.ref,
    required Object this.error,
    required this.allGames,
    required this.pinndedIds,
  }) : aboutTourModel = null,
       _selectedRoundId = null,
       super(AsyncValue.error(error, StackTrace.current));

  final Ref ref;
  String? _selectedRoundId;
  final AboutTourModel? aboutTourModel;
  final Object? error;

  List<Games> allGames;
  List<String> pinndedIds;

  // Search mode tracking
  bool _isSearchMode = false;
  List<Games>? _originalGamesBeforeSearch;

  void _setupListeners() {
    // Only setup listeners if we have aboutTourModel (not in loading/error states)
    if (aboutTourModel == null) return;

    // FIXED: Listen to pin changes and refresh state immediately
    ref.listen<AsyncValue<List<String>>>(gamesPinprovider(aboutTourModel!.id), (
      previous,
      next,
    ) {
      final previousPinned = previous?.valueOrNull ?? [];
      final currentPinned = next.valueOrNull ?? [];

      // Only update if pinned games actually changed
      if (!_listEquals(previousPinned, currentPinned)) {
        debugPrint('📌 Pinned games changed: ${currentPinned.length} pinned');
        pinndedIds = currentPinned;
        // Immediately refresh the state with updated pins
        _updateState(allGames);
      }
    });
  }

  // Helper method to compare lists
  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _init() async {
    try {
      await _updateState(allGames);
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }
  // In GamesTourScreenProvider class, modify the togglePinGame method:

  Future<void> togglePinGame(String gameId) async {
    // Check if we have the required dependencies
    if (aboutTourModel == null) {
      debugPrint('Cannot toggle pin: tour details not available');
      return;
    }

    try {
      final pinnedStorage = ref.read(pinGameLocalStorage);
      final currentPinnedIds = List<String>.from(pinndedIds);

      if (currentPinnedIds.contains(gameId)) {
        await pinnedStorage.removePinnedGameId(aboutTourModel!.id, gameId);
        currentPinnedIds.remove(gameId);
        debugPrint('📌 Unpinned game: $gameId');
      } else {
        await pinnedStorage.addPinnedGameId(aboutTourModel!.id, gameId);
        currentPinnedIds.add(gameId);
        debugPrint('📌 Pinned game: $gameId');
      }

      // FIXED: Update local state immediately and refresh provider
      pinndedIds = currentPinnedIds;

      // Force refresh the pin provider to sync with storage
      ref.invalidate(gamesPinprovider);

      // FIXED: Temporarily disable round scrolling during pin operations
      final originalSelectedRoundId = _selectedRoundId;
      _selectedRoundId = null; // Prevent scroll position update

      // Immediately update the display state
      await _updateState(allGames);

      // Restore the selected round ID without triggering scroll
      _selectedRoundId = originalSelectedRoundId;
    } catch (e, st) {
      debugPrint('Error toggling pin for game $gameId: $e');
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
    } else {
      _isSearchMode = false;
      _updateState(allGames);
    }
  }

  Future<void> unpinAllGames() async {
    try {
      await ref.read(pinGameLocalStorage).clearAllPinnedGames();
      pinndedIds = [];
      ref.invalidate(gamesPinprovider);
      await _updateState(allGames);
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  Future<void> _updateState(List<Games> allGames) async {
    try {
      // If not in search mode, also update the original games cache
      if (!_isSearchMode) {
        _originalGamesBeforeSearch = List<Games>.from(allGames);
        debugPrint('🔍 Updated original games cache: ${allGames.length} games');
      }

      // Sort games by round first, then by other criteria
      final sortedGames = List<Games>.from(allGames);

      sortedGames.sort((a, b) {
        // First priority: Pinned games (but only if not in search mode)
        if (!_isSearchMode) {
          final aPinned = pinndedIds.contains(a.id);
          final bPinned = pinndedIds.contains(b.id);
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

      if (mounted) {
        state = AsyncValue.data(
          GamesScreenModel(
            gamesTourModels: gamesTourModels,
            pinnedGamedIs: _isSearchMode ? [] : pinndedIds,
          ),
        );

        debugPrint(
          '🔍 State updated with ${gamesTourModels.length} games (search mode: $_isSearchMode, pinned: ${pinndedIds.length})',
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
      if (!_isSearchMode) {
        _originalGamesBeforeSearch = List<Games>.from(allGames);
        debugPrint(
          '🔍 Stored original games: ${_originalGamesBeforeSearch!.length} games',
        );
      }

      _isSearchMode = true;

      final gamesLocalStorageProvider = ref.read(gamesLocalStorage);
      final searchResult = await gamesLocalStorageProvider
          .searchGamesWithScoring(tourId: aboutTourModel!.id, query: query);

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
          GamesScreenModel(gamesTourModels: gamesTourModels, pinnedGamedIs: []),
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
      ref.refresh(gamesTourProvider(aboutTourModel!.id));
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  @override
  void dispose() {
    _originalGamesBeforeSearch = null;
    _isSearchMode = false;
    super.dispose();
  }
}
