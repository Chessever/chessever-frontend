import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

enum GamesListViewMode { gamesCard, chessBoardGrid, chessBoard }

final gamesListViewModeProvider = StateProvider<GamesListViewMode>(
  (ref) => GamesListViewMode.gamesCard,
);

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

    _ref.read(gamesListViewModeProvider.notifier).state = newMode;
  }
}
