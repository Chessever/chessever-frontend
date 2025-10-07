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

  /// Batch fetch evals for multiple FENs - much faster than individual fetches
  Future<Map<String, Evals>> batchFetchFromSupabase(List<String> fens) async {
    if (fens.isEmpty) return {};

    final result = <String, Evals>{};

    try {
      // Fetch all positions at once using IN clause
      final positions = await supabase
          .from('positions')
          .select()
          .inFilter('fen', fens);

      if (positions.isEmpty) return {};

      final positionIds = <int>[];
      final fenToPositionId = <String, int>{};

      for (final pos in positions) {
        final id = pos['id'] as int?;
        final fen = pos['fen'] as String?;
        if (id != null && fen != null) {
          positionIds.add(id);
          fenToPositionId[fen] = id;
        }
      }

      if (positionIds.isEmpty) return {};

      // Fetch all evals at once using IN clause
      final evalsData = await supabase
          .from('evals')
          .select()
          .inFilter('position_id', positionIds);

      // Group evals by position_id and take first (highest depth)
      final evalsByPositionId = <int, Evals>{};
      for (final evalJson in evalsData) {
        final eval = Evals.fromJson(evalJson);
        final posId = eval.positionId;

        if (!evalsByPositionId.containsKey(posId) ||
            evalsByPositionId[posId]!.depth < eval.depth) {
          evalsByPositionId[posId] = eval;
        }
      }

      // Map back to FENs
      for (final entry in fenToPositionId.entries) {
        final fen = entry.key;
        final posId = entry.value;
        if (evalsByPositionId.containsKey(posId)) {
          result[fen] = evalsByPositionId[posId]!;
        }
      }
    } catch (e) {
      print('❌ Batch fetch from Supabase failed: $e');
    }

    return result;
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
