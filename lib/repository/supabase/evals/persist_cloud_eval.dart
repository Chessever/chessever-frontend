import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/supabase/evals/evals.dart';
import 'package:chessever2/repository/supabase/evals/evals_repository.dart';
import 'package:chessever2/repository/supabase/position/position_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final persistCloudEvalProvider = AutoDisposeProvider<PersistCloudEval>((ref) {
  return PersistCloudEval(
    posRepo: ref.read(positionRepositoryProvider),
    evalsRepo: ref.read(evalsRepositoryProvider),
  );
});

class PersistCloudEval {
  final PositionRepository _posRepo;
  final EvalRepository _evalRepo;

  PersistCloudEval({
    required PositionRepository posRepo,
    required EvalRepository evalsRepo,
  }) : _posRepo = posRepo,
       _evalRepo = evalsRepo;

  /// Persists CloudEval into the existing tables.
  Future<Evals> call(String fen, CloudEval cloud) async {
    return await _evalRepo.handleApiCall(() async {
      // All DB operations happen on the same client → implicit transaction
      final supabase = _evalRepo.supabase;

      // 1️⃣ positions row
      final position = await _posRepo.create(fen);
      final positionId = position.id;

      // 2️⃣ evals row
      final eval = await _evalRepo.upsert(
        Evals(
          positionId: positionId,
          knodes: cloud.knodes,
          depth: cloud.depth,
          pvs: cloud.pvs.map((pv) => {'moves': pv.moves, 'cp': pv.cp, 'mate':pv.mate}).toList(),
        ),
      );

      // 3️⃣ pvs rows
      final pvsRows =
          cloud.pvs.asMap().entries.map((e) {
            final idx = e.key;
            final pv = e.value;

            // decide which column to populate
            final cp = pv.cp.abs() < 100_000 ? pv.cp : null;
            final mate =
                pv.cp.abs() >= 100_000 ? (pv.cp / 100_000).round() : null;

            return {
              'eval_id': eval.id,
              'idx': idx,
              'cp': cp,
              'mate': mate,
              'line': pv.moves,
            };
          }).toList();

      await supabase.from('pvs').insert(pvsRows);
      return eval;
    });
  }
}
