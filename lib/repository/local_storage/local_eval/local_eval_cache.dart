import 'dart:convert';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final localEvalCacheProvider = AutoDisposeProvider<LocalEvalCache>(
  (_) => LocalEvalCache(),
);

class LocalEvalCache {
  static const _prefix = 'cloud_eval_';

  Future<void> save(String fen, CloudEval eval) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$fen', jsonEncode(eval.toJson()));
  }

  Future<CloudEval?> fetch(String fen) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$fen');
    if (raw == null) return null;
    try {
      return CloudEval.fromJson(jsonDecode(raw));
    } catch (_) {
      return null; // corrupted entry → pretend we don't have it
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
    for (final k in keys) {
      await prefs.remove(k);
    }
  }
}
