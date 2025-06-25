import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class PlayerViewModel {
  static const String _favoritePlayerIdsKey = 'favorite_player_ids';

  final List<Map<String, dynamic>> _players = [
    {
      'id': '1',
      'name': 'Magnus, Carlsen',
      'countryCode': 'NO',
      'elo': 2837,
      'age': 35,
    },
    {
      'id': '2',
      'name': 'Hikaru, Nakamura',
      'countryCode': 'US',
      'elo': 2804,
      'age': 38,
    },
    {
      'id': '3',
      'name': 'Erigaisi, Arjun',
      'countryCode': 'IN',
      'elo': 2782,
      'age': 22,
    },
    {
      'id': '4',
      'name': 'Carauna, Fabiano',
      'countryCode': 'US',
      'elo': 2777,
      'age': 33,
    },
    {
      'id': '5',
      'name': 'Gukesh, D',
      'countryCode': 'IN',
      'elo': 2776,
      'age': 19,
    },
    {
      'id': '6',
      'name': 'Abdusattorov, N',
      'countryCode': 'UZ',
      'elo': 2767,
      'age': 21,
    },
    {
      'id': '7',
      'name': 'Praggnanandhaa, R',
      'countryCode': 'IN',
      'elo': 2766,
      'age': 20,
    },
    {
      'id': '8',
      'name': 'Simmons, R',
      'countryCode': 'NP',
      'elo': 2766,
      'age': 22,
    },
  ];

  Set<String> _favoritePlayerIds = {};
  bool _isInitialized = false;

  // Initialize the view model and load favorites
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _loadFavoritePlayerIds();
      _isInitialized = true;
      print('Initialized PlayerViewModel with favorites: $_favoritePlayerIds');

      // Ensure persistence of initial favorites if needed
      if (_favoritePlayerIds.isEmpty) {
        // Don't add any default favorites
        await _saveFavoritePlayerIds();
      }
    } catch (e) {
      print('Error initializing PlayerViewModel: $e');
    }
  }

  // Load favorite player IDs from SharedPreferences
  Future<void> _loadFavoritePlayerIds() async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = prefs.getString(_favoritePlayerIdsKey);

    if (favoritesJson != null) {
      final List<dynamic> decoded = jsonDecode(favoritesJson);
      _favoritePlayerIds = Set<String>.from(decoded.cast<String>());
    }
  }

  // Save favorite player IDs to SharedPreferences
  Future<void> _saveFavoritePlayerIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favoritesJson = jsonEncode(_favoritePlayerIds.toList());
      await prefs.setString(_favoritePlayerIdsKey, favoritesJson);
      print('Saved favorite player IDs: $_favoritePlayerIds');
    } catch (e) {
      print('Error saving favorite player IDs: $e');
    }
  }

  // Get all players with their favorite status
  List<Map<String, dynamic>> getPlayers() {
    return _players.map((player) {
      final playerWithFavorite = Map<String, dynamic>.from(player);
      playerWithFavorite['isFavorite'] = _favoritePlayerIds.contains(
        player['id'],
      );
      return playerWithFavorite;
    }).toList();
  }

  // Search players by name
  List<Map<String, dynamic>> searchPlayers(String query) {
    if (query.isEmpty) {
      return getPlayers();
    }

    final lowercaseQuery = query.toLowerCase();
    return getPlayers()
        .where(
          (player) =>
              player['name'].toString().toLowerCase().contains(lowercaseQuery),
        )
        .toList();
  }

  // Toggle favorite status for a player
  Future<void> toggleFavorite(String playerId) async {
    await initialize();

    if (_favoritePlayerIds.contains(playerId)) {
      _favoritePlayerIds.remove(playerId);
    } else {
      _favoritePlayerIds.add(playerId);
    }

    await _saveFavoritePlayerIds();
  }

  // Check if a player is a favorite
  bool isPlayerFavorite(String playerId) {
    return _favoritePlayerIds.contains(playerId);
  }

  // Get all favorite players
  List<Map<String, dynamic>> getFavoritePlayers() {
    return getPlayers()
        .where((player) => _favoritePlayerIds.contains(player['id']))
        .toList();
  }

  // Get a player by ID
  Map<String, dynamic>? getPlayerById(String id) {
    try {
      return _players.firstWhere((player) => player['id'] == id);
    } catch (e) {
      return null;
    }
  }

  // Get a player by name
  Map<String, dynamic>? getPlayerByName(String name) {
    try {
      return _players.firstWhere((player) => player['name'] == name);
    } catch (e) {
      return null;
    }
  }
}
