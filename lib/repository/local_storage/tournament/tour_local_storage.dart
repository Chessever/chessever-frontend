import 'dart:convert';

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

  Future<void> fetchAndSaveTournament(String groupId) async {
    try {
      final tours = await ref
          .read(tourRepositoryProvider)
          .getTourByGroupId(groupId);

      final db = ref.read(appDatabaseProvider);
      final encoded = tours.map((t) => json.encode(t.toJson())).toList();
      await db.setCache(key: _getCacheKey(groupId), value: jsonEncode(encoded));
    } catch (error, _) {
      // Local storage failure is not critical - Supabase is source of truth
    }
  }

  Future<List<Tour>> getToursBasedOnGroupId(String groupId) async {
    try {
      await fetchAndSaveTournament(groupId);
      final db = ref.read(appDatabaseProvider);
      final entry = await db.getCache(key: _getCacheKey(groupId));

      if (entry == null) return <Tour>[];

      final jsonList = jsonDecode(entry.value) as List;
      return jsonList
          .map((e) => Tour.fromJson(json.decode(e as String)))
          .toList();
    } catch (e) {
      return <Tour>[];
    }
  }

  Future<List<Tour>> getTours(String groupId) async {
    try {
      return ref.read(tourRepositoryProvider).getTourByGroupId(groupId);
    } catch (e, _) {
      return <Tour>[];
    }
  }
}
