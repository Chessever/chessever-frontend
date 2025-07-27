import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/lichess/cloud_eval/lichess_eval_repository.dart';
import 'package:chessever2/repository/local_storage/local_eval/local_eval_cache.dart';
import 'package:chessever2/repository/supabase/evals/evals_repository.dart';
import 'package:chessever2/repository/supabase/evals/persist_cloud_eval.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' show FutureProvider;

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
        .evalsToCloudEval(
          fen,
          supabaseEval,
        );
    await local.save(fen, cloud); // keep local in sync
    return cloud;
  }

  // 3️⃣  Lichess → Supabase → local
  final cloud = await lichess.getEval(fen);
  await persist.call(fen, cloud); // writes positions, evals, pvs
  await local.save(fen, cloud); // local cache
  return cloud;
});
