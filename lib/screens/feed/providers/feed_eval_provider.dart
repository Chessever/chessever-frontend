import 'dart:async';

import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/chessboard/provider/stockfish_singleton.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// One evaluation for the Feed's eval bar, from White's side: pawns, or a
/// mate count. [evaluating] while an engine search is still running and
/// nothing has come back yet.
@immutable
class FeedEval {
  const FeedEval({this.pawns, this.mate, this.evaluating = false});

  static const FeedEval none = FeedEval();
  static const FeedEval pending = FeedEval(evaluating: true);

  final double? pawns;
  final int? mate;
  final bool evaluating;

  bool get hasValue => pawns != null || (mate != null && mate != 0);

  @override
  bool operator ==(Object other) =>
      other is FeedEval &&
      other.pawns == pawns &&
      other.mate == mate &&
      other.evaluating == evaluating;

  @override
  int get hashCode => Object.hash(pawns, mate, evaluating);
}

/// A position the eval bar wants a number for. [allowEngine] is false while
/// the clip autoplays: then only the eval cache and the Gamebase lookup the
/// game cards use are asked, never the engine.
@immutable
class FeedEvalRequest {
  const FeedEvalRequest(this.fen, {required this.allowEngine});

  final String fen;
  final bool allowEngine;

  @override
  bool operator ==(Object other) =>
      other is FeedEvalRequest &&
      other.fen == fen &&
      other.allowEngine == allowEngine;

  @override
  int get hashCode => Object.hash(fen, allowEngine);
}

/// The engine the Feed asks when a position has no cached number. A seam so
/// tests can count requests without a native engine.
abstract class FeedEngine {
  const FeedEngine();

  /// Searches [fen] under the viewer's evaluation-gauge settings, reporting
  /// each deeper result through [onUpdate]. Resolves to the settled result,
  /// or null when the search was cancelled or found nothing.
  Future<CloudEval?> evaluate(
    String fen, {
    required EngineSettings settings,
    required void Function(List<Pv> pvs, int depth) onUpdate,
  });

  Future<void> cancel();
}

/// The board screen's own engine, under the same rules: the evaluation
/// gauge's search time and depth cap from the viewer's engine settings, one
/// line, the visible position first.
///
/// Never passes `allowInDebug`: debug builds deliberately run no board
/// Stockfish (see [kEnableStockfishInDebug]), so there the bar simply stays
/// on the cached number or neutral.
class StockfishFeedEngine extends FeedEngine {
  const StockfishFeedEngine();

  static const String ownerId = 'feed_clip';

  /// Depth used when the viewer picked an unlimited search time: the Feed is
  /// a glance, not an analysis session.
  static const int unlimitedDepth = 30;

  @override
  Future<CloudEval?> evaluate(
    String fen, {
    required EngineSettings settings,
    required void Function(List<Pv> pvs, int depth) onUpdate,
  }) async {
    final duration = settings.searchDurationFor(
      EngineComponent.evaluationGauge,
    );
    final maxDepth = settings.maxDepthFor(EngineComponent.evaluationGauge);
    final result = await StockfishSingleton().evaluatePosition(
      fen,
      depth: duration == null ? unlimitedDepth.clamp(1, maxDepth) : 15,
      searchDuration: duration,
      maxDepth: maxDepth,
      multiPV: 1,
      isCurrentPosition: true,
      ownerId: ownerId,
      onPvUpdate: onUpdate,
    );
    if (result.isCancelled) return null;
    if (result.pvs.isEmpty || result.pvs.first.moves.isEmpty) return null;
    return CloudEval(
      fen: fen,
      knodes: result.knodes,
      depth: result.depth,
      pvs: result.pvs,
      requestedMultiPv: 1,
    );
  }

  @override
  Future<void> cancel() =>
      StockfishSingleton().cancelEvaluationsForOwner(ownerId);
}

final feedEngineProvider = Provider<FeedEngine>(
  (ref) => const StockfishFeedEngine(),
);

