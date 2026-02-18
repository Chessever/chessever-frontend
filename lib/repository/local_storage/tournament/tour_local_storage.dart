import 'dart:convert';
import 'dart:async';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tourLocalStorageProvider = Provider<_TourLocalStorage>(
  (ref) => _TourLocalStorage(ref),
);

class _TourLocalStorage {
  _TourLocalStorage(this.ref);

  final Ref ref;

  String _getCacheKey(String groupId) => 'tour_$groupId';

  Future<List<Tour>> fetchAndSaveTournament(String groupId) async {
    final tours = await ref
        .read(tourRepositoryProvider)
        .getTourByGroupId(groupId);
    unawaited(_saveToursToCache(groupId, tours));
    return tours;
  }

  Future<List<Tour>> getToursBasedOnGroupId(String groupId) async {
    try {
      // Supabase is the source of truth; SQLite stays fallback-only.
      return await fetchAndSaveTournament(groupId);
    } catch (e) {
      return _getCachedTours(groupId);
    }
  }

  Future<List<Tour>> getTours(String groupId) async {
    try {
      return ref.read(tourRepositoryProvider).getTourByGroupId(groupId);
    } catch (e, _) {
      return _getCachedTours(groupId);
    }
  }

  Future<void> _saveToursToCache(String groupId, List<Tour> tours) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final encoded = tours.map((t) => json.encode(t.toJson())).toList();
      await db.setCache(key: _getCacheKey(groupId), value: jsonEncode(encoded));
    } catch (_) {
      // Local storage failure is not critical - Supabase is source of truth
    }
  }

  Future<List<Tour>> _getCachedTours(String groupId) async {
    try {
      final db = ref.read(appDatabaseProvider);
      final entry = await db.getCache(key: _getCacheKey(groupId));
      if (entry == null) return <Tour>[];

      final jsonList = jsonDecode(entry.value) as List;
      return jsonList
          .map((e) => Tour.fromJson(json.decode(e as String)))
          .toList();
    } catch (_) {
      return <Tour>[];
    }
  }
}
