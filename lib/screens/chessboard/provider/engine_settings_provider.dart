import 'package:chessever2/repository/local_storage/engine_settings_repository/engine_settings_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum EngineComponent {
  evaluationGauge,
  principalVariation,
  moveImpact,
  cascadeEval,
}

class EngineSearchProgress {
  const EngineSearchProgress({
    required this.depth,
    required this.kiloNodes,
  });

  final int depth;
  final int kiloNodes;
}

class EngineSettings {
  const EngineSettings({
    this.showEngineGauge = true,
    this.searchTimeIndex = 2,
    this.principalVariationCount = 3,
  });

  final bool showEngineGauge;
  final int searchTimeIndex;
  final int principalVariationCount;

  static const int minPrincipalVariation = 1;
  static const int maxPrincipalVariation = 5;

  static const List<int?> _searchTimeSecondsOptions = <int?>[
    5,
    10,
    20,
    30,
    60,
    null, // null represents "unlimited"
  ];

  static const List<String> searchTimeLabels = <String>[
    '5s',
    '10s',
    '20s',
    '30s',
    '60s',
    '∞',
  ];

  static const Map<EngineComponent, double> _componentTimeMultipliers = {
    EngineComponent.evaluationGauge: 1.0,
    EngineComponent.principalVariation: 1.0,
    EngineComponent.cascadeEval: 0.6,
    EngineComponent.moveImpact: 0.4,
  };

  static const Map<EngineComponent, int?> _componentUnlimitedCaps = {
    EngineComponent.evaluationGauge: null,
    EngineComponent.principalVariation: null,
    EngineComponent.cascadeEval: 45,
    EngineComponent.moveImpact: 30,
  };

  EngineSettings copyWith({
    bool? showEngineGauge,
    int? searchTimeIndex,
    int? principalVariationCount,
  }) {
    return EngineSettings(
      showEngineGauge: showEngineGauge ?? this.showEngineGauge,
      searchTimeIndex: searchTimeIndex ?? this.searchTimeIndex,
      principalVariationCount:
          (principalVariationCount ?? this.principalVariationCount)
              .clamp(minPrincipalVariation, maxPrincipalVariation),
    );
  }

  int? baseSearchTimeSeconds() {
    final safeIndex = searchTimeIndex.clamp(0, _searchTimeSecondsOptions.length - 1);
    return _searchTimeSecondsOptions[safeIndex];
  }

  Duration? searchDurationFor(EngineComponent component) {
    final baseSeconds = baseSearchTimeSeconds();
    final multiplier = _componentTimeMultipliers[component] ?? 1.0;

    if (baseSeconds == null) {
      final cappedSeconds = _componentUnlimitedCaps[component];
      if (cappedSeconds == null) {
        return null;
      }
      final cappedDuration = Duration(seconds: cappedSeconds);
      return cappedDuration;
    }

    final scaledMs = (baseSeconds * 1000 * multiplier).round().clamp(2000, 180000);
    return Duration(milliseconds: scaledMs);
  }

  String searchTimeLabel() {
    final safeIndex = searchTimeIndex.clamp(0, searchTimeLabels.length - 1);
    return searchTimeLabels[safeIndex];
  }
}

final engineSettingsProvider =
    StateNotifierProvider<EngineSettingsNotifier, EngineSettings>((ref) {
      final notifier = EngineSettingsNotifier(ref);
      notifier._init();
      return notifier;
    });

class EngineSettingsNotifier extends StateNotifier<EngineSettings> {
  EngineSettingsNotifier(this.ref) : super(const EngineSettings());

  final Ref ref;
  bool _hasLoaded = false;

  Future<void> _init() async {
    if (_hasLoaded) return;
    _hasLoaded = true;

    final repo = ref.read(engineSettingsRepositoryProvider);
    final record = await repo.load();
    if (record != null) {
      state = EngineSettings(
        showEngineGauge: record.showEngineGauge,
        searchTimeIndex: record.searchTimeIndex,
        principalVariationCount: record.principalVariationCount,
      );
    }
  }

  Future<void> toggleEngineGauge(bool value) async {
    state = state.copyWith(showEngineGauge: value);
    await _persist();
  }

  Future<void> setSearchTimeIndex(int index) async {
    final clamped = index.clamp(0, EngineSettings.searchTimeLabels.length - 1);
    state = state.copyWith(searchTimeIndex: clamped);
    await _persist();
  }

  Future<void> setPrincipalVariationCount(int count) async {
    final clamped = count
        .clamp(EngineSettings.minPrincipalVariation, EngineSettings.maxPrincipalVariation);
    state = state.copyWith(principalVariationCount: clamped);
    await _persist();
  }

  Future<void> _persist() async {
    final repo = ref.read(engineSettingsRepositoryProvider);
    final record = EngineSettingsRecord(
      showEngineGauge: state.showEngineGauge,
      searchTimeIndex: state.searchTimeIndex,
      principalVariationCount: state.principalVariationCount,
    );
    await repo.save(record);
  }
}
