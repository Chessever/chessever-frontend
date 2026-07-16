import 'dart:convert';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tourDetailRepoProvider = AutoDisposeProvider<_TourDetailRepo>((ref) {
  return _TourDetailRepo();
});

class _TourDetailRepo {
  static const _prefix = 'selected_tour_';

  /// How long an explicit dropdown pick keeps overriding the default
  /// category-selection strategy. After this window the persisted
  /// selection is deleted and ignored.
  static const selectionTtl = Duration(hours: 12);

  Future<void> saveSelectedTourId({
    required String groupEventId,
    required String tourId,
  }) async {
    final db = AppDatabase.instance;
    await db.setString(
      '$_prefix$groupEventId',
      jsonEncode({
        'tourId': tourId,
        'savedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  /// Returns the user's explicit tour selection if it was saved within
  /// [selectionTtl]; otherwise deletes the stale entry and returns null.
  /// Legacy plain-string values (saved before timestamps existed) have an
  /// unknowable age and are treated as expired.
  Future<String?> getSelectedTourId(String groupEventId) async {
    final db = AppDatabase.instance;
    final raw = await db.getString('$_prefix$groupEventId');
    if (raw == null || raw.isEmpty) {
      return null;
    }

    String? tourId;
    DateTime? savedAt;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        tourId = decoded['tourId'] as String?;
        final savedAtRaw = decoded['savedAt'];
        if (savedAtRaw is String) {
          savedAt = DateTime.tryParse(savedAtRaw);
        }
      }
    } catch (_) {
      // Not JSON — legacy value handled below.
    }

    final isExpired =
        tourId == null ||
        tourId.isEmpty ||
        savedAt == null ||
        DateTime.now().toUtc().difference(savedAt.toUtc()) > selectionTtl;

    if (isExpired) {
      await clearSelectedTourId(groupEventId);
      return null;
    }
    return tourId;
  }

  /// Optional: clear tourId for a given groupEventId
  Future<void> clearSelectedTourId(String groupEventId) async {
    final db = AppDatabase.instance;
    await db.remove('$_prefix$groupEventId');
  }
}
