import 'dart:async';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final countryManRepository = Provider((ref) => _CountryManRepository(ref));

class _CountryManRepository {
  _CountryManRepository(this.ref);

  final Ref ref;

  static const _countryCodeCacheKey = 'selected_country_code';

  SupabaseClient get _supabase => Supabase.instance.client;

  /// Save countryman selection with Supabase + SQLite dual persistence
  /// @param countryCode - The 2-letter country code (e.g., 'US', 'TR', 'GB')
  Future<void> saveCountryMan(String countryCode) async {
    try {
      final userId = _supabase.auth.currentUser?.id;

      // Always save to SQLite first (immediate, works offline)
      await _saveLocalCountry(userId, countryCode);

      // If user is logged in, persist to Supabase (fire-and-forget, non-blocking)
      if (userId != null) {
        unawaited(_saveToSupabase(userId, countryCode));
      } else {
        debugPrint('[CountryMan] No user logged in, skipping Supabase sync');
      }
    } catch (e, st) {
      debugPrint('[CountryMan] Error saving countryman: $e');
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
      debugPrint('[CountryMan] Saved to Supabase: $countryCode');
    } catch (e) {
      debugPrint('[CountryMan] Failed to save to Supabase: $e');
    }
  }

  Future<void> removeCountrySelection() async {
    // Remove from SQLite first (immediate)
    final userId = _supabase.auth.currentUser?.id;
    await _removeLocalCountry(userId);
    debugPrint('[CountryMan] Removed from local storage');

    // Remove from Supabase (fire-and-forget, non-blocking)
    if (userId != null) {
      unawaited(_removeFromSupabase(userId));
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
      debugPrint('[CountryMan] Removed from Supabase');
    } catch (e) {
      debugPrint('[CountryMan] Failed to remove from Supabase: $e');
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
            debugPrint('[CountryMan] Loaded from Supabase: $countryCode');

            // Cache to SQLite for offline access
            await _saveLocalCountry(userId, countryCode);

            return countryCode;
          }
        } catch (e) {
          debugPrint('[CountryMan] Failed to load from Supabase: $e');
          // Fall through to SQLite
        }
      }

      // Fallback to SQLite (offline mode or not logged in)
      final cachedCode = await _getLocalCountry(userId);
      if (cachedCode != null && cachedCode.isNotEmpty) {
        debugPrint('[CountryMan] Loaded from SQLite: $cachedCode');
        // If logged in but Supabase was missing, push the cached value upstream
        if (userId != null) {
          unawaited(_saveToSupabase(userId, cachedCode));
        }
        return cachedCode;
      }

      debugPrint('[CountryMan] No saved countryman found');
      return null;
    } catch (e, st) {
      debugPrint('[CountryMan] Error loading countryman: $e');
      debugPrint('[CountryMan] Stack: $st');
      return null;
    }
  }

  /// Sync any locally cached selection up to Supabase
  Future<void> syncLocalSelectionToSupabase() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final cachedCode = await _getLocalCountry(userId);
    if (cachedCode == null || cachedCode.isEmpty) return;

    try {
      await _saveToSupabase(userId, cachedCode);
      debugPrint('[CountryMan] Synced local selection to Supabase: $cachedCode');
    } catch (e) {
      debugPrint('[CountryMan] Failed to sync cached country to Supabase: $e');
    }
  }

  Future<void> _saveLocalCountry(String? userId, String countryCode) async {
    try {
      final db = ref.read(appDatabaseProvider);
      await db.setCache(
        key: _countryCodeCacheKey,
        value: countryCode,
        userId: userId,
      );
      debugPrint('[CountryMan] Saved locally for ${userId ?? "guest"}: $countryCode');
    } catch (e) {
      // Local storage failure is not critical
    }
  }

  Future<String?> _getLocalCountry(String? userId) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final entry = await db.getCache(key: _countryCodeCacheKey, userId: userId);
      if (entry != null) return entry.value;

      // Fallback to guest cache
      if (userId != null) {
        final guestEntry = await db.getCache(key: _countryCodeCacheKey);
        return guestEntry?.value;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _removeLocalCountry(String? userId) async {
    try {
      final db = ref.read(appDatabaseProvider);
      await db.removeCache(key: _countryCodeCacheKey, userId: userId);
      await db.removeCache(key: _countryCodeCacheKey); // guest fallback
    } catch (e) {
      // Local storage failure is not critical
    }
  }

  /// Clear only local cache (SQLite) without touching Supabase.
  /// Use this on logout so user's preference persists in Supabase for next login.
  Future<void> clearLocalCacheOnly() async {
    final userId = _supabase.auth.currentUser?.id;
    await _removeLocalCountry(userId);
    debugPrint('[CountryMan] Cleared local cache only (Supabase untouched)');
  }
}
