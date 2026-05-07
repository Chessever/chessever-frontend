import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/local_storage/local_eval/local_eval_cache.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';

import 'package:chessever2/repository/supabase/evals/persist_cloud_eval.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show FutureProvider, Ref;
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
const int _gameCardFallbackDepth = 12;
const int boardEvalSufficientDepth = 20;
const Duration _localEvalLookupTimeout = Duration(milliseconds: 120);
const Duration _gameCardEvalKeepAliveDuration = Duration(seconds: 4);

void _keepGameCardEvalAliveBriefly(Ref ref) {
  final link = ref.keepAlive();
  final timer = Timer(_gameCardEvalKeepAliveDuration, link.close);
  ref.onDispose(timer.cancel);
}

bool _shouldPersistCloudEval(CloudEval eval) {
  return eval.meetsPersistenceThreshold(
    minDepth: _minPersistDepth,
    minFullMoves: _minPersistFullMoves,
  );
}

bool _shouldPersistGameCardEval(CloudEval eval) {
  return eval.depth >= _gameCardFallbackDepth && eval.pvs.isNotEmpty;
}

Future<CloudEval?> _readLocalEvalFast({
  required LocalEvalCache local,
  required String fen,
  required int multiPV,
  required String sourceTag,
  int minDepth = 0,
}) async {
  try {
    final cached = await local
        .fetch(fen, multiPV: multiPV, minDepth: minDepth)
        .timeout(_localEvalLookupTimeout, onTimeout: () => null);
    if (cached != null && _isValidEvaluation(cached)) {
      final fenParts = fen.split(' ');
      final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
      final cp = cached.pvs.isNotEmpty ? cached.pvs.first.cp : 0;
      debugPrint(
        "🔵 EVAL SOURCE ($sourceTag): LOCAL CACHE - fen=$fen, side=$sideToMove, cp=$cp",
      );
      return cached;
    }
  } catch (e) {
    debugPrint('⚠️ $sourceTag: Local cache error: $e');
  }
  return null;
}

CloudEval _emptyCloudEval(String fen, {required int multiPV}) {
  return CloudEval(
    fen: fen,
    knodes: 0,
    depth: 0,
    pvs: const [],
    requestedMultiPv: multiPV,
  );
}

bool _isMatePv(Pv pv) {
  return pv.isMate || pv.mate != null || pv.cp.abs() >= 100000;
}

bool cloudEvalSkipsBoardStockfish(CloudEval eval) {
  if (eval.pvs.isEmpty) return false;
  // We must have actual moves to show in the UI; evaluation alone is not enough.
  if (eval.pvs.first.moves.trim().isEmpty) return false;
  return _isMatePv(eval.pvs.first) || eval.depth >= boardEvalSufficientDepth;
}

Future<CloudEval?> _readGamebaseEvalFast({
  required GamebaseRepository gamebase,
  required LocalEvalCache local,
  required PersistCloudEval persist,
  required String fen,
  required String sourceTag,
}) async {
  try {
    final gamebaseEval = await gamebase
        .getEvalByFen(fen)
        .timeout(const Duration(milliseconds: 600), onTimeout: () => null);

    if (gamebaseEval != null && _isValidEvaluation(gamebaseEval)) {
      final fenParts = fen.split(' ');
      final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
      final cp = gamebaseEval.pvs.isNotEmpty ? gamebaseEval.pvs.first.cp : 0;
      debugPrint(
        "💎 EVAL SOURCE ($sourceTag): GAMEBASE - fen=$fen, side=$sideToMove, cp=$cp, depth=${gamebaseEval.depth}",
      );

      if (_shouldPersistCloudEval(gamebaseEval)) {
        // OPTIMIZATION: Save to local cache in background
        // Supabase persistence disabled as per user request
        unawaited(
          local
              .save(
                fen,
                gamebaseEval,
                multiPV:
                    gamebaseEval.requestedMultiPv ?? gamebaseEval.pvs.length,
              )
              .catchError((e) {
                debugPrint(
                  '⚠️ $sourceTag: Background local save failed for $fen: $e',
                );
              }),
        );
      } else {
        // Just local cache
        unawaited(
          local
              .save(
                fen,
                gamebaseEval,
                multiPV:
                    gamebaseEval.requestedMultiPv ?? gamebaseEval.pvs.length,
              )
              .catchError((_) => null),
        );
      }
      return gamebaseEval;
    }
  } catch (e) {
    debugPrint('⚠️ $sourceTag: Gamebase error: $e');
  }
  debugPrint("⚪️ EVAL SOURCE ($sourceTag): GAMEBASE MISS - fen=$fen");
  return null;
}

/// 1. local → 2. Gamebase → 3. Supabase → 4. Stockfish
/// Uses autoDispose to cancel evaluations when switching games
final cascadeEvalProvider = FutureProvider.family.autoDispose<
  CloudEval,
  CascadeEvalParams
