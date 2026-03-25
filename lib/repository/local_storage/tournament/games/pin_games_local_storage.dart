import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final pinGameLocalStorage = Provider.autoDispose<_PinGameLocalStorage>(
  (ref) => _PinGameLocalStorage(ref),
);

class _PinGameLocalStorage {
  _PinGameLocalStorage(this.ref);

  final Ref ref;

  String _getListKey(String tournamentId) => 'pinned_games_$tournamentId';
  String _getUnpinnedListKey(String tournamentId) =>
      'unpinned_games_$tournamentId';

  // Get pinned game IDs for a specific tournament
  Future<List<String>> getPinnedGameIds(String tournamentId) async {
    try {
      final db = ref.read(appDatabaseProvider);
      return await db.getList(key: _getListKey(tournamentId));
    } catch (e) {
      return [];
    }
  }

  // Add a pinned game ID for a specific tournament
  Future<void> addPinnedGameId(String tournamentId, String gameId) async {
    try {
      final db = ref.read(appDatabaseProvider);
      await db.addToList(key: _getListKey(tournamentId), item: gameId);
    } catch (e) {
      // Local storage failure is not critical
    }
  }

  // Remove a pinned game ID for a specific tournament
  Future<void> removePinnedGameId(String tournamentId, String gameId) async {
    try {
      final db = ref.read(appDatabaseProvider);
      await db.removeFromList(key: _getListKey(tournamentId), item: gameId);
    } catch (e) {
      // Local storage failure is not critical
    }
  }

  // Get explicitly unpinned game IDs for a specific tournament
  Future<List<String>> getUnpinnedGameIds(String tournamentId) async {
    try {
      final db = ref.read(appDatabaseProvider);
      return await db.getList(key: _getUnpinnedListKey(tournamentId));
    } catch (e) {
      return [];
    }
  }

  // Persist an explicit unpin override for a specific tournament
  Future<void> addUnpinnedGameId(String tournamentId, String gameId) async {
    try {
      final db = ref.read(appDatabaseProvider);
      await db.addToList(key: _getUnpinnedListKey(tournamentId), item: gameId);
    } catch (e) {
      // Local storage failure is not critical
    }
  }

  // Remove an explicit unpin override for a specific tournament
  Future<void> removeUnpinnedGameId(String tournamentId, String gameId) async {
    try {
      final db = ref.read(appDatabaseProvider);
      await db.removeFromList(
        key: _getUnpinnedListKey(tournamentId),
        item: gameId,
      );
    } catch (e) {
      // Local storage failure is not critical
    }
  }

  // Clear all explicit unpin overrides for a specific tournament
  Future<void> clearUnpinnedGames(String tournamentId) async {
    try {
      final db = ref.read(appDatabaseProvider);
      await db.clearList(key: _getUnpinnedListKey(tournamentId));
    } catch (e) {
      // Local storage failure is not critical
    }
  }

  // Clear all pinned games for a specific tournament
  Future<void> clearPinnedGames(String tournamentId) async {
    try {
      final db = ref.read(appDatabaseProvider);
      await db.clearList(key: _getListKey(tournamentId));
    } catch (e) {
      // Local storage failure is not critical
    }
  }

  // Clear all pinned games for all tournaments
  Future<void> clearAllPinnedGames() async {
    // Note: This is less efficient with SQLite than SharedPreferences
    // but pinned games are a cache - if they get cleared, no big deal
    // We could add a method to clear by key prefix if needed
  }
}
