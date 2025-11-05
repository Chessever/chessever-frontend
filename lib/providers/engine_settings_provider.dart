import 'dart:convert';
import 'package:chessever2/repository/engine_settings/models/engine_settings_model.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Enum to identify which engine component is making the analysis request
enum EngineComponent {
  evaluationGauge,
  principalVariation,
  moveImpact,
  cascadeEval,
}

/// Track the progress of an engine search
class EngineSearchProgress {
  static const int minReportDepth = 12;

  EngineSearchProgress({
    required int depth,
    required this.kiloNodes,
    this.fenFragment = '',
    DateTime? timestamp,
  }) : depth = depth < minReportDepth ? minReportDepth : depth,
       timestamp = timestamp ?? DateTime.now();

  final int depth;
  final int kiloNodes;
  final String fenFragment;
  final DateTime timestamp;

  EngineSearchProgress copyWith({
    int? depth,
    int? kiloNodes,
    String? fenFragment,
    DateTime? timestamp,
  }) {
    return EngineSearchProgress(
      depth: depth ?? this.depth,
      kiloNodes: kiloNodes ?? this.kiloNodes,
      fenFragment: fenFragment ?? this.fenFragment,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

String _componentLabel(EngineComponent component) {
  switch (component) {
    case EngineComponent.evaluationGauge:
      return 'EvaluationGauge';
    case EngineComponent.principalVariation:
      return 'PrincipalVariation';
    case EngineComponent.moveImpact:
      return 'MoveImpact';
    case EngineComponent.cascadeEval:
      return 'CascadeEval';
  }
}

/// Provider to track engine depth for each component
class EngineDepthTrackerNotifier
    extends StateNotifier<Map<EngineComponent, EngineSearchProgress>> {
  EngineDepthTrackerNotifier() : super(const {});

  void update({
    required EngineComponent component,
    required EngineSearchProgress progress,
    String? context,
  }) {
    final label = _componentLabel(component);
    final fragment = progress.fenFragment;
    final fragmentLength = fragment.length < 20 ? fragment.length : 20;
    final fragmentPreview = fragment.substring(0, fragmentLength);
    final fragmentSuffix = fragment.length > fragmentLength ? '...' : '';
    final fenInfo =
        fragment.isEmpty ? '' : ' ($fragmentPreview$fragmentSuffix)';
    final ctx = (context == null || context.isEmpty) ? '' : ' [$context]';
    debugPrint(
      '🧠 DepthTracker: $label depth=${progress.depth} knodes=${progress.kiloNodes}$fenInfo$ctx',
    );
    state = {...state, component: progress};
  }

  void clear(EngineComponent component, {String? reason}) {
    if (!state.containsKey(component)) return;
    final label = _componentLabel(component);
    final ctx = (reason == null || reason.isEmpty) ? '' : ' ($reason)';
    debugPrint('🧠 DepthTracker: cleared $label$ctx');
    state = Map.from(state)..remove(component);
  }

  void clearAll({String? reason}) {
    if (state.isEmpty) return;
    final ctx = (reason == null || reason.isEmpty) ? '' : ' ($reason)';
    debugPrint('🧠 DepthTracker: cleared all$ctx');
    state = const {};
  }
}

final engineDepthTrackerProvider = StateNotifierProvider<
  EngineDepthTrackerNotifier,
  Map<EngineComponent, EngineSearchProgress>
>((ref) => EngineDepthTrackerNotifier());

/// Represents the most relevant engine depth snapshot at a moment in time.
class EngineDepthSnapshot {
  final EngineComponent component;
  final EngineSearchProgress progress;

  const EngineDepthSnapshot({required this.component, required this.progress});
}

/// Priority order for selecting the most relevant engine component.
const List<EngineComponent> _engineDepthPriority = <EngineComponent>[
  EngineComponent.evaluationGauge,
  EngineComponent.principalVariation,
  EngineComponent.cascadeEval,
  EngineComponent.moveImpact,
];

/// Central provider exposing the latest engine depth snapshot regardless of source.
final engineDepthStatusProvider = Provider<EngineDepthSnapshot?>((ref) {
  final depthMap = ref.watch(engineDepthTrackerProvider);
  if (depthMap.isEmpty) {
    return null;
  }

  for (final component in _engineDepthPriority) {
    final progress = depthMap[component];
    if (progress != null) {
      return EngineDepthSnapshot(component: component, progress: progress);
    }
  }

  // Fallback: return the most recent entry by timestamp when priority components are absent
  EngineComponent? latestComponent;
  EngineSearchProgress? latestProgress;
  for (final entry in depthMap.entries) {
    if (latestProgress == null ||
        entry.value.timestamp.isAfter(latestProgress.timestamp)) {
      latestComponent = entry.key;
      latestProgress = entry.value;
    }
  }

  if (latestComponent == null || latestProgress == null) {
    return null;
  }

  return EngineDepthSnapshot(
    component: latestComponent,
    progress: latestProgress,
  );
});

/// Engine settings configuration class
class EngineSettings {
  const EngineSettings({
    this.showEngineGauge = true,
    this.showDepthOverlay = true,
    this.showPvArrows = true,
    this.searchTimeIndex = 2,
    int principalVariationIndex = 2, // Default to 3 lines (index 2)
  }) : principalVariationIndex = principalVariationIndex < 0 
           ? 0 
           : (principalVariationIndex > 4 // Max index is 4 (we have 5 labels: 0-4)
               ? 4 
               : principalVariationIndex);

  final bool showEngineGauge;
  final bool showDepthOverlay;
  final bool showPvArrows;
  final int searchTimeIndex;
  final int principalVariationIndex;

  // Principal variation options: 1, 2, 3, 4, 5 (max 5)
  static const List<int?> _principalVariationOptions = <int?>[
    1,
    2,
    3,
    4,
    5,
  ];

  static const List<String> principalVariationLabels = <String>[
    '1',
    '2',
    '3',
    '4',
    '5',
  ];

  static const List<int?> _searchTimeSecondsOptions = <int?>[
    5,
    10,
    20,
    30,
    60,
    null, // null represents "unlimited" (infinite search)
  ];

  static const List<String> searchTimeLabels = <String>[
    '5s',
    '10s',
    '20s',
    '30s',
    '60s',
    '∞',
  ];

  /// Get the multiPV count for Lichess API requests
  /// Lichess only supports up to 5 variations, max is 5
  int multiPvForLichess() {
    final safeIndex = principalVariationIndex.clamp(
      0,
      _principalVariationOptions.length - 1,
    );
    final value = _principalVariationOptions[safeIndex];
    // Cap at 5 for Lichess (their API maximum)
    return (value ?? 5).clamp(1, 5);
  }

  /// Get the multiPV count for Stockfish evaluation
  /// Returns requested count (1-5)
  int multiPvForStockfish() {
    final safeIndex = principalVariationIndex.clamp(
      0,
      _principalVariationOptions.length - 1,
    );
    final value = _principalVariationOptions[safeIndex];
    // Max is 5 since we removed the "All" option
    return (value ?? 5).clamp(1, 5);
  }

  /// Check if user selected "All" variations (always false now, kept for compatibility)
  bool isShowingAllPvs() {
    return false; // "All" option removed, max is 5
  }

  /// Get display label for current PV setting
  String principalVariationLabel() {
    final safeIndex = principalVariationIndex.clamp(
      0,
      principalVariationLabels.length - 1,
    );
    return principalVariationLabels[safeIndex];
  }

  static const Map<EngineComponent, double> _componentTimeMultipliers = {
    EngineComponent.evaluationGauge: 1.0,
    EngineComponent.principalVariation: 1.0,
    EngineComponent.cascadeEval: 0.6,
    EngineComponent.moveImpact: 0.4,
  };

  static const Map<EngineComponent, int?> _componentUnlimitedCaps = {
    EngineComponent.evaluationGauge: null, // Allow true infinite search
    EngineComponent.principalVariation: null, // Allow true infinite search
    EngineComponent.cascadeEval: 45, // Cap at 45s for cascade
    EngineComponent.moveImpact: 30, // Cap at 30s for move impact
  };

  /// Maximum depth limits for each component
  static const Map<EngineComponent, int> _componentMaxDepth = {
    EngineComponent.evaluationGauge: 99, // Eval bar can go deep
    EngineComponent.principalVariation:
        50, // PV analysis capped at 50 (100 half-moves) - shows ~10-20 full moves
    EngineComponent.cascadeEval: 99, // Fallback eval can go deep
    EngineComponent.moveImpact: 20, // Move impact doesn't need deep analysis
  };

  int maxDepthFor(EngineComponent component) {
    return _componentMaxDepth[component] ?? 99;
  }

  EngineSettings copyWith({
    bool? showEngineGauge,
    bool? showDepthOverlay,
    bool? showPvArrows,
    int? searchTimeIndex,
    int? principalVariationIndex,
  }) {
    return EngineSettings(
      showEngineGauge: showEngineGauge ?? this.showEngineGauge,
      showDepthOverlay: showDepthOverlay ?? this.showDepthOverlay,
      showPvArrows: showPvArrows ?? this.showPvArrows,
      searchTimeIndex: searchTimeIndex ?? this.searchTimeIndex,
      principalVariationIndex: (principalVariationIndex ??
              this.principalVariationIndex)
          .clamp(0, principalVariationLabels.length - 1),
    );
  }

  int? baseSearchTimeSeconds() {
    final safeIndex = searchTimeIndex.clamp(
      0,
      _searchTimeSecondsOptions.length - 1,
    );
    return _searchTimeSecondsOptions[safeIndex];
  }

  Duration? searchDurationFor(EngineComponent component) {
    final baseSeconds = baseSearchTimeSeconds();
    final multiplier = _componentTimeMultipliers[component] ?? 1.0;

    if (baseSeconds == null) {
      // Infinite search selected
      final cappedSeconds = _componentUnlimitedCaps[component];
      if (cappedSeconds == null) {
        return null; // True infinite search
      }
      final cappedDuration = Duration(seconds: cappedSeconds);
      return cappedDuration;
    }

    // Apply multiplier and clamp to reasonable range
    final scaledMs = (baseSeconds * 1000 * multiplier).round().clamp(
      2000,
      180000,
    );
    return Duration(milliseconds: scaledMs);
  }

  String searchTimeLabel() {
    final safeIndex = searchTimeIndex.clamp(0, searchTimeLabels.length - 1);
    return searchTimeLabels[safeIndex];
  }
}

/// Provider for managing engine settings with Supabase + SharedPreferences sync
final engineSettingsProviderNew =
    AsyncNotifierProvider<EngineSettingsNotifierNew, EngineSettings>(
      EngineSettingsNotifierNew.new,
    );

class EngineSettingsNotifierNew extends AsyncNotifier<EngineSettings> {
  static const String _cacheKey = 'cached_engine_settings';

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  Future<EngineSettings> build() async {
    return await _loadSettings();
  }

  Future<EngineSettings> _loadSettings() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[EngineSettings] No user logged in, returning defaults');
        return const EngineSettings();
      }

      // Fetch from Supabase (source of truth)
      final response =
          await _supabase
              .from('user_engine_settings')
              .select()
              .eq('user_id', userId)
              .maybeSingle();

      if (response == null) {
        debugPrint(
          '[EngineSettings] No settings found in Supabase, creating defaults',
        );
        // Save defaults to Supabase (upsert handles race conditions)
        try {
          await _saveToSupabase(const EngineSettings(), userId);
        } catch (e) {
          // Ignore duplicate errors - another process may have created it
          debugPrint(
            '[EngineSettings] Info: ${e.toString().contains('duplicate') ? 'Settings already exist' : 'Error creating defaults: $e'}',
          );
        }
        return const EngineSettings();
      }

      final model = EngineSettingsModel.fromSupabase(response);
      final settings = EngineSettings(
        showEngineGauge: model.showEngineGauge,
        showDepthOverlay: model.showDepthOverlay,
        showPvArrows: model.showPvArrows,
        searchTimeIndex: model.searchTimeIndex,
        principalVariationIndex: model.principalVariationIndex,
      );

      // Cache locally
      await _cacheSettings(settings);

      debugPrint('[EngineSettings] Fetched settings from Supabase');
      return settings;
    } catch (e, st) {
      debugPrint('[EngineSettings] Error fetching from Supabase: $e');
      debugPrint('[EngineSettings] Stack: $st');

      // Fallback to local cache
      return await _getCachedSettings();
    }
  }

