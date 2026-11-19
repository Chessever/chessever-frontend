import 'package:flutter/material.dart';

/// The page route a board opens in when its opener reads back the game the
/// reader was last on (the index the opener scrolls its own list to).
///
/// The board's chevron pops with that index. Every other way out carries no
/// result: the iOS edge swipe, Android back and predictive back,
/// `maybePop()`. Those fall back to [currentResult], which reads the same
/// index from the board mounted in this route, so the opener gets the same
/// value however the reader left.
///
/// `ChessBoardScreenNew` binds itself when it mounts; nothing else needs to.
class BoardPageRoute extends MaterialPageRoute<int> {
  BoardPageRoute({
    required super.builder,
    super.settings,
    super.requestFocus,
    super.maintainState,
    super.fullscreenDialog,
    super.allowSnapshotting,
  });

  Object? _owner;
  ValueGetter<int?>? _readResult;

  /// Makes [read] the source of this route's pop result. [owner] is the
  /// board's state; binding again replaces the previous owner.
  void bindResult(Object owner, ValueGetter<int?> read) {
    _owner = owner;
    _readResult = read;
  }

  /// Drops [owner]'s binding. A stale owner (one a newer board replaced)
  /// changes nothing.
  void unbindResult(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _readResult = null;
  }

  @override
  int? get currentResult => _readResult?.call() ?? super.currentResult;
}
