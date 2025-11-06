import 'dart:convert';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final localEvalCacheProvider = AutoDisposeProvider<LocalEvalCache>(
  (_) => LocalEvalCache(),
);

class LocalEvalCache {
  static const _prefix = 'cloud_eval_';
  static const _versionKey = 'cloud_eval_version';
  static const _currentVersion = 6; // Bumped: Clear cache missing multiPV in key

  Future<void> save(String fen, CloudEval eval, {int? multiPV}) async {
    final prefs = await SharedPreferences.getInstance();
    final storedVersion = prefs.getInt(_versionKey) ?? 1;
    if (storedVersion < _currentVersion) {
      await _clearWithPrefs(prefs);
    }
    await prefs.setInt(_versionKey, _currentVersion);
    
    // Include multiPV in cache key to avoid wrong PV count collision
    final key = multiPV != null && multiPV > 0
        ? '$_prefix${fen}_pv$multiPV'
        : '$_prefix$fen';
    await prefs.setString(key, jsonEncode(eval.toJson()));
  }

  Future<CloudEval?> fetch(String fen, {int? multiPV}) async {
    final prefs = await SharedPreferences.getInstance();
    final storedVersion = prefs.getInt(_versionKey) ?? 1;
    if (storedVersion < _currentVersion) {
      await _clearWithPrefs(prefs);
      await prefs.setInt(_versionKey, _currentVersion);
      return null;
    }

    // Include multiPV in cache key to fetch correct PV count
    final key = multiPV != null && multiPV > 0
        ? '$_prefix${fen}_pv$multiPV'
        : '$_prefix$fen';
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return CloudEval.fromJson(jsonDecode(raw));
    } catch (_) {
      return null; // corrupted entry → pretend we don't have it
    }
  }

  /// Batch fetch multiple evals at once - much faster than individual fetches
  Future<Map<String, CloudEval>> batchFetch(List<String> fens) async {
    final result = <String, CloudEval>{};
    if (fens.isEmpty) return result;

    final prefs = await SharedPreferences.getInstance();
    final storedVersion = prefs.getInt(_versionKey) ?? 1;
    if (storedVersion < _currentVersion) {
      await _clearWithPrefs(prefs);
      await prefs.setInt(_versionKey, _currentVersion);
      return result;
    }

    for (final fen in fens) {
      final raw = prefs.getString('$_prefix$fen');
      if (raw != null) {
        try {
          result[fen] = CloudEval.fromJson(jsonDecode(raw));
        } catch (_) {
          // corrupted entry → skip it
        }
      }
    }

    return result;
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await _clearWithPrefs(prefs);
    await prefs.setInt(_versionKey, _currentVersion);
  }

  Future<void> _clearWithPrefs(SharedPreferences prefs) async {
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final k in keys) {
      await prefs.remove(k);
    }
  }
}
