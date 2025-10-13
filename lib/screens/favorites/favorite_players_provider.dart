import 'package:chessever2/repository/local_storage/favorite/favourate_standings_player_services.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
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

    try {
      final updatedPlayers =
          currentState.players.where((p) => p.name != player.name).toList();

      state = AsyncValue.data(currentState.copyWith(players: updatedPlayers));

      await _favoritesService.toggleFavorite(player);
    } catch (e, stack) {
      debugPrint('Error: $e');
      debugPrint('Stack: $stack');

      await refreshFavorites();
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

final filteredFavoritePlayersProvider =
    Provider.autoDispose<List<PlayerStandingModel>>((ref) {
      final searchQuery = ref.watch(favoriteSearchQueryProvider);
      final favoritesState = ref.watch(favoritePlayersNotifierProvider);

      return favoritesState.when(
        data: (state) {
          if (searchQuery.isEmpty) {
            return state.players;
          }
          final lowerQuery = searchQuery.toLowerCase();
          return state.players
              .where((player) => player.name.toLowerCase().contains(lowerQuery))
              .toList();
        },
        loading: () => [],
        error: (_, __) => [],
      );
    });

final favoriteSearchQueryProvider = StateProvider.autoDispose<String>(
  (ref) => '',
);
