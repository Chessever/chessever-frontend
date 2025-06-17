import 'dart:async';
import 'dart:convert';

import '../models/player.dart';
// Import http package for API calls when you're ready to implement
// import 'package:http/http.dart' as http;

class PlayerService {
  // Singleton pattern
  static final PlayerService _instance = PlayerService._internal();
  factory PlayerService() => _instance;
  PlayerService._internal();

  // In-memory cache of players
  final List<Player> _cachedPlayers = [
    Player(
      id: '1',
      name: 'GM Magnus Carlsen',
      countryCode: 'NO',
      elo: 2830,
      age: 34,
      isFavorite: true,
    ),
    Player(
      id: '2',
      name: 'GM Hikaru Nakamura',
      countryCode: 'US',
      elo: 2798,
      age: 37,
      isFavorite: false,
    ),
    Player(
      id: '3',
      name: 'GM Fabiano Caruana',
      countryCode: 'US',
      elo: 2805,
      age: 33,
      isFavorite: false,
    ),
    Player(
      id: '4',
      name: 'GM Ian Nepomniachtchi',
      countryCode: 'RU',
      elo: 2785,
      age: 35,
      isFavorite: false,
    ),
    Player(
      id: '5',
      name: 'GM Ding Liren',
      countryCode: 'CN',
      elo: 2815,
      age: 33,
      isFavorite: true,
    ),
    Player(
      id: '6',
      name: 'GM Wesley So',
      countryCode: 'US',
      elo: 2770,
      age: 32,
      isFavorite: false,
    ),
    Player(
      id: '7',
      name: 'GM Alireza Firouzja',
      countryCode: 'FR',
      elo: 2782,
      age: 22,
      isFavorite: false,
    ),
  ];

  // Get all players (simulates API call)
  Future<List<Player>> getPlayers() async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));
    return [..._cachedPlayers];
  }

  // Get a specific player by ID (simulates API call)
  Future<Player?> getPlayerById(String id) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 300));

    final player = _cachedPlayers.firstWhere(
      (player) => player.id == id,
      orElse:
          () => Player(
            id: '-1',
            name: 'Unknown Player',
            countryCode: 'XX',
            elo: 0,
            age: 0,
          ),
    );

    return player.id == '-1' ? null : player;
  }

  // Toggle favorite status for a player
  Future<void> toggleFavorite(String playerId) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 300));

    final index = _cachedPlayers.indexWhere((player) => player.id == playerId);
    if (index >= 0) {
      _cachedPlayers[index] = _cachedPlayers[index].copyWith(
        isFavorite: !_cachedPlayers[index].isFavorite,
      );
    }
  }

  // Search players by name (simulates API call with filter)
  Future<List<Player>> searchPlayers(String query) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    final lowercaseQuery = query.toLowerCase();
    return _cachedPlayers
        .where((player) => player.name.toLowerCase().contains(lowercaseQuery))
        .toList();
  }

  // Get top players by ELO rating
  Future<List<Player>> getTopPlayers({int limit = 5}) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 500));

    final sorted = [..._cachedPlayers]..sort((a, b) => b.elo.compareTo(a.elo));
    return sorted.take(limit).toList();
  }

  // Add a new player (simulates API call)
  Future<Player> addPlayer(Player player) async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 1000));

    _cachedPlayers.add(player);
    return player;
  }

  // TODO: Implementation for real API calls
  // Future<List<Player>> fetchPlayersFromApi() async {
  //   final response = await http.get(Uri.parse('https://api.example.com/players'));
  //
  //   if (response.statusCode == 200) {
  //     final List<dynamic> data = json.decode(response.body);
  //     return data.map((json) => Player.fromJson(json)).toList();
  //   } else {
  //     throw Exception('Failed to load players');
  //   }
  // }
}
