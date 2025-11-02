import 'package:chessever2/repository/local_storage/favorite/favourate_standings_player_services.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class FavoritePlayersState {
  final List<PlayerStandingModel> players;
  final bool isLoading;
  final String? error;

  const FavoritePlayersState({
    required this.players,
    this.isLoading = false,
    this.error,
  });

  FavoritePlayersState copyWith({
    List<PlayerStandingModel>? players,
    bool? isLoading,
    String? error,
  }) {
    return FavoritePlayersState(
      players: players ?? this.players,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class FavoritePlayersNotifier
    extends AutoDisposeAsyncNotifier<FavoritePlayersState> {
  FavoriteStandingsPlayerService get _favoritesService =>
      ref.read(favoriteStandingsPlayerService);

  @override
  Future<FavoritePlayersState> build() async {
    return await _loadFavorites();
  }

  Future<FavoritePlayersState> _loadFavorites() async {
    try {
      final favoritePlayers = await _favoritesService.getFavoritePlayers();
      return FavoritePlayersState(players: favoritePlayers, isLoading: false);
    } catch (e, stack) {
      debugPrint('Error: $e');
      debugPrint('Stack: $stack');
      rethrow;
    }
  }

  Future<void> removeFavorite(PlayerStandingModel player) async {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    // STEP 1: Optimistic update - update UI immediately
    final updatedPlayers =
        currentState.players.where((p) => p.name != player.name).toList();
    state = AsyncValue.data(currentState.copyWith(players: updatedPlayers));

    try {
      // STEP 2: Sync to Supabase in background
      await _favoritesService.toggleFavorite(player);
    } catch (e, stack) {
      debugPrint('Error: $e');
      debugPrint('Stack: $stack');

      // STEP 3: Revert optimistic update on error (without loading state)
      state = AsyncValue.data(currentState);
    }
  }

  Future<bool> toggleFavorite(PlayerStandingModel player) async {
    if (player.fideId != null) {
      final currentState = state.valueOrNull;
      if (currentState == null) {
        return (await _favoritesService.getFavoritePlayers()).any(
          (p) => p.fideId == player.fideId,
        );
      }

      final isFav = currentState.players.any((p) => p.fideId == player.fideId);

      if (isFav) {
        await removeFavorite(player);
        // Increment favorites version to trigger immediate games re-sort
        ref.read(favoritesVersionProvider.notifier).state++;
        debugPrint('[FavoritePlayers] Incremented favorites version after removing favorite');
        return false;
      } else {
        await addFavorite(player);
        // Increment favorites version to trigger immediate games re-sort
        ref.read(favoritesVersionProvider.notifier).state++;
        debugPrint('[FavoritePlayers] Incremented favorites version after adding favorite');
        return true;
      }
    }
    return false;
  }

  Future<void> addFavorite(PlayerStandingModel player) async {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    // STEP 1: Optimistic update - update UI immediately
    final updatedPlayers = List<PlayerStandingModel>.from(
      currentState.players,
    )..add(player);
    state = AsyncValue.data(currentState.copyWith(players: updatedPlayers));

    try {
      // STEP 2: Sync to Supabase in background
      await _favoritesService.toggleFavorite(player);
    } catch (e, stack) {
      debugPrint('Error: $e');
      debugPrint('Stack: $stack');

      // STEP 3: Revert optimistic update on error (without loading state)
      state = AsyncValue.data(currentState);
    }
  }

  void onSearchFavorite(String query) {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    if (query.isEmpty) {
      state = AsyncValue.data(
        currentState.copyWith(players: currentState.players),
      );
    } else {
      final filteredPlayers =
          currentState.players
              .where(
                (player) =>
                    player.name.toLowerCase().contains(query.toLowerCase()),
              )
              .toList();
      state = AsyncValue.data(currentState.copyWith(players: filteredPlayers));
    }
  }

  Future<void> refreshFavorites() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadFavorites());
  }
}

final favoritePlayersNotifierProvider = AsyncNotifierProvider.autoDispose<
  FavoritePlayersNotifier,
  FavoritePlayersState
>(() => FavoritePlayersNotifier());

final filteredFavoritePlayersProvider = Provider.family
    .autoDispose<List<PlayerStandingModel>, String>((ref, query) {
      final players = ref.watch(favoritePlayersNotifierProvider).value!.players;

      if (query.isEmpty) {
        return players;
      }
      String normalize(String s) =>
          s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

      return players.where((player) {
        final name = normalize(player.name);
        final q = normalize(query);
        return name.contains(q);
      }).toList();
    });
