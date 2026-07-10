import 'package:chessever2/screens/studies/data/study_bookmark.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum StudyBookmarkFailureKind {
  unauthenticated,
  conflict,
  invalid,
  unavailable,
}

final class StudyBookmarkException implements Exception {
  const StudyBookmarkException({
    required this.kind,
    required this.message,
    this.cause,
  });

  final StudyBookmarkFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => 'StudyBookmarkException(${kind.name}): $message';
}

abstract interface class StudyBookmarkBackend {
  String? get currentUserId;

  Future<List<Map<String, dynamic>>> fetchBookmarks({required int limit});

  Future<Map<String, dynamic>> saveBookmark(Map<String, dynamic> payload);

  Future<Map<String, dynamic>> saveProgress(Map<String, dynamic> payload);

  Future<void> deleteBookmark(String lichessStudyId);
}

final class SupabaseStudyBookmarkBackend implements StudyBookmarkBackend {
  const SupabaseStudyBookmarkBackend(this._client);

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<List<Map<String, dynamic>>> fetchBookmarks({
    required int limit,
  }) async {
    final userId = _requireUserId();
    final rows = await _client
        .from('user_study_bookmarks')
        .select(_bookmarkColumns)
        .eq('user_id', userId)
        .limit(limit);
    return rows.map(Map<String, dynamic>.from).toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> saveBookmark(
    Map<String, dynamic> payload,
  ) async {
    final userId = _requireUserId();
    final studyId = payload['lichess_study_id'] as String;
    await _client
        .from('user_study_bookmarks')
        .upsert(
          payload,
          onConflict: 'user_id,lichess_study_id',
          ignoreDuplicates: true,
          defaultToNull: false,
        );
    final row =
        await _client
            .from('user_study_bookmarks')
            .update(<String, dynamic>{
              'display_snapshot': payload['display_snapshot'],
            })
            .eq('user_id', userId)
            .eq('lichess_study_id', studyId)
            .select(_bookmarkColumns)
            .single();
    return Map<String, dynamic>.from(row);
  }

  @override
  Future<Map<String, dynamic>> saveProgress(
    Map<String, dynamic> payload,
  ) async {
    _requireUserId();
    final row =
        await _client
            .from('user_study_bookmarks')
            .upsert(
              payload,
              onConflict: 'user_id,lichess_study_id',
              defaultToNull: true,
            )
            .select(_bookmarkColumns)
            .single();
    return Map<String, dynamic>.from(row);
  }

  @override
  Future<void> deleteBookmark(String lichessStudyId) async {
    final userId = _requireUserId();
    await _client
        .from('user_study_bookmarks')
        .delete()
        .eq('user_id', userId)
        .eq('lichess_study_id', lichessStudyId);
  }

  String _requireUserId() {
    final userId = currentUserId;
    if (userId == null || userId.isEmpty) {
      throw const StudyBookmarkException(
        kind: StudyBookmarkFailureKind.unauthenticated,
        message: 'Sign in to save Studies.',
      );
    }
    return userId;
  }
}

abstract interface class StudyBookmarkStore {
  Future<List<StudyBookmarkReference>> fetch({
    int limit = kMaximumSavedStudyReferences,
  });

  Future<StudyBookmarkReference> bookmark({
    required String lichessStudyId,
    StudyBookmarkDisplaySnapshot snapshot,
  });

  Future<StudyBookmarkReference> upsertProgress({
    required String lichessStudyId,
    required String lichessChapterId,
    required int lastPly,
    String? contentVersion,
    StudyBookmarkDisplaySnapshot snapshot,
  });

  Future<void> unbookmark(String lichessStudyId);
}

final class StudyBookmarkRepository implements StudyBookmarkStore {
  const StudyBookmarkRepository(this._backend);

  final StudyBookmarkBackend _backend;

  @override
  Future<List<StudyBookmarkReference>> fetch({
    int limit = kMaximumSavedStudyReferences,
  }) async {
    if (limit < 1 || limit > kMaximumSavedStudyReferences) {
      throw RangeError.range(limit, 1, kMaximumSavedStudyReferences, 'limit');
    }
    final userId = _requireUserId();
    try {
      final rows = await _backend.fetchBookmarks(limit: limit);
      final references = rows
        .map((row) => decodeStudyBookmarkReference(row, userId: userId))
        .toList(growable: false)..sort(compareStudyBookmarkRecency);
      return List<StudyBookmarkReference>.unmodifiable(references);
    } on StudyBookmarkException {
      rethrow;
    } on PostgrestException catch (error) {
      throw mapStudyBookmarkPostgrestException(error);
    } on FormatException catch (error) {
      throw StudyBookmarkException(
        kind: StudyBookmarkFailureKind.invalid,
        message: 'Saved Study references contain invalid data.',
        cause: error,
      );
    } catch (error) {
      throw StudyBookmarkException(
        kind: StudyBookmarkFailureKind.unavailable,
        message: 'Saved Studies are unavailable right now.',
        cause: error,
      );
    }
  }

