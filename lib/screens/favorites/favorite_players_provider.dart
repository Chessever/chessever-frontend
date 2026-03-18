import 'dart:async';
import 'package:chessever2/repository/local_storage/favorite/favourate_standings_player_services.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/tour_detail/player_tour/player_tour_screen_provider.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
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
      final cached = await _favoritesService.getCachedFavoritePlayers();
      if (cached.isNotEmpty) {
        unawaited(_refreshFromSupabase());
        return FavoritePlayersState(players: cached, isLoading: false);
      }

      final favoritePlayers =
          await _favoritesService.fetchFavoritePlayersFromSupabase();
      return FavoritePlayersState(players: favoritePlayers, isLoading: false);
    } catch (e, stack) {
      debugPrint('Error: $e');
      debugPrint('Stack: $stack');
      rethrow;
    }
  }

  Future<void> _refreshFromSupabase() async {
    try {
      final favoritePlayers =
          await _favoritesService.fetchFavoritePlayersFromSupabase();
      state = AsyncValue.data(
        FavoritePlayersState(players: favoritePlayers, isLoading: false),
      );
    } catch (e, stack) {
      // Catches errors including if notifier was disposed after async gap
      debugPrint('[FavoritePlayers] Refresh error: $e');
      debugPrint('[FavoritePlayers] Stack: $stack');
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
      _trackFavoritePlayerToggle(
        player: player,
        isFavorited: false,
        totalCount: updatedPlayers.length,
        source: 'favorites_screen',
      );
    } catch (e, stack) {
      debugPrint('Error: $e');
      debugPrint('Stack: $stack');

      // STEP 3: Revert optimistic update on error (without loading state)
      state = AsyncValue.data(currentState);
    }
  }

  Future<bool> toggleFavorite(PlayerStandingModel player) async {
    final currentState = state.valueOrNull;
    if (currentState == null) {
      if (player.fideId != null) {
        return (await _favoritesService.getFavoritePlayers()).any(
          (p) => p.fideId == player.fideId,
        );
      }
      return false;
    }

    final isFav = player.fideId != null
        ? currentState.players.any((p) => p.fideId == player.fideId)
        : currentState.players.any((p) => p.name == player.name);

    if (isFav) {
      await removeFavorite(player);
    } else {
      await addFavorite(player);
    }

    // Always increment favorites version to trigger immediate games re-sort,
    // regardless of whether the player has a fideId.
    ref.read(favoritesVersionProvider.notifier).state++;
    debugPrint(
      '[FavoritePlayers] Incremented favorites version after ${isFav ? 'removing' : 'adding'} favorite',
    );
    return !isFav;
  }

  Future<void> addFavorite(PlayerStandingModel player) async {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    // STEP 1: Optimistic update - update UI immediately
    final updatedPlayers = List<PlayerStandingModel>.from(currentState.players)
      ..add(player);
    state = AsyncValue.data(currentState.copyWith(players: updatedPlayers));

    try {
      // STEP 2: Sync to Supabase in background
      await _favoritesService.toggleFavorite(player);
      _trackFavoritePlayerToggle(
        player: player,
        isFavorited: true,
        totalCount: updatedPlayers.length,
        source: 'favorites_screen',
      );
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

  void _trackFavoritePlayerToggle({
    required PlayerStandingModel player,
    required bool isFavorited,
    required int totalCount,
    required String source,
  }) {
    unawaited(
      AnalyticsService.instance.trackEvent(
        'Player Favorite Toggled',
        properties: {
          'player_name': player.name,
          'fide_id': player.fideId,
          'country_code': player.countryCode,
          'rating': player.score,
          'title': player.title,
          'is_favorited': isFavorited,
          'source': source,
          'new_favorites_total': totalCount,
        },
      ),
    );

    unawaited(
      AnalyticsService.instance.setUserProperties({
        'favorite_player_count': totalCount,
      }),
    );
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
