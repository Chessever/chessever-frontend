import 'dart:async';
import 'package:chessever2/config/app_environment.dart';
import 'package:chessever2/repository/engine_settings/engine_settings_store.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
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
  // Stockfish depth overlay should never appear lower than D:08, even when the
  // engine is just starting a fresh search on a new position.
  static const int minReportDepth = 8;

  EngineSearchProgress({
    required this.depth,
    required this.kiloNodes,
    this.fenFragment = '',
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

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
    bool allowDecrease = true,
  }) {
    final existing = state[component];
    if (!allowDecrease &&
        existing != null &&
        progress.depth <= existing.depth) {
      state = {
        ...state,
        component: existing.copyWith(timestamp: progress.timestamp),
      };
      return;
    }
    // final label = _componentLabel(component);
    // final fragment = progress.fenFragment;
    // final fragmentLength = fragment.length < 20 ? fragment.length : 20;
    // final fragmentPreview = fragment.substring(0, fragmentLength);
    // final fragmentSuffix = fragment.length > fragmentLength ? '...' : '';
    // final fenInfo =
    //     fragment.isEmpty ? '' : ' ($fragmentPreview$fragmentSuffix)';
    // final ctx = (context == null || context.isEmpty) ? '' : ' [$context]';
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

/// How engine principal-variation lines are laid out everywhere in the app
/// (board screen + Library opening explorer). Index order MUST match the
/// `engine_lines_view_index` column: 0 = cards, 1 = list.
enum EngineLinesView {
  /// ChessEver style — horizontally swipeable PV cards.
  cards,

  /// Traditional style — vertical, one line per row (default).
  list,
}

/// Map a persisted integer index to [EngineLinesView], defaulting to list.
EngineLinesView engineLinesViewFromIndex(int? index) {
  if (index == null || index < 0 || index >= EngineLinesView.values.length) {
    return EngineLinesView.list;
  }
  return EngineLinesView.values[index];
}

/// Engine settings configuration class
class EngineSettings {
  const EngineSettings({
    this.showEngineGauge = true,
    this.showEngineGaugeOnBoard = true,
    this.showEngineGaugeInGrid = true,
    this.showDepthOverlay = true,
    this.showPvArrows = true,
    this.showEngineAnalysis = true,
    this.searchTimeIndex = 0,
    this.engineLinesView = EngineLinesView.list,
    int principalVariationIndex = 4, // Default to 5 lines (index 4)
    int maxArrowsOnBoard = 2, // Default to 3 arrows (index 2)
  }) : principalVariationIndex =
           principalVariationIndex < 0
               ? 0
               : (principalVariationIndex >
                       4 // Max index is 4 (we have 5 labels: 0-4)
                   ? 4
                   : principalVariationIndex),
       maxArrowsOnBoard =
           maxArrowsOnBoard < 0
               ? 0
               : (maxArrowsOnBoard > 4 ? 4 : maxArrowsOnBoard);

  final bool showEngineGauge;
  final bool showEngineGaugeOnBoard;
  final bool showEngineGaugeInGrid;

  bool get shouldShowEngineGaugeOnBoard =>
      showEngineGauge && showEngineGaugeOnBoard;

  bool get shouldShowEngineGaugeInGrid =>
      showEngineGauge && showEngineGaugeInGrid;

  final bool showDepthOverlay;
  final bool showPvArrows;
  final bool
  showEngineAnalysis; // Controls visibility of PV cards & arrows (computer icon)
  final int searchTimeIndex;
  final int principalVariationIndex;
  final int
  maxArrowsOnBoard; // Index for max arrows on board (0-4 = 1-5 arrows)
  final EngineLinesView
  engineLinesView; // Layout for engine PV lines (cards vs list)

  // Principal variation options: 1, 2, 3, 4, 5 (max 5)
  static const List<int?> _principalVariationOptions = <int?>[1, 2, 3, 4, 5];

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

  // Max arrows on board options: 1, 2, 3, 4, 5
  static const List<int> _maxArrowsOptions = <int>[1, 2, 3, 4, 5];

  static const List<String> maxArrowsLabels = <String>['1', '2', '3', '4', '5'];

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

  /// Get the max number of arrows to show on the board
  int getMaxArrowsOnBoard() {
    final safeIndex = maxArrowsOnBoard.clamp(0, _maxArrowsOptions.length - 1);
    return _maxArrowsOptions[safeIndex];
  }

  /// Get display label for current max arrows setting
  String maxArrowsLabel() {
    final safeIndex = maxArrowsOnBoard.clamp(0, maxArrowsLabels.length - 1);
    return maxArrowsLabels[safeIndex];
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
    bool? showEngineGaugeOnBoard,
    bool? showEngineGaugeInGrid,
    bool? showDepthOverlay,
    bool? showPvArrows,
    bool? showEngineAnalysis,
    int? searchTimeIndex,
    EngineLinesView? engineLinesView,
    int? principalVariationIndex,
    int? maxArrowsOnBoard,
  }) {
    return EngineSettings(
      showEngineGauge: showEngineGauge ?? this.showEngineGauge,
      showEngineGaugeOnBoard:
          showEngineGaugeOnBoard ?? this.showEngineGaugeOnBoard,
      showEngineGaugeInGrid:
          showEngineGaugeInGrid ?? this.showEngineGaugeInGrid,
      showDepthOverlay: showDepthOverlay ?? this.showDepthOverlay,
      showPvArrows: showPvArrows ?? this.showPvArrows,
      showEngineAnalysis: showEngineAnalysis ?? this.showEngineAnalysis,
      searchTimeIndex: searchTimeIndex ?? this.searchTimeIndex,
      engineLinesView: engineLinesView ?? this.engineLinesView,
      principalVariationIndex: (principalVariationIndex ??
              this.principalVariationIndex)
          .clamp(0, principalVariationLabels.length - 1),
      maxArrowsOnBoard: (maxArrowsOnBoard ?? this.maxArrowsOnBoard).clamp(
        0,
        maxArrowsLabels.length - 1,
      ),
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

  /// Single source of truth for the main board analysis Stockfish job.
  ///
  /// Board eval, progressive MultiPV, and depth display must all use this
  /// profile so user engine-settings (search time, line count, depth caps)
  /// are applied exactly — never re-derived with ad-hoc caps on the call site.
  BoardEngineSearchProfile resolveBoardSearchProfile() {
    final multiPv = multiPvForStockfish();

    final gaugeDuration = searchDurationFor(EngineComponent.evaluationGauge);
    final pvDuration = searchDurationFor(EngineComponent.principalVariation);
    // Null duration on either component means the user chose ∞ (unlimited).
    final Duration? searchDuration;
    if (gaugeDuration == null || pvDuration == null) {
      searchDuration = null;
    } else {
      searchDuration =
          gaugeDuration >= pvDuration ? gaugeDuration : pvDuration;
    }

    final gaugeMax = maxDepthFor(EngineComponent.evaluationGauge);
    final pvMax = maxDepthFor(EngineComponent.principalVariation);
    // Board needs both eval bar and PV lines from one search: use the tighter
    // of the two component caps (PV is 50, gauge is 99 → 50).
    var maxDepth = gaugeMax <= pvMax ? gaugeMax : pvMax;
    if (maxDepth < 1) maxDepth = 1;
    if (maxDepth > 99) maxDepth = 99;

    return BoardEngineSearchProfile(
      multiPv: multiPv,
      searchDuration: searchDuration,
      maxDepth: maxDepth,
    );
  }
}

EngineSettings applyCachedEngineGaugeSurfaceSettings(
  EngineSettings settings,
  Map<String, dynamic> cache,
) {
  return settings.copyWith(
    showEngineGaugeOnBoard:
        cache['showEngineGaugeOnBoard'] as bool? ??
        settings.showEngineGaugeOnBoard,
    showEngineGaugeInGrid:
        cache['showEngineGaugeInGrid'] as bool? ??
        settings.showEngineGaugeInGrid,
  );
}

/// Resolved Stockfish parameters for on-board analysis (eval bar + engine lines).
///
/// Built only from [EngineSettings] so tests and the board provider share one
/// mapping: search-time index → movetime, PV index → MultiPV, component maps →
/// max depth. `searchDuration == null` means no wall-clock limit (∞); Stockfish
/// then searches to [maxDepth] only.
class BoardEngineSearchProfile {
  const BoardEngineSearchProfile({
    required this.multiPv,
    required this.searchDuration,
    required this.maxDepth,
  });

  /// Principal variations requested (1–5), from [EngineSettings.multiPvForStockfish].
  final int multiPv;

  /// Wall-clock search budget, or null when the user selected unlimited (∞).
  final Duration? searchDuration;

  /// Hard depth ceiling for this board job (from component max-depth maps).
  final int maxDepth;

  /// True when the user selected unlimited search time.
  bool get isUnlimitedSearch => searchDuration == null;
}

final engineSettingsCacheProvider = Provider<EngineSettingsCache>(
  (ref) => SqliteEngineSettingsCache(),
);

final engineSettingsBackendProvider = Provider<EngineSettingsBackend>(
  (ref) => SupabaseEngineSettingsBackend(Supabase.instance.client),
);

/// Observe SDK identity directly, including anonymous users and restoration.
/// Same-account token refreshes never reset a store's serial write lane.
final engineSettingsAccountProvider = Provider<String?>((ref) {
  final auth = Supabase.instance.client.auth;
  final userId = auth.currentUser?.id;
  final subscription = auth.onAuthStateChange.listen((event) {
    if (auth.currentUser?.id != userId) ref.invalidateSelf();
  }, onError: (Object _) {
    // A transient auth error must not turn a retained session into a guest.
  });
  ref.onDispose(() => unawaited(subscription.cancel()));
  return userId;
});

final engineSettingsEnvironmentProvider = Provider<String>(
  (ref) =>
      '${AppEnvironment.flavor.name}:${AppEnvironment.expectedSupabaseProjectRef}',
);

final engineSettingsStoreProvider =
    Provider.family<EngineSettingsStore, EngineSettingsScope>(
      (ref, scope) => EngineSettingsStore(
        scope: scope,
        cache: ref.watch(engineSettingsCacheProvider),
        backend: ref.watch(engineSettingsBackendProvider),
        importLegacySurfaces: scope.environment.startsWith('production:'),
      ),
    );

EngineSettings _settingsFromFields(Map<String, dynamic> fields) {
  final map = {...engineSettingsDefaults, ...validEngineSettingsFields(fields)};
  return EngineSettings(
    showEngineGauge: map['showEngineGauge'],
    showEngineGaugeOnBoard: map['showEngineGaugeOnBoard'],
    showEngineGaugeInGrid: map['showEngineGaugeInGrid'],
    showDepthOverlay: map['showDepthOverlay'],
    showPvArrows: map['showPvArrows'],
    showEngineAnalysis: map['showEngineAnalysis'],
    searchTimeIndex: map['searchTimeIndex'],
    engineLinesView: engineLinesViewFromIndex(map['engineLinesView']),
    principalVariationIndex: map['principalVariationIndex'],
    maxArrowsOnBoard: map['maxArrowsOnBoard'],
  );
}

/// Provider for account-scoped durable settings and pending-field cloud sync.
final engineSettingsProviderNew =
    AsyncNotifierProvider<EngineSettingsNotifierNew, EngineSettings>(
      EngineSettingsNotifierNew.new,
    );

class EngineSettingsNotifierNew extends AsyncNotifier<EngineSettings> {
  late EngineSettingsStore _store;
  int _generation = 0;
  int _changeEpoch = 0;
  bool _ready = false;

  @override
  Future<EngineSettings> build() async {
    final scope = (
      environment: ref.watch(engineSettingsEnvironmentProvider),
      userId: ref.watch(engineSettingsAccountProvider),
    );
    final store = ref.watch(engineSettingsStoreProvider(scope));
    _store = store;
    _ready = false;
    final generation = ++_generation;
    ref.onDispose(() {
      _ready = false;
      ++_generation;
    });
    final local = await store.loadLocal();
    if (generation == _generation) {
      _ready = true;
      // Publish SQLite immediately; a delayed/offline cloud must not block UI.
      unawaited(Future<void>(() => _syncStore(store, generation, _changeEpoch)));
    }
    return _settingsFromFields(local);
  }

  EngineSettings _currentSettings() {
    // AsyncValue retains previous data while an account rebuild is loading.
    if (!_ready ||
        _store.scope.userId != ref.read(engineSettingsAccountProvider) ||
        _store.scope.environment != ref.read(engineSettingsEnvironmentProvider)) {
      throw StateError('Engine settings are still restoring');
    }
    return state.requireValue;
  }

  Future<void> _syncStore(
    EngineSettingsStore store,
    int generation,
    int epoch,
  ) async {
    await store.sync();
    if (_ready && generation == _generation && epoch == _changeEpoch) {
      state = AsyncValue.data(_settingsFromFields(store.values));
    }
  }

  /// Toggle evaluation bar visibility across all surfaces without changing the
  /// saved per-surface choices.
  Future<void> toggleEngineGauge(bool value) async {
    final currentState = _currentSettings();
    final newSettings = currentState.copyWith(showEngineGauge: value);
    state = AsyncValue.data(newSettings);
    await _persist({'showEngineGauge': value});
  }

  /// Toggle evaluation bar visibility on opened boards.
  Future<void> toggleEngineGaugeOnBoard(bool value) async {
    final currentState = _currentSettings();
    final newSettings = currentState.copyWith(showEngineGaugeOnBoard: value);
    state = AsyncValue.data(newSettings);
    // Surface preferences are intentionally device-local. Sending the full
    // settings object to Supabase here would update unrelated synced fields
    // with a potentially stale snapshot.
    await _persist({'showEngineGaugeOnBoard': value}, sync: false);
  }

  /// Toggle evaluation bar visibility in game grids.
  Future<void> toggleEngineGaugeInGrid(bool value) async {
    final currentState = _currentSettings();
    final newSettings = currentState.copyWith(showEngineGaugeInGrid: value);
    state = AsyncValue.data(newSettings);
    // Keep this local for the same reason as the board-surface preference.
    await _persist({'showEngineGaugeInGrid': value}, sync: false);
  }

  /// Toggle depth overlay visibility
  Future<void> toggleDepthOverlay(bool value) async {
    final currentState = _currentSettings();
    final newSettings = currentState.copyWith(showDepthOverlay: value);
    state = AsyncValue.data(newSettings);
    await _persist({'showDepthOverlay': value});
  }

  /// Toggle PV arrows visibility
  Future<void> togglePvArrows(bool value) async {
    final currentState = _currentSettings();
    final newSettings = currentState.copyWith(showPvArrows: value);
    state = AsyncValue.data(newSettings);
    await _persist({'showPvArrows': value});
  }

  /// Toggle engine analysis visibility (PV cards & arrows from computer icon)
  /// When turned off, also stops the Stockfish engine to save resources
  Future<void> toggleEngineAnalysis(bool value) async {
    final generation = _generation;
    // Optimistic local update so UI reacts instantly
    final optimistic = _currentSettings().copyWith(
      showEngineAnalysis: value,
    );
    debugPrint('🎯 EngineSettings: Engine analysis visibility set to $value');
    state = AsyncValue.data(optimistic);

    // Queue only this field before stopping the engine. Never reload cloud:
    // that used to replace an unsynced thinking-time selection.
    await _persist({'showEngineAnalysis': value});

    // When turning off, stop the Stockfish engine to save resources
    if (!value &&
        _ready &&
        generation == _generation &&
        state.valueOrNull?.showEngineAnalysis == false) {
      debugPrint(
        '🛑 EngineSettings: Stopping Stockfish engine (analysis disabled)',
      );
      await StockfishSingleton().cancelAllEvaluations();
      // Clear depth tracker since engine is stopped
      if (_ready && generation == _generation) {
        ref
            .read(engineDepthTrackerProvider.notifier)
            .clearAll(reason: 'engine analysis disabled');
      }
    }
  }

  /// Set search time index
  Future<void> setSearchTimeIndex(int index) async {
    final generation = _generation;
    final clamped = index.clamp(0, EngineSettings.searchTimeLabels.length - 1);
    final currentState = _currentSettings();
    final newSettings = currentState.copyWith(searchTimeIndex: clamped);
    debugPrint(
      '🔧 EngineSettings: Search time changed to ${newSettings.searchTimeLabel()}',
    );
    state = AsyncValue.data(newSettings);
    await _persist({'searchTimeIndex': clamped});

    // Clear depth tracker when settings change to force fresh evaluation
    if (_ready && generation == _generation) {
      ref
          .read(engineDepthTrackerProvider.notifier)
          .clearAll(reason: 'settings changed');
    }
  }

  /// Set principal variation index
  Future<void> setPrincipalVariationIndex(int index) async {
    final generation = _generation;
    final clamped = index.clamp(
      0,
      EngineSettings.principalVariationLabels.length - 1,
    );
    final currentState = _currentSettings();
    final newSettings = currentState.copyWith(principalVariationIndex: clamped);
    final label = newSettings.principalVariationLabel();
    debugPrint('🔧 EngineSettings: PV setting changed to $label');
    state = AsyncValue.data(newSettings);
    await _persist({'principalVariationIndex': clamped});

    // Clear depth tracker when settings change to force fresh evaluation
    if (_ready && generation == _generation) {
      ref
          .read(engineDepthTrackerProvider.notifier)
          .clearAll(reason: 'PV setting changed');
    }
  }

  /// Set engine lines view layout (cards vs list). Applies everywhere.
  Future<void> setEngineLinesView(EngineLinesView view) async {
    final currentState = _currentSettings();
    if (currentState.engineLinesView == view) return;
    final newSettings = currentState.copyWith(engineLinesView: view);
    debugPrint('🔧 EngineSettings: Engine lines view changed to ${view.name}');
    state = AsyncValue.data(newSettings);
    await _persist({'engineLinesView': view.index});
  }

  /// Set max arrows on board index
  Future<void> setMaxArrowsOnBoard(int index) async {
    final clamped = index.clamp(0, EngineSettings.maxArrowsLabels.length - 1);
    final currentState = _currentSettings();
    final newSettings = currentState.copyWith(maxArrowsOnBoard: clamped);
    final label = newSettings.maxArrowsLabel();
    debugPrint('🔧 EngineSettings: Max arrows on board changed to $label');
    state = AsyncValue.data(newSettings);
    await _persist({'maxArrowsOnBoard': clamped});
  }

  /// Refresh settings from Supabase
  Future<void> refresh() async {
    if (!_ready) await future;
    await _syncStore(_store, _generation, _changeEpoch);
  }

  /// Sync settings from Supabase to local cache
  Future<void> syncFromSupabase() async {
    debugPrint('[EngineSettings] Starting sync...');
    try {
      await refresh();
      debugPrint('[EngineSettings] Sync attempt finished');
    } catch (e, st) {
      debugPrint('[EngineSettings] Error syncing: $e');
      debugPrint('[EngineSettings] Stack: $st');
    }
  }

  // Private methods

  Future<void> _persist(Map<String, dynamic> patch, {bool sync = true}) async {
    final store = _store;
    final generation = _generation;
    final epoch = ++_changeEpoch;
    try {
      await store.change(patch);
    } catch (_) {
      if (_ready && generation == _generation && epoch == _changeEpoch) {
        state = AsyncValue.data(_settingsFromFields(store.values));
      }
      rethrow; // A failed SQLite write is not durable success.
    }
    if (sync) unawaited(_syncStore(store, generation, epoch));
  }

  /// Clear this scope only; account switches use separate snapshots/outboxes.
  Future<void> clearCache() async {
    _currentSettings();
    ++_changeEpoch;
    final store = _store;
    final generation = _generation;
    await store.clear();
    if (_ready && generation == _generation) {
      state = AsyncValue.data(_settingsFromFields(store.values));
    }
  }
}
