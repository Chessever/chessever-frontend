import 'dart:convert';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Migrates old SharedPreferences favorites to Supabase
/// This ensures backwards compatibility for users updating the app
class FavoritesMigration {
  // Old keys used by the previous system (GLOBAL - not user-specific)
  // These are legacy keys from before we had user-specific storage
  static const String _oldPlayersKey = 'favorite_players';
  static const List<String> _oldEventKeys = [
    'current', // GroupEventCategory.current.name
    'upcoming', // GroupEventCategory.forYou.name
    'past', // GroupEventCategory.past.name
  ];

  /// Returns user-specific migration key to ensure each user only migrates once
  /// v4: Disabled event migration - old keys stored ALL events, not just favorites
  static String _migrationKeyForUser(String userId) =>
      'favorites_migration_complete_v4_$userId';

  /// Run the migration once per user
  /// This is safe to call multiple times - it only runs once per user
  /// NOTE: Event migration is DISABLED - the old keys (current, upcoming, past)
  /// stored ALL fetched events, not just favorites. Only player favorites are migrated.
  static Future<SharedPreferences?> _getPrefs() async =>
      SharedPreferencesService.instance.ensureInitialized();

  static Future<void> migrateIfNeeded() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[FavoritesMigration] No user logged in, skipping migration');
        return;
      }

      final prefs = await _getPrefs();
      if (prefs == null) {
        debugPrint('[FavoritesMigration] SharedPreferences unavailable, skipping');
        return;
      }

      // User-specific migration flag - v4 to force re-run after disabling event migration
      final userMigrationKey = _migrationKeyForUser(userId);
      final migrationComplete = prefs.getBool(userMigrationKey) ?? false;
      if (migrationComplete) {
        debugPrint('[FavoritesMigration] Already migrated for user $userId, skipping');
        return;
      }

      // Always clear legacy event keys - they contain ALL events, not favorites
      // This prevents any future incorrect migrations
      await _clearLegacyKeys(prefs);

      // Check if there's player data to migrate
      final hasPlayerData = prefs.containsKey(_oldPlayersKey) &&
          (prefs.getString(_oldPlayersKey)?.isNotEmpty ?? false);

      if (!hasPlayerData) {
        debugPrint('[FavoritesMigration] No player data to migrate, marking complete');
        await prefs.setBool(userMigrationKey, true);
        return;
      }

      debugPrint('[FavoritesMigration] Starting player migration for user: $userId');

      // Only migrate players - NOT events
      // The old event keys (current, upcoming, past) stored ALL fetched events, not favorites
      final success = await _migratePlayers(prefs, userId);

      if (success) {
        await prefs.setBool(userMigrationKey, true);
        debugPrint('[FavoritesMigration] ✅ Player migration complete!');
      } else {
        debugPrint(
          '[FavoritesMigration] ⚠️ Migration did not complete. Will retry on next launch.',
        );
      }
    } catch (e, st) {
      debugPrint('[FavoritesMigration] ❌ Error during migration: $e');
      debugPrint('[FavoritesMigration] Stack: $st');
      // Don't rethrow - migration errors shouldn't block app startup
    }
  }

  /// Migrate player favorites from old system
  static Future<bool> _migratePlayers(
    SharedPreferences prefs,
    String userId,
  ) async {
    try {
      final supabase = Supabase.instance.client;
      final favoritesJson = prefs.getString(_oldPlayersKey);

      if (favoritesJson == null) {
        debugPrint('[FavoritesMigration] No players to migrate');
        return true;
      }

      final List<dynamic> decoded = jsonDecode(favoritesJson);
      final playersToMigrate = <Map<String, dynamic>>[];

      debugPrint('[FavoritesMigration] Found ${decoded.length} players in old system');

      for (var item in decoded) {
        try {
          final player = PlayerStandingModel.fromJson(
            item as Map<String, dynamic>,
          );

          // Store the complete PlayerStandingModel data in metadata
          playersToMigrate.add({
            'user_id': userId,
            'fide_id': player.fideId?.toString(),
            'player_name': player.name,
            'metadata': player.toJson(), // Store complete model
          });
        } catch (e) {
          debugPrint('[FavoritesMigration] Error parsing player: $e, item: $item');
          // Skip this player and continue
        }
      }

      if (playersToMigrate.isEmpty) {
        debugPrint('[FavoritesMigration] No valid players to migrate');
        return true;
      }

      debugPrint(
        '[FavoritesMigration] Migrating ${playersToMigrate.length} players to Supabase...',
      );

      // Insert to Supabase (use upsert with onConflict to handle duplicates)
      await supabase.from('user_favorite_players').upsert(
        playersToMigrate,
        onConflict: 'user_id,player_name',
        ignoreDuplicates: true,
      );

      debugPrint(
        '[FavoritesMigration] ✅ Successfully migrated ${playersToMigrate.length} players',
      );
      return true;
    } catch (e, st) {
      debugPrint('[FavoritesMigration] Error migrating players: $e');
      debugPrint('[FavoritesMigration] Stack: $st');
      // Don't rethrow - continue with app startup
      return false;
    }
  }

  /// Clear legacy keys after successful migration
  /// This prevents the same data from being migrated to multiple users
  static Future<void> _clearLegacyKeys(SharedPreferences prefs) async {
    debugPrint('[FavoritesMigration] Clearing legacy keys...');

    // Clear old players key
    if (prefs.containsKey(_oldPlayersKey)) {
      await prefs.remove(_oldPlayersKey);
    }

    // Clear old event keys
    for (final key in _oldEventKeys) {
      if (prefs.containsKey(key)) {
        await prefs.remove(key);
      }
    }

    // Also clear old migration flags
    await prefs.remove('favorites_migration_complete_v1');
    await prefs.remove('favorites_migration_complete_v2');

    debugPrint('[FavoritesMigration] Legacy keys cleared');
  }

  /// Reset migration flag for a specific user (useful for testing)
  static Future<void> resetMigration() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('[FavoritesMigration] No user logged in, cannot reset');
      return;
    }
    final prefs = await _getPrefs();
    if (prefs == null) return;
    await prefs.remove(_migrationKeyForUser(userId));
    debugPrint('[FavoritesMigration] Migration flag reset for user $userId');
  }

  /// One-time cleanup for users affected by the bad v1/v2 migration
  /// This deletes all favorite events from Supabase that were incorrectly migrated
  /// Safe to call multiple times - only runs once per user
  static Future<void> cleanupBadMigrationDataIfNeeded() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[FavoritesMigration] No user logged in, skipping cleanup');
        return;
      }

      final prefs = await _getPrefs();
      if (prefs == null) {
        debugPrint('[FavoritesMigration] SharedPreferences unavailable, skipping cleanup');
        return;
      }
      final cleanupKey = 'favorites_cleanup_v1_$userId';
      final cleanupDone = prefs.getBool(cleanupKey) ?? false;

      if (cleanupDone) {
        debugPrint('[FavoritesMigration] Cleanup already done for user $userId');
        return;
      }

      debugPrint('[FavoritesMigration] 🧹 Starting bad migration cleanup for user: $userId');

      // Delete all favorite events from Supabase for this user
      // These were incorrectly migrated from non-user-specific SharedPreferences
      final supabase = Supabase.instance.client;

      // Count before delete for logging
      final countResponse = await supabase
          .from('user_favorite_events')
          .select('id')
          .eq('user_id', userId);
      final eventCount = (countResponse as List).length;

      if (eventCount > 0) {
        await supabase
            .from('user_favorite_events')
            .delete()
            .eq('user_id', userId);
        debugPrint('[FavoritesMigration] ✅ Deleted $eventCount incorrectly migrated events');
      } else {
        debugPrint('[FavoritesMigration] No events to clean up');
      }

      // Mark cleanup as done for this user
      await prefs.setBool(cleanupKey, true);
      debugPrint('[FavoritesMigration] ✅ Cleanup complete for user $userId');
    } catch (e, st) {
      debugPrint('[FavoritesMigration] ❌ Error during cleanup: $e');
      debugPrint('[FavoritesMigration] Stack: $st');
      // Don't rethrow - cleanup errors shouldn't block app
    }
  }

  /// Cleanup stale favorite player caches that may cause UI duplicates
  /// This forces a fresh sync from Supabase on next load
  /// Safe to call multiple times - only runs once per user per version
  static Future<void> cleanupStaleFavoritesCacheIfNeeded() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[FavoritesMigration] No user logged in, skipping cache cleanup');
        return;
      }

      final prefs = await _getPrefs();
      if (prefs == null) {
        debugPrint('[FavoritesMigration] SharedPreferences unavailable, skipping cache cleanup');
        return;
      }
      // v1: Initial cleanup for double-sync duplicate issue
      final cleanupKey = 'favorites_cache_cleanup_v1_$userId';
      final cleanupDone = prefs.getBool(cleanupKey) ?? false;

      if (cleanupDone) {
        debugPrint('[FavoritesMigration] Cache cleanup already done for user $userId');
        return;
      }

      debugPrint('[FavoritesMigration] 🧹 Clearing stale favorite caches for user: $userId');

      // Clear all user-specific favorite player caches
      // These use different key patterns across providers
      final keysToRemove = <String>[
        'cached_favorite_players_$userId',
        'cached_favorite_players_full_$userId',
        'cached_favorite_players_anonymous',
        'cached_favorite_players_full_anonymous',
        // Also clear the old global cache key that may have cross-user pollution
        'cached_favorite_players_full',
      ];

      for (final key in keysToRemove) {
        if (prefs.containsKey(key)) {
          await prefs.remove(key);
          debugPrint('[FavoritesMigration] Removed cache key: $key');
        }
      }

      // Mark cleanup as done
      await prefs.setBool(cleanupKey, true);
      debugPrint('[FavoritesMigration] ✅ Cache cleanup complete for user $userId');
    } catch (e, st) {
      debugPrint('[FavoritesMigration] ❌ Error during cache cleanup: $e');
      debugPrint('[FavoritesMigration] Stack: $st');
      // Don't rethrow - cleanup errors shouldn't block app
    }
  }

}
