import 'dart:async';

import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/lichess/cloud_eval/lichess_eval_repository.dart';
import 'package:chessever2/repository/local_storage/local_eval/local_eval_cache.dart';
import 'package:chessever2/repository/supabase/evals/evals_repository.dart';
import 'package:chessever2/repository/supabase/evals/persist_cloud_eval.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show FutureProvider;
import 'stockfish_singleton.dart';

/// Track Lichess API rate limiting to avoid abuse
class _LichessRateLimitTracker {
  static DateTime? _lastRateLimitTime;
  static const _cooldownDuration = Duration(minutes: 2);

  static bool isInCooldown() {
    if (_lastRateLimitTime == null) return false;
    final now = DateTime.now();
    final cooldownEnds = _lastRateLimitTime!.add(_cooldownDuration);
    return now.isBefore(cooldownEnds);
  }

  static void recordRateLimit() {
    _lastRateLimitTime = DateTime.now();
    print(
      '⚠️ LICHESS: Rate limited, entering ${_cooldownDuration.inMinutes}min cooldown',
    );
  }

  static void reset() {
    _lastRateLimitTime = null;
    print('✅ LICHESS: Rate limit cooldown cleared');
  }
}

// REMOVED: _activeBackgroundUpgrades
// No longer needed since we removed progressive ladder and background upgrades

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

/// 1. local → 2. Supabase → 3. lichess
/// Uses autoDispose to cancel evaluations when switching games
final cascadeEvalProvider = FutureProvider.family.autoDispose<
  CloudEval,
  CascadeEvalParams
