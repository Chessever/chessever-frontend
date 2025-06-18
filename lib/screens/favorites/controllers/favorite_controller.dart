// filepath: /Users/p1/Desktop/chessever/lib/screens/favorites/controllers/favorite_controller.dart
import '../../../services/favorites_service.dart';

class FavoriteController {
  List<Map<String, dynamic>> _favoritePlayers = [];

  // Get all favorite players
  List<Map<String, dynamic>> getFavoritePlayers() {
    return _favoritePlayers;
  }

  // Search favorite players by name
  List<Map<String, dynamic>> searchFavoritePlayers(String query) {
    if (query.isEmpty) {
      return _favoritePlayers;
    }

    final lowercaseQuery = query.toLowerCase();
    return _favoritePlayers
        .where(
          (player) =>
              player['name'].toString().toLowerCase().contains(lowercaseQuery),
        )
        .toList();
  }

  // Remove a player from favorites
  Future<void> removeFromFavorites(String playerName) async {
    // Find the player in the favorites list
    final index = _favoritePlayers.indexWhere(
      (player) => player['name'] == playerName,
    );

    if (index != -1) {
      // Remove from the local list
      _favoritePlayers.removeAt(index);

      // Update the favorites status through the service
      await FavoritesService.updatePlayerFavoriteStatus(playerName, false);
    }
  }

  // Fetch all favorite players
  Future<void> fetchFavoritePlayers() async {
    // Simulate API call delay
    await Future.delayed(const Duration(milliseconds: 500));

    // Get all favorite players from the service
    _favoritePlayers = await FavoritesService.getAllFavoritePlayers();
  }
}
