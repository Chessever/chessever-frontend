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
    // Validate input
    if (fen.isEmpty) {
      throw ArgumentError('FEN cannot be empty');
    }
    if (cloud.pvs.isEmpty) {
      throw ArgumentError('CloudEval must have at least one PV');
    }

    // Log what we're saving (CloudEval should already be in white's perspective from Lichess repo)
    final fenParts = fen.split(' ');
    final sideToMove = fenParts.length >= 2 ? fenParts[1] : 'w';
    final cp = cloud.pvs.isNotEmpty ? cloud.pvs.first.cp : 0;
    print("💾 SAVING TO SUPABASE: fen=$fen, side=$sideToMove, cp=$cp (should already be white's perspective)");

    return await _evalRepo.handleApiCall(() async {
      // All DB operations happen on the same client → implicit transaction
      final supabase = _evalRepo.supabase;

      // 1️⃣ positions row
      final position = await _posRepo.create(fen);
      final positionId = position.id;

      if (positionId == null) {
        throw StateError('Failed to create position record for FEN: $fen');
      }

      // 2️⃣ evals row - use upsert which handles existing records
      final eval = await _evalRepo.upsert(
        Evals(
          positionId: positionId,
          knodes: cloud.knodes,
          depth: cloud.depth,
          pvs: cloud.pvs.map((pv) => {'moves': pv.moves, 'cp': pv.cp, 'mate':pv.mate}).toList(),
        ),
      );

      // For existing records, the upsert returns the original eval without an id
      // Get the actual eval from the database to have the proper id
      if (eval.id == null) {
        final existingEvals = await _evalRepo.getByPositionId(positionId);
        if (existingEvals.isNotEmpty) {
          final existingEval = existingEvals.first;
          return existingEval; // Return existing eval, don't try to insert PVs again
        }
        throw StateError('Failed to create eval record for position: $positionId');
      }

      // 3️⃣ pvs rows - only insert if eval was created successfully
      final pvsRows =
          cloud.pvs.asMap().entries.map((e) {
            final idx = e.key;
            final pv = e.value;

            // Decide which column to populate based on mate flag and cp value
            int? cp;
            int? mate;

            if (pv.isMate && pv.mate != null) {
              // Use actual mate count from PV
              mate = pv.mate;
              cp = null; // Don't store cp for mate positions
            } else if (pv.cp.abs() >= 100_000) {
              // Fallback: derive mate from high cp value
              final derivedMate = pv.cp > 0 ?
                  (100000 - pv.cp.abs()) :
                  -(100000 - pv.cp.abs());
              mate = derivedMate;
              cp = null;
            } else {
              // Normal centipawn evaluation
              cp = pv.cp;
              mate = null;
            }

            return {
              'eval_id': eval.id!, // Safe to use ! since we validated above
              'idx': idx,
              'cp': cp,
              'mate': mate,
              'line': pv.moves.isNotEmpty ? pv.moves : 'no moves', // Ensure line is not empty
            };
          }).toList();

      // Insert PVs with error handling
      try {
        await supabase.from('pvs').insert(pvsRows);
      } catch (e) {
        // If PV insertion fails, we still return the eval
        // The eval data is more important than the detailed PV breakdown
        print('Warning: Failed to insert PV rows: $e');
      }

      return eval;
    });
  }
}
