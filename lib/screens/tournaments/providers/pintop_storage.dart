import 'package:shared_preferences/shared_preferences.dart';

class PinnedGamesStorage {
  static const _keyPinnedGames = 'pinned_games';

  Future<List<String>> getPinnedGameIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyPinnedGames) ?? [];
  }

  Future<void> savePinnedGameIds(List<String> pinnedIds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyPinnedGames, pinnedIds);
  }

  Future<void> addPinnedGameId(String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedIds = prefs.getStringList(_keyPinnedGames) ?? [];
    if (!pinnedIds.contains(gameId)) {
      pinnedIds.add(gameId);
      await prefs.setStringList(_keyPinnedGames, pinnedIds);
    }
  }

  Future<void> removePinnedGameId(String gameId) async {
    final prefs = await SharedPreferences.getInstance();
    final pinnedIds = prefs.getStringList(_keyPinnedGames) ?? [];
    pinnedIds.remove(gameId);
    await prefs.setStringList(_keyPinnedGames, pinnedIds);
  }

  Future<void> clearAllPinnedGames() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPinnedGames);
  }
}
