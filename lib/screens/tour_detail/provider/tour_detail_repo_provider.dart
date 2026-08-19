import 'dart:convert';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final tourDetailRepoProvider = AutoDisposeProvider<TourDetailRepo>((ref) {
  return TourDetailRepo();
});

class PersistedTourSelection {
  const PersistedTourSelection({required this.tourId, required this.savedAt});

  final String tourId;
  final DateTime savedAt;
}

/// Parses the SQLite payload written by [TourDetailRepo.saveSelectedTourId].
///
/// Returns null for empty, legacy plain-string, or otherwise unreadable
/// values. Those are treated as expired by the repo layer.
PersistedTourSelection? parsePersistedTourSelection(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    final tourId = map['tourId'] as String?;
    final savedAtRaw = map['savedAt'];
    final savedAt = savedAtRaw is String ? DateTime.tryParse(savedAtRaw) : null;
    if (tourId == null || tourId.isEmpty || savedAt == null) return null;
    return PersistedTourSelection(tourId: tourId, savedAt: savedAt);
  } catch (_) {
    return null;
  }
}

bool isPersistedTourSelectionFresh(
  PersistedTourSelection selection, {
  DateTime? now,
  Duration ttl = TourDetailRepo.selectionTtl,
}) {
  final current = now ?? DateTime.now().toUtc();
  return current.difference(selection.savedAt.toUtc()) <= ttl;
}

class TourDetailRepo {
  static const prefix = 'selected_tour_';

  /// How long an explicit dropdown pick keeps overriding the default
  /// category-selection strategy. After this window the persisted
  /// selection is deleted and ignored.
  static const selectionTtl = Duration(hours: 12);

  String keyFor(String groupEventId) => '$prefix$groupEventId';

  Future<void> saveSelectedTourId({
    required String groupEventId,
    required String tourId,
  }) async {
    final db = AppDatabase.instance;
    await db.setString(
      keyFor(groupEventId),
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
    final raw = await db.getString(keyFor(groupEventId));
    final parsed = parsePersistedTourSelection(raw);
    if (parsed == null || !isPersistedTourSelectionFresh(parsed)) {
      if (raw != null && raw.isNotEmpty) {
        await clearSelectedTourId(groupEventId);
      }
      return null;
    }
    return parsed.tourId;
  }

  /// Optional: clear tourId for a given groupEventId
  Future<void> clearSelectedTourId(String groupEventId) async {
    final db = AppDatabase.instance;
    await db.remove(keyFor(groupEventId));
  }
}
