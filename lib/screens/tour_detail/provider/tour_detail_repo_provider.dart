import 'dart:convert';

import 'package:chessever2/repository/sqlite/app_database.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

abstract interface class TourSelectionStore {
  Future<void> setString(String key, String value);

  Future<String?> getString(String key);

  Future<void> remove(String key);
}

class AppDatabaseTourSelectionStore implements TourSelectionStore {
  const AppDatabaseTourSelectionStore();

  @override
  Future<void> setString(String key, String value) =>
      AppDatabase.instance.setString(key, value);

  @override
  Future<String?> getString(String key) => AppDatabase.instance.getString(key);

  @override
  Future<void> remove(String key) => AppDatabase.instance.remove(key);
}

final tourSelectionStoreProvider = Provider<TourSelectionStore>((ref) {
  return const AppDatabaseTourSelectionStore();
});

/// App-scoped so the synchronous selection cache survives teardown and
/// recreation of [tourDetailScreenProvider].
final tourDetailRepoProvider = Provider<TourDetailRepo>((ref) {
  return TourDetailRepo(storage: ref.watch(tourSelectionStoreProvider));
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
  TourDetailRepo({
    TourSelectionStore storage = const AppDatabaseTourSelectionStore(),
    DateTime Function()? now,
  }) : _storage = storage,
       _now = now ?? DateTime.now;

  static const prefix = 'selected_tour_';

  final TourSelectionStore _storage;
  final DateTime Function() _now;
  final Map<String, PersistedTourSelection> _sessionSelections =
      <String, PersistedTourSelection>{};

  /// How long an explicit dropdown pick keeps overriding the default
  /// category-selection strategy. After this window the persisted
  /// selection is deleted and ignored.
  static const selectionTtl = Duration(hours: 12);

  String keyFor(String groupEventId) => '$prefix$groupEventId';

  Future<void> saveSelectedTourId({
    required String groupEventId,
    required String tourId,
  }) async {
    // Set this before the first await. The dropdown callback is intentionally
    // fire-and-forget, so a fast back/re-entry must not depend on Android disk
    // I/O having completed yet.
    final savedAt = _now().toUtc();
    _sessionSelections[groupEventId] = PersistedTourSelection(
      tourId: tourId,
      savedAt: savedAt,
    );
    await _storage.setString(
      keyFor(groupEventId),
      jsonEncode({'tourId': tourId, 'savedAt': savedAt.toIso8601String()}),
    );
  }

  /// Returns the user's explicit tour selection if it was saved within
  /// [selectionTtl]; otherwise deletes the stale entry and returns null.
  /// Legacy plain-string values (saved before timestamps existed) have an
  /// unknowable age and are treated as expired.
  Future<String?> getSelectedTourId(String groupEventId) async {
    final sessionSelection = _sessionSelections[groupEventId];
    if (sessionSelection != null) {
      if (isPersistedTourSelectionFresh(
        sessionSelection,
        now: _now().toUtc(),
      )) {
        return sessionSelection.tourId;
      }
      _sessionSelections.remove(groupEventId);
    }

    try {
      final raw = await _storage.getString(keyFor(groupEventId));
      final parsed = parsePersistedTourSelection(raw);
      if (parsed == null ||
          !isPersistedTourSelectionFresh(parsed, now: _now().toUtc())) {
        if (raw != null && raw.isNotEmpty) {
          await _storage.remove(keyFor(groupEventId));
        }
        return null;
      }
      _sessionSelections[groupEventId] = parsed;
      return parsed.tourId;
    } catch (_) {
      // Fresh session selections return before disk access. Without one, let
      // the caller use the normal default-selection strategy.
      return null;
    }
  }

  /// Optional: clear tourId for a given groupEventId
  Future<void> clearSelectedTourId(String groupEventId) async {
    _sessionSelections.remove(groupEventId);
    await _storage.remove(keyFor(groupEventId));
  }
}
