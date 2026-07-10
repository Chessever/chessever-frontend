import 'package:chessever2/screens/studies/data/study_bookmark.dart';
import 'package:chessever2/screens/studies/data/study_bookmark_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _hash =
    'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  group('StudyBookmarkRepository', () {
    test('maps canonical bookmark and progress payloads', () async {
      final backend = _FakeBackend();
      final repository = StudyBookmarkRepository(backend);
      final snapshot = StudyBookmarkDisplaySnapshot.validated(
        title: 'Practical endings',
        authorUsername: 'author',
        attribution: 'Study by author on Lichess',
      );

      await repository.bookmark(lichessStudyId: 'AbCd0001', snapshot: snapshot);

      expect(backend.bookmarkPayload, <String, dynamic>{
        'user_id': 'user-1',
        'lichess_study_id': 'AbCd0001',
        'display_snapshot': <String, dynamic>{
          'title': 'Practical endings',
          'author_username': 'author',
          'attribution': 'Study by author on Lichess',
        },
      });

      await repository.upsertProgress(
        lichessStudyId: 'AbCd0001',
        lichessChapterId: 'Chapter9',
        lastPly: 42,
        contentVersion: _hash,
        snapshot: snapshot,
      );

      expect(backend.progressPayload, containsPair('last_ply', 42));
      expect(
        backend.progressPayload,
        containsPair('lichess_chapter_id', 'Chapter9'),
      );
      expect(backend.progressPayload, containsPair('content_version', _hash));
    });

    test('rejects noncanonical IDs and invented versions before I/O', () async {
      final backend = _FakeBackend();
      final repository = StudyBookmarkRepository(backend);

      await expectLater(
        repository.bookmark(lichessStudyId: 'not-a-study'),
        throwsArgumentError,
      );
      await expectLater(
        repository.upsertProgress(
          lichessStudyId: 'AbCd0001',
          lichessChapterId: 'Chapter9',
          lastPly: 1,
          contentVersion: 'version-one',
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.upsertProgress(
          lichessStudyId: 'AbCd0001',
          lichessChapterId: 'Chapter9',
          lastPly: 1,
          contentVersion:
              'sha256:ABCDEF6789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        ),
        throwsArgumentError,
      );

      expect(backend.writeCalls, 0);
    });

    test(
      'allows null content version for legacy or unknown metadata',
      () async {
        final backend = _FakeBackend();
        final repository = StudyBookmarkRepository(backend);

        await repository.upsertProgress(
          lichessStudyId: 'AbCd0001',
          lichessChapterId: 'Chapter9',
          lastPly: 7,
        );

        expect(backend.progressPayload, isNot(contains('content_version')));
      },
    );

    test('orders fetched rows by recent progress then bookmark time', () async {
      final backend = _FakeBackend(
        rows: <Map<String, dynamic>>[
          _row(id: 'AbCd0001', bookmarkedHour: 10),
          _row(
            id: 'AbCd0002',
            bookmarkedHour: 8,
            progressHour: 12,
            chapterId: 'Chapter2',
            lastPly: 18,
          ),
          _row(id: 'AbCd0003', bookmarkedHour: 11),
        ],
      );
      final repository = StudyBookmarkRepository(backend);

      final values = await repository.fetch();

      expect(values.map((value) => value.lichessStudyId), <String>[
        'AbCd0002',
        'AbCd0003',
        'AbCd0001',
      ]);
    });

    test('maps auth, conflict, invalid and unavailable failures safely', () {
      for (final entry in <(PostgrestException, StudyBookmarkFailureKind)>[
        (
          const PostgrestException(message: 'JWT expired', code: '28000'),
          StudyBookmarkFailureKind.unauthenticated,
        ),
        (
          const PostgrestException(message: 'conflict', code: '40001'),
          StudyBookmarkFailureKind.conflict,
        ),
        (
          const PostgrestException(message: 'check failed', code: '23514'),
          StudyBookmarkFailureKind.invalid,
        ),
        (
          const PostgrestException(message: 'offline', code: '50000'),
          StudyBookmarkFailureKind.unavailable,
        ),
      ]) {
        final mapped = mapStudyBookmarkPostgrestException(entry.$1);
        expect(mapped.kind, entry.$2);
        expect(mapped.toString(), isNot(contains('JWT expired')));
      }
    });

    test('rejects a row owned by a different authenticated user', () {
      expect(
        () => decodeStudyBookmarkReference(
          _row(id: 'AbCd0001', bookmarkedHour: 10)..['user_id'] = 'user-2',
          userId: 'user-1',
        ),
        throwsFormatException,
      );
    });
  });
}

final class _FakeBackend implements StudyBookmarkBackend {
  _FakeBackend({this.rows = const <Map<String, dynamic>>[]});

  final List<Map<String, dynamic>> rows;
  Map<String, dynamic>? bookmarkPayload;
  Map<String, dynamic>? progressPayload;

  int get writeCalls =>
      (bookmarkPayload == null ? 0 : 1) + (progressPayload == null ? 0 : 1);

  @override
  String? get currentUserId => 'user-1';

  @override
  Future<void> deleteBookmark(String lichessStudyId) async {}

  @override
  Future<List<Map<String, dynamic>>> fetchBookmarks({
    required int limit,
  }) async {
    return rows.take(limit).toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> saveBookmark(
    Map<String, dynamic> payload,
  ) async {
    bookmarkPayload = payload;
    return _row(id: payload['lichess_study_id'] as String, bookmarkedHour: 10)
      ..['display_snapshot'] = payload['display_snapshot'];
  }

  @override
  Future<Map<String, dynamic>> saveProgress(
    Map<String, dynamic> payload,
  ) async {
    progressPayload = payload;
    return _row(
        id: payload['lichess_study_id'] as String,
        bookmarkedHour: 10,
        progressHour: 11,
        chapterId: payload['lichess_chapter_id'] as String,
        lastPly: payload['last_ply'] as int,
      )
      ..['content_version'] = payload['content_version']
      ..['display_snapshot'] = payload['display_snapshot'];
  }
}

Map<String, dynamic> _row({
  required String id,
  required int bookmarkedHour,
  int? progressHour,
  String? chapterId,
  int? lastPly,
}) => <String, dynamic>{
  'user_id': 'user-1',
  'lichess_study_id': id,
  'lichess_chapter_id': chapterId,
  'last_ply': lastPly,
  'content_version': progressHour == null ? null : _hash,
  'display_snapshot': <String, dynamic>{'title': 'Saved $id'},
  'bookmarked_at':
      '2026-07-10T${bookmarkedHour.toString().padLeft(2, '0')}:00:00Z',
  'progress_updated_at':
      progressHour == null
          ? null
          : '2026-07-10T${progressHour.toString().padLeft(2, '0')}:00:00Z',
  'updated_at': '2026-07-10T13:00:00Z',
};
