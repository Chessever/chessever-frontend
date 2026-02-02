import 'dart:async';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Persisted user preference for showing the Gamebase (book icon) overlay.
///
/// Defaults to enabled so the overlay is active on first use.
final gamebaseOverlayEnabledProvider =
    AsyncNotifierProvider<GamebaseOverlayEnabledNotifier, bool>(
      GamebaseOverlayEnabledNotifier.new,
    );

class GamebaseOverlayEnabledNotifier extends AsyncNotifier<bool> {
  static const String _prefsKey = 'gamebase_overlay_enabled';

  @override
  Future<bool> build() async {
    try {
      final db = AppDatabase.instance;
      return await db.getBool(_prefsKey) ?? true;
    } catch (e) {
      debugPrint('[GamebaseOverlay] Failed to load preference: $e');
      return true;
    }
  }

  Future<void> setEnabled(bool enabled) async {
    state = AsyncValue.data(enabled);
    unawaited(_persist(enabled));
  }

  Future<void> toggle() async {
    final current = state.valueOrNull ?? true;
    await setEnabled(!current);
  }

  Future<void> _persist(bool enabled) async {
    try {
      final db = AppDatabase.instance;
      await db.setBool(_prefsKey, enabled);
    } catch (e) {
      debugPrint('[GamebaseOverlay] Failed to persist preference: $e');
    }
  }
}