>((ref, params) async {
  final fen = params.fen;
  final multiPV = params.multiPV;
  final local = ref.watch(localEvalCacheProvider);
  final persist = ref.watch(persistCloudEvalProvider);
  final gamebase = ref.read(gamebaseRepositoryProvider);

  if (fen.isEmpty) {
    return _emptyCloudEval(fen, multiPV: multiPV);
  }

  // 1️⃣  Local cache (with multiPV in key)
  final cachedLocal = await _readLocalEvalFast(
    local: local,
    fen: fen,
    multiPV: multiPV,
    sourceTag: 'cascadeEval',
  );
  if (cachedLocal != null) {
    return cachedLocal;
  }
  final gamebaseEval = await _readGamebaseEvalFast(
    gamebase: gamebase,
    local: local,
    persist: persist,
    fen: fen,
    sourceTag: 'cascadeEval',
  );
  if (gamebaseEval != null) {
    return gamebaseEval;
  }

  // 2️⃣  Supabase (DISABLED - using Gamebase + Stockfish only)
  /*
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
  */

  // 3️⃣  Stockfish (primary engine - Lichess removed)
  final engineSettingsValue = ref.read(engineSettingsProviderNew).value;
  final resolvedSettings = engineSettingsValue ?? const EngineSettings();

  // Clamp stockfish MultiPV to user preference and request (1-5)
  final settingsMultiPv = resolvedSettings.multiPvForStockfish();
  final resolvedMultiPv =
      multiPV <= settingsMultiPv ? multiPV : settingsMultiPv;

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
      debugPrint(
        '⚠️ cascadeEval: Stockfish returned empty result for $fen (likely cancelled)',
      );
      return _emptyCloudEval(fen, multiPV: resolvedMultiPv);
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
      // Supabase persistence disabled as per user request
      unawaited(
        local
            .save(
              fen,
              cloudFromSf,
              multiPV: cloudFromSf.requestedMultiPv ?? cloudFromSf.pvs.length,
            )
            .catchError((error) {
              debugPrint(
                '⚠️ cascadeEval: Background local save failed for $fen: $error',
              );
            }),
      );
    }

    return cloudFromSf;
  } catch (engineError, engineStack) {
    debugPrint('❌ cascadeEval: Stockfish failed for $fen: $engineError');
    debugPrint(engineStack.toString());
    // Return empty result instead of throwing - prevents UI errors on rapid navigation
    return _emptyCloudEval(fen, multiPV: resolvedMultiPv);
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

/// SEQUENTIAL cache-only cascade: local → Gamebase → Supabase.
/// Used for board evaluation - Stockfish is managed by the board notifier.
/// Uses autoDispose to cancel evaluations when switching games
final cascadeEvalProviderForBoard = FutureProvider.family.autoDispose<
  CloudEval,
  CascadeEvalParams
>((ref, params) async {
  final fen = params.fen;
  final multiPV = params.multiPV;
  final local = ref.watch(localEvalCacheProvider);
  final persist = ref.watch(persistCloudEvalProvider);
  final gamebase = ref.read(gamebaseRepositoryProvider);

  if (fen.isEmpty) {
    return _emptyCloudEval(fen, multiPV: multiPV);
  }

  // 1️⃣ Check local cache first (instant, with multiPV in key)
  final cachedLocal = await _readLocalEvalFast(
    local: local,
    fen: fen,
    multiPV: multiPV,
    sourceTag: 'board',
  );
  if (cachedLocal != null) {
    return cachedLocal;
  }
  final gamebaseEval = await _readGamebaseEvalFast(
    gamebase: gamebase,
    local: local,
    persist: persist,
    fen: fen,
    sourceTag: 'board',
  );
  if (gamebaseEval != null) {
    return gamebaseEval;
  }

  // 2️⃣ Query Supabase (DISABLED - using Gamebase + Stockfish only)
  /*
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
  */

  // 3️⃣ Return empty - Stockfish is managed by board notifier directly
  // This provider is for quick cache/Supabase lookups only
  // The board notifier handles Stockfish evaluation separately to avoid duplicate jobs
  debugPrint(
    '⚠️ cascadeEvalForBoard: No cached eval for $fen, board notifier will use Stockfish',
  );
  return _emptyCloudEval(fen, multiPV: multiPV);
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

/// Evaluation provider for game cards and FEN previews.
/// Uses local cache → Gamebase → Supabase first and falls back to low-priority
/// local Stockfish only when no cached/remote eval exists. Any available depth
/// is accepted for the remote/cache sources on these non-board surfaces.
final gameCardEvalWithStockfishFallbackProvider = FutureProvider.family.autoDispose<
  CloudEval,
  String // FEN string
>((ref, fen) async {
  _keepGameCardEvalAliveBriefly(ref);
  final local = ref.watch(localEvalCacheProvider);
  final persist = ref.watch(persistCloudEvalProvider);
  final gamebase = ref.read(gamebaseRepositoryProvider);

  if (fen.isEmpty) {
    return _emptyCloudEval(fen, multiPV: 1);
  }

  const multiPV = 1;

  final cachedLocal = await _readLocalEvalFast(
    local: local,
    fen: fen,
    multiPV: multiPV,
    sourceTag: 'gameCard',
  );
  if (cachedLocal != null) {
    return cachedLocal;
  }
  final gamebaseEval = await _readGamebaseEvalFast(
    gamebase: gamebase,
    local: local,
    persist: persist,
    fen: fen,
    sourceTag: 'gameCard',
  );
  if (gamebaseEval != null) {
    return gamebaseEval;
  }

  // Supabase lookup (DISABLED - using Gamebase + Stockfish only)
  /*
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
          "🟡 EVAL SOURCE (gameCard): SUPABASE - fen=$fen, side=$sideToMove, cp=$cp, depth=${cloud.depth}",
        );
        unawaited(
          local
              .save(
                fen,
                cloud,
                multiPV: cloud.requestedMultiPv ?? cloud.pvs.length,
              )
              .catchError((_) => null),
        );
        return cloud;
      }
    }
  } catch (e) {
    debugPrint('⚠️ gameCardEval: Supabase error for $fen: $e');
  }
  */

  try {
    final sfEval = await StockfishSingleton().evaluatePosition(
      fen,
      depth: _gameCardFallbackDepth,
      multiPV: multiPV,
      isCurrentPosition: false,
      allowCache: true,
    );

    if (sfEval.pvs.isEmpty || sfEval.pvs.first.moves.isEmpty) {
      debugPrint('⚠️ gameCardEval: Stockfish returned empty result for $fen');
      return _emptyCloudEval(fen, multiPV: multiPV);
    }

    final cloudFromSf = CloudEval(
      fen: fen,
      knodes: sfEval.knodes,
      depth: sfEval.depth,
      pvs: sfEval.pvs,
      requestedMultiPv: multiPV,
    );

    final fenParts = fen.split(' ');
    final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
    final cp = cloudFromSf.pvs.isNotEmpty ? cloudFromSf.pvs.first.cp : 0;
    debugPrint(
      "🟢 EVAL SOURCE (gameCard): STOCKFISH - fen=$fen, side=$sideToMove, cp=$cp, depth=${cloudFromSf.depth}",
    );

    if (_shouldPersistGameCardEval(cloudFromSf)) {
      // Supabase persistence disabled as per user request
      unawaited(
        local
            .save(
              fen,
              cloudFromSf,
              multiPV: cloudFromSf.requestedMultiPv ?? cloudFromSf.pvs.length,
            )
            .catchError((error) {
              debugPrint(
                '⚠️ gameCardEval: Background local save failed for $fen: $error',
              );
            }),
      );
    }

    return cloudFromSf;
  } catch (e) {
    debugPrint('⚠️ gameCardEval: Stockfish error for $fen: $e');
    return _emptyCloudEval(fen, multiPV: multiPV);
  }
});

/// Cache/server-only evaluation provider for scroll surfaces.
///
/// This intentionally avoids starting Stockfish while a feed is actively
/// scrolling. Callers can switch back to [gameCardEvalWithStockfishFallbackProvider]
/// as soon as scrolling settles, preserving eval quality without competing with
/// frame rendering during a fling.
final gameCardEvalCacheOnlyProvider = FutureProvider.family
    .autoDispose<CloudEval, String>((ref, fen) async {
      _keepGameCardEvalAliveBriefly(ref);
      if (fen.isEmpty) {
        return _emptyCloudEval(fen, multiPV: 1);
      }

      final cached = await _readGameCardCacheOrRemoteEval(
        ref: ref,
        fen: fen,
        sourceTag: 'gameCardScroll',
      );
      return cached ?? _emptyCloudEval(fen, multiPV: 1);
    });

Future<CloudEval?> _readGameCardCacheOrRemoteEval({
  required Ref ref,
  required String fen,
  required String sourceTag,
}) async {
  const multiPV = 1;
  final local = ref.watch(localEvalCacheProvider);
  final persist = ref.watch(persistCloudEvalProvider);
  final gamebase = ref.read(gamebaseRepositoryProvider);

  final cachedLocal = await _readLocalEvalFast(
    local: local,
    fen: fen,
    multiPV: multiPV,
    sourceTag: sourceTag,
  );
  if (cachedLocal != null) {
    return cachedLocal;
  }

  return _readGamebaseEvalFast(
    gamebase: gamebase,
    local: local,
    persist: persist,
    fen: fen,
    sourceTag: sourceTag,
  );
}
