import 'package:chessground/chessground.dart';
import 'package:flutter/widgets.dart';

/// App-level coordinator for chessground's decoded piece image cache.
///
/// Chessground already lazy-loads missing images, but a board renders without
/// pieces until that async load completes. Use this before publishing a piece
/// set to visible boards so the first painted frame has decoded piece images.
class ChessgroundPieceImageCache {
  ChessgroundPieceImageCache._();

  static PieceSet? _loadedPieceSet;
  static Future<void>? _pendingLoad;

  static Future<void> ensurePieceSetLoaded(
    PieceSet pieceSet, {
    bool clearBeforeLoad = false,
  }) {
    final previousLoad =
        _pendingLoad?.catchError((Object _, StackTrace _) {}) ??
        Future<void>.value();

    late final Future<void> nextLoad;
    nextLoad = previousLoad.then((_) async {
      final cache = ChessgroundImages.instance;
      final assets = pieceSet.assets;
      final switchingPieceSet =
          _loadedPieceSet != null && _loadedPieceSet != pieceSet;

      if (clearBeforeLoad || switchingPieceSet) {
        cache.clear();
      }

      if (!cache.isAllLoaded(assets)) {
        await cache.loadAll(assets, devicePixelRatio: _devicePixelRatio);
      }

      _loadedPieceSet = pieceSet;
    });

    _pendingLoad = nextLoad.whenComplete(() {
      if (identical(_pendingLoad, nextLoad)) {
        _pendingLoad = null;
      }
    });

    return nextLoad;
  }

  static double? get _devicePixelRatio =>
      WidgetsBinding.instance.platformDispatcher.implicitView?.devicePixelRatio;
}
