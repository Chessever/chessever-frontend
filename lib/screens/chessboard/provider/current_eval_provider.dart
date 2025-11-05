import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/lichess/cloud_eval/lichess_eval_repository.dart';
import 'package:chessever2/repository/local_storage/local_eval/local_eval_cache.dart';
import 'package:chessever2/repository/supabase/evals/evals_repository.dart';
import 'package:chessever2/repository/supabase/evals/persist_cloud_eval.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show FutureProvider;
import 'stockfish_singleton.dart';

/// Parameters for cascade eval with configurable multiPV and priority
class CascadeEvalParams {
  final String fen;
  final int multiPV;
  final bool isCurrentPosition; // Priority flag for user's currently viewed position
  
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
final cascadeEvalProvider = FutureProvider.family.autoDispose<CloudEval, CascadeEvalParams>((
  ref,
  params,
) async {
  final fen = params.fen;
  final multiPV = params.multiPV;
  final isCurrentPosition = params.isCurrentPosition;
  final local = ref.read(localEvalCacheProvider);
  final persist = ref.read(persistCloudEvalProvider);
  final lichess = ref.read(lichessEvalRepoProvider);
  try {
    if (fen.isEmpty) throw Exception('Empty FEN');

    // 1️⃣  Local cache
    final cached = await local.fetch(fen);
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
        .fetchFromSupabase(fen);
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
      local.save(fen, cloud).catchError((e) => null);
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
    Future.wait<void>([persist.call(fen, cloud), local.save(fen, cloud)])
        .catchError((e) => <void>[]);
    return cloud;
  } catch (_) {
    // Use progressive depth strategy here too
    final sfEval = await StockfishSingleton().evaluatePosition(
      fen,
      depth: 12,
      multiPV: multiPV,
      isCurrentPosition: isCurrentPosition,
    );
    final cloudFromSF = CloudEval(
      fen: fen,
      knodes: sfEval.knodes,
      depth: sfEval.depth,
      pvs: sfEval.pvs,
    );
    // Trigger background upgrade to depth 20
    _upgradeEvaluationInBackground(fen, persist, local, multiPV, isCurrentPosition);
    // OPTIMIZATION: Save to caches in background (unawaited)
    Future.wait<void>([
      persist.call(fen, cloudFromSF),
      local.save(fen, cloudFromSF),
    ]).catchError((e) => <void>[]);
    return cloudFromSF;
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
/// Respects Lichess API rate limits by querying sequentially
/// Uses autoDispose to cancel evaluations when switching games
final cascadeEvalProviderForBoard = FutureProvider.family.autoDispose<CloudEval, CascadeEvalParams>((
  ref,
  params,
) async {
  final fen = params.fen;
  final multiPV = params.multiPV;
  final isCurrentPosition = params.isCurrentPosition;
  final local = ref.read(localEvalCacheProvider);
  final persist = ref.read(persistCloudEvalProvider);
  final lichess = ref.read(lichessEvalRepoProvider);
  final evalsRepo = ref.read(evalsRepositoryProvider);

  try {
    if (fen.isEmpty) throw Exception('Empty FEN');

    // 1️⃣ Check local cache first (instant)
    final cached = await local.fetch(fen);
    if (cached != null && _isValidEvaluation(cached)) {
      final fenParts = fen.split(' ');
      final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
      final cp = cached.pvs.isNotEmpty ? cached.pvs.first.cp : 0;
      print("🔵 EVAL SOURCE: LOCAL CACHE (instant) - fen=$fen, side=$sideToMove, cp=$cp");
      return cached;
    }

    // 2️⃣ Query Supabase AND Lichess in parallel for maximum speed
    print('🚀 EVAL: Querying Supabase and Lichess in parallel for $fen');

    final supabaseFuture = evalsRepo
        .fetchFromSupabase(fen)
        .then((supabaseEval) {
          if (supabaseEval == null) return null;
          final cloud = evalsRepo.evalsToCloudEval(fen, supabaseEval);
          if (_isValidEvaluation(cloud)) {
            final fenParts = fen.split(' ');
            final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
            final cp = cloud.pvs.isNotEmpty ? cloud.pvs.first.cp : 0;
            print("🟡 EVAL SOURCE: SUPABASE - fen=$fen, side=$sideToMove, cp=$cp");
            // Background save to local cache
            local.save(fen, cloud).catchError((e) => null);
            return cloud;
          }
          return null;
        })
        .catchError((e) {
          print('Supabase eval failed: $e');
          return null;
        });

    final lichessFuture = lichess
        .getEval(fen, multiPv: multiPV)
        .then((cloud) {
          if (_isValidEvaluation(cloud)) {
            final fenParts = fen.split(' ');
            final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
            final cp = cloud.pvs.isNotEmpty ? cloud.pvs.first.cp : 0;
            print("🟢 EVAL SOURCE: LICHESS (${cloud.pvs.length} PVs) - fen=$fen, side=$sideToMove, cp=$cp");
            // Background save to both caches
            Future.wait<void>([
              persist.call(fen, cloud),
              local.save(fen, cloud),
            ]).catchError((e) => <void>[]);
            return cloud;
          }
          return null;
        })
        .catchError((e) {
          if (e is! NoEvalException) {
            print('Lichess eval failed: $e');
          }
          return null;
        });

    // Wait for both cloud sources to complete in parallel
    final results = await Future.wait([supabaseFuture, lichessFuture]);

    // Return first valid result (Supabase is first in array, so prioritized)
    for (final result in results) {
      if (result != null) return result;
    }

    // 3️⃣ FALLBACK: All cloud sources failed, use Stockfish with progressive depth
    // STRATEGY: Start with depth 12 for fast results with good move count, then upgrade to depth 20
    print('⚡ EVAL SOURCE: STOCKFISH FALLBACK (depth 12→20) for $fen');
    try {
      // QUICK EVAL: depth 12 gives fast results with 8-12 moves typically
      // NO TIMEOUT - respects user's search time settings from engine settings
      final sfEval = await StockfishSingleton().evaluatePosition(
        fen,
        depth: 12,
        multiPV: multiPV,
        isCurrentPosition: isCurrentPosition, // Prioritize current position
      );
      final quickCloudFromSF = CloudEval(
        fen: fen,
        knodes: sfEval.knodes,
        depth: sfEval.depth,
        pvs: sfEval.pvs,
      );
      
      print('✅ QUICK EVAL: Returning depth ${sfEval.depth} result with ${sfEval.pvs.first.moves.split(' ').length} moves');
      
      // BACKGROUND UPGRADE: Trigger deeper analysis (depth 20) for more moves & accuracy
      // This will cache the better result with 15-20+ moves per line
      _upgradeEvaluationInBackground(fen, persist, local, multiPV, isCurrentPosition);
      
      // Save quick result to cache (will be replaced by deeper eval)
      local.save(fen, quickCloudFromSF).catchError((e) => null);
      
      return quickCloudFromSF;
    } catch (e) {
      print('❌ Stockfish fallback failed for $fen: $e');
      rethrow;
    }
  } catch (error, _) {
    rethrow;
  }
});

/// Background helper to upgrade evaluation depth without blocking UI
void _upgradeEvaluationInBackground(
  String fen,
  PersistCloudEval persist,
  LocalEvalCache local,
  int multiPV,
  bool isCurrentPosition,
) {
  // Fire and forget - run deeper analysis in background
  Future.delayed(Duration.zero, () async {
    try {
      print('🔄 BACKGROUND UPGRADE: Starting depth 20 eval for $fen with $multiPV PVs');
      // NO TIMEOUT - respects user's search time settings from engine settings
      final deepEval = await StockfishSingleton().evaluatePosition(
        fen,
        depth: 20,
        multiPV: multiPV,
        isCurrentPosition: isCurrentPosition, // Maintain priority for background upgrade
      );
      
      final deepCloud = CloudEval(
        fen: fen,
        knodes: deepEval.knodes,
        depth: deepEval.depth,
        pvs: deepEval.pvs,
      );
      
      // Cache the improved result
      await Future.wait<void>([
        persist.call(fen, deepCloud),
        local.save(fen, deepCloud),
      ]);
      
      print('✅ BACKGROUND UPGRADE: Cached depth ${deepEval.depth} result with ${deepEval.pvs.first.moves.split(' ').length} moves');
    } catch (e) {
      print('⚠️ Background upgrade failed for $fen: $e');
      // Don't crash - quick eval is already showing
    }
  });
}
