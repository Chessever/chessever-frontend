import 'package:chessever2/repository/local_storage/tournament/games/games_local_storage.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/model/about_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart';
import 'package:chessever2/repository/local_storage/tournament/games/pin_games_local_storage.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_pin_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/games_tour_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_screen_provider.dart';
import 'package:chessever2/widgets/search/gameSearch/enhanced_game_search.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Provider to track scroll position for round changes
final roundScrollPositionProvider = StateProvider<int?>((ref) => null);
final scrollToGameIndexProvider = StateProvider<int?>((ref) => null);

// Updated provider with listener-based approach
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
      error: tourDetailAsync.error!,
      allGames: [],
      pinndedIds: [],
    );
  }
  final games = gamesAsync.valueOrNull ?? [];
  final pinnedIds = ref.watch(gamesPinprovider).value ?? [];

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
  int? _lastViewedGameIndex;

  void setLastViewedGameIndex(int? index) {
    if (index == null) return;
    _lastViewedGameIndex = index;
    _scrollToLastViewedGame();
  }

  Future<void> _scrollToLastViewedGame() async {
    if (_lastViewedGameIndex == null) return;

    final games = state.valueOrNull?.gamesTourModels;
    if (games == null || _lastViewedGameIndex! >= games.length) return;

    final game = games[_lastViewedGameIndex!];
    final roundId = game.roundId;

    final roundGames = games.where((g) => g.roundId == roundId).toList();
    final localIndex = roundGames.indexWhere((g) => g.gameId == game.gameId);
    if (localIndex == -1) return;

    ref.read(scrollToGameIndexProvider.notifier).state = _lastViewedGameIndex;
  }

  void _setupListeners() {
    ref.listen<AsyncValue<dynamic>>(
      gamesAppBarProvider,
      (previous, next) {
        final newSelectedRound = next.valueOrNull?.selectedId;

        if (newSelectedRound != _selectedRoundId) {
          debugPrint(
            '🔄 Round changed from $_selectedRoundId to $newSelectedRound',
          );
          _selectedRoundId = newSelectedRound;

          _updateScrollPositionForRound();
        }
      },
    );
  }

  void _updateScrollPositionForRound() {
    if (_selectedRoundId == null || _isSearchMode) return;

    final currentState = state.valueOrNull;
    if (currentState != null && allGames.isNotEmpty) {
      final scrollToIndex = _findFirstGameIndexForRound(
        currentState.gamesTourModels,
        _selectedRoundId!,
      );

      if (scrollToIndex != null) {
        ref.read(roundScrollPositionProvider.notifier).state = scrollToIndex;
        debugPrint('🔄 Updated scroll position to index: $scrollToIndex');
      }
    }
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
      await _init();
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
    } else {
      _isSearchMode = false;
      _updateState(allGames);
    }
  }

  Future<void> unpinAllGames() async {
    try {
      await ref.read(pinGameLocalStorage).clearAllPinnedGames();
      await _init();
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

      // Calculate scroll position for selected round (only if not in search mode)
      int? scrollToIndex;
      if (_selectedRoundId != null && !_isSearchMode) {
        scrollToIndex = _findFirstGameIndexForRound(
          gamesTourModels,
          _selectedRoundId!,
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
            pinnedGamedIs: _isSearchMode ? [] : pinndedIds,
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
        final originalGame = allGames.firstWhere(
          (game) => game.id == games[i].gameId,
          orElse: () => throw StateError('Game not found'),
        );
        if (originalGame.roundId == roundId) {
          return i;
        }
    }
    return null;
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
      ref.refresh(gamesTourProvider(aboutTourModel!.id));
    } catch (e, st) {
      if (mounted) {
        state = AsyncValue.error(e, st);
      }
    }
  }

  // Method to scroll to a specific round
  void scrollToRound(String roundId) {
    _selectedRoundId = roundId;
    _updateScrollPositionForRound();
  }

  @override
  void dispose() {
    _originalGamesBeforeSearch = null;
    _isSearchMode = false;
    super.dispose();
  }
}
