// lib/repository/local_storage/favorite/favourate_standings_player_services.dart

import 'dart:convert';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:flutter/foundation.dart';

final favoriteStandingsPlayerService = Provider<FavoriteStandingsPlayerService>((
    ref,
    ) {
  return FavoriteStandingsPlayerService(ref);
});

class FavoriteStandingsPlayerService {
  static const String _favoritePlayersKey = 'favorite_players';
  final Ref ref;

  FavoriteStandingsPlayerService(this.ref);

  Future<List<PlayerStandingModel>> getFavoritePlayers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favoritesJson = prefs.getString(_favoritePlayersKey);

      if (favoritesJson != null) {
        final List<dynamic> decoded = jsonDecode(favoritesJson);

        // Filter out any items that fail to parse
        final List<PlayerStandingModel> players = [];
        for (var item in decoded) {
          try {
            players.add(PlayerStandingModel.fromJson(item as Map<String, dynamic>));
          } catch (e) {
            debugPrint('Error parsing player from favorites: $e');
            debugPrint('Problematic item: $item');
            // Skip this item and continue
          }
        }
        return players;
      }
      return <PlayerStandingModel>[];
    } catch (e, stack) {
      debugPrint('Error in getFavoritePlayers: $e');
      debugPrint('Stack: $stack');
      // Return empty list instead of crashing
      return <PlayerStandingModel>[];
    }
  }

  Future<void> saveFavoritePlayers(
      List<PlayerStandingModel> favoritePlayers,
      ) async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = jsonEncode(
      favoritePlayers.map((p) => p.toJson()).toList(),
    );
    await prefs.setString(_favoritePlayersKey, favoritesJson);
  }

  Future<void> toggleFavorite(PlayerStandingModel player) async {
    final favorites = await getFavoritePlayers();
    final existingIndex = favorites.indexWhere((p) => p.name == player.name);

    if (existingIndex != -1) {
      favorites.removeAt(existingIndex);
    } else {
      favorites.add(player);
    }
    await saveFavoritePlayers(favorites);
  }

  Future<bool> isFavorite(String playerName) async {
    final favorites = await getFavoritePlayers();
    return favorites.any((p) => p.name == playerName);
  }
}