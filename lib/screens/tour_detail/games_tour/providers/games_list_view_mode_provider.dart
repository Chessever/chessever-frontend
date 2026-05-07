import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum GamesListViewMode { gamesCard, chessBoardGrid, chessBoard }

/// Provider that returns the persisted games list view mode from board settings
final gamesListViewModeProvider = Provider<GamesListViewMode>((ref) {
  final boardSettings = ref.watch(boardSettingsProviderNew);
  final index =
      boardSettings.valueOrNull?.gamesListViewModeIndex ??
      0; // Safe loading fallback: compact cards until persisted settings resolve
  return GamesListViewMode.values[index.clamp(
    0,
    GamesListViewMode.values.length - 1,
  )];
});

final gamesListViewModeSwitcher = AutoDisposeProvider(
  (ref) => _GamesListViewModeController(ref),
);

class _GamesListViewModeController {
  _GamesListViewModeController(this._ref);

  final Ref _ref;

  void toggleViewMode() {
    HapticFeedback.lightImpact();
    final currentMode = _ref.read(gamesListViewModeProvider);
    GamesListViewMode newMode;

    switch (currentMode) {
      case GamesListViewMode.gamesCard:
        newMode = GamesListViewMode.chessBoardGrid;
        break;
      case GamesListViewMode.chessBoardGrid:
        newMode = GamesListViewMode.chessBoard;
        break;
      case GamesListViewMode.chessBoard:
        newMode = GamesListViewMode.gamesCard;
        break;
    }

    // Persist the new mode to Supabase via board settings
    _ref
        .read(boardSettingsProviderNew.notifier)
        .setGamesListViewModeIndex(newMode.index);
  }
}