  /// Toggle engine gauge visibility
  Future<void> toggleEngineGauge(bool value) async {
    final currentState = state.valueOrNull ?? const EngineSettings();
    final newSettings = currentState.copyWith(showEngineGauge: value);
    state = AsyncValue.data(newSettings);
    await _persist(newSettings);
  }

  /// Toggle depth overlay visibility
  Future<void> toggleDepthOverlay(bool value) async {
    final currentState = state.valueOrNull ?? const EngineSettings();
    final newSettings = currentState.copyWith(showDepthOverlay: value);
    state = AsyncValue.data(newSettings);
    await _persist(newSettings);
  }

  /// Toggle PV arrows visibility
  Future<void> togglePvArrows(bool value) async {
    final currentState = state.valueOrNull ?? const EngineSettings();
    final newSettings = currentState.copyWith(showPvArrows: value);
    state = AsyncValue.data(newSettings);
    await _persist(newSettings);
  }

  /// Set search time index
  Future<void> setSearchTimeIndex(int index) async {
    final clamped = index.clamp(0, EngineSettings.searchTimeLabels.length - 1);
    final currentState = state.valueOrNull ?? const EngineSettings();
    final newSettings = currentState.copyWith(searchTimeIndex: clamped);
    debugPrint(
      '🔧 EngineSettings: Search time changed to ${newSettings.searchTimeLabel()}',
    );
    state = AsyncValue.data(newSettings);
    await _persist(newSettings);

    // Clear depth tracker when settings change to force fresh evaluation
    ref
        .read(engineDepthTrackerProvider.notifier)
        .clearAll(reason: 'settings changed');
  }

