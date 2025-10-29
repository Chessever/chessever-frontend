import 'dart:convert';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Migrates old SharedPreferences favorites to Supabase
/// This ensures backwards compatibility for users updating the app
class FavoritesMigration {
  static const String _migrationCompleteKey = 'favorites_migration_complete_v1';

  // Old keys used by the previous system
  static const String _oldPlayersKey = 'favorite_players';
  static const List<String> _oldEventKeys = [
    'current', // GroupEventCategory.current.name
    'upcoming', // GroupEventCategory.upcoming.name
    'past', // GroupEventCategory.past.name
  ];

  /// Run the migration once on app startup
  /// This is safe to call multiple times - it only runs once
  static Future<void> migrateIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if migration already completed
      final migrationComplete = prefs.getBool(_migrationCompleteKey) ?? false;
      if (migrationComplete) {
        debugPrint('[FavoritesMigration] Already migrated, skipping');
        return;
      }

      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[FavoritesMigration] No user logged in, skipping migration');
        return;
      }

      debugPrint('[FavoritesMigration] Starting migration for user: $userId');

      // Migrate events and players in parallel
      await Future.wait([
        _migrateEvents(prefs, userId),
        _migratePlayers(prefs, userId),
      ]);

      // Mark migration as complete
      await prefs.setBool(_migrationCompleteKey, true);
      debugPrint('[FavoritesMigration] ✅ Migration complete!');
    } catch (e, st) {
      debugPrint('[FavoritesMigration] ❌ Error during migration: $e');
      debugPrint('[FavoritesMigration] Stack: $st');
      // Don't rethrow - migration errors shouldn't block app startup
    }
  }

  /// Migrate event favorites from old starred system
  static Future<void> _migrateEvents(SharedPreferences prefs, String userId) async {
    try {
      final supabase = Supabase.instance.client;
      final eventsToMigrate = <Map<String, dynamic>>[];

      // Collect all starred events from different categories
      for (final categoryKey in _oldEventKeys) {
        final starredList = prefs.getStringList(categoryKey) ?? [];
        debugPrint('[FavoritesMigration] Found ${starredList.length} events in category: $categoryKey');

        for (final eventId in starredList) {
          // Skip if already in list (avoid duplicates)
          if (eventsToMigrate.any((e) => e['event_id'] == eventId)) {
            continue;
          }

          eventsToMigrate.add({
            'user_id': userId,
            'event_id': eventId,
            'event_name': eventId, // We only have ID, name will be same
            'metadata': <String, dynamic>{}, // No metadata in old system
          });
        }
      }

      if (eventsToMigrate.isEmpty) {
        debugPrint('[FavoritesMigration] No events to migrate');
        return;
      }

      debugPrint('[FavoritesMigration] Migrating ${eventsToMigrate.length} events to Supabase...');

      // Insert to Supabase (use upsert to avoid duplicates)
      await supabase
          .from('user_favorite_events')
          .upsert(eventsToMigrate);

      debugPrint('[FavoritesMigration] ✅ Successfully migrated ${eventsToMigrate.length} events');
    } catch (e, st) {
      debugPrint('[FavoritesMigration] Error migrating events: $e');
      debugPrint('[FavoritesMigration] Stack: $st');
      // Don't rethrow - continue with other migrations
    }
  }

  /// Migrate player favorites from old system
  static Future<void> _migratePlayers(SharedPreferences prefs, String userId) async {
    try {
      final supabase = Supabase.instance.client;
      final favoritesJson = prefs.getString(_oldPlayersKey);

      if (favoritesJson == null) {
        debugPrint('[FavoritesMigration] No players to migrate');
        return;
      }

      final List<dynamic> decoded = jsonDecode(favoritesJson);
      final playersToMigrate = <Map<String, dynamic>>[];

      debugPrint('[FavoritesMigration] Found ${decoded.length} players in old system');

      for (var item in decoded) {
        try {
          final player = PlayerStandingModel.fromJson(item as Map<String, dynamic>);

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
        return;
      }

      debugPrint('[FavoritesMigration] Migrating ${playersToMigrate.length} players to Supabase...');

      // Insert to Supabase (use upsert to avoid duplicates)
      await supabase
          .from('user_favorite_players')
          .upsert(playersToMigrate);

      debugPrint('[FavoritesMigration] ✅ Successfully migrated ${playersToMigrate.length} players');
    } catch (e, st) {
      debugPrint('[FavoritesMigration] Error migrating players: $e');
      debugPrint('[FavoritesMigration] Stack: $st');
      // Don't rethrow - continue with app startup
    }
  }

  /// Reset migration flag (useful for testing)
  static Future<void> resetMigration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_migrationCompleteKey);
    debugPrint('[FavoritesMigration] Migration flag reset');
  }
}