  @override
  Future<StudyBookmarkReference> bookmark({
    required String lichessStudyId,
    StudyBookmarkDisplaySnapshot snapshot =
        const StudyBookmarkDisplaySnapshot(),
  }) {
    return _upsert(lichessStudyId: lichessStudyId, snapshot: snapshot);
  }

  @override
  Future<StudyBookmarkReference> upsertProgress({
    required String lichessStudyId,
    required String lichessChapterId,
    required int lastPly,
    String? contentVersion,
    StudyBookmarkDisplaySnapshot snapshot =
        const StudyBookmarkDisplaySnapshot(),
  }) {
    if (lastPly < 0 || lastPly > 1000000) {
      throw RangeError.range(lastPly, 0, 1000000, 'lastPly');
    }
    return _upsert(
      lichessStudyId: lichessStudyId,
      lichessChapterId: lichessChapterId,
      lastPly: lastPly,
      contentVersion: contentVersion,
      snapshot: snapshot,
    );
  }

  Future<StudyBookmarkReference> _upsert({
    required String lichessStudyId,
    required StudyBookmarkDisplaySnapshot snapshot,
    String? lichessChapterId,
    int? lastPly,
    String? contentVersion,
  }) async {
    final userId = _requireUserId();
    final normalizedStudyId = normalizeLichessStudyId(lichessStudyId);
    final normalizedChapterId = normalizeLichessChapterId(lichessChapterId);
    final normalizedVersion = normalizeStudyContentVersion(contentVersion);
    final payload = <String, dynamic>{
      'user_id': userId,
      'lichess_study_id': normalizedStudyId,
      'display_snapshot': snapshot.toJson(),
      if (normalizedChapterId != null)
        'lichess_chapter_id': normalizedChapterId,
      if (lastPly != null) 'last_ply': lastPly,
      if (normalizedVersion != null) 'content_version': normalizedVersion,
    };
    try {
      final row =
          normalizedChapterId == null
              ? await _backend.saveBookmark(payload)
              : await _backend.saveProgress(payload);
      return decodeStudyBookmarkReference(row, userId: userId);
    } on StudyBookmarkException {
      rethrow;
    } on PostgrestException catch (error) {
      throw mapStudyBookmarkPostgrestException(error);
    } on FormatException catch (error) {
      throw StudyBookmarkException(
        kind: StudyBookmarkFailureKind.invalid,
        message: 'The saved Study response was invalid.',
        cause: error,
      );
    } catch (error) {
      throw StudyBookmarkException(
        kind: StudyBookmarkFailureKind.unavailable,
        message: 'The Study bookmark could not be saved.',
        cause: error,
      );
    }
  }

  @override
  Future<void> unbookmark(String lichessStudyId) async {
    _requireUserId();
    final normalizedStudyId = normalizeLichessStudyId(lichessStudyId);
    try {
      await _backend.deleteBookmark(normalizedStudyId);
    } on StudyBookmarkException {
      rethrow;
    } on PostgrestException catch (error) {
      throw mapStudyBookmarkPostgrestException(error);
    } catch (error) {
      throw StudyBookmarkException(
        kind: StudyBookmarkFailureKind.unavailable,
        message: 'The Study bookmark could not be removed.',
        cause: error,
      );
    }
  }

