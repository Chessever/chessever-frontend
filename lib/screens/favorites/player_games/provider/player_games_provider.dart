import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/favorites/player_games/view_model/player_games_state.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const int _pageSize = 20; // Number of games per page

/// AsyncNotifier for paginated player games
class PlayerGamesNotifier extends AutoDisposeFamilyAsyncNotifier<PlayerGamesState, String> {
  String get fideId => arg;

  GameRepository get _gameRepository => ref.read(gameRepositoryProvider);
  TourRepository get _tourRepository => ref.read(tourRepositoryProvider);

  @override
  Future<PlayerGamesState> build(String arg) async {
    // Load initial games on build
    return await _loadInitialGames();
  }

  /// Load initial games (first page)
  Future<PlayerGamesState> _loadInitialGames() async {
    try {
      debugPrint('===== PlayerGamesNotifier: Loading games for fideId: $fideId =====');

      final games = await _gameRepository.getGamesByFideId(
        fideId,
        limit: _pageSize,
      );

      debugPrint('===== Fetched ${games.length} games from repository =====');

      if (games.isEmpty) {
        debugPrint('===== No games found for fideId: $fideId =====');
        return const PlayerGamesState(
          tournamentGroups: [],
          isLoading: false,
          hasMore: false,
          currentPage: 1,
        );
      }

      debugPrint('===== Converting ${games.length} games to GamesTourModel =====');
      // Convert to GamesTourModel
      final gamesTourModels = games
          .map((game) => GamesTourModel.fromGame(game))
          .toList();

      debugPrint('===== Grouping games by tournament =====');
      // Group by tournament
      final tournamentGroups = await _groupGamesByTournament(gamesTourModels);

      debugPrint('===== Created ${tournamentGroups.length} tournament groups =====');

      return PlayerGamesState(
        tournamentGroups: tournamentGroups,
        isLoading: false,
        hasMore: games.length >= _pageSize,
        currentPage: 1,
      );
    } catch (e, stack) {
      debugPrint('===== ERROR in _loadInitialGames =====');
      debugPrint('FideId: $fideId');
      debugPrint('Error type: ${e.runtimeType}');
      debugPrint('Error: $e');
      debugPrint('Stack trace: $stack');
      rethrow;
    }
  }

  /// Load more games (pagination)
  Future<void> loadMoreGames() async {
    final currentState = state.valueOrNull;
    if (currentState == null || currentState.isLoading || !currentState.hasMore) {
      return;
    }

    // Set loading state
    state = AsyncValue.data(currentState.copyWith(isLoading: true));

    try {
      // Calculate offset based on current total games
      final offset = currentState.totalGamesCount;

      // Fetch next page
      final games = await _gameRepository.getGamesByFideIdPaginated(
        fideId,
        limit: _pageSize,
        offset: offset,
      );

      if (games.isEmpty) {
        state = AsyncValue.data(currentState.copyWith(
          isLoading: false,
          hasMore: false,
        ));
        return;
      }

      // Convert to GamesTourModel
      final newGamesTourModels = games
          .map((game) => GamesTourModel.fromGame(game))
          .toList();

      // Merge new games with existing tournament groups
      final updatedGroups = await _mergeGamesIntoGroups(
        newGamesTourModels,
        currentState.tournamentGroups,
      );

      state = AsyncValue.data(currentState.copyWith(
        tournamentGroups: updatedGroups,
        isLoading: false,
        hasMore: games.length >= _pageSize,
        currentPage: currentState.currentPage + 1,
      ));
    } catch (e, stack) {
      debugPrint('Error loading more games: $e');
      debugPrint('Stack trace: $stack');
      state = AsyncValue.data(currentState.copyWith(
        isLoading: false,
        error: 'Failed to load more games: $e',
      ));
    }
  }

