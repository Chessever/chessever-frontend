// lib/repository/local_storage/favorite/favourate_standings_player_services.dart

import 'dart:convert';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final favoriteStandingsPlayerService = Provider<FavoriteStandingsPlayerService>((
    ref,
    ) {
  return FavoriteStandingsPlayerService(ref);
});

class FavoriteStandingsPlayerService {
  static const String _cacheKey = 'cached_favorite_players_full';
  final Ref ref;

  FavoriteStandingsPlayerService(this.ref);

  SupabaseClient get _supabase => Supabase.instance.client;

  /// Get favorite players from Supabase (source of truth), fallback to cache
  Future<List<PlayerStandingModel>> getFavoritePlayers() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[FavoriteStandings] No user logged in, returning empty list');
        return [];
      }

      // Fetch from Supabase (source of truth)
      final response = await _supabase
          .from('user_favorite_players')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      final players = (response as List)
          .map((json) => _playerFromSupabase(json))
          .whereType<PlayerStandingModel>() // Filter out nulls from parse errors
          .toList();

      // Cache locally
      await _cachePlayers(players);

      debugPrint('[FavoriteStandings] Fetched ${players.length} players from Supabase');
      return players;
    } catch (e, stack) {
      debugPrint('[FavoriteStandings] Error fetching from Supabase: $e');
      debugPrint('[FavoriteStandings] Stack: $stack');

      // Fallback to local cache
      return await _getCachedPlayers();
    }
  }

  /// Save favorite players to Supabase and cache
  Future<void> saveFavoritePlayers(
      List<PlayerStandingModel> favoritePlayers,
      ) async {
    // For backward compatibility, also save to SharedPreferences cache
    await _cachePlayers(favoritePlayers);
  }

  /// Toggle favorite status (add or remove)
  Future<void> toggleFavorite(PlayerStandingModel player) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
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

        debugPrint('[FavoriteStandings] Removed player ${player.name} from Supabase');
      } else {
        // Add to Supabase - store full PlayerStandingModel data in metadata
        final metadata = player.toJson();

        await _supabase.from('user_favorite_players').upsert({
          'user_id': userId,
          'fide_id': player.fideId?.toString(),
          'player_name': player.name,
          'metadata': metadata,
        });

        debugPrint('[FavoriteStandings] Added player ${player.name} to Supabase');
      }

      // Update cache
      final updatedFavorites = existingIndex != -1
          ? (favorites..removeAt(existingIndex))
          : (favorites..add(player));
      await _cachePlayers(updatedFavorites);
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

      // Check if metadata has all required fields for a complete PlayerStandingModel
      final hasCompleteMetadata = metadata != null &&
          metadata.containsKey('name') &&
          metadata.containsKey('score') &&
          metadata.containsKey('scoreChange');

      if (hasCompleteMetadata) {
        // Full model from complete metadata
        return PlayerStandingModel.fromJson(metadata);
      }

      // Fallback: create basic model from available data (for incomplete/old data)
      return PlayerStandingModel(
        countryCode: metadata?['countryCode'] as String? ?? '',
        title: metadata?['title'] as String?,
        name: json['player_name'] as String,
        score: metadata?['rating'] as int? ?? 0, // Use rating as score for ELO display
        scoreChange: 0,
        matchScore: null,
        fideId: json['fide_id'] != null ? int.tryParse(json['fide_id'] as String) : null,
      );
    } catch (e) {
      debugPrint('[FavoriteStandings] Error parsing player: $e');
      debugPrint('[FavoriteStandings] JSON: $json');
      return null;
    }
  }

  /// Cache players locally in SharedPreferences
  Future<void> _cachePlayers(List<PlayerStandingModel> players) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(players.map((p) => p.toJson()).toList());
      await prefs.setString(_cacheKey, json);
      debugPrint('[FavoriteStandings] Cached ${players.length} players locally');
    } catch (e) {
      debugPrint('[FavoriteStandings] Error caching players: $e');
    }
  }

  /// Get cached players from SharedPreferences
  Future<List<PlayerStandingModel>> _getCachedPlayers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_cacheKey);
      if (json == null) {
        debugPrint('[FavoriteStandings] No cache found');
        return [];
      }

      final list = jsonDecode(json) as List;
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