  String _requireUserId() {
    final userId = _backend.currentUserId;
    if (userId == null || userId.isEmpty) {
      throw const StudyBookmarkException(
        kind: StudyBookmarkFailureKind.unauthenticated,
        message: 'Sign in to use Saved Studies.',
      );
    }
    return userId;
  }
}

final studyBookmarkRepositoryProvider = Provider<StudyBookmarkStore>((ref) {
  return StudyBookmarkRepository(
    SupabaseStudyBookmarkBackend(Supabase.instance.client),
  );
});

StudyBookmarkReference decodeStudyBookmarkReference(
  Map<String, dynamic> row, {
  required String userId,
}) {
  final rowUserId = _requiredString(row['user_id'], 'user_id');
  if (rowUserId != userId) {
    throw const FormatException('Bookmark owner does not match the session.');
  }
  final studyId = normalizeLichessStudyId(
    _requiredString(row['lichess_study_id'], 'lichess_study_id'),
  );
  final chapterId = normalizeLichessChapterId(
    _optionalString(row['lichess_chapter_id'], 'lichess_chapter_id'),
  );
  final lastPly = _optionalInt(row['last_ply'], 'last_ply');
  if (lastPly != null && (lastPly < 0 || lastPly > 1000000)) {
    throw const FormatException('last_ply must be nonnegative.');
  }
  if ((chapterId == null) != (lastPly == null)) {
    throw const FormatException('Study progress fields must be paired.');
  }
  final progressUpdatedAt = _optionalDate(
    row['progress_updated_at'],
    'progress_updated_at',
  );
  if ((lastPly == null) != (progressUpdatedAt == null)) {
    throw const FormatException('Study progress timestamp is inconsistent.');
  }
  return StudyBookmarkReference(
    userId: rowUserId,
    lichessStudyId: studyId,
    lichessChapterId: chapterId,
    lastPly: lastPly,
    contentVersion: normalizeStudyContentVersion(
      _optionalString(row['content_version'], 'content_version'),
    ),
    displaySnapshot: StudyBookmarkDisplaySnapshot.fromJson(
      row['display_snapshot'],
    ),
    bookmarkedAt: _requiredDate(row['bookmarked_at'], 'bookmarked_at'),
    progressUpdatedAt: progressUpdatedAt,
    updatedAt: _requiredDate(row['updated_at'], 'updated_at'),
  );
}

int compareStudyBookmarkRecency(
  StudyBookmarkReference left,
  StudyBookmarkReference right,
) {
  final activity = right.recentActivityAt.compareTo(left.recentActivityAt);
  if (activity != 0) return activity;
  final bookmarked = right.bookmarkedAt.compareTo(left.bookmarkedAt);
  if (bookmarked != 0) return bookmarked;
  return left.lichessStudyId.compareTo(right.lichessStudyId);
}

StudyBookmarkException mapStudyBookmarkPostgrestException(
  PostgrestException error,
) {
  final signal =
      <Object?>[
        error.message,
        error.details,
        error.hint,
      ].whereType<Object>().join(' ').toUpperCase();
  if (error.code == '28000' ||
      error.code == '42501' ||
      signal.contains('JWT') ||
      signal.contains('AUTH')) {
    return StudyBookmarkException(
      kind: StudyBookmarkFailureKind.unauthenticated,
      message: 'Sign in to use Saved Studies.',
      cause: error,
    );
  }
  if (error.code == '23505' ||
      error.code == '40001' ||
      signal.contains('CONFLICT')) {
    return StudyBookmarkException(
      kind: StudyBookmarkFailureKind.conflict,
      message: 'Saved Studies changed elsewhere. Refresh and try again.',
      cause: error,
    );
  }
  if (error.code == '22001' || error.code == '22023' || error.code == '23514') {
    return StudyBookmarkException(
      kind: StudyBookmarkFailureKind.invalid,
      message: 'The Study bookmark is not valid.',
      cause: error,
    );
  }
  return StudyBookmarkException(
    kind: StudyBookmarkFailureKind.unavailable,
    message: 'Saved Studies are unavailable right now.',
    cause: error,
  );
}

const String _bookmarkColumns =
    'user_id, lichess_study_id, lichess_chapter_id, last_ply, '
    'content_version, display_snapshot, bookmarked_at, '
    'progress_updated_at, updated_at';

String _requiredString(Object? value, String field) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$field must be a non-empty string.');
  }
  return value.trim();
}

String? _optionalString(Object? value, String field) {
  if (value == null) return null;
  if (value is! String) throw FormatException('$field must be a string.');
  return value;
}

int? _optionalInt(Object? value, String field) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  throw FormatException('$field must be an integer.');
}

DateTime _requiredDate(Object? value, String field) {
  final parsed = _optionalDate(value, field);
  if (parsed == null) throw FormatException('$field must be a timestamp.');
  return parsed;
}

DateTime? _optionalDate(Object? value, String field) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toUtc();
  }
  throw FormatException('$field must be a timestamp.');
}