/// The cached number for [fen]: the local eval cache, then Gamebase, exactly
/// as the game cards look it up. Null on a miss.
final feedCachedEvalProvider = FutureProvider.autoDispose
    .family<CloudEval?, String>((ref, fen) async {
      try {
        final cloud = await ref.watch(
          gameCardEvalCacheOnlyProvider(fen).future,
        );
        final pv = cloud.pvs.isEmpty ? null : cloud.pvs.first;
        if (pv == null || pv.moves.trim().isEmpty) return null;
        return cloud;
      } catch (_) {
        return null;
      }
    });

/// The eval bar's number for one Feed position.
///
/// Cache first (free and instant for anything the app has seen); on a miss,
/// and only when [FeedEvalRequest.allowEngine], the engine under the
/// viewer's evaluation-gauge settings, streaming deeper results as they
/// land. Leaving the position (or the Feed) cancels the search.
final feedPositionEvalProvider = StreamProvider.autoDispose
    .family<FeedEval, FeedEvalRequest>((ref, request) {
      final controller = StreamController<FeedEval>();
      var disposed = false;
      final engine = ref.watch(feedEngineProvider);
      int? search;
      ref.onDispose(() {
        disposed = true;
        // Only the newest search is cancelled: the next position's search
        // may already be running under the same owner by the time this one
        // is disposed, and it pre-empts this one by itself anyway.
        if (search != null && search == _feedSearchSeq) {
          unawaited(engine.cancel());
        }
        unawaited(controller.close());
      });

      final whiteToMove = feedFenWhiteToMove(request.fen);
      FeedEval? last;
      void emit(FeedEval value) {
        if (disposed) return;
        if (value.hasValue) last = value;
        controller.add(value);
      }

      Future<void> run() async {
        emit(FeedEval.pending);
        final cached = await ref.watch(
          feedCachedEvalProvider(request.fen).future,
        );
        if (disposed) return;
        if (cached != null) {
          emit(feedEvalFromPv(cached.pvs.first, whiteToMove: whiteToMove));
          return;
        }
        if (!request.allowEngine) {
          emit(FeedEval.none);
          return;
        }
        final settings = await ref.watch(engineSettingsProviderNew.future);
        if (disposed) return;
        search = ++_feedSearchSeq;
        final result = await engine.evaluate(
          request.fen,
          settings: settings,
          onUpdate: (pvs, depth) {
            if (pvs.isEmpty || pvs.first.moves.isEmpty) return;
            emit(feedEvalFromPv(pvs.first, whiteToMove: whiteToMove));
          },
        );
        if (disposed) return;
        // A search cut short keeps the deepest number it reported.
        emit(
          result == null || result.pvs.isEmpty
              ? last ?? FeedEval.none
              : feedEvalFromPv(result.pvs.first, whiteToMove: whiteToMove),
        );
      }

      run().catchError((Object error) {
        debugPrint('[Feed] eval failed: $error');
        emit(FeedEval.none);
      });
      return controller.stream;
    });

/// Bumped by each engine search the Feed starts; see the dispose above.
int _feedSearchSeq = 0;

/// Whether White is to move in [fen] (true when the field is unreadable).
bool feedFenWhiteToMove(String fen) {
  final parts = fen.trim().split(RegExp(r'\s+'));
  return parts.length < 2 || parts[1] != 'b';
}

/// [pv] from White's side. Engine info lines speak for the side to move
/// (`whitePerspective: false`); cached and settled results are already
/// White's.
@visibleForTesting
FeedEval feedEvalFromPv(Pv pv, {required bool whiteToMove}) {
  final sign = pv.whitePerspective || whiteToMove ? 1 : -1;
  final mate = pv.isMate ? pv.mate : null;
  if (mate != null && mate != 0) return FeedEval(mate: mate * sign);
  return FeedEval(pawns: pv.cp * sign / 100.0);
}
