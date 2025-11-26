import 'dart:async';
import 'dart:convert';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Provider for managing player favorites
/// Business logic lives here, not in a separate repository
final favoritePlayersProviderNew =
    AsyncNotifierProvider<FavoritePlayersNotifierNew, List<FavoritePlayer>>(
  FavoritePlayersNotifierNew.new,
);

class FavoritePlayersNotifierNew extends AsyncNotifier<List<FavoritePlayer>> {
  static const String _cacheKeyPrefix = 'cached_favorite_players_';

  SupabaseClient get _supabase => Supabase.instance.client;

  /// Get user-specific cache key to prevent cross-user cache pollution
  String get _cacheKey {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return '${_cacheKeyPrefix}anonymous';
    return '$_cacheKeyPrefix$userId';
  }

  @override
  Future<List<FavoritePlayer>> build() async {
    return await _loadFavorites();
  }

  Future<List<FavoritePlayer>> _loadFavorites() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[FavoritePlayers] No user logged in, returning empty list');
        return [];
      }

      // Fetch from Supabase (source of truth)
      final response = await _supabase
          .from('user_favorite_players')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final players = (response as List)
          .map((json) => FavoritePlayer.fromSupabase(json))
          .toList();

      // Cache locally
      await _cachePlayers(players);

      debugPrint('[FavoritePlayers] Fetched ${players.length} players from Supabase');
      return players;
    } catch (e, st) {
      debugPrint('[FavoritePlayers] Error fetching from Supabase: $e');
      debugPrint('[FavoritePlayers] Stack: $st');

      // Fallback to local cache
      return await _getCachedPlayers();
    }
  }

  /// Add player to favorites
  Future<void> addFavorite({
    String? fideId,
    required String playerName,
    String? countryCode,
    int? rating,
    String? title,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User must be logged in to favorite players');
      }

      final metadata = <String, dynamic>{
        if (countryCode != null) 'countryCode': countryCode,
        if (rating != null) 'rating': rating,
        if (title != null) 'title': title,
      };

      // Insert to Supabase (upsert prevents duplicates)
      await _supabase.from('user_favorite_players').upsert(
        {
          'user_id': userId,
          'fide_id': fideId,
          'player_name': playerName,
          'metadata': metadata,
        },
        onConflict: 'user_id,player_name',
        ignoreDuplicates: true,
      );

      debugPrint('[FavoritePlayers] Added player $playerName to Supabase');

      // Refresh state
      await refresh();
      _syncFavoritePlayerCountAnalytics(state.valueOrNull?.length ?? 0);
    } catch (e, st) {
      debugPrint('[FavoritePlayers] Error adding player: $e');
      debugPrint('[FavoritePlayers] Stack: $st');
      rethrow;
    }
  }

  /// Remove player from favorites
  Future<void> removeFavorite(String playerName) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User must be logged in to remove favorites');
      }

      // Delete from Supabase
      await _supabase
          .from('user_favorite_players')
          .delete()
          .eq('user_id', userId)
          .eq('player_name', playerName);

      debugPrint('[FavoritePlayers] Removed player $playerName from Supabase');

      // Refresh state
      await refresh();
      _syncFavoritePlayerCountAnalytics(state.valueOrNull?.length ?? 0);
    } catch (e, st) {
      debugPrint('[FavoritePlayers] Error removing player: $e');
      debugPrint('[FavoritePlayers] Stack: $st');
      rethrow;
    }
  }

  /// Toggle player favorite status
  Future<bool> toggleFavorite({
    String? fideId,
    required String playerName,
    String? countryCode,
    int? rating,
    String? title,
  }) async {
    final currentState = state.valueOrNull ?? [];
    final isFavorited = currentState.any((p) => p.playerName == playerName);

    if (isFavorited) {
      await removeFavorite(playerName);
      return false;
    } else {
      await addFavorite(
        fideId: fideId,
        playerName: playerName,
        countryCode: countryCode,
        rating: rating,
        title: title,
      );
      return true;
    }
  }

  /// Check if player is favorited
  bool isFavorited(String playerName) {
    final currentState = state.valueOrNull;
    if (currentState == null) return false;
    return currentState.any((p) => p.playerName == playerName);
  }

  /// Refresh favorites from Supabase
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadFavorites());
  }

  /// Sync favorites from Supabase to local cache
  Future<void> syncFromSupabase() async {
    debugPrint('[FavoritePlayers] Starting sync...');
    try {
      await refresh();
      debugPrint('[FavoritePlayers] Sync complete');
    } catch (e, st) {
      debugPrint('[FavoritePlayers] Error syncing: $e');
      debugPrint('[FavoritePlayers] Stack: $st');
    }
  }

  // Cache management
  Future<void> _cachePlayers(List<FavoritePlayer> players) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(players.map((p) => p.toSupabase()).toList());
      await prefs.setString(_cacheKey, json);
      debugPrint('[FavoritePlayers] Cached ${players.length} players locally');
    } catch (e) {
      debugPrint('[FavoritePlayers] Error caching players: $e');
    }
  }

  Future<List<FavoritePlayer>> _getCachedPlayers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_cacheKey);
      if (json == null) return [];

      final list = jsonDecode(json) as List;
      return list.map((json) => FavoritePlayer.fromSupabase(json)).toList();
    } catch (e) {
      debugPrint('[FavoritePlayers] Error getting cached players: $e');
      return [];
    }
  }

  /// Clear cache (useful on sign out)
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      debugPrint('[FavoritePlayers] Cleared cache');
    } catch (e) {
      debugPrint('[FavoritePlayers] Error clearing cache: $e');
    }
  }

  void _syncFavoritePlayerCountAnalytics(int count) {
    unawaited(
      AnalyticsService.instance.setUserProperties({
        'favorite_player_count': count,
      }),
    );
  }
}

/// Provider to check if a specific player is favorited
final isPlayerFavoritedProvider =
    Provider.family<bool, String>((ref, playerName) {
  final favorites = ref.watch(favoritePlayersProviderNew);
  return favorites.maybeWhen(
    data: (players) => players.any((p) => p.playerName == playerName),
    orElse: () => false,
  );
});