  /// Set principal variation index
  Future<void> setPrincipalVariationIndex(int index) async {
    final clamped = index.clamp(
      0,
      EngineSettings.principalVariationLabels.length - 1,
    );
    final currentState = state.valueOrNull ?? const EngineSettings();
    final newSettings = currentState.copyWith(principalVariationIndex: clamped);
    final label = newSettings.principalVariationLabel();
    debugPrint('🔧 EngineSettings: PV setting changed to $label');
    state = AsyncValue.data(newSettings);
    await _persist(newSettings);

    // Clear depth tracker when settings change to force fresh evaluation
    ref
        .read(engineDepthTrackerProvider.notifier)
        .clearAll(reason: 'PV setting changed');
  }

  /// Refresh settings from Supabase
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadSettings());
  }

  /// Sync settings from Supabase to local cache
  Future<void> syncFromSupabase() async {
    debugPrint('[EngineSettings] Starting sync...');
    try {
      await refresh();
      debugPrint('[EngineSettings] Sync complete');
    } catch (e, st) {
      debugPrint('[EngineSettings] Error syncing: $e');
      debugPrint('[EngineSettings] Stack: $st');
    }
  }

  // Private methods

  Future<void> _persist(EngineSettings settings) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('[EngineSettings] No user logged in, skipping persist');
        return;
      }

      // Save to Supabase
      await _saveToSupabase(settings, userId);

      // Cache locally
      await _cacheSettings(settings);
    } catch (e, st) {
      debugPrint('[EngineSettings] Error persisting settings: $e');
      debugPrint('[EngineSettings] Stack: $st');
      rethrow;
    }
  }

  Future<void> _saveToSupabase(EngineSettings settings, String userId) async {
    try {
      // Use upsert with onConflict to handle existing records
      await _supabase.from('user_engine_settings').upsert(
        {
          'user_id': userId,
          'show_engine_gauge': settings.showEngineGauge,
          'show_depth_overlay': settings.showDepthOverlay,
          'show_pv_arrows': settings.showPvArrows,
          'search_time_index': settings.searchTimeIndex,
          'principal_variation_index': settings.principalVariationIndex,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id', // Specify conflict column
      );
      debugPrint('[EngineSettings] ✅ Saved to Supabase');
    } catch (e) {
      debugPrint('[EngineSettings] ❌ Error saving to Supabase: $e');
      rethrow;
    }
  }

  Future<void> _cacheSettings(EngineSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode({
        'showEngineGauge': settings.showEngineGauge,
        'showDepthOverlay': settings.showDepthOverlay,
        'showPvArrows': settings.showPvArrows,
        'searchTimeIndex': settings.searchTimeIndex,
        'principalVariationIndex': settings.principalVariationIndex,
      });
      await prefs.setString(_cacheKey, json);
      debugPrint('[EngineSettings] Cached settings locally');
    } catch (e) {
      debugPrint('[EngineSettings] Error caching settings: $e');
    }
  }

  Future<EngineSettings> _getCachedSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_cacheKey);
      if (json == null) {
        debugPrint('[EngineSettings] No cached settings, using defaults');
        return const EngineSettings();
      }

      final map = jsonDecode(json) as Map<String, dynamic>;
      final settings = EngineSettings(
        showEngineGauge: map['showEngineGauge'] as bool? ?? true,
        showDepthOverlay: map['showDepthOverlay'] as bool? ?? true,
        showPvArrows: map['showPvArrows'] as bool? ?? true,
        searchTimeIndex: map['searchTimeIndex'] as int? ?? 2,
        principalVariationIndex: map['principalVariationIndex'] as int? ?? 2,
      );
      debugPrint('[EngineSettings] Loaded settings from cache');
      return settings;
    } catch (e) {
      debugPrint('[EngineSettings] Error getting cached settings: $e');
      return const EngineSettings();
    }
  }

  /// Clear cache (useful on sign out)
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      debugPrint('[EngineSettings] Cleared cache');
    } catch (e) {
      debugPrint('[EngineSettings] Error clearing cache: $e');
    }
  }
}
