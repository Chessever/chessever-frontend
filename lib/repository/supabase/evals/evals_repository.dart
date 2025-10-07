import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/supabase/base_repository.dart';
import 'package:chessever2/repository/supabase/evals/evals.dart';
import 'package:chessever2/repository/supabase/position/position_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final evalsRepositoryProvider = AutoDisposeProvider<EvalRepository>(
  (ref) => EvalRepository(ref),
);

class EvalRepository extends BaseRepository {
  EvalRepository(this.ref);

  final ref;

  Future<Evals> upsert(Evals eval) => handleApiCall(() async {
    final existingRecord = await supabase
        .from('evals')
        .select()
        .eq('position_id', eval.positionId)
        .eq('depth', eval.depth)
        .maybeSingle();

    if (existingRecord != null) {
      final id = existingRecord['id'] as int?;
      if (id != null) {
        final updatePayload = {
          'knodes': eval.knodes,
          'depth': eval.depth,
          'pvs': eval.pvs,
        };
        final updated = await supabase
            .from('evals')
            .update(updatePayload)
            .eq('id', id)
            .select()
            .single();
        print('Eval record updated for position ${eval.positionId} (id=$id)');
        return Evals.fromJson(updated);
      }
      print('Eval record exists without id for position ${eval.positionId}, reusing existing data');
      return Evals.fromJson(Map<String, dynamic>.from(existingRecord));
    }

    final payload = eval.toJson();
    final newData =
        await supabase.from('evals').insert(payload).select().single();
    return Evals.fromJson(newData);
  });

  Future<Evals?> getById(int id) => handleApiCall(() async {
    final data =
        await supabase.from('evals').select().eq('id', id).maybeSingle();
    return data != null ? Evals.fromJson(data) : null;
  });

  Future<List<Evals>> getByPositionId(int positionId) =>
      handleApiCall(() async {
        final data = await supabase
            .from('evals')
            .select()
            .eq('position_id', positionId);
        return data.map<Evals>((json) => Evals.fromJson(json)).toList();
      });

  Future<Evals?> fetchFromSupabase(String fen) async {
    final posRepo = ref.read(positionRepositoryProvider);

    final pos = await posRepo.getByFen(fen);
    if (pos == null) return null;

    final evals = await getByPositionId(pos.id);
    if (evals.isEmpty) return null;

    return evals.first;
  }

  CloudEval evalsToCloudEval(String fen, Evals eval) {
    final fenParts = fen.split(' ');
    final isBlackToMove = fenParts.length >= 2 && fenParts[1] == 'b';

    bool legacyPerspective = false;

    final pvsList = <Pv>[];
    for (final entry in (eval.pvs as List)) {
      final map = Map<String, dynamic>.from(entry as Map);
      final hasPerspectiveKey = map.containsKey('whitePerspective');

      final moves = (map['moves'] as String?) ?? '';

      int cp = 0;
      bool isMate = false;
      int? mate;

      final dynamic mateValue = map['mate'];
      if (mateValue != null) {
        final parsedMate = int.tryParse(mateValue.toString());
        if (parsedMate != null) {
          mate = parsedMate;
          isMate = true;
          cp = parsedMate.sign * 100000;
        }
      }

      if (!isMate) {
        final dynamic cpValue = map['cp'];
        if (cpValue is int) {
          cp = cpValue;
        } else if (cpValue != null) {
          cp = int.tryParse(cpValue.toString()) ?? 0;
        }
      }

      bool whitePerspective = (map['whitePerspective'] as bool?) ?? false;

      if (!whitePerspective && !hasPerspectiveKey) {
        legacyPerspective = true;
        whitePerspective = true;
        if (isBlackToMove) {
          cp = -cp;
          if (mate != null) mate = -mate;
        }
      } else if (!whitePerspective) {
        // Stored from black's perspective explicitly - normalize
        whitePerspective = true;
        cp = -cp;
        if (mate != null) mate = -mate;
      }

      pvsList.add(
        Pv(
          moves: moves,
          cp: cp,
          isMate: isMate,
          mate: mate,
          whitePerspective: whitePerspective,
        ),
      );
    }

    if (legacyPerspective) {
      print('🔧 SUPABASE: Normalized legacy evaluation for $fen to white perspective');
    }

    return CloudEval(
      fen: fen,
      knodes: eval.knodes,
      depth: eval.depth,
      pvs: pvsList,
    );
  }

  Future<void> delete(int id) =>
      handleApiCall(() => supabase.from('evals').delete().eq('id', id));
}
