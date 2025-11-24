import 'dart:async';

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final countryManRepository = Provider((ref) => _CountryManRepository(ref));

class _CountryManRepository {
  _CountryManRepository(this.ref);

  final Ref ref;

  static const _baseCountryCodeKey = 'selected_country_code';
  static const _baseCountryNameKey = 'selected_country_name'; // Legacy support

  SupabaseClient get _supabase => Supabase.instance.client;

  String _buildCountryCodeKey(String? userId) =>
      userId == null ? _baseCountryCodeKey : '$_baseCountryCodeKey:$userId';

  /// Save countryman selection with Supabase + SharedPreferences dual persistence
  /// @param countryCode - The 2-letter country code (e.g., 'US', 'TR', 'GB')
  Future<void> saveCountryMan(String countryCode) async {
    try {
      final userId = _supabase.auth.currentUser?.id;

      // Always save to SharedPreferences first (immediate, works offline)
      await _saveLocalCountry(userId, countryCode);

      // If user is logged in, persist to Supabase (fire-and-forget, non-blocking)
      if (userId != null) {
        unawaited(
          _saveToSupabase(userId, countryCode),
        );
      } else {
        debugPrint(
          '[CountryMan] ℹ️ No user logged in, skipping Supabase sync',
        );
      }
    } catch (e, st) {
      debugPrint('[CountryMan] ❌ Error saving countryman: $e');
      debugPrint('[CountryMan] Stack: $st');
    }
  }

  /// Internal method to save to Supabase (fire-and-forget)
  Future<void> _saveToSupabase(String userId, String countryCode) async {
    try {
      await _supabase.from('user_engine_settings').upsert(
        {
          'user_id': userId,
          'selected_country_code': countryCode,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id',
      );
      debugPrint('[CountryMan] ✅ Saved to Supabase: $countryCode');
    } catch (e) {
      debugPrint('[CountryMan] ⚠️ Failed to save to Supabase: $e');
    }
  }

  Future<void> removeCountrySelection() async {
    // Remove from SharedPreferences first (immediate)
    final userId = _supabase.auth.currentUser?.id;
    await _removeLocalCountry(userId);
    debugPrint('[CountryMan] ✅ Removed from SharedPreferences');

    // Remove from Supabase (fire-and-forget, non-blocking)
    if (userId != null) {
      unawaited(
        _removeFromSupabase(userId),
      );
    }
  }

  /// Internal method to remove from Supabase (fire-and-forget)
  Future<void> _removeFromSupabase(String userId) async {
    try {
      await _supabase.from('user_engine_settings').upsert(
        {
          'user_id': userId,
          'selected_country_code': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id',
      );
      debugPrint('[CountryMan] ✅ Removed from Supabase');
    } catch (e) {
      debugPrint('[CountryMan] ⚠️ Failed to remove from Supabase: $e');
    }
  }

  /// Get saved countryman with Supabase as source of truth
  /// Returns country code (e.g., 'US', 'TR', 'GB') or null if not set
  Future<String?> getSavedCountryMan() async {
    try {
      final userId = _supabase.auth.currentUser?.id;

      // If user is logged in, try Supabase first (source of truth)
      if (userId != null) {
        try {
          final response = await _supabase
              .from('user_engine_settings')
              .select('selected_country_code')
              .eq('user_id', userId)
              .maybeSingle();

          if (response != null && response['selected_country_code'] != null) {
            final countryCode = response['selected_country_code'] as String;
            debugPrint('[CountryMan] ✅ Loaded from Supabase: $countryCode');

            // Cache to SharedPreferences for offline access
            await _saveLocalCountry(userId, countryCode);

            return countryCode;
          }
        } catch (e) {
          debugPrint('[CountryMan] ⚠️ Failed to load from Supabase: $e');
          // Fall through to SharedPreferences
        }
      }

      // Fallback to SharedPreferences (offline mode or not logged in)
      final cachedCode = await _getLocalCountry(userId);
      if (cachedCode != null && cachedCode.isNotEmpty) {
        debugPrint('[CountryMan] ✅ Loaded from SharedPreferences: $cachedCode');
        // If logged in but Supabase was missing, push the cached value upstream for this user only.
        if (userId != null) {
          unawaited(_saveToSupabase(userId, cachedCode));
        }
        return cachedCode;
      }

      // Legacy: try old country name key (for backward compatibility)
      final legacyName = await ref
          .read(sharedPreferencesRepository)
          .getString(_baseCountryNameKey);
      if (legacyName != null && legacyName.isNotEmpty) {
        debugPrint('[CountryMan] ℹ️ Found legacy country name: $legacyName');
        // Return 'LEGACY:' prefix so provider knows to convert name to code
        return 'LEGACY:$legacyName';
      }

      debugPrint('[CountryMan] ℹ️ No saved countryman found');
      return null;
    } catch (e, st) {
      debugPrint('[CountryMan] ❌ Error loading countryman: $e');
      debugPrint('[CountryMan] Stack: $st');
      return null;
    }
  }

  /// Sync any locally cached selection up to Supabase (for users who picked country while unauthenticated).
  Future<void> syncLocalSelectionToSupabase() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final cachedCode = await _getLocalCountry(userId);
    if (cachedCode == null || cachedCode.isEmpty) return;

    try {
      await _saveToSupabase(userId, cachedCode);
      debugPrint('[CountryMan] ✅ Synced local selection to Supabase: $cachedCode');
    } catch (e) {
      debugPrint('[CountryMan] ⚠️ Failed to sync cached country to Supabase: $e');
    }
  }

  Future<void> _saveLocalCountry(String? userId, String countryCode) async {
    // Save under user-specific key to avoid cross-account leakage.
    await ref
        .read(sharedPreferencesRepository)
        .setString(_buildCountryCodeKey(userId), countryCode);
    // Keep legacy key for backward compatibility when no user is logged in.
    if (userId == null) {
      await ref
          .read(sharedPreferencesRepository)
          .setString(_baseCountryCodeKey, countryCode);
    }
    debugPrint('[CountryMan] ✅ Saved locally for ${userId ?? "guest"}: $countryCode');
  }

  Future<String?> _getLocalCountry(String? userId) async {
    final userSpecific =
        await ref.read(sharedPreferencesRepository).getString(_buildCountryCodeKey(userId));
    if (userSpecific != null && userSpecific.isNotEmpty) return userSpecific;
    // Fallback to legacy key (no user scoping).
    return ref.read(sharedPreferencesRepository).getString(_baseCountryCodeKey);
  }

  Future<void> _removeLocalCountry(String? userId) async {
    await ref.read(sharedPreferencesRepository).removeData(_buildCountryCodeKey(userId));
    await ref.read(sharedPreferencesRepository).removeData(_baseCountryCodeKey);
    await ref.read(sharedPreferencesRepository).removeData(_baseCountryNameKey);
  }
}
