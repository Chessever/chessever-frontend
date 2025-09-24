import 'dart:convert';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';

final unifiedFavoritesService = Provider<UnifiedFavoritesService>((ref) {
  return UnifiedFavoritesService();
});

class UnifiedFavoritesService {
  static const String _favoriteEventsKey = 'favorite_events_list';
  static const String _favoritePlayersKey = 'favorite_players_list';
  static const String _favoriteTournamentPlayersKey = 'favorite_tournament_players';

  // Event favorites methods - store event IDs with minimal metadata
  Future<List<Map<String, dynamic>>> getFavoriteEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final eventsJson = prefs.getString(_favoriteEventsKey);

    if (eventsJson != null) {
      final List<dynamic> decoded = jsonDecode(eventsJson);
      return decoded.cast<Map<String, dynamic>>();
    }
    return <Map<String, dynamic>>[];
  }

  Future<void> saveFavoriteEvents(List<Map<String, dynamic>> events) async {
    final prefs = await SharedPreferences.getInstance();
    final eventsJson = jsonEncode(events);
    await prefs.setString(_favoriteEventsKey, eventsJson);
  }

  Future<void> toggleEventFavorite(GroupEventCardModel event) async {
    final favorites = await getFavoriteEvents();
    final existingIndex = favorites.indexWhere((e) => e['id'] == event.id);

    if (existingIndex != -1) {
      favorites.removeAt(existingIndex);
    } else {
      favorites.add({
        'id': event.id,
        'title': event.title,
        'timeControl': event.timeControl,
        'maxAvgElo': event.maxAvgElo,
        'dates': event.dates,
        'addedAt': DateTime.now().toIso8601String(),
      });
    }
    await saveFavoriteEvents(favorites);
  }

  Future<bool> isEventFavorite(String eventId) async {
    final favorites = await getFavoriteEvents();
    return favorites.any((e) => e['id'] == eventId);
  }

  // Player favorites methods - store player data
  Future<List<Map<String, dynamic>>> getFavoritePlayers() async {
    final prefs = await SharedPreferences.getInstance();
    final playersJson = prefs.getString(_favoritePlayersKey);

    if (playersJson != null) {
      final List<dynamic> decoded = jsonDecode(playersJson);
      return decoded.cast<Map<String, dynamic>>();
    }
    return <Map<String, dynamic>>[];
  }

  Future<void> saveFavoritePlayers(List<Map<String, dynamic>> players) async {
    final prefs = await SharedPreferences.getInstance();
    final playersJson = jsonEncode(players);
    await prefs.setString(_favoritePlayersKey, playersJson);
  }

  Future<void> togglePlayerFavorite({
    required String fideId,
    required String playerName,
    required String? countryCode,
    required int? rating,
    required String? title,
  }) async {
    final favorites = await getFavoritePlayers();
    final existingIndex = favorites.indexWhere((p) => p['fideId'] == fideId);

    if (existingIndex != -1) {
      favorites.removeAt(existingIndex);
    } else {
      favorites.add({
        'fideId': fideId,
        'name': playerName,
        'countryCode': countryCode,
        'rating': rating,
        'title': title,
        'addedAt': DateTime.now().toIso8601String(),
      });
    }
    await saveFavoritePlayers(favorites);
  }

  Future<bool> isPlayerFavorite(String fideId) async {
    final favorites = await getFavoritePlayers();
    return favorites.any((p) => p['fideId'] == fideId);
  }

  // Tournament player favorites methods (using existing PlayerStandingModel)
  Future<List<PlayerStandingModel>> getFavoriteTournamentPlayers() async {
    final prefs = await SharedPreferences.getInstance();
    final playersJson = prefs.getString(_favoriteTournamentPlayersKey);

    if (playersJson != null) {
      final List<dynamic> decoded = jsonDecode(playersJson);
      return decoded.map((item) => PlayerStandingModel.fromJson(item)).toList();
    }
    return <PlayerStandingModel>[];
  }

  Future<void> saveFavoriteTournamentPlayers(List<PlayerStandingModel> players) async {
    final prefs = await SharedPreferences.getInstance();
    final playersJson = jsonEncode(players.map((p) => p.toJson()).toList());
    await prefs.setString(_favoriteTournamentPlayersKey, playersJson);
  }

  Future<void> toggleTournamentPlayerFavorite(PlayerStandingModel player) async {
    final favorites = await getFavoriteTournamentPlayers();
    final existingIndex = favorites.indexWhere((p) => p.name == player.name);

    if (existingIndex != -1) {
      favorites.removeAt(existingIndex);
    } else {
      favorites.add(player);
    }
    await saveFavoriteTournamentPlayers(favorites);
  }

  Future<bool> isTournamentPlayerFavorite(String playerName) async {
    final favorites = await getFavoriteTournamentPlayers();
    return favorites.any((p) => p.name == playerName);
  }

  // Remove favorite methods
  Future<void> removeFavoriteEvent(String eventId) async {
    final favorites = await getFavoriteEvents();
    favorites.removeWhere((e) => e['id'] == eventId);
    await saveFavoriteEvents(favorites);
  }

  Future<void> removeFavoritePlayer(String fideId) async {
    final favorites = await getFavoritePlayers();
    favorites.removeWhere((p) => p['fideId'] == fideId);
    await saveFavoritePlayers(favorites);
  }

  Future<void> removeFavoriteTournamentPlayer(String playerName) async {
    final favorites = await getFavoriteTournamentPlayers();
    favorites.removeWhere((p) => p.name == playerName);
    await saveFavoriteTournamentPlayers(favorites);
  }
}