  /// Refresh games (pull to refresh)
  Future<void> refreshGames() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadInitialGames());
  }

  /// Group games by tournament
  Future<List<TournamentGamesGroup>> _groupGamesByTournament(
    List<GamesTourModel> games,
  ) async {
    if (games.isEmpty) return [];

    try {
      debugPrint('===== Grouping ${games.length} games by tournament =====');

      // Group by tour_id while preserving order
      final Map<String, List<GamesTourModel>> groupedGames = {};
      final List<String> tourOrder = [];

      for (final game in games) {
        final tourId = game.tourId;
        if (!groupedGames.containsKey(tourId)) {
          groupedGames[tourId] = [];
          tourOrder.add(tourId);
        }
        groupedGames[tourId]!.add(game);
      }

      debugPrint('===== Found ${groupedGames.length} unique tournaments =====');
      debugPrint('===== Tournament IDs: ${groupedGames.keys.toList()} =====');

      // Fetch tournament info
      final uniqueTourIds = groupedGames.keys.toList();
      debugPrint('===== Fetching tournament info for ${uniqueTourIds.length} tours =====');

      final tournaments = await _tourRepository.getToursByIds(uniqueTourIds);
      debugPrint('===== Fetched ${tournaments.length} tournament records =====');

      final tourMap = {for (var tour in tournaments) tour.id: tour};

      // Create tournament groups
      final tournamentGroups = <TournamentGamesGroup>[];
      for (final tourId in tourOrder) {
        final tour = tourMap[tourId];
        if (tour != null && groupedGames[tourId] != null) {
          // Parse dates if available
          DateTime? startDate;
          DateTime? endDate;
          if (tour.dates.isNotEmpty) {
            startDate = tour.dates.first;
            if (tour.dates.length > 1) {
              endDate = tour.dates.last;
            }
          }

          debugPrint('===== Creating group for tour: ${tour.name} with ${groupedGames[tourId]!.length} games =====');

          tournamentGroups.add(TournamentGamesGroup(
            tourId: tour.id,
            tourName: tour.name,
            tourSlug: tour.slug,
            tourImage: tour.image,
            startDate: startDate,
            endDate: endDate,
            games: groupedGames[tourId]!,
          ));
        } else {
          debugPrint('===== WARNING: No tour found for tourId: $tourId =====');
        }
      }

      debugPrint('===== Successfully created ${tournamentGroups.length} tournament groups =====');
      return tournamentGroups;
    } catch (e, stack) {
      debugPrint('===== ERROR in _groupGamesByTournament =====');
      debugPrint('Error: $e');
      debugPrint('Stack: $stack');
      rethrow;
    }
  }

  /// Merge new games into existing tournament groups
  Future<List<TournamentGamesGroup>> _mergeGamesIntoGroups(
    List<GamesTourModel> newGames,
    List<TournamentGamesGroup> existingGroups,
  ) async {
    if (newGames.isEmpty) return existingGroups;

    // Create a mutable copy of existing groups
    final updatedGroups = List<TournamentGamesGroup>.from(existingGroups);
    final existingTourIds = {for (var g in updatedGroups) g.tourId};

    // Group new games by tournament
    final Map<String, List<GamesTourModel>> newGroupedGames = {};
    final List<String> newTourIds = [];

    for (final game in newGames) {
      final tourId = game.tourId;
      if (!newGroupedGames.containsKey(tourId)) {
        newGroupedGames[tourId] = [];
        if (!existingTourIds.contains(tourId)) {
          newTourIds.add(tourId);
        }
      }
      newGroupedGames[tourId]!.add(game);
    }

    // Fetch info for new tournaments
    Map<String, dynamic> tourMap = {};
    if (newTourIds.isNotEmpty) {
      final tournaments = await _tourRepository.getToursByIds(newTourIds);
      tourMap = {for (var tour in tournaments) tour.id: tour};
    }

    // Merge games into existing groups or create new groups
    for (final tourId in newGroupedGames.keys) {
      final existingGroupIndex = updatedGroups.indexWhere(
        (g) => g.tourId == tourId,
      );

      if (existingGroupIndex != -1) {
        // Add games to existing group
        final existingGroup = updatedGroups[existingGroupIndex];
        updatedGroups[existingGroupIndex] = existingGroup.copyWith(
          games: [...existingGroup.games, ...newGroupedGames[tourId]!],
        );
      } else {
        // Create new group
        final tour = tourMap[tourId];
        if (tour != null) {
          DateTime? startDate;
          DateTime? endDate;
          if (tour.dates.isNotEmpty) {
            startDate = tour.dates.first;
            if (tour.dates.length > 1) {
              endDate = tour.dates.last;
            }
          }

          updatedGroups.add(TournamentGamesGroup(
            tourId: tour.id,
            tourName: tour.name,
            tourSlug: tour.slug,
            tourImage: tour.image,
            startDate: startDate,
            endDate: endDate,
            games: newGroupedGames[tourId]!,
          ));
        }
      }
    }

    return updatedGroups;
  }
}

/// Provider factory for player games using AsyncNotifier
final playerGamesProvider = AsyncNotifierProvider.autoDispose
    .family<PlayerGamesNotifier, PlayerGamesState, String>(
  () => PlayerGamesNotifier(),
);
