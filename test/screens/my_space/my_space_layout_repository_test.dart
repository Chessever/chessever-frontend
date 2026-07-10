import 'package:chessever2/screens/my_space/data/my_space_layout_repository.dart';
import 'package:chessever2/screens/my_space/domain/my_space_layout.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'decodes a versioned stored row without trusting redundant user input',
    () {
      final stored = decodeMySpaceStoredLayout(_row());

      expect(stored.userId, 'user-1');
      expect(stored.revision, 3);
      expect(stored.layout, MySpaceLayout.curatedDefault);
      expect(stored.createdAt, DateTime.utc(2026, 7, 10, 8));
      expect(stored.updatedAt, DateTime.utc(2026, 7, 10, 9));
    },
  );

  test('fetch returns null when the owner has no saved layout', () async {
    final backend = _FakeBackend(fetchRow: null);
    final repository = MySpaceLayoutRepository(backend);

    expect(await repository.fetch(), isNull);
    expect(backend.fetchCalls, 1);
  });

  test('save validates locally and forwards optimistic revision', () async {
    final backend = _FakeBackend(fetchRow: null, saveRow: _row(revision: 4));
    final repository = MySpaceLayoutRepository(backend);

    final stored = await repository.save(
      layout: MySpaceLayout.curatedDefault,
      expectedRevision: 3,
    );

    expect(stored.revision, 4);
    expect(backend.expectedRevision, 3);
    expect(backend.savedLayout, MySpaceLayout.curatedDefault.toJson());
  });

  test('invalid local revisions never reach the backend', () async {
    final backend = _FakeBackend(fetchRow: null, saveRow: _row());
    final repository = MySpaceLayoutRepository(backend);

    await expectLater(
      repository.save(
        layout: MySpaceLayout.curatedDefault,
        expectedRevision: -1,
      ),
      throwsArgumentError,
    );
    expect(backend.saveCalls, 0);
  });

  test('maps server authority and concurrency failures to typed kinds', () {
    for (final entry in <(PostgrestException, MySpaceLayoutFailureKind)>[
      (
        const PostgrestException(
          message: 'MY_SPACE_LAYOUT_UNAUTHENTICATED',
          code: '28000',
        ),
        MySpaceLayoutFailureKind.unauthenticated,
      ),
      (
        const PostgrestException(
          message: 'MY_SPACE_LAYOUT_PREMIUM_REQUIRED',
          code: '42501',
        ),
        MySpaceLayoutFailureKind.premiumRequired,
      ),
      (
        const PostgrestException(
          message: 'MY_SPACE_LAYOUT_REVISION_CONFLICT',
          code: '40001',
        ),
        MySpaceLayoutFailureKind.revisionConflict,
      ),
      (
        const PostgrestException(
          message: 'MY_SPACE_LAYOUT_INVALID_DOCUMENT',
          code: '22023',
        ),
        MySpaceLayoutFailureKind.invalidDocument,
      ),
    ]) {
      expect(mapMySpacePostgrestException(entry.$1).kind, entry.$2);
    }
  });

  test('rejects malformed or unsupported stored rows', () {
    expect(
      () => decodeMySpaceStoredLayout(_row(revision: 0)),
      throwsFormatException,
    );
    expect(
      () => decodeMySpaceStoredLayout({..._row(), 'schema_version': 99}),
      throwsFormatException,
    );
  });
}

Map<String, dynamic> _row({int revision = 3}) => {
  'user_id': 'user-1',
  'schema_version': MySpaceLayout.currentSchemaVersion,
  'revision': revision,
  'shelves': MySpaceLayout.curatedDefault.toJson()['shelves'],
  'created_at': '2026-07-10T08:00:00.000Z',
  'updated_at': '2026-07-10T09:00:00.000Z',
};

final class _FakeBackend implements MySpaceLayoutBackend {
  _FakeBackend({required this.fetchRow, this.saveRow});

  final Map<String, dynamic>? fetchRow;
  final Map<String, dynamic>? saveRow;
  int fetchCalls = 0;
  int saveCalls = 0;
  int? expectedRevision;
  Map<String, dynamic>? savedLayout;

  @override
  Future<Map<String, dynamic>?> fetchCurrentUserLayout() async {
    fetchCalls += 1;
    return fetchRow;
  }

  @override
  Future<Map<String, dynamic>> saveCurrentUserLayout({
    required Map<String, dynamic> layout,
    required int expectedRevision,
  }) async {
    saveCalls += 1;
    savedLayout = layout;
    this.expectedRevision = expectedRevision;
    return saveRow!;
  }
}
