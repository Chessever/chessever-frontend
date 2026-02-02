import 'dart:convert';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final localEvalCacheProvider = AutoDisposeProvider<LocalEvalCache>(
  (ref) => LocalEvalCache(ref),
);

class LocalEvalCache {
  LocalEvalCache(this.ref);

  final Ref ref;

  static const _cacheKeyPrefix = 'cloud_eval_';
  static const _versionKey = 'cloud_eval_version';
  static const _currentVersion = 12; // v12: Migrated to SQLite
  static const _maxCacheSize = 500;

  Future<void> save(String fen, CloudEval eval, {int? multiPV}) async {
    try {
      final db = ref.read(appDatabaseProvider);

      // Check version and clear if outdated
      final storedVersion = await db.getInt(_versionKey) ?? 1;
      if (storedVersion < _currentVersion) {
        await _clearAll();
      }
      await db.setInt(_versionKey, _currentVersion);

      final effectiveMultiPv =
          (multiPV ?? eval.requestedMultiPv ?? eval.pvs.length).clamp(0, 5);
      final key = _buildKey(fen, effectiveMultiPv);
      await db.setCache(key: key, value: jsonEncode(eval.toJson()));

      // Also store legacy key so older readers (or callers without multiPV) still benefit
      if (effectiveMultiPv > 0) {
        final legacyKey = '$_cacheKeyPrefix$fen';
        await db.setCache(key: legacyKey, value: jsonEncode(eval.toJson()));
      }
    } catch (e) {
      // Cache failure is not critical
    }
  }

  Future<CloudEval?> fetch(String fen, {int? multiPV}) async {
    try {
      final db = ref.read(appDatabaseProvider);

      final storedVersion = await db.getInt(_versionKey) ?? 1;
      if (storedVersion < _currentVersion) {
        await _clearAll();
        await db.setInt(_versionKey, _currentVersion);
        return null;
      }

      final desired = (multiPV ?? 0);
      final keysToTry = <String>[];

      if (desired > 0) {
        for (int pv = desired; pv >= 1; pv--) {
          keysToTry.add(_buildKey(fen, pv));
        }
      }

      // Legacy fallbacks (no PV suffix)
      keysToTry.add('$_cacheKeyPrefix$fen');

      for (final key in keysToTry) {
        final entry = await db.getCache(key: key);
        if (entry == null) continue;

        try {
          final eval = CloudEval.fromJson(jsonDecode(entry.value));
          if (eval.pvs.isEmpty) continue;

          if (desired > 0) {
            if (eval.pvs.length < desired) {
              continue;
            }
            if (eval.pvs.length > desired) {
              final trimmed = CloudEval(
                fen: eval.fen,
                knodes: eval.knodes,
                depth: eval.depth,
                pvs: eval.pvs.take(desired).toList(growable: false),
                requestedMultiPv: desired,
              );
              return trimmed;
            }
            if (eval.requestedMultiPv != desired) {
              return CloudEval(
                fen: eval.fen,
                knodes: eval.knodes,
                depth: eval.depth,
                pvs: eval.pvs,
                requestedMultiPv: desired,
              );
            }
          }
          return eval.requestedMultiPv == null
              ? CloudEval(
                  fen: eval.fen,
                  knodes: eval.knodes,
                  depth: eval.depth,
                  pvs: eval.pvs,
                  requestedMultiPv: eval.pvs.length,
                )
              : eval;
        } catch (_) {
          // corrupted entry - skip it
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Batch fetch multiple evals at once - much faster than individual fetches
  Future<Map<String, CloudEval>> batchFetch(List<String> fens) async {
    final result = <String, CloudEval>{};
    if (fens.isEmpty) return result;

    try {
      final db = ref.read(appDatabaseProvider);

      final storedVersion = await db.getInt(_versionKey) ?? 1;
      if (storedVersion < _currentVersion) {
        await _clearAll();
        await db.setInt(_versionKey, _currentVersion);
        return result;
      }

      for (final fen in fens) {
        final entry = await db.getCache(key: _buildKey(fen, 0));
        if (entry != null) {
          try {
            result[fen] = CloudEval.fromJson(jsonDecode(entry.value));
          } catch (_) {
            // corrupted entry - skip it
          }
        }
      }
    } catch (e) {
      // Cache failure is not critical
    }

    return result;
  }

  Future<void> clear() async {
    await _clearAll();
    try {
      final db = ref.read(appDatabaseProvider);
      await db.setInt(_versionKey, _currentVersion);
    } catch (e) {
      // Cache failure is not critical
    }
  }

  Future<void> _clearAll() async {
    try {
      final db = ref.read(appDatabaseProvider);
      await db.clearCacheByPrefix(_cacheKeyPrefix);
    } catch (e) {
      // Cache failure is not critical
    }
  }

  String _buildKey(String fen, int multiPV) {
    if (multiPV <= 0) return '$_cacheKeyPrefix$fen';
    return '$_cacheKeyPrefix${fen}_pv$multiPV';
  }
}