>((ref, params) async {
  final fen = params.fen;
  final multiPV = params.multiPV;
  final local = ref.watch(localEvalCacheProvider);
  final persist = ref.watch(persistCloudEvalProvider);
  final lichess = ref.watch(lichessEvalRepoProvider);
  try {
    if (fen.isEmpty) throw Exception('Empty FEN');

    // 1️⃣  Local cache (with multiPV in key)
    final cached = await local.fetch(fen, multiPV: multiPV);
    if (cached != null) {
      final fenParts = fen.split(' ');
      final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
      final cp = cached.pvs.isNotEmpty ? cached.pvs.first.cp : 0;
      print(
        "🔵 EVAL SOURCE (cascadeEval): LOCAL CACHE - fen=$fen, side=$sideToMove, cp=$cp",
      );
      return cached;
    }

    // 2️⃣  Supabase
    final supabaseEval = await ref
        .read(evalsRepositoryProvider)
        .fetchFromSupabase(fen, desiredMultiPv: multiPV);
    if (supabaseEval != null) {
      final cloud = ref
          .read(evalsRepositoryProvider)
          .evalsToCloudEval(fen, supabaseEval);
      final fenParts = fen.split(' ');
      final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
      final cp = cloud.pvs.isNotEmpty ? cloud.pvs.first.cp : 0;
      print(
        "🟡 EVAL SOURCE (cascadeEval): SUPABASE - fen=$fen, side=$sideToMove, cp=$cp",
      );
      // OPTIMIZATION: Save to local cache in background (unawaited)
      local.save(fen, cloud, multiPV: cloud.pvs.length).catchError((e) => null);
      return cloud;
    }

    // 3️⃣  Lichess → Supabase → local (request multiPV from user settings)

    final cloud = await lichess.getEval(fen, multiPv: multiPV);
    final fenParts = fen.split(' ');
    final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
    final cp = cloud.pvs.isNotEmpty ? cloud.pvs.first.cp : 0;
    print(
      "🟢 EVAL SOURCE (cascadeEval): LICHESS (${cloud.pvs.length} PVs) - fen=$fen, side=$sideToMove, cp=$cp",
    );
    // OPTIMIZATION: Save to caches in background (unawaited)
    Future.wait<void>([
      persist.call(fen, cloud),
      local.save(fen, cloud, multiPV: cloud.pvs.length),
    ]).catchError((e) => <void>[]);
    return cloud;
  } catch (e, st) {
    print('❌ cascadeEvalProvider: Cloud sources failed for $fen - $e');
    print(st);
    final engineSettingsValue = ref.read(engineSettingsProviderNew).value;
    final resolvedSettings = engineSettingsValue ?? const EngineSettings();

    // Clamp stockfish MultiPV to user preference and request (1-5)
    final settingsMultiPv = resolvedSettings.multiPvForStockfish();
    final fallbackMultiPv =
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
      print(
        '⚡ cascadeEvalProvider: Falling back to Stockfish (depth=$maxDepthSetting, multiPV=$fallbackMultiPv, duration=${searchDuration?.inSeconds}s)',
      );
      final sfEval = await StockfishSingleton().evaluatePosition(
        fen,
        depth: maxDepthSetting,
        maxDepth: maxDepthSetting,
        multiPV: fallbackMultiPv,
        searchDuration: searchDuration,
        isCurrentPosition: params.isCurrentPosition,
      );

      if (sfEval.pvs.isEmpty || sfEval.pvs.first.moves.isEmpty) {
        throw Exception('Stockfish returned empty PVs for $fen');
      }

      final cloudFromSf = CloudEval(
        fen: fen,
        knodes: sfEval.knodes,
        depth: sfEval.depth,
        pvs: sfEval.pvs,
      );

      // Persist Stockfish result asynchronously for future reuse
      Future.wait<void>([
        persist.call(fen, cloudFromSf),
        local.save(fen, cloudFromSf, multiPV: cloudFromSf.pvs.length),
      ]).catchError((error) {
        print(
          '⚠️ cascadeEvalProvider: Background persist failed for $fen: $error',
        );
        return <void>[];
      });

      return cloudFromSf;
    } catch (engineError, engineStack) {
      print(
        '❌ cascadeEvalProvider: Stockfish fallback failed for $fen: $engineError',
      );
      print(engineStack);
      // Propagate failure with original stack
      return Future.error(engineError, engineStack);
    }
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

/// SEQUENTIAL cascade: local → Supabase → Lichess → Stockfish
/// Respects Lichess API rate limits by querying SEQUENTIALLY (not parallel)
/// Uses autoDispose to cancel evaluations when switching games
final cascadeEvalProviderForBoard = FutureProvider.family.autoDispose<
  CloudEval,
  CascadeEvalParams
>((ref, params) async {
  final fen = params.fen;
  final multiPV = params.multiPV;
  final local = ref.watch(localEvalCacheProvider);
  final persist = ref.watch(persistCloudEvalProvider);
  final lichess = ref.watch(lichessEvalRepoProvider);
  final evalsRepo = ref.watch(evalsRepositoryProvider);

  try {
    if (fen.isEmpty) throw Exception('Empty FEN');

    // 1️⃣ Check local cache first (instant, with multiPV in key)
    final cached = await local.fetch(fen, multiPV: multiPV);
    if (cached != null && _isValidEvaluation(cached)) {
      final fenParts = fen.split(' ');
      final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
      final cp = cached.pvs.isNotEmpty ? cached.pvs.first.cp : 0;
      print(
        "🔵 EVAL SOURCE: LOCAL CACHE (instant) - fen=$fen, side=$sideToMove, cp=$cp",
      );
      return cached;
    }

    // 2️⃣ Query Supabase FIRST (our database, no rate limits)
    print('🔍 EVAL: Checking Supabase for $fen');
    try {
      final supabaseEval = await evalsRepo.fetchFromSupabase(
        fen,
        desiredMultiPv: multiPV,
      );
      if (supabaseEval != null) {
        final cloud = evalsRepo.evalsToCloudEval(fen, supabaseEval);
        if (_isValidEvaluation(cloud)) {
          final fenParts = fen.split(' ');
          final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
          final cp = cloud.pvs.isNotEmpty ? cloud.pvs.first.cp : 0;
          print(
            "🟡 EVAL SOURCE: SUPABASE - fen=$fen, side=$sideToMove, cp=$cp",
          );
          // Background save to local cache
          local
              .save(fen, cloud, multiPV: cloud.pvs.length)
              .catchError((e) => null);
          return cloud;
        }
      }
    } catch (e) {
      print('⚠️ Supabase eval failed: $e, continuing to Lichess...');
    }

    // 3️⃣ LICHESS FALLBACK ONLY (NO LOCAL ENGINE HERE)
    // Important: The local engine is managed exclusively by the board notifier
    // to avoid duplicate jobs and massive queue growth.
    final cloud = await _fetchLichessWithFallback(fen, multiPV, lichess);
    // Persist in background
    Future.wait<void>([
      persist.call(fen, cloud),
      local.save(fen, cloud, multiPV: cloud.pvs.length),
    ]).catchError((_) => <void>[]);
    return cloud;
  } catch (error, _) {
    rethrow;
  }
});

/// Helper to fetch from Lichess with proper error handling
Future<CloudEval> _fetchLichessWithFallback(
  String fen,
  int multiPV,
  dynamic lichess, // Type inferred from provider
) async {
  try {
    return await lichess.getEval(fen, multiPv: multiPV);
  } catch (e) {
    // Let the error propagate for error handling
    throw Exception('Lichess fetch failed: $e');
  }
}

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
