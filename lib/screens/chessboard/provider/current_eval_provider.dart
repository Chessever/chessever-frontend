import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/lichess/cloud_eval/lichess_eval_repository.dart';
import 'package:chessever2/repository/local_storage/local_eval/local_eval_cache.dart';
import 'package:chessever2/repository/supabase/evals/evals_repository.dart';
import 'package:chessever2/repository/supabase/evals/persist_cloud_eval.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show FutureProvider;
import 'stockfish_singleton.dart';

/// 1. local → 2. Supabase → 3. lichess
final cascadeEvalProvider = FutureProvider.family<CloudEval, String>((
  ref,
  fen,
) async {
  if (fen.isEmpty) throw Exception('Empty FEN');

  final local = ref.read(localEvalCacheProvider);
  final persist = ref.read(persistCloudEvalProvider);
  final lichess = ref.read(lichessEvalRepoProvider);

  // 1️⃣  Local cache
  final cached = await local.fetch(fen);
  if (cached != null) return cached;

  // 2️⃣  Supabase
  final supabaseEval = await ref
      .read(evalsRepositoryProvider)
      .fetchFromSupabase(fen);
  if (supabaseEval != null) {
    final cloud = await ref
        .read(evalsRepositoryProvider)
        .evalsToCloudEval(fen, supabaseEval);
    await local.save(fen, cloud); // keep local in sync
    return cloud;
  }

  // 3️⃣  Lichess → Supabase → local

  try {
    final cloud = await lichess.getEval(fen);
    Future.wait<void>([persist.call(fen, cloud), local.save(fen, cloud)]);
    return cloud;
  } on NoEvalException catch (_) {
    final sfEval = await StockfishSingleton().evaluatePosition(fen, depth: 15);
    final cloudFromSF = CloudEval(
      fen: fen,
      knodes: sfEval.knodes,
      depth: sfEval.depth,
      pvs: sfEval.pvs,
    );
    Future.wait<void>([
      persist.call(fen, cloudFromSF),
      local.save(fen, cloudFromSF),
    ]);
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

/// local → 2. Supabase → 3. lichess -> 4. Fallback -> Local Stockfish
final cascadeEvalProviderForBoard = FutureProvider.family<CloudEval, String>((
  ref,
  fen,
) async {
  final local = ref.read(localEvalCacheProvider);
  final persist = ref.read(persistCloudEvalProvider);
  final lichess = ref.read(lichessEvalRepoProvider);
  try {
    if (fen.isEmpty) throw Exception('Empty FEN');

    // 1️⃣  Local cache
    final cached = await local.fetch(fen);
    if (cached != null && _isValidEvaluation(cached)) {
      return cached;
    }

    // 2️⃣  Supabase
    final supabaseEval = await ref
        .read(evalsRepositoryProvider)
        .fetchFromSupabase(fen);
    if (supabaseEval != null) {
      final cloud = await ref
          .read(evalsRepositoryProvider)
          .evalsToCloudEval(fen, supabaseEval);

      // Validate the evaluation - if it's suspicious, skip and try next source
      if (_isValidEvaluation(cloud)) {
        await local.save(fen, cloud); // keep local in sync
        return cloud;
      } else {
        print(
          'Supabase eval invalid for $fen: cp=${cloud.pvs.first.cp}, moves=${cloud.pvs.first.moves}',
        );
      }
    }

    // 3️⃣  Lichess → Supabase → local
    try {
      final cloud = await lichess.getEval(fen);
      if (_isValidEvaluation(cloud)) {
        // Don't await this - let it run in background
        Future.wait<void>([
          persist.call(fen, cloud), // writes positions, evals, pvs
          local.save(fen, cloud), // local cache
        ]).catchError((e) {
          print('Background save failed for $fen: $e');
          return <void>[];
        });
        return cloud;
      } else {
        print('Lichess eval invalid for $fen: cp=${cloud.pvs.first.cp}');
      }
    } on NoEvalException catch (_) {
      print('No evaluation available on Lichess for $fen, will try Stockfish fallback');
      // Continue to Stockfish fallback - don't return here
    } catch (lichessError) {
      print('Lichess eval failed for $fen: $lichessError');
      // Continue to fallback - don't return here
    }

    // 4️⃣  If all else fails, throw to trigger local Stockfish fallback
    throw Exception(
      'All cloud evaluation sources failed or returned invalid data for $fen',
    );
  } catch (error, _) {
    rethrow;
  }
});
