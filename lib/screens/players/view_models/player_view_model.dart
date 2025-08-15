import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../repository/supabase/players/players_repository.dart';

class PlayerViewModel {
  static const String _favoritePlayerIdsKey = 'favorite_player_ids';

  final PlayersRepository _repo = PlayersRepository();
  final List<Map<String, dynamic>> _players = [];
  bool _isInitialized = false;

  int _offset = 0;
  final int _pageSize = 50;
  bool _hasMore = true;

  Set<String> _favoritePlayerIds = {};

  Future<void> initialize({bool clear = false}) async {
    if (clear) {
      _players.clear();
      _offset = 0;
      _hasMore = true;
    }
    if (_isInitialized && !clear) return;
    _isInitialized = true;
    await _loadFavoritePlayerIds();
  }

  Future<void> _loadFavoritePlayerIds() async {
    final prefs = await SharedPreferences.getInstance();
    final favoritesJson = prefs.getString(_favoritePlayerIdsKey);

    if (favoritesJson != null) {
      final List<dynamic> decoded = jsonDecode(favoritesJson);
      _favoritePlayerIds = Set<String>.from(decoded.cast<String>());
    }
  }

  Future<List<Map<String, dynamic>>> fetchNextPage() async {
    if (!_hasMore) return [];

    final page = await _repo.fetchPlayersPage(
      offset: _offset,
      pageSize: _pageSize,
    );

    final List<Map<String, dynamic>> newPlayers = [];

    for (var game in page) {
      final playersList =
          (game['players'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ??
          [];
      for (var player in playersList) {
        final key = '${player['name']}_${player['rating']}';
        if (!_players.any((p) => '${p['name']}_${p['rating']}' == key)) {
          final playerData = {
            'fideId': player['fideId'],
            'name': player['name'],
            'rating': player['rating'] ?? 0,
            'title': player['title'] ?? '',
            'fed': player['fed'],
            'clock': player['clock'],
            'isFavorite': _favoritePlayerIds.contains(
              player['fideId'].toString(),
            ),
          };
          _players.add(playerData);
          newPlayers.add(playerData);
        }
      }
    }

    _offset += _pageSize;
    _hasMore = page.isNotEmpty;

    return newPlayers;
  }

  Future<void> toggleFavorite(String fideId) async {
    if (_favoritePlayerIds.contains(fideId)) {
      _favoritePlayerIds.remove(fideId);
    } else {
      _favoritePlayerIds.add(fideId);
    }
    await _saveFavoritePlayerIds();

    final index = _players.indexWhere((p) => p['fideId'].toString() == fideId);
    if (index != -1) {
      _players[index]['isFavorite'] = _favoritePlayerIds.contains(fideId);
    }
  }

  Future<void> _saveFavoritePlayerIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favoritesJson = jsonEncode(_favoritePlayerIds.toList());
      await prefs.setString(_favoritePlayerIdsKey, favoritesJson);
    } catch (e) {
      print('Error saving favorite player IDs: $e');
    }
  }
}
