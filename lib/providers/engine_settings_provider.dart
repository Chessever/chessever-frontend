import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EngineSettings {
  final bool preferLocal; // prefer local Stockfish over cloud
  final int multiPv; // number of PV lines
  final int threads; // Stockfish Threads
  final int hashMb; // Hash size in MB
  final int? maxDepth; // Optional max depth cap
  final int timeoutMs; // Movetime for dynamic deepening
  // UI flags (from engine_configs_final branch)
  final bool showEngineGauge; // show side evaluation gauge
  final bool showDepthOverlay; // show depth overlay on board
  final bool showPvArrows; // show PV arrows on board
  final int searchTimeIndex; // discrete time index (5s..∞)
  final int principalVariationCount; // 1..5

  const EngineSettings({
    this.preferLocal = false,
    this.multiPv = 3,
    this.threads = 1,
    this.hashMb = 64,
    this.maxDepth, // null means no cap
    this.timeoutMs = 6000,
    this.showEngineGauge = true,
    this.showDepthOverlay = true,
    this.showPvArrows = true,
    this.searchTimeIndex = 2,
    this.principalVariationCount = 3,
  });

  EngineSettings copyWith({
    bool? preferLocal,
    int? multiPv,
    int? threads,
    int? hashMb,
    int? maxDepth,
    int? timeoutMs,
    bool? showEngineGauge,
    bool? showDepthOverlay,
    bool? showPvArrows,
    int? searchTimeIndex,
    int? principalVariationCount,
  }) {
    return EngineSettings(
      preferLocal: preferLocal ?? this.preferLocal,
      multiPv: multiPv ?? this.multiPv,
      threads: threads ?? this.threads,
      hashMb: hashMb ?? this.hashMb,
      maxDepth: maxDepth ?? this.maxDepth,
      timeoutMs: timeoutMs ?? this.timeoutMs,
      showEngineGauge: showEngineGauge ?? this.showEngineGauge,
      showDepthOverlay: showDepthOverlay ?? this.showDepthOverlay,
      showPvArrows: showPvArrows ?? this.showPvArrows,
      searchTimeIndex: searchTimeIndex ?? this.searchTimeIndex,
      principalVariationCount:
          principalVariationCount ?? this.principalVariationCount,
    );
  }

  Map<String, dynamic> toMap() => {
        'preferLocal': preferLocal,
        'multiPv': multiPv,
        'threads': threads,
        'hashMb': hashMb,
        'maxDepth': maxDepth,
        'timeoutMs': timeoutMs,
        'showEngineGauge': showEngineGauge,
        'showDepthOverlay': showDepthOverlay,
        'showPvArrows': showPvArrows,
        'searchTimeIndex': searchTimeIndex,
        'principalVariationCount': principalVariationCount,
      };

  static EngineSettings fromMap(Map<String, dynamic> map) {
    return EngineSettings(
      preferLocal: (map['preferLocal'] as bool?) ?? false,
      multiPv: (map['multiPv'] as int?) ?? 3,
      threads: (map['threads'] as int?) ?? 1,
      hashMb: (map['hashMb'] as int?) ?? 64,
      maxDepth: map['maxDepth'] as int?,
      timeoutMs: (map['timeoutMs'] as int?) ?? 6000,
      showEngineGauge: (map['showEngineGauge'] as bool?) ?? true,
      showDepthOverlay: (map['showDepthOverlay'] as bool?) ?? true,
      showPvArrows: (map['showPvArrows'] as bool?) ?? true,
      searchTimeIndex: (map['searchTimeIndex'] as int?) ?? 2,
      principalVariationCount: (map['principalVariationCount'] as int?) ?? 3,
    );
  }
}

final engineSettingsProvider =
    AsyncNotifierProvider<EngineSettingsNotifier, EngineSettings>(
  EngineSettingsNotifier.new,
);

class EngineSettingsNotifier extends AsyncNotifier<EngineSettings> {
  static const _prefsKey = 'engine_settings_v1';

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  Future<EngineSettings> build() async {
    return await _load();
  }

  Future<EngineSettings> _load() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      // Load from Supabase first if user is logged in
      if (userId != null) {
        final rows = await _supabase
            .from('user_engine_settings')
            .select()
            .eq('user_id', userId)
            .limit(1);
        if (rows is List && rows.isNotEmpty) {
          final row = rows.first as Map<String, dynamic>;
          final settings = EngineSettings(
            preferLocal: (row['prefer_local'] as bool?) ?? false,
            multiPv: (row['multi_pv'] as int?) ?? 3,
            threads: (row['threads'] as int?) ?? 1,
            hashMb: (row['hash_mb'] as int?) ?? 64,
            maxDepth: row['max_depth'] as int?,
            timeoutMs: (row['timeout_ms'] as int?) ?? 6000,
            showEngineGauge: (row['show_engine_gauge'] as bool?) ?? true,
            showDepthOverlay: (row['show_depth_overlay'] as bool?) ?? true,
            showPvArrows: (row['show_pv_arrows'] as bool?) ?? true,
            searchTimeIndex: (row['search_time_index'] as int?) ?? 2,
            principalVariationCount:
                (row['principal_variation_count'] as int?) ?? 3,
          );
          // cache locally
          await _cache(settings);
          return settings;
        }
      }
      // fallback to local cache
      final cached = await _getCached();
      return cached ?? const EngineSettings();
    } catch (e, st) {
      debugPrint('[EngineSettings] Load failed: $e\n$st');
      return (await _getCached()) ?? const EngineSettings();
    }
  }

  Future<void> update(EngineSettings newSettings) async {
    state = AsyncValue.data(newSettings);
    await _cache(newSettings);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) {
        await _supabase.from('user_engine_settings').upsert({
          'user_id': userId,
          'prefer_local': newSettings.preferLocal,
          'multi_pv': newSettings.multiPv,
          'threads': newSettings.threads,
          'hash_mb': newSettings.hashMb,
          'max_depth': newSettings.maxDepth,
          'timeout_ms': newSettings.timeoutMs,
          'show_engine_gauge': newSettings.showEngineGauge,
          'show_depth_overlay': newSettings.showDepthOverlay,
          'show_pv_arrows': newSettings.showPvArrows,
          'search_time_index': newSettings.searchTimeIndex,
          'principal_variation_count': newSettings.principalVariationCount,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e, st) {
      debugPrint('[EngineSettings] Upsert failed: $e\n$st');
      // Keep local state; Supabase will sync later
    }
  }

  Future<void> _cache(EngineSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(settings.toMap()));
    } catch (e) {
      debugPrint('[EngineSettings] Cache failed: $e');
    }
  }

  Future<EngineSettings?> _getCached() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefsKey);
      if (json == null) return null;
      return EngineSettings.fromMap(jsonDecode(json) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[EngineSettings] Read cache failed: $e');
      return null;
    }
  }
}
