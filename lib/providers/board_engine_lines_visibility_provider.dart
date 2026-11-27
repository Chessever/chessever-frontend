import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Device-only visibility of the in-game PV panel. The existing Cards/List
/// setting still owns layout, including the standalone Opening Explorer.
/// A separate key keeps older cached settings and cloud refreshes compatible.
class BoardEngineLinesVisibilityStore {
  static const preferenceKey = 'board_engine_lines_visible';

  Future<bool?> load() => AppDatabase.instance.getBool(preferenceKey);

  Future<void> save(bool visible) =>
      AppDatabase.instance.setBool(preferenceKey, visible);
}

final boardEngineLinesVisibilityStoreProvider =
    Provider<BoardEngineLinesVisibilityStore>(
      (ref) => BoardEngineLinesVisibilityStore(),
    );

final boardEngineLinesVisibleProvider =
    AsyncNotifierProvider<BoardEngineLinesVisibleNotifier, bool>(
      BoardEngineLinesVisibleNotifier.new,
    );

class BoardEngineLinesVisibleNotifier extends AsyncNotifier<bool> {
  Future<void> _pendingWrite = Future<void>.value();

  @override
  Future<bool> build() async {
    try {
      final saved = await ref.read(boardEngineLinesVisibilityStoreProvider).load();
      if (saved != null) return saved;
      // An older install could hide lines through the legacy analysis master.
      // Use that intent until the user makes an explicit local Lines choice.
      return (await ref.read(engineSettingsProviderNew.future)).showEngineAnalysis;
    } catch (_) {
      debugPrint('[BoardEngineLines] Could not load device preference');
      return true;
    }
  }

  Future<void> setVisible(bool visible) async {
    // Do not let a late initial read overwrite a choice made while loading.
    await future;
    final store = ref.read(boardEngineLinesVisibilityStoreProvider);
    state = AsyncData(visible);
    // Serialize writes so rapid Off/Cards/List taps persist the last choice.
    // A failed save must not poison the queue for subsequent choices.
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        await store.save(visible);
      } catch (_) {
        debugPrint('[BoardEngineLines] Could not save device preference');
      }
    });
    await _pendingWrite;
  }
}
