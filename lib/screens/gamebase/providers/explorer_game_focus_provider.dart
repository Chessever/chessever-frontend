import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'gamebase_explorer_state.dart';
import 'gamebase_providers.dart';

/// A game card focused for continuation traversal inside the opening
/// explorer's inline games section (Trello #984).
///
/// While a focus is held, the hosting screen's bottom-nav arrows drive the
/// focused card's continuation instead of the main board.
@immutable
class ExplorerGameFocus {
  const ExplorerGameFocus({
    required this.gameId,
    required this.anchorFen,
    required this.sans,
    required this.fens,
    required this.ply,
  });

  /// Gamebase id of the focused game row.
  final String gameId;

  /// FEN of the explored position the continuation starts from. Focus is
  /// auto-cleared as soon as the explorer moves off this position.
  final String anchorFen;

  /// SAN for each continuation ply.
  final List<String> sans;

  /// `fens[0]` is [anchorFen]; `fens[i]` is the position after applying
  /// `sans[0..i-1]`. Always `sans.length + 1` entries.
  final List<String> fens;

  /// Index of the last applied continuation ply; -1 = at the anchor position.
  final int ply;

  bool get canGoForward => ply < sans.length - 1;
  bool get canGoBackward => ply > -1;

  /// FEN the focused card's miniboard should render.
  String get boardFen => fens[(ply + 1).clamp(0, fens.length - 1)];

  ExplorerGameFocus copyWith({int? ply}) => ExplorerGameFocus(
    gameId: gameId,
    anchorFen: anchorFen,
    sans: sans,
    fens: fens,
    ply: ply ?? this.ply,
  );
}

class ExplorerFocusedGameNotifier extends StateNotifier<ExplorerGameFocus?> {
  ExplorerFocusedGameNotifier() : super(null);

  /// Focuses [gameId], starting at [ply] (clamped into the continuation).
  void focus({
    required String gameId,
    required String anchorFen,
    required List<String> sans,
    required List<String> fens,
    int ply = 0,
  }) {
    if (sans.isEmpty || fens.length != sans.length + 1) return;
    state = ExplorerGameFocus(
      gameId: gameId,
      anchorFen: anchorFen,
      sans: List<String>.unmodifiable(sans),
      fens: List<String>.unmodifiable(fens),
      ply: ply.clamp(-1, sans.length - 1),
    );
  }

  void jumpTo(int ply) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(ply: ply.clamp(-1, current.sans.length - 1));
  }

  void forward() {
    final current = state;
    if (current == null || !current.canGoForward) return;
    state = current.copyWith(ply: current.ply + 1);
  }

  void backward() {
    final current = state;
    if (current == null || !current.canGoBackward) return;
    state = current.copyWith(ply: current.ply - 1);
  }

  void clear() {
    if (state != null) state = null;
  }

  /// Safe variant for widget-dispose paths that may race provider teardown.
  void clearIfActive() {
    if (!mounted) return;
    clear();
  }

  /// Any explorer position change invalidates the focus — the continuation
  /// belongs to the position it was queried from.
  void onExplorerPositionChanged(String currentFen) {
    final current = state;
    if (current == null) return;
    if (currentFen != current.anchorFen) state = null;
  }
}

/// Currently focused explorer game card, or null when the main board owns the
/// bottom-nav arrows.
final explorerFocusedGameProvider = StateNotifierProvider.autoDispose<
  ExplorerFocusedGameNotifier,
  ExplorerGameFocus?
>((ref) {
  final notifier = ExplorerFocusedGameNotifier();
  // Making a move on the main board / tapping an explorer move row both land
  // here as a position change, releasing the arrows back to the board.
  ref.listen<GamebaseExplorerState>(gamebaseExplorerProvider, (previous, next) {
    notifier.onExplorerPositionChanged(next.currentFen);
  });
  return notifier;
});
