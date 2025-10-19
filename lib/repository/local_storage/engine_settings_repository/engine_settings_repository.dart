import 'dart:convert';

import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class EngineSettingsRecord {
  const EngineSettingsRecord({
    required this.showEngineGauge,
    required this.searchTimeIndex,
    required this.principalVariationCount,
  });

  final bool showEngineGauge;
  final int searchTimeIndex;
  final int principalVariationCount;

  Map<String, dynamic> toJson() => {
        'showEngineGauge': showEngineGauge,
        'searchTimeIndex': searchTimeIndex,
        'principalVariationCount': principalVariationCount,
      };

  static EngineSettingsRecord fromJson(Map<String, dynamic> json) {
    return EngineSettingsRecord(
      showEngineGauge: json['showEngineGauge'] as bool? ?? true,
      searchTimeIndex: json['searchTimeIndex'] as int? ?? 2,
      principalVariationCount: json['principalVariationCount'] as int? ?? 3,
    );
  }
}

class _EngineSettingsRepository {
  _EngineSettingsRepository(this.ref);

  final Ref ref;

  static const _engineSettingsKey = 'engine_settings_v1';

  Future<void> save(EngineSettingsRecord record) async {
    final prefs = ref.read(sharedPreferencesRepository);
    final payload = jsonEncode(record.toJson());
    await prefs.setString(_engineSettingsKey, payload);
  }

  Future<EngineSettingsRecord?> load() async {
    final prefs = ref.read(sharedPreferencesRepository);
    final stored = await prefs.getString(_engineSettingsKey);
    if (stored == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(stored) as Map<String, dynamic>;
      return EngineSettingsRecord.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }
}

final engineSettingsRepositoryProvider = AutoDisposeProvider<_EngineSettingsRepository>((ref) {
  return _EngineSettingsRepository(ref);
});
