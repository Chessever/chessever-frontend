import 'dart:convert';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';

final favoriteStandingsPlayerService = Provider<_FavoriteStandingsPlayer>((
  ref,
) {
  return _FavoriteStandingsPlayer();
});

class _FavoriteStandingsPlayer {
  static const String _favoritePlayersKey = 'favorite_players';

  Future<List<PlayerStandingModel>> getFavoritePlayers() async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = prefs.getString(_favoritePlayersKey);

    if (favoritesJson != null) {
      final List<dynamic> decoded = jsonDecode(favoritesJson);
      return decoded.map((item) => PlayerStandingModel.fromJson(item)).toList();
    }
    return <PlayerStandingModel>[];
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
