import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/local_storage/local_eval/local_eval_cache.dart';
import 'package:chessever2/repository/supabase/evals/evals_repository.dart';
import 'package:chessever2/repository/supabase/evals/persist_cloud_eval.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show FutureProvider;
import 'stockfish_singleton.dart';

// REMOVED: _LichessRateLimitTracker - Lichess API removed, relying only on Stockfish
// REMOVED: lichess_eval_repository import - no longer used

/// Parameters for cascade eval with configurable multiPV and priority
class CascadeEvalParams {
  final String fen;
  final int multiPV;
  final bool
  isCurrentPosition; // Priority flag for user's currently viewed position

  const CascadeEvalParams({
    required this.fen,
    this.multiPV = 3,
    this.isCurrentPosition = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CascadeEvalParams &&
          other.fen == fen &&
          other.multiPV == multiPV &&
          other.isCurrentPosition == isCurrentPosition;

  @override
  int get hashCode => Object.hash(fen, multiPV, isCurrentPosition);
}

const int _minPersistDepth = 20;
const int _minPersistFullMoves = 8;

bool _shouldPersistCloudEval(CloudEval eval) {
  return eval.meetsPersistenceThreshold(
    minDepth: _minPersistDepth,
    minFullMoves: _minPersistFullMoves,
  );
}

/// 1. local → 2. Supabase → 3. Stockfish (Lichess removed)
/// Uses autoDispose to cancel evaluations when switching games
final cascadeEvalProvider = FutureProvider.family.autoDispose<
  CloudEval,
  CascadeEvalParams
>((ref, params) async {
  final fen = params.fen;
  final multiPV = params.multiPV;
  final local = ref.watch(localEvalCacheProvider);
  final persist = ref.watch(persistCloudEvalProvider);
  final evalsRepo = ref.watch(evalsRepositoryProvider);

  if (fen.isEmpty) {
    return CloudEval(
      fen: fen,
      knodes: 0,
      depth: 0,
      pvs: const [],
      requestedMultiPv: multiPV,
    );
  }

  // 1️⃣  Local cache (with multiPV in key)
  try {
    final cached = await local.fetch(fen, multiPV: multiPV);
    if (cached != null && _isValidEvaluation(cached)) {
      final fenParts = fen.split(' ');
      final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
      final cp = cached.pvs.isNotEmpty ? cached.pvs.first.cp : 0;
      debugPrint(
        "🔵 EVAL SOURCE (cascadeEval): LOCAL CACHE - fen=$fen, side=$sideToMove, cp=$cp",
      );
      return cached;
    }
  } catch (e) {
    debugPrint('⚠️ cascadeEval: Local cache error: $e');
  }

  // 2️⃣  Supabase
  try {
    final supabaseEval = await evalsRepo
        .fetchFromSupabase(fen, desiredMultiPv: multiPV)
        .timeout(const Duration(milliseconds: 600), onTimeout: () => null);
    if (supabaseEval != null) {
      final cloud = evalsRepo.evalsToCloudEval(fen, supabaseEval);
      if (_isValidEvaluation(cloud)) {
        final fenParts = fen.split(' ');
        final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
        final cp = cloud.pvs.isNotEmpty ? cloud.pvs.first.cp : 0;
        debugPrint(
          "🟡 EVAL SOURCE (cascadeEval): SUPABASE - fen=$fen, side=$sideToMove, cp=$cp",
        );
        if (_shouldPersistCloudEval(cloud)) {
          // OPTIMIZATION: Save to local cache in background (unawaited)
          unawaited(
            local
                .save(
                  fen,
                  cloud,
                  multiPV: cloud.requestedMultiPv ?? cloud.pvs.length,
                )
                .catchError((e) => null),
          );
        }
        return cloud;
      }
    }
  } catch (e) {
    debugPrint('⚠️ cascadeEval: Supabase error: $e');
  }

  // 3️⃣  Stockfish (primary engine - Lichess removed)
  final engineSettingsValue = ref.read(engineSettingsProviderNew).value;
  final resolvedSettings = engineSettingsValue ?? const EngineSettings();

  // Clamp stockfish MultiPV to user preference and request (1-5)
  final settingsMultiPv = resolvedSettings.multiPvForStockfish();
  final resolvedMultiPv = multiPV <= settingsMultiPv ? multiPV : settingsMultiPv;

  final searchDuration = resolvedSettings.searchDurationFor(
    EngineComponent.cascadeEval,
  );
  var maxDepthSetting = resolvedSettings.maxDepthFor(
    EngineComponent.cascadeEval,
  );
  if (maxDepthSetting < 1) {
    maxDepthSetting = 1;
  } else if (maxDepthSetting > 99) {
    maxDepthSetting = 99;
  }

  try {
    debugPrint(
      '⚡ cascadeEval: Using Stockfish (depth=$maxDepthSetting, multiPV=$resolvedMultiPv, duration=${searchDuration?.inSeconds}s) for $fen',
    );
    final sfEval = await StockfishSingleton().evaluatePosition(
      fen,
      depth: maxDepthSetting,
      maxDepth: maxDepthSetting,
      multiPV: resolvedMultiPv,
      searchDuration: searchDuration,
      isCurrentPosition: params.isCurrentPosition,
    );

    // Handle cancelled/empty results gracefully - don't throw, return empty
    if (sfEval.pvs.isEmpty || sfEval.pvs.first.moves.isEmpty) {
      debugPrint('⚠️ cascadeEval: Stockfish returned empty result for $fen (likely cancelled)');
      return CloudEval(
        fen: fen,
        knodes: 0,
        depth: 0,
        pvs: const [],
        requestedMultiPv: resolvedMultiPv,
      );
    }

    final cloudFromSf = CloudEval(
      fen: fen,
      knodes: sfEval.knodes,
      depth: sfEval.depth,
      pvs: sfEval.pvs,
      requestedMultiPv: resolvedMultiPv,
    );

    final fenParts = fen.split(' ');
    final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
    final cp = cloudFromSf.pvs.isNotEmpty ? cloudFromSf.pvs.first.cp : 0;
    debugPrint(
      "🟢 EVAL SOURCE (cascadeEval): STOCKFISH (depth=${cloudFromSf.depth}) - fen=$fen, side=$sideToMove, cp=$cp",
    );

    if (_shouldPersistCloudEval(cloudFromSf)) {
      // Persist Stockfish result asynchronously for future reuse
      unawaited(
        Future.wait<void>([
          persist.call(fen, cloudFromSf),
          local.save(
            fen,
            cloudFromSf,
            multiPV: cloudFromSf.requestedMultiPv ?? cloudFromSf.pvs.length,
          ),
        ]).catchError((error) {
          debugPrint(
            '⚠️ cascadeEval: Background persist failed for $fen: $error',
          );
          return <void>[];
        }),
      );
    }

    return cloudFromSf;
  } catch (engineError, engineStack) {
    debugPrint(
      '❌ cascadeEval: Stockfish failed for $fen: $engineError',
    );
    debugPrint(engineStack.toString());
    // Return empty result instead of throwing - prevents UI errors on rapid navigation
    return CloudEval(
      fen: fen,
      knodes: 0,
      depth: 0,
      pvs: const [],
      requestedMultiPv: resolvedMultiPv,
    );
  }
});

/// Helper function to validate if an evaluation makes sense
bool _isValidEvaluation(CloudEval cloud) {
  if (cloud.pvs.isEmpty) return false;

  final firstPv = cloud.pvs.first;

  // If it's exactly 0 cp with no moves, it's likely invalid
  if (firstPv.cp == 0 && firstPv.moves.isEmpty) return false;

  // Accept mate scores (high cp values >= 100000 are mate scores)
  if (firstPv.cp.abs() >= 100000) {
    return true;
  }

  // Accept any evaluation with moves (including 0.0 - balanced positions are valid)
  if (firstPv.moves.isNotEmpty) return true;

  return false;
}

/// SEQUENTIAL cascade: local → Supabase → Stockfish (Lichess removed)
/// Used for board evaluation - returns empty result instead of throwing errors
/// Uses autoDispose to cancel evaluations when switching games
final cascadeEvalProviderForBoard = FutureProvider.family.autoDispose<
  CloudEval,
  CascadeEvalParams
>((ref, params) async {
  final fen = params.fen;
  final multiPV = params.multiPV;
  final local = ref.watch(localEvalCacheProvider);
  final evalsRepo = ref.watch(evalsRepositoryProvider);

  if (fen.isEmpty) {
    return CloudEval(
      fen: fen,
      knodes: 0,
      depth: 0,
      pvs: const [],
      requestedMultiPv: multiPV,
    );
  }

  // 1️⃣ Check local cache first (instant, with multiPV in key)
  try {
    final cached = await local.fetch(fen, multiPV: multiPV);
    if (cached != null && _isValidEvaluation(cached)) {
      final fenParts = fen.split(' ');
      final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
      final cp = cached.pvs.isNotEmpty ? cached.pvs.first.cp : 0;
      debugPrint(
        "🔵 EVAL SOURCE (board): LOCAL CACHE - fen=$fen, side=$sideToMove, cp=$cp",
      );
      return cached;
    }
  } catch (e) {
    debugPrint('⚠️ cascadeEvalForBoard: Local cache error: $e');
  }

  // 2️⃣ Query Supabase (our database, no rate limits)
  try {
    final supabaseEval = await evalsRepo
        .fetchFromSupabase(
          fen,
          desiredMultiPv: multiPV,
        )
        .timeout(const Duration(milliseconds: 600), onTimeout: () => null);
    if (supabaseEval != null) {
      final cloud = evalsRepo.evalsToCloudEval(fen, supabaseEval);
      if (_isValidEvaluation(cloud)) {
        final fenParts = fen.split(' ');
        final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
        final cp = cloud.pvs.isNotEmpty ? cloud.pvs.first.cp : 0;
        debugPrint(
          "🟡 EVAL SOURCE (board): SUPABASE - fen=$fen, side=$sideToMove, cp=$cp",
        );
        // Background save to local cache when meaningful
        if (_shouldPersistCloudEval(cloud)) {
          unawaited(
            local
                .save(
                  fen,
                  cloud,
                  multiPV: cloud.requestedMultiPv ?? cloud.pvs.length,
                )
                .catchError((e) => null),
          );
        }
        return cloud;
      }
    }
  } catch (e) {
    debugPrint('⚠️ cascadeEvalForBoard: Supabase error: $e');
  }

  // 3️⃣ Return empty - Stockfish is managed by board notifier directly
  // This provider is for quick cache/Supabase lookups only
  // The board notifier handles Stockfish evaluation separately to avoid duplicate jobs
  debugPrint('⚠️ cascadeEvalForBoard: No cached eval for $fen, board notifier will use Stockfish');
  return CloudEval(
    fen: fen,
    knodes: 0,
    depth: 0,
    pvs: const [],
    requestedMultiPv: multiPV,
  );
});

// REMOVED: All background upgrade functions
//
// The progressive depth ladder and background upgrades were causing:
// - Multiple Stockfish instances running simultaneously
// - Evaluation gauge showing different depth than PV cards
// - Stockfish singleton being used incorrectly
//
// New approach: PROGRESSIVE DEEPENING (depth 12→50)
// - Stockfish naturally progresses: 1→2→3→...→12→13→14→...→50
// - UI displays results starting from depth 12 (via minReportDepth guard)
// - Each depth update (~0.1s intervals) triggers real-time UI refresh
// - onDepthUpdate callback in board provider fires at each depth level
// - PV cards and eval bar update simultaneously as depth increases
// - Priority: Show depth 12 FAST, then continuously improve to 50

/// Evaluation provider for game cards with Stockfish fallback.
/// Uses cascade (local → Supabase → Stockfish) - Lichess removed.
/// - Auto-disposes when card scrolls out of view (via autoDispose)
/// - Low priority Stockfish (isCurrentPosition: false) to not interfere with active board
/// - Depth 8 is fast enough for responsive UI fallback
final gameCardEvalWithStockfishFallbackProvider = FutureProvider.family.autoDispose<
  CloudEval,
  String // FEN string
>((ref, fen) async {
  if (fen.isEmpty) {
    return CloudEval(
      fen: fen,
      knodes: 0,
      depth: 0,
      pvs: const [],
      requestedMultiPv: 1,
    );
  }

  const multiPV = 1;
  final local = ref.watch(localEvalCacheProvider);
  final evalsRepo = ref.watch(evalsRepositoryProvider);

  // 1️⃣ Check local cache first (instant hit)
  try {
    final cached = await local.fetch(fen, multiPV: multiPV);
    if (cached != null && _isValidEvaluation(cached)) {
      return cached;
    }
  } catch (e) {
    debugPrint('⚠️ gameCardEval: Local cache error: $e');
  }

  // 2️⃣ Try Supabase
  try {
    final supabaseEval = await evalsRepo
        .fetchFromSupabase(fen, desiredMultiPv: multiPV)
        .timeout(const Duration(milliseconds: 600), onTimeout: () => null);
    if (supabaseEval != null) {
      final cloud = evalsRepo.evalsToCloudEval(fen, supabaseEval);
      if (_isValidEvaluation(cloud)) {
        // Background cache save
        unawaited(
          local.save(fen, cloud, multiPV: cloud.requestedMultiPv ?? cloud.pvs.length)
              .catchError((_) => null),
        );
        return cloud;
      }
    }
  } catch (e) {
    debugPrint('⚠️ gameCardEval: Supabase error: $e');
  }

  // 3️⃣ Stockfish fallback at depth 8 (Lichess removed)
  const fallbackDepth = 8;
  try {
    final sfEval = await StockfishSingleton().evaluatePosition(
      fen,
      depth: fallbackDepth,
      multiPV: multiPV,
      isCurrentPosition: false, // Low priority for background game cards
      allowCache: true,
    );

    // Handle cancelled/empty results gracefully
    if (sfEval.pvs.isEmpty || sfEval.pvs.first.moves.isEmpty) {
      debugPrint('⚠️ gameCardEval: Stockfish returned empty result for $fen');
      return CloudEval(
        fen: fen,
        knodes: 0,
        depth: 0,
        pvs: const [],
        requestedMultiPv: multiPV,
      );
    }

    final cloudFromSf = CloudEval(
      fen: fen,
      knodes: sfEval.knodes,
      depth: sfEval.depth,
      pvs: sfEval.pvs,
      requestedMultiPv: multiPV,
    );

    // Cache Stockfish result for future use (fire-and-forget)
    unawaited(
      local.save(fen, cloudFromSf, multiPV: multiPV).catchError((_) => null),
    );

    return cloudFromSf;
  } catch (e) {
    debugPrint('⚠️ gameCardEval: Stockfish error for $fen: $e');
    // Return empty result on error - don't block the UI
    return CloudEval(
      fen: fen,
      knodes: 0,
      depth: 0,
      pvs: const [],
      requestedMultiPv: multiPV,
    );
  }
});
