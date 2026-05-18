import 'dart:async';
import 'dart:convert';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/screens/favorites/favorite_players_provider.dart';
import 'package:chessever2/services/analytics/analytics_service.dart';
import 'package:chessever2/revenue_cat_service/revenue_cat_service.dart';
import 'package:chessever2/utils/favorite_constants.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
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

  /// Guards concurrent calls to _loadFavorites so only one Supabase
  /// request + cache write happens at a time.
  static Completer<List<FavoritePlayer>>? _loadCompleter;
  bool _backgroundRefreshRunning = false;

  /// Get user-specific cache key to prevent cross-user cache pollution
  String get _cacheKey {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return '${_cacheKeyPrefix}anonymous';
    return '$_cacheKeyPrefix$userId';
  }

  @override
  Future<List<FavoritePlayer>> build() async {
    return await _loadFavorites(preferCacheFirst: true);
  }

  Future<List<FavoritePlayer>> _loadFavorites({
    required bool preferCacheFirst,
  }) async {
    // Deduplicate concurrent calls (e.g. build() + refresh() racing)
    if (_loadCompleter != null) return _loadCompleter!.future;

    _loadCompleter = Completer<List<FavoritePlayer>>();
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[FavoritePlayers] No user logged in, returning empty list');
        final result = <FavoritePlayer>[];
        _loadCompleter!.complete(result);
        return result;
      }

      if (preferCacheFirst) {
        final cached = await _getCachedPlayers();
        if (cached.isNotEmpty) {
          debugPrint(
            '[FavoritePlayers] Loaded ${cached.length} players from cache (cache-first)',
          );
          _loadCompleter!.complete(cached);
          unawaited(_refreshInBackground(userId, cached));
          return cached;
        }
      }

      final players = await _fetchFromSupabase(userId);
      _loadCompleter!.complete(players);
      return players;
    } catch (e, st) {
      debugPrint('[FavoritePlayers] Error fetching from Supabase: $e');
      debugPrint('[FavoritePlayers] Stack: $st');

      // Fallback to local cache
      final cached = await _getCachedPlayers();
      _loadCompleter!.complete(cached);
      return cached;
    } finally {
      _loadCompleter = null;
    }
  }

  Future<List<FavoritePlayer>> _fetchFromSupabase(String userId) async {
    final response = await _supabase
        .from('user_favorite_players')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    final players =
        (response as List)
            .map((json) => FavoritePlayer.fromSupabase(json))
            .toList();

    // Cache locally in background (Supabase stays primary path)
    unawaited(_cachePlayers(players));
    debugPrint(
      '[FavoritePlayers] Fetched ${players.length} players from Supabase',
    );
    return players;
  }

  Future<void> _refreshInBackground(
    String userId,
    List<FavoritePlayer> currentPlayers,
  ) async {
    if (_backgroundRefreshRunning) return;
    _backgroundRefreshRunning = true;
    try {
      final fresh = await _fetchFromSupabase(userId);
      if (_hasDifferentPlayers(currentPlayers, fresh)) {
        state = AsyncValue.data(fresh);
      }
    } catch (_) {
      // Background refresh is best-effort; keep cached state.
    } finally {
      _backgroundRefreshRunning = false;
    }
  }

  bool _hasDifferentPlayers(
    List<FavoritePlayer> current,
    List<FavoritePlayer> next,
  ) {
    if (current.length != next.length) return true;
    for (var i = 0; i < current.length; i++) {
      final a = current[i];
      final b = next[i];
      if (a.id != b.id ||
          a.updatedAt != b.updatedAt ||
          a.playerName != b.playerName ||
          a.fideId != b.fideId) {
        return true;
      }
    }
    return false;
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

      // Enforce free-tier favorite cap. The count comes from a fresh
      // server-side COUNT, NOT from `state.valueOrNull?.length`, because
      // the AsyncNotifier reflects the cached Supabase realtime stream
      // which lags behind the latest INSERT by the round-trip time. The
      // same race let users slip past the saved-games cap before — same
      // pattern, same fix.
      final isSubscribed = await RevenueCatService().isSubscribed();
      if (!isSubscribed) {
        final currentCount = await _supabase
            .from('user_favorite_players')
            .count(CountOption.exact)
            .eq('user_id', userId);
        if (currentCount >= kFreeFavoriteLimit) {
          debugPrint(
            '[FavoritePlayers] Free user at limit ($kFreeFavoriteLimit), blocking add',
          );
          throw FavoriteLimitExceededException(kFreeFavoriteLimit);
        }
      }

      // Check if already exists by fide_id to prevent duplicates
      if (fideId != null && fideId.isNotEmpty) {
        final existing =
            await _supabase
                .from('user_favorite_players')
                .select('id')
                .eq('user_id', userId)
                .eq('fide_id', fideId)
                .maybeSingle();

        if (existing != null) {
          debugPrint(
            '[FavoritePlayers] Player $playerName already favorited (fide_id: $fideId)',
          );
          return;
        }
      }

      final metadata = <String, dynamic>{
        if (countryCode != null) 'countryCode': countryCode,
        if (rating != null) 'rating': rating,
        if (title != null) 'title': title,
      };

      // Insert to Supabase (upsert prevents duplicates by player_name as fallback)
      await _supabase
          .from('user_favorite_players')
          .upsert(
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
      // Keep legacy provider in sync for remaining consumers
      ref.invalidate(favoritePlayersNotifierProvider);
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
      // Keep legacy provider in sync for remaining consumers
      ref.invalidate(favoritePlayersNotifierProvider);
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
    state = await AsyncValue.guard(
      () => _loadFavorites(preferCacheFirst: false),
    );
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
      final db = AppDatabase.instance;
      final userId = _supabase.auth.currentUser?.id;
      final json = jsonEncode(players.map((p) => p.toSupabase()).toList());
      await db.setCache(key: _cacheKey, value: json, userId: userId);
      debugPrint('[FavoritePlayers] Cached ${players.length} players locally');
    } catch (e) {
      debugPrint('[FavoritePlayers] Error caching players: $e');
    }
  }

  Future<List<FavoritePlayer>> _getCachedPlayers() async {
    try {
      final db = AppDatabase.instance;
      final userId = _supabase.auth.currentUser?.id;
      final entry = await db.getCache(key: _cacheKey, userId: userId);
      if (entry == null) return [];

      final list = jsonDecode(entry.value) as List;
      return list.map((json) => FavoritePlayer.fromSupabase(json)).toList();
    } catch (e) {
      debugPrint('[FavoritePlayers] Error getting cached players: $e');
      return [];
    }
  }

  /// Clear cache (useful on sign out)
  Future<void> clearCache() async {
    try {
      final db = AppDatabase.instance;
      final userId = _supabase.auth.currentUser?.id;
      await db.removeCache(key: _cacheKey, userId: userId);
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
final isPlayerFavoritedProvider = Provider.family<bool, String>((
  ref,
  playerName,
) {
  final favorites = ref.watch(favoritePlayersProviderNew);
  return favorites.maybeWhen(
    data: (players) => players.any((p) => p.playerName == playerName),
    orElse: () => false,
  );
});
