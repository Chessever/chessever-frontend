import 'dart:convert';
import 'package:chessever2/screens/standings/player_standing_model.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:crypto/crypto.dart';

/// Migrates old SharedPreferences favorites to Supabase
/// This ensures backwards compatibility for users updating the app
class FavoritesMigration {
  // Bump version to force re-run after legacy failure cases
  static const String _migrationCompleteKey = 'favorites_migration_complete_v2';

  // Old keys used by the previous system
  static const String _oldPlayersKey = 'favorite_players';
  static const List<String> _oldEventKeys = [
    'current', // GroupEventCategory.current.name
    'upcoming', // GroupEventCategory.forYou.name
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

      // Migrate events and players in parallel, and only mark complete if both succeed
      final results = await Future.wait<bool>([
        _migrateEvents(prefs, userId),
        _migratePlayers(prefs, userId),
      ]);

      final allSucceeded = results.every((r) => r);
      if (allSucceeded) {
        await prefs.setBool(_migrationCompleteKey, true);
        debugPrint('[FavoritesMigration] ✅ Migration complete!');
      } else {
        debugPrint(
          '[FavoritesMigration] ⚠️ Migration did not fully complete. Will retry on next launch.',
        );
      }
    } catch (e, st) {
      debugPrint('[FavoritesMigration] ❌ Error during migration: $e');
      debugPrint('[FavoritesMigration] Stack: $st');
      // Don't rethrow - migration errors shouldn't block app startup
    }
  }

  /// Migrate event favorites from old starred system
  static Future<bool> _migrateEvents(
    SharedPreferences prefs,
    String userId,
  ) async {
    try {
      final supabase = Supabase.instance.client;
      final eventsToMigrate = <Map<String, dynamic>>[];
      final seenEventIds = <String>{};

      // Collect all starred events from different categories
      for (final categoryKey in _oldEventKeys) {
        final starredList = prefs.getStringList(categoryKey) ?? [];
        debugPrint(
          '[FavoritesMigration] Found ${starredList.length} events in category: $categoryKey',
        );

        for (final rawEvent in starredList) {
          final normalized = _normalizeLegacyEvent(rawEvent);
          if (normalized == null) {
            continue;
          }

          final eventId = normalized.eventId;
          if (seenEventIds.contains(eventId)) {
            continue;
          }
          seenEventIds.add(eventId);

          eventsToMigrate.add({
            'user_id': userId,
            'event_id': eventId,
            'event_name': normalized.eventName,
            'metadata': normalized.metadata,
          });
        }
      }

      if (eventsToMigrate.isEmpty) {
        debugPrint('[FavoritesMigration] No events to migrate');
        return true;
      }

      debugPrint(
        '[FavoritesMigration] Migrating ${eventsToMigrate.length} events to Supabase...',
      );

      // Insert to Supabase (use upsert to avoid duplicates)
      await supabase.from('user_favorite_events').upsert(eventsToMigrate);

      debugPrint(
        '[FavoritesMigration] ✅ Successfully migrated ${eventsToMigrate.length} events',
      );
      return true;
    } catch (e, st) {
      debugPrint('[FavoritesMigration] Error migrating events: $e');
      debugPrint('[FavoritesMigration] Stack: $st');
      // Don't rethrow - continue with other migrations
      return false;
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

      // Insert to Supabase (use upsert to avoid duplicates)
      await supabase.from('user_favorite_players').upsert(playersToMigrate);

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

  /// Reset migration flag (useful for testing)
  static Future<void> resetMigration() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_migrationCompleteKey);
    debugPrint('[FavoritesMigration] Migration flag reset');
  }

  /// Normalize legacy event data to a safe, indexable payload.
  /// Returns null if the entry cannot be parsed into a usable identifier.
  static _NormalizedEvent? _normalizeLegacyEvent(String rawEvent) {
    Map<String, dynamic>? decodedMap;
    String? eventId;
    String? eventName;

    try {
      final decoded = jsonDecode(rawEvent);
      if (decoded is Map<String, dynamic>) {
        decodedMap = decoded;
        eventId =
            decodedMap['id']?.toString() ??
            decodedMap['event_id']?.toString() ??
            decodedMap['slug']?.toString() ??
            decodedMap['uuid']?.toString();
        eventName =
            decodedMap['name']?.toString() ??
            decodedMap['title']?.toString() ??
            decodedMap['event_name']?.toString();
      }
    } catch (_) {
      // Not JSON; fall through to using raw string
    }

    final resolvedId = _safeEventId(eventId ?? rawEvent);
    if (resolvedId.isEmpty) {
      debugPrint(
        '[FavoritesMigration] Skipping legacy event with empty id. Raw: $rawEvent',
      );
      return null;
    }

    final resolvedName = _safeEventName(eventName, resolvedId);
    final metadata = <String, dynamic>{
      'legacy_raw': _truncate(rawEvent, 800),
      'legacy_source': 'favorites_migration_v1',
    };

    if (decodedMap != null) {
      metadata['legacy_payload'] = _truncate(jsonEncode(decodedMap), 800);
    }
    if (eventId != null && eventId != resolvedId) {
      metadata['original_event_id'] = _truncate(eventId, 200);
    }
    if (eventName != null && eventName != resolvedName) {
      metadata['original_event_name'] = _truncate(eventName, 200);
    }

    return _NormalizedEvent(
      eventId: resolvedId,
      eventName: resolvedName,
      metadata: metadata,
    );
  }

  static String _safeEventId(String rawId) {
    final trimmed = rawId.trim();
    if (trimmed.isEmpty) return '';

    // If identifier is too large for the index, use a stable hash
    final byteLength = utf8.encode(trimmed).length;
    const int maxIndexedBytes = 180; // conservative buffer under the ~2704b cap
    if (byteLength > maxIndexedBytes) {
      final hashed = md5.convert(utf8.encode(trimmed)).toString();
      debugPrint(
        '[FavoritesMigration] Hashing oversized event id (bytes=$byteLength) -> $hashed',
      );
      return 'legacy_$hashed';
    }
    return trimmed;
  }

  static String _safeEventName(String? rawName, String fallbackId) {
    final base = (rawName ?? '').trim();
    final chosen = base.isNotEmpty ? base : fallbackId;
    return _truncate(chosen, 120);
  }

  static String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return value.substring(0, maxLength);
  }
}

class _NormalizedEvent {
  final String eventId;
  final String eventName;
  final Map<String, dynamic> metadata;

  const _NormalizedEvent({
    required this.eventId,
    required this.eventName,
    required this.metadata,
  });
}
