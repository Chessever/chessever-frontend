import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chessever2/repository/supabase/players/players_repository.dart';

class PlayerViewModel {
  static const String _favoritePlayerIdsKey = 'favorite_player_ids';

  final PlayersRepository _repo = PlayersRepository();
  final List<Map<String, dynamic>> _players = [];
  bool _isInitialized = false;

  int _offset = 0;
  final int _pageSize = 50;
  bool _hasMore = true;
  String _search = '';
  String? _countryCode;

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

  Future<List<Map<String, dynamic>>> fetchNextPage({
    String search = '',
    String? countryCode,
  }) async {
    if (!_hasMore) return [];

    _search = search;
    _countryCode = countryCode;

    final page = await _repo.fetchPlayersPage(
      offset: _offset,
      pageSize: _pageSize,
      search: _search,
      countryCode: _countryCode,
    );

    final List<Map<String, dynamic>> newPlayers = [];

    for (final player in page) {
      final key = '${player['name']}_${player['fide_id'] ?? player['fideId'] ?? ''}';
      if (_players.any((p) => '${p['name']}_${p['fideId']}' == key)) continue;

      final fideId = player['fide_id'] ?? player['fideId'];
      final playerData = {
        'fideId': fideId?.toString(),
        'name': player['name'],
        'rating': player['rating'] ?? 0,
        'title': player['title'] ?? '',
        'fed': player['fed'] ?? player['country_code'],
        'isFavorite': _favoritePlayerIds.contains(
          fideId?.toString() ?? '',
        ),
      };
      _players.add(playerData);
      newPlayers.add(playerData);
    }

    _offset += _pageSize;
    _hasMore = page.length == _pageSize;

    return newPlayers;
  }

  Future<void> toggleFavorite(String fideId) async {
    final isFav = _favoritePlayerIds.contains(fideId);
    await updateFavoriteFlag(fideId, !isFav);
  }

  Future<void> updateFavoriteFlag(String fideId, bool isFavorite) async {
    if (isFavorite) {
      _favoritePlayerIds.add(fideId);
    } else {
      _favoritePlayerIds.remove(fideId);
    }

    await _saveFavoritePlayerIds();

    final index = _players.indexWhere((p) => p['fideId'].toString() == fideId);
    if (index != -1) {
      _players[index]['isFavorite'] = isFavorite;
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
