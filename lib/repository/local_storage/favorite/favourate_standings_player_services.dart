// lib/repository/local_storage/favorite/favourate_standings_player_services.dart

import 'dart:async';
import 'dart:convert';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final favoriteStandingsPlayerService = Provider<FavoriteStandingsPlayerService>(
  (ref) {
    return FavoriteStandingsPlayerService(ref);
  },
);

class FavoriteStandingsPlayerService {
  static const String _cacheKey = 'cached_favorite_players';
  final Ref ref;

  FavoriteStandingsPlayerService(this.ref);

  SupabaseClient get _supabase => Supabase.instance.client;

  String? _getCurrentUserId() => _supabase.auth.currentUser?.id;

  /// Guards concurrent calls to _fetchFavoritePlayersFromSupabase so only
  /// one Supabase request + cache write happens at a time.
  Completer<List<PlayerStandingModel>>? _fetchCompleter;

  /// Get favorite players from Supabase (source of truth), fallback to cache
  Future<List<PlayerStandingModel>> getFavoritePlayers() async {
    final cached = await _getCachedPlayers();
    if (cached.isNotEmpty) {
      return cached;
    }

    return _fetchFavoritePlayersFromSupabase();
  }

  Future<List<PlayerStandingModel>> getCachedFavoritePlayers() async {
    return _getCachedPlayers();
  }

  Future<List<PlayerStandingModel>> fetchFavoritePlayersFromSupabase() async {
    return _fetchFavoritePlayersFromSupabase();
  }

  Future<List<PlayerStandingModel>> _fetchFavoritePlayersFromSupabase() async {
    // Deduplicate concurrent calls — multiple providers hit this simultaneously
    // on app startup, causing 4x redundant Supabase fetches + cache writes.
    if (_fetchCompleter != null) return _fetchCompleter!.future;

    _fetchCompleter = Completer<List<PlayerStandingModel>>();
    try {
      final userId = _getCurrentUserId();
      if (userId == null) {
        debugPrint(
          '[FavoriteStandings] No user logged in, returning empty list',
        );
        final result = <PlayerStandingModel>[];
        _fetchCompleter!.complete(result);
        return result;
      }

      // Fetch from Supabase (source of truth)
      final response = await _supabase
          .from('user_favorite_players')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final players =
          (response as List)
              .map((json) => _playerFromSupabase(json))
              .whereType<PlayerStandingModel>()
              .toList();

      // Cache locally in background (Supabase stays primary path)
      unawaited(_cachePlayers(players, userId));

      debugPrint(
        '[FavoriteStandings] Fetched ${players.length} players from Supabase',
      );
      _fetchCompleter!.complete(players);
      return players;
    } catch (e, stack) {
      debugPrint('[FavoriteStandings] Error fetching from Supabase: $e');
      debugPrint('[FavoriteStandings] Stack: $stack');

      // Fallback to local cache
      final cached = await _getCachedPlayers();
      _fetchCompleter!.complete(cached);
      return cached;
    } finally {
      _fetchCompleter = null;
    }
  }

  /// Save favorite players to Supabase and cache
  Future<void> saveFavoritePlayers(
    List<PlayerStandingModel> favoritePlayers,
  ) async {
    final userId = _getCurrentUserId();
    await _cachePlayers(favoritePlayers, userId);
  }

  /// Toggle favorite status (add or remove)
  Future<void> toggleFavorite(PlayerStandingModel player) async {
    try {
      final userId = _getCurrentUserId();
      if (userId == null) {
        throw Exception('User must be logged in to favorite players');
      }

      final favorites = await getFavoritePlayers();
      final existingIndex = favorites.indexWhere((p) => p.name == player.name);

      if (existingIndex != -1) {
        // Remove from Supabase
        await _supabase
            .from('user_favorite_players')
            .delete()
            .eq('user_id', userId)
            .eq('player_name', player.name);

        debugPrint(
          '[FavoriteStandings] Removed player ${player.name} from Supabase',
        );
      } else {
        // Add to Supabase
        final metadata = player.toJson();

        await _supabase
            .from('user_favorite_players')
            .upsert(
              {
                'user_id': userId,
                'fide_id': player.fideId?.toString(),
                'player_name': player.name,
                'metadata': metadata,
              },
              onConflict: 'user_id,player_name',
              ignoreDuplicates: true,
            );

        debugPrint(
          '[FavoriteStandings] Added player ${player.name} to Supabase',
        );
      }

      // Update cache
      final updatedFavorites =
          existingIndex != -1
              ? (favorites..removeAt(existingIndex))
              : (favorites..add(player));
      await _cachePlayers(updatedFavorites, userId);
    } catch (e, stack) {
      debugPrint('[FavoriteStandings] Error toggling favorite: $e');
      debugPrint('[FavoriteStandings] Stack: $stack');
      rethrow;
    }
  }

  /// Check if player is favorited
  Future<bool> isFavorite(String playerName) async {
    final favorites = await getFavoritePlayers();
    return favorites.any((p) => p.name == playerName);
  }

  // PRIVATE HELPERS

  /// Convert Supabase JSON to PlayerStandingModel
  PlayerStandingModel? _playerFromSupabase(Map<String, dynamic> json) {
    try {
      final metadata = json['metadata'] as Map<String, dynamic>?;

      final hasCompleteMetadata =
          metadata != null &&
          metadata.containsKey('name') &&
          metadata.containsKey('score') &&
          metadata.containsKey('scoreChange');

      if (hasCompleteMetadata) {
        return PlayerStandingModel.fromJson(metadata);
      }

      return PlayerStandingModel(
        countryCode: metadata?['countryCode'] as String? ?? '',
        title: metadata?['title'] as String?,
        name: json['player_name'] as String,
        score: metadata?['rating'] as int? ?? 0,
        scoreChange: 0,
        matchScore: null,
        fideId:
            json['fide_id'] != null
                ? int.tryParse(json['fide_id'] as String)
                : null,
      );
    } catch (e) {
      debugPrint('[FavoriteStandings] Error parsing player: $e');
      debugPrint('[FavoriteStandings] JSON: $json');
      return null;
    }
  }

  /// Cache players locally in SQLite
  Future<void> _cachePlayers(
    List<PlayerStandingModel> players,
    String? userId,
  ) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final json = jsonEncode(players.map((p) => p.toJson()).toList());
      await db.setCache(key: _cacheKey, value: json, userId: userId);
      debugPrint(
        '[FavoriteStandings] Cached ${players.length} players locally',
      );
    } catch (e) {
      debugPrint('[FavoriteStandings] Error caching players: $e');
    }
  }

  /// Get cached players from SQLite
  Future<List<PlayerStandingModel>> _getCachedPlayers() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final userId = _getCurrentUserId();
      final entry = await db.getCache(key: _cacheKey, userId: userId);
      if (entry == null) {
        debugPrint('[FavoriteStandings] No cache found');
        return [];
      }

      final list = jsonDecode(entry.value) as List;
      return list
          .map((json) {
            try {
              return PlayerStandingModel.fromJson(json);
            } catch (e) {
              debugPrint('[FavoriteStandings] Error parsing cached player: $e');
              return null;
            }
          })
          .whereType<PlayerStandingModel>()
          .toList();
    } catch (e) {
      debugPrint('[FavoriteStandings] Error getting cached players: $e');
      return [];
    }
  }
}
