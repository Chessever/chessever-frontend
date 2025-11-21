import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chessever2/repository/supabase/players/players_repository.dart';

class PlayerViewModel {
  static const String _favoritePlayerIdsKey = 'favorite_player_ids';

  final PlayersRepository _repo = PlayersRepository();
  final List<Map<String, dynamic>> _players = [];
  bool _isInitialized = false;

  int _offset = 0;
  final int _pageSize = 20;
  bool _hasMore = true;
  bool _isOnboarding = false;
  bool _onboardingInitialFetched = false;

  Set<String> _favoritePlayerIds = {};

  Future<void> initialize({bool clear = false, bool isOnboarding = false}) async {
    if (clear) {
      _players.clear();
      _offset = 0;
      _hasMore = true;
      _onboardingInitialFetched = false;
    }
    _isOnboarding = isOnboarding;
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
    // For onboarding with no search: use optimized fetch
    if (_isOnboarding && search.isEmpty && !_onboardingInitialFetched) {
      _onboardingInitialFetched = true;
      return _fetchOnboardingPlayers(countryCode ?? 'US');
    }

    // For search: use search-specific method
    if (search.isNotEmpty) {
      return _fetchSearchResults(search);
    }

    // Regular paginated fetch
    if (!_hasMore) return [];
    return _fetchPaginatedPlayers(countryCode);
  }

  Future<List<Map<String, dynamic>>> _fetchOnboardingPlayers(String countryCode) async {
    final players = await _repo.fetchOnboardingPlayers(
      countryCode: countryCode,
      countryLimit: 8,
      globalLimit: 7,
    );

    final enriched = _enrichWithFavorites(players);
    _players.addAll(enriched);
    _hasMore = false; // Onboarding shows fixed list, no pagination needed
    return enriched;
  }

  Future<List<Map<String, dynamic>>> _fetchSearchResults(String query) async {
    // Reset for new search
    if (_offset == 0) {
      _players.clear();
    }

    final players = await _repo.searchPlayers(
      query: query,
      offset: _offset,
      pageSize: _pageSize,
    );

    final enriched = _enrichWithFavorites(players);
    _offset += _pageSize;
    _hasMore = players.length == _pageSize;

    // Deduplicate
    final newPlayers = <Map<String, dynamic>>[];
    for (final player in enriched) {
      final key = player['fideId'];
      if (!_players.any((p) => p['fideId'] == key)) {
        _players.add(player);
        newPlayers.add(player);
      }
    }

    return newPlayers;
  }

  Future<List<Map<String, dynamic>>> _fetchPaginatedPlayers(String? countryCode) async {
    final players = await _repo.fetchPlayersPage(
      offset: _offset,
      pageSize: _pageSize,
      countryCode: countryCode,
    );

    final enriched = _enrichWithFavorites(players);
    _offset += _pageSize;
    _hasMore = players.length == _pageSize;

    // Deduplicate
    final newPlayers = <Map<String, dynamic>>[];
    for (final player in enriched) {
      final key = player['fideId'];
      if (!_players.any((p) => p['fideId'] == key)) {
        _players.add(player);
        newPlayers.add(player);
      }
    }

    return newPlayers;
  }

  List<Map<String, dynamic>> _enrichWithFavorites(List<Map<String, dynamic>> players) {
    return players.map((player) {
      final fideId = player['fideId']?.toString() ?? '';
      return {
        ...player,
        'isFavorite': _favoritePlayerIds.contains(fideId),
      };
    }).toList();
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

  void resetSearch() {
    _offset = 0;
    _hasMore = true;
    _onboardingInitialFetched = false;
  }
}
