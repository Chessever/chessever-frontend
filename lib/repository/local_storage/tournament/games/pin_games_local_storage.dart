import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final pinGameLocalStorage = Provider.autoDispose<_PinGameLocalStorage>(
  (ref) => _PinGameLocalStorage(),
);

class _PinGameLocalStorage {
  static const _keyPrefix = 'pinned_games_tournament_';

  // Generate key for specific tournament
  String _getTournamentKey(String tournamentId) {
    return '$_keyPrefix$tournamentId';
  }

  // Get pinned game IDs for a specific tournament
  Future<List<String>> getPinnedGameIds(String tournamentId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getTournamentKey(tournamentId);
    return prefs.getStringList(key) ?? [];
  }

  // Add a pinned game ID for a specific tournament
  Future<void> addPinnedGameId(String tournamentId, String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getTournamentKey(tournamentId);
    final pinnedIds = prefs.getStringList(key) ?? [];
    if (!pinnedIds.contains(gameId)) {
      pinnedIds.add(gameId);
      await prefs.setStringList(key, pinnedIds);
    }
  }

  // Remove a pinned game ID for a specific tournament
  Future<void> removePinnedGameId(String tournamentId, String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getTournamentKey(tournamentId);
    final pinnedIds = prefs.getStringList(key) ?? [];
    pinnedIds.remove(gameId);
    await prefs.setStringList(key, pinnedIds);
  }

  // Clear all pinned games for a specific tournament
  Future<void> clearPinnedGames(String tournamentId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getTournamentKey(tournamentId);
    await prefs.remove(key);
  }

  // Clear all pinned games for all tournaments
  Future<void> clearAllPinnedGames() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final tournamentKeys = keys.where((key) => key.startsWith(_keyPrefix));

    for (final key in tournamentKeys) {
      await prefs.remove(key);
    }
  }
}
