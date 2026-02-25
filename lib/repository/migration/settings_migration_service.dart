import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final settingsMigrationServiceProvider = Provider(
  (ref) => SettingsMigrationService(ref),
);

/// Service to handle one-time migration of local settings from SharedPreferences to Supabase
/// NOTE: This reads from SharedPreferences as the SOURCE (legacy data) to migrate to Supabase.
/// The migration flag itself is stored in SQLite (the new storage system).
class SettingsMigrationService {
  SettingsMigrationService(this.ref);

  final Ref ref;

  static const String _migrationKey = 'settings_migrated_to_supabase_v1';

  SupabaseClient get _supabase => Supabase.instance.client;

  /// Check if migration has already been performed
  Future<bool> isMigrated() async {
    final flag = await AppDatabase.instance.getBool(_migrationKey);
    return flag ?? false;
  }

  /// Perform one-time migration of local settings to Supabase
  /// This should only be called when a user is authenticated
  Future<void> migrateSettingsToSupabase() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[Migration] ⚠️ No user logged in, skipping migration');
        return;
      }

      // Check if already migrated
      if (await isMigrated()) {
        debugPrint('[Migration] ℹ️ Already migrated, skipping');
        return;
      }

      debugPrint(
        '[Migration] 🔄 Starting settings migration for user: $userId',
      );

      final prefs = ref.read(sharedPreferencesRepository);
      final migrationData = <String, dynamic>{
        'user_id': userId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      // Migrate engine settings from SharedPreferences
      final showEngineGauge = await prefs.getBool('show_engine_gauge');
      if (showEngineGauge != null) {
        migrationData['show_engine_gauge'] = showEngineGauge;
        debugPrint('[Migration]   📦 show_engine_gauge: $showEngineGauge');
      }

      final showDepthOverlay = await prefs.getBool('show_depth_overlay');
      if (showDepthOverlay != null) {
        migrationData['show_depth_overlay'] = showDepthOverlay;
        debugPrint('[Migration]   📦 show_depth_overlay: $showDepthOverlay');
      }

      final showPvArrows = await prefs.getBool('show_pv_arrows');
      if (showPvArrows != null) {
        migrationData['show_pv_arrows'] = showPvArrows;
        debugPrint('[Migration]   📦 show_pv_arrows: $showPvArrows');
      }

      final showEngineAnalysis = await prefs.getBool('show_engine_analysis');
      if (showEngineAnalysis != null) {
        migrationData['show_engine_analysis'] = showEngineAnalysis;
        debugPrint(
          '[Migration]   📦 show_engine_analysis: $showEngineAnalysis',
        );
      }

      final searchTimeIndex = await prefs.getInt('search_time_index');
      if (searchTimeIndex != null) {
        migrationData['search_time_index'] = searchTimeIndex;
        debugPrint('[Migration]   📦 search_time_index: $searchTimeIndex');
      }

      final principalVariationIndex = await prefs.getInt(
        'principal_variation_index',
      );
      if (principalVariationIndex != null) {
        migrationData['principal_variation_index'] = principalVariationIndex;
        debugPrint(
          '[Migration]   📦 principal_variation_index: $principalVariationIndex',
        );
      }

      // Migrate board settings
      final boardColorIndex = await prefs.getInt('board_color_index');
      if (boardColorIndex != null) {
        migrationData['board_color_index'] = boardColorIndex;
        debugPrint('[Migration]   📦 board_color_index: $boardColorIndex');
      }

      final showEvaluationBar = await prefs.getBool('show_evaluation_bar');
      if (showEvaluationBar != null) {
        migrationData['show_evaluation_bar'] = showEvaluationBar;
        debugPrint('[Migration]   📦 show_evaluation_bar: $showEvaluationBar');
      }

      final soundEnabled = await prefs.getBool('sound_enabled');
      if (soundEnabled != null) {
        migrationData['sound_enabled'] = soundEnabled;
        debugPrint('[Migration]   📦 sound_enabled: $soundEnabled');
      }

      final chatEnabled = await prefs.getBool('chat_enabled');
      if (chatEnabled != null) {
        migrationData['chat_enabled'] = chatEnabled;
        debugPrint('[Migration]   📦 chat_enabled: $chatEnabled');
      }

      final pieceStyleIndex = await prefs.getInt('piece_style_index');
      if (pieceStyleIndex != null) {
        migrationData['piece_style_index'] = pieceStyleIndex;
        debugPrint('[Migration]   📦 piece_style_index: $pieceStyleIndex');
      }

      // Migrate country selection
      // First check new format (country code)
      String? countryCode = await prefs.getString('selected_country_code');

      // If not found, check legacy format (country name)
      if (countryCode == null || countryCode.isEmpty) {
        final countryName = await prefs.getString('selected_country_name');
        if (countryName != null && countryName.isNotEmpty) {
          // We'll store the legacy name with LEGACY prefix so the system can convert it
          countryCode = 'MIGRATE:$countryName';
          debugPrint(
            '[Migration]   📦 selected_country (legacy name): $countryName',
          );
        }
      } else {
        debugPrint('[Migration]   📦 selected_country_code: $countryCode');
      }

      // Note: We handle the legacy migration in the country_dropdown_provider
      // So if countryCode starts with MIGRATE:, it will be converted to code format
      if (countryCode != null && countryCode.isNotEmpty) {
        if (countryCode.startsWith('MIGRATE:')) {
          // Strip MIGRATE prefix for now, let the app handle conversion later
          // We just want to preserve the data
          final legacyName = countryCode.substring(8);
          debugPrint(
            '[Migration]   ⚠️ Legacy country name found: $legacyName (will be converted by app)',
          );
          // Don't migrate legacy format - let the app's normal flow handle it
        } else {
          migrationData['selected_country_code'] = countryCode;
        }
      }

      // Only perform upsert if we have data to migrate (beyond just user_id and updated_at)
      if (migrationData.length > 2) {
        try {
          await _supabase
              .from('user_engine_settings')
              .upsert(migrationData, onConflict: 'user_id');
          debugPrint(
            '[Migration] ✅ Successfully migrated ${migrationData.length - 2} settings to Supabase',
          );
        } catch (e) {
          debugPrint('[Migration] ❌ Failed to upsert to Supabase: $e');
          // Don't mark as migrated if it failed
          return;
        }
      } else {
        debugPrint('[Migration] ℹ️ No local settings found to migrate');
      }

      // Mark migration as complete (use SQLite for the flag)
      await AppDatabase.instance.setBool(_migrationKey, true);
      debugPrint('[Migration] ✅ Migration complete, flag set');
    } catch (e, st) {
      debugPrint('[Migration] ❌ Error during migration: $e');
      debugPrint('[Migration] Stack: $st');
      // Don't rethrow - migration should be silent and not block auth flow
    }
  }

  /// Reset migration flag (for testing purposes only)
  @visibleForTesting
  Future<void> resetMigrationFlag() async {
    await AppDatabase.instance.remove(_migrationKey);
    debugPrint('[Migration] 🔄 Migration flag reset');
  }
}
