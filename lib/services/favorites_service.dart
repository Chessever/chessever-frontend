import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class FavoritesService {
  // Storage keys for favorites
  static const String _favoritePlayersKey = 'favorite_players';
  static const String _favoriteTournamentsKey = 'favorite_tournaments';

  // In-memory storage for favorites
  static final List<Map<String, dynamic>> _favoritePlayers = [];
  static final List<Map<String, dynamic>> _favoriteTournaments = [];
  static bool _isInitialized = false;

  // Initialize the service
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      // Load player favorites
      final playersJson = prefs.getString(_favoritePlayersKey);
      if (playersJson != null) {
        final List<dynamic> decoded = jsonDecode(playersJson);
        _favoritePlayers.clear();
        _favoritePlayers.addAll(decoded.cast<Map<String, dynamic>>());
      }

      // Load tournament favorites
      final tournamentsJson = prefs.getString(_favoriteTournamentsKey);
      if (tournamentsJson != null) {
        final List<dynamic> decoded = jsonDecode(tournamentsJson);
        _favoriteTournaments.clear();
        _favoriteTournaments.addAll(decoded.cast<Map<String, dynamic>>());
      }

      _isInitialized = true;
    } catch (e) {
      print('Error initializing FavoritesService: $e');
    }
  }

  // PLAYER FAVORITES METHODS
  // Get all starred_repository players
  static Future<List<Map<String, dynamic>>> getAllFavoritePlayers() async {
    await initialize();
    return List<Map<String, dynamic>>.from(_favoritePlayers);
  }

  // Check if a player is in favorites
  static Future<bool> isPlayerFavorite(String playerName) async {
    await initialize();
    return _favoritePlayers.any((player) => player['name'] == playerName);
  }

  // Update starred_repository status for a player
  static Future<void> updatePlayerFavoriteStatus(
    String playerName,
    bool isFavorite,
  ) async {
    await initialize();

    if (isFavorite) {
      // Add to favorites if not already in the list
      if (!_favoritePlayers.any((player) => player['name'] == playerName)) {
        // Get player data from the global player list
        final player = await _getPlayerByName(playerName);

        if (player.isNotEmpty) {
          final favoritePlayer = Map<String, dynamic>.from(player);
          favoritePlayer['isFavorite'] = true;
          _favoritePlayers.add(favoritePlayer);
          await _persistPlayerFavorites();
        }
      }
    } else {
      // Remove from favorites
      _favoritePlayers.removeWhere((player) => player['name'] == playerName);
      await _persistPlayerFavorites();
    }
  }

  // Helper method to get a player by name from the global player list
  static Future<Map<String, dynamic>> _getPlayerByName(
    String playerName,
  ) async {
    // This would normally fetch from a database or API
    // For now, we use a static list of players
    final allPlayers = [
      {'name': 'Magnus, Carlsen', 'countryCode': 'NO', 'elo': 2837, 'age': 35},
      {'name': 'Hikaru, Nakamura', 'countryCode': 'US', 'elo': 2804, 'age': 38},
      {'name': 'Erigaisi, Arjun', 'countryCode': 'IN', 'elo': 2782, 'age': 22},
      {'name': 'Carauna, Fabiano', 'countryCode': 'US', 'elo': 2777, 'age': 33},
      {'name': 'Gukesh, D', 'countryCode': 'IN', 'elo': 2776, 'age': 19},
      {'name': 'Abdusattorov, N', 'countryCode': 'UZ', 'elo': 2767, 'age': 21},
      {
        'name': 'Praggnanandhaa, R',
        'countryCode': 'IN',
        'elo': 2766,
        'age': 20,
      },
    ];

    return allPlayers.firstWhere(
      (player) => player['name'] == playerName,
      orElse: () => <String, Object>{},
    );
  }

  // Save all favorites at once
  static Future<void> saveFavorites(List<Map<String, dynamic>> players) async {
    await initialize();

    // Clear existing favorites
    _favoritePlayers.clear();

    // Add all players marked as favorites
    for (final player in players) {
      if (player['isFavorite'] == true) {
        _favoritePlayers.add(Map<String, dynamic>.from(player));
      }
    }

    await _persistPlayerFavorites();
  }

  // Update starred_repository status in a list of players
  static Future<List<Map<String, dynamic>>> updateFavoritesStatus(
    List<Map<String, dynamic>> players,
  ) async {
    await initialize();

    // Create a copy of the input list
    final updatedPlayers = List<Map<String, dynamic>>.from(players);

    // Get the current list of favorites
    final favorites = await getAllFavoritePlayers();

    // Update the isFavorite flag for each player
    for (var i = 0; i < updatedPlayers.length; i++) {
      final playerName = updatedPlayers[i]['name'];
      updatedPlayers[i]['isFavorite'] = favorites.any(
        (favorite) => favorite['name'] == playerName,
      );
    }

    return updatedPlayers;
  }

  // TOURNAMENT FAVORITES METHODS
  // Get all starred_repository tournaments
  static Future<List<Map<String, dynamic>>> getAllFavoriteTournaments() async {
    await initialize();
    return List<Map<String, dynamic>>.from(_favoriteTournaments);
  }

  // Check if a tournament is in favorites
  static Future<bool> isTournamentFavorite(String tournamentTitle) async {
    await initialize();
    return _favoriteTournaments.any(
      (tournament) => tournament['title'] == tournamentTitle,
    );
  }

  // Toggle tournament starred_repository status
  static Future<bool> toggleTournamentFavorite(
    String title,
    String dates,
    String location,
    int playerCount,
    int elo,
  ) async {
    await initialize();

    // Check if tournament is already a starred_repository
    final index = _favoriteTournaments.indexWhere(
      (tournament) => tournament['title'] == title,
    );

    if (index != -1) {
      // Remove from favorites
      _favoriteTournaments.removeAt(index);
      await _persistTournamentFavorites();
      return false; // Not a starred_repository anymore
    } else {
      // Add to favorites
      final tournament = {
        'title': title,
        'dates': dates,
        'location': location,
        'playerCount': playerCount,
        'elo': elo,
      };

      _favoriteTournaments.add(tournament);
      await _persistTournamentFavorites();
      return true; // Now a starred_repository
    }
  }

  // Persist player favorites to storage
  static Future<void> _persistPlayerFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favoritesJson = jsonEncode(_favoritePlayers);
      await prefs.setString(_favoritePlayersKey, favoritesJson);
    } catch (e) {
      print('Error persisting player favorites: $e');
    }
  }

  // Persist tournament favorites to storage
  static Future<void> _persistTournamentFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favoritesJson = jsonEncode(_favoriteTournaments);
      await prefs.setString(_favoriteTournamentsKey, favoritesJson);
    } catch (e) {
      print('Error persisting tournament favorites: $e');
    }
  }

  // Persist all favorites to storage
  static Future<void> _persistFavorites() async {
    await _persistPlayerFavorites();
    await _persistTournamentFavorites();
  }
}
