import '../../../services/favorites_service.dart';

class PlayerController {
  // Dummy data for players
  final List<Map<String, dynamic>> _players = [
    {
      'name': 'Magnus, Carlsen',
      'countryCode': 'NO',
      'elo': 2837,
      'age': 35,
      'isFavorite': true,
    },
    {
      'name': 'Hikaru, Nakamura',
      'countryCode': 'US',
      'elo': 2804,
      'age': 38,
      'isFavorite': false,
    },
    {
      'name': 'Erigaisi, Arjun',
      'countryCode': 'IN',
      'elo': 2782,
      'age': 22,
      'isFavorite': false,
    },
    {
      'name': 'Carauna, Fabiano',
      'countryCode': 'US',
      'elo': 2777,
      'age': 33,
      'isFavorite': false,
    },
    {
      'name': 'Gukesh, D',
      'countryCode': 'IN',
      'elo': 2776,
      'age': 19,
      'isFavorite': false,
    },
    {
      'name': 'Abdusattorov, N',
      'countryCode': 'UZ',
      'elo': 2767,
      'age': 21,
      'isFavorite': false,
    },
    {
      'name': 'Praggnanandhaa, R',
      'countryCode': 'IN',
      'elo': 2766,
      'age': 20,
      'isFavorite': false,
    },
  ];

  // Get all players
  List<Map<String, dynamic>> getPlayers() {
    return _players;
  }

  // Search players by name
  List<Map<String, dynamic>> searchPlayers(String query) {
    if (query.isEmpty) {
      return _players;
    }

    final lowercaseQuery = query.toLowerCase();
    return _players
        .where(
          (player) =>
              player['name'].toString().toLowerCase().contains(lowercaseQuery),
        )
        .toList();
  }

  // Toggle starred_repository status for a player
  Future<void> toggleFavorite(String playerName) async {
    final index = _players.indexWhere((player) => player['name'] == playerName);

    if (index != -1) {
      // Update local state immediately for UI responsiveness
      _players[index]['isFavorite'] = !_players[index]['isFavorite'];

      // Persist the changes
      await FavoritesService.saveFavorites(_players);
    }
  }

  // This method will be replaced by an actual API call in the future
  Future<void> fetchPlayers() async {
    // Simulate API call delay
    await Future.delayed(const Duration(milliseconds: 500));

    // Load player data and update with starred_repository status
    final updatedPlayers = await FavoritesService.updateFavoritesStatus(
      _players,
    );

    // Update the players list with the updated starred_repository status
    for (int i = 0; i < _players.length; i++) {
      final updatedIndex = updatedPlayers.indexWhere(
        (player) => player['name'] == _players[i]['name'],
      );

      if (updatedIndex != -1) {
        _players[i]['isFavorite'] = updatedPlayers[updatedIndex]['isFavorite'];
      }
    }
  }
}
