import 'dart:async';
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

  /// Prevents concurrent version check/clear operations
  static Completer<void>? _versionCheckCompleter;
  static bool _versionVerified = false;

  /// Ensures version is checked and cache cleared if needed (only once per session)
  Future<void> _ensureVersionChecked() async {
    // Fast path: already verified this session
    if (_versionVerified) return;

    // If another operation is already checking version, wait for it
    if (_versionCheckCompleter != null) {
      await _versionCheckCompleter!.future;
      return;
    }

    // We're the first - create completer and do the check
    _versionCheckCompleter = Completer<void>();
    try {
      final db = ref.read(appDatabaseProvider);
      final storedVersion = await db.getInt(_versionKey) ?? 1;
      if (storedVersion < _currentVersion) {
        // Clear old cache and set new version in a single transaction
        await db.clearCacheByPrefix(_cacheKeyPrefix);
        await db.setInt(_versionKey, _currentVersion);
      }
      _versionVerified = true;
      _versionCheckCompleter!.complete();
    } catch (e) {
      _versionCheckCompleter!.completeError(e);
      rethrow;
    } finally {
      _versionCheckCompleter = null;
    }
  }

  Future<void> save(String fen, CloudEval eval, {int? multiPV}) async {
    try {
      // Single synchronized version check
      await _ensureVersionChecked();

      final db = ref.read(appDatabaseProvider);

      final effectiveMultiPv =
          (multiPV ?? eval.requestedMultiPv ?? eval.pvs.length).clamp(0, 5);
      final key = _buildKey(fen, effectiveMultiPv);
      final jsonValue = jsonEncode(eval.toJson());

      // Batch both writes (main key + legacy key) in a single transaction
      final entries = <String, String>{key: jsonValue};
      if (effectiveMultiPv > 0) {
        entries['$_cacheKeyPrefix$fen'] = jsonValue;
      }
      await db.setCacheBatch(entries);
    } catch (e) {
      // Cache failure is not critical
    }
  }

  Future<CloudEval?> fetch(String fen, {int? multiPV}) async {
    try {
      // Single synchronized version check
      await _ensureVersionChecked();

      final db = ref.read(appDatabaseProvider);

      final desired = (multiPV ?? 0);
      final keysToTry = <String>[];

      if (desired > 0) {
        for (int pv = desired; pv >= 1; pv--) {
          keysToTry.add(_buildKey(fen, pv));
        }
      }

      // Legacy fallbacks (no PV suffix)
      keysToTry.add('$_cacheKeyPrefix$fen');

      // Single SQL query for all candidate keys instead of N sequential reads
      final entries = await db.getCacheMulti(keys: keysToTry);

      // Iterate in priority order (highest PV first)
      for (final key in keysToTry) {
        final entry = entries[key];
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

  /// Batch fetch multiple evals at once — single SQL query instead of N reads
  Future<Map<String, CloudEval>> batchFetch(List<String> fens) async {
    final result = <String, CloudEval>{};
    if (fens.isEmpty) return result;

    try {
      // Single synchronized version check
      await _ensureVersionChecked();

      final db = ref.read(appDatabaseProvider);

      final keys = fens.map((fen) => _buildKey(fen, 0)).toList();
      final entries = await db.getCacheMulti(keys: keys);

      for (final fen in fens) {
        final entry = entries[_buildKey(fen, 0)];
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
    _versionVerified = false; // Reset so next access re-checks version
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
