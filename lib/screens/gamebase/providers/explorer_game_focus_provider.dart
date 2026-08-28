import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'gamebase_explorer_state.dart';
import 'gamebase_providers.dart';

/// Interval for focused-card long-press auto-repeat (parity with board ~150ms).
const Duration kExplorerCardLongPressInterval = Duration(milliseconds: 150);

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

  Timer? _longPressTimer;

  /// Focuses [gameId], starting at [ply] (clamped into the continuation).
  void focus({
    required String gameId,
    required String anchorFen,
    required List<String> sans,
    required List<String> fens,
    int ply = 0,
  }) {
    if (sans.isEmpty || fens.length != sans.length + 1) return;
    stopLongPress();
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

  /// Auto-repeat [forward] while the bottom-nav forward control is held.
  /// Stops at line end or when [stopLongPress] is called.
  void startLongPressForward() {
    _longPressTimer?.cancel();
    _longPressTimer = Timer.periodic(kExplorerCardLongPressInterval, (_) {
      final current = state;
      if (current == null || !current.canGoForward) {
        stopLongPress();
        return;
      }
      forward();
    });
  }

  /// Auto-repeat [backward] while the bottom-nav back control is held.
  /// Stops at the start of the line or when [stopLongPress] is called.
  void startLongPressBackward() {
    _longPressTimer?.cancel();
    _longPressTimer = Timer.periodic(kExplorerCardLongPressInterval, (_) {
      final current = state;
      if (current == null || !current.canGoBackward) {
        stopLongPress();
        return;
      }
      backward();
    });
  }

  /// Cancels any in-flight long-press auto-repeat.
  void stopLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  /// Whether a long-press auto-repeat timer is currently active.
  @visibleForTesting
  bool get isLongPressing => _longPressTimer != null;

  void clear() {
    stopLongPress();
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
    if (currentFen != current.anchorFen) {
      stopLongPress();
      state = null;
    }
  }

  @override
  void dispose() {
    stopLongPress();
    super.dispose();
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
}, dependencies: [gamebaseExplorerProvider]);

/// True while the explorer move list has scrolled so the inline games section
/// is pinned under the sticky header. Board chrome expands the games surface
/// over engine lines + the move table (bottom nav stays put for card arrows).
/// Cleared when scrolling back to moves or leaving the explorer panel.
final explorerInlineGamesPinnedProvider = StateProvider<bool>((_) => false);

/// Drop engine PV so the explorer games surface expands over that strip and
/// the move-table region. Pin alone is not enough — explorer page must be
/// visible on the active board page. Bottom nav is never hidden for this.
bool shouldExpandExplorerGamesOverPv({
  required bool pageVisible,
  required bool explorerPanelVisible,
  required bool gamesPinned,
}) => pageVisible && explorerPanelVisible && gamesPinned;

/// Resolved bottom-nav arrow callbacks + enable flags for the board chrome.
///
/// When [focus] is non-null the arrows walk the focused explorer card's
/// continuation via [focusNotifier] — including while
/// [explorerInlineGamesPinnedProvider] is true (pin only expands layout).
@immutable
class BoardNavArrowRouting {
  const BoardNavArrowRouting({
    required this.onLeftMove,
    required this.onRightMove,
    required this.canMoveForward,
    required this.canMoveBackward,
    required this.onLongPressBackwardStart,
    required this.onLongPressBackwardEnd,
    required this.onLongPressForwardStart,
    required this.onLongPressForwardEnd,
  });

  final VoidCallback? onLeftMove;
  final VoidCallback? onRightMove;
  final bool canMoveForward;
  final bool canMoveBackward;
  final VoidCallback? onLongPressBackwardStart;
  final VoidCallback? onLongPressBackwardEnd;
  final VoidCallback? onLongPressForwardStart;
  final VoidCallback? onLongPressForwardEnd;
}

/// Shipped ownership rules for board bottom-nav arrows (Trello #984).
///
/// Callers pass board-side handlers; when a card is focused those are ignored
/// and the focus notifier owns forward/back (and long-press auto-repeat).
BoardNavArrowRouting resolveBoardNavArrowRouting({
  required ExplorerGameFocus? focus,
  required ExplorerFocusedGameNotifier focusNotifier,
  required bool boardCanMoveForward,
  required bool boardCanMoveBackward,
  required VoidCallback onBoardForward,
  required VoidCallback onBoardBackward,
  required VoidCallback onBoardLongPressBackwardStart,
  required VoidCallback onBoardLongPressBackwardEnd,
  required VoidCallback onBoardLongPressForwardStart,
  required VoidCallback onBoardLongPressForwardEnd,
}) {
  if (focus != null) {
    return BoardNavArrowRouting(
      onLeftMove: focus.canGoBackward ? focusNotifier.backward : null,
      onRightMove: focus.canGoForward ? focusNotifier.forward : null,
      canMoveForward: focus.canGoForward,
      canMoveBackward: focus.canGoBackward,
      // Long-press auto-repeats through the card continuation (same model as
      // board notation hold). End always stops so release/cancel is safe even
      // when the line already ended mid-hold.
      onLongPressBackwardStart:
          focus.canGoBackward ? focusNotifier.startLongPressBackward : null,
      onLongPressBackwardEnd: focusNotifier.stopLongPress,
      onLongPressForwardStart:
          focus.canGoForward ? focusNotifier.startLongPressForward : null,
      onLongPressForwardEnd: focusNotifier.stopLongPress,
    );
  }
  return BoardNavArrowRouting(
    onLeftMove: boardCanMoveBackward ? onBoardBackward : null,
    onRightMove: boardCanMoveForward ? onBoardForward : null,
    canMoveForward: boardCanMoveForward,
    canMoveBackward: boardCanMoveBackward,
    onLongPressBackwardStart: onBoardLongPressBackwardStart,
    onLongPressBackwardEnd: onBoardLongPressBackwardEnd,
    onLongPressForwardStart:
        boardCanMoveForward ? onBoardLongPressForwardStart : null,
    onLongPressForwardEnd: onBoardLongPressForwardEnd,
  );
}
