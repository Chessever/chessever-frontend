import 'package:chessever2/screens/my_space/data/my_space_layout_repository.dart';
import 'package:chessever2/screens/my_space/domain/my_space_layout.dart';
import 'package:chessever2/screens/my_space/providers/my_space_layout_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  test(
    'disabled rollout returns the useful default without network I/O',
    () async {
      final backend = _Backend();
      final container = _container(backend, enabled: false);

      final snapshot = await container.read(mySpaceLayoutProvider.future);

      expect(snapshot.layout, MySpaceLayout.curatedDefault);
      expect(snapshot.persistenceAvailable, isFalse);
      expect(backend.fetchCalls, 0);
    },
  );

  test(
    'loads the stored version and revision when rollout is enabled',
    () async {
      final backend = _Backend(fetchRow: _row(revision: 7));
      final container = _container(backend);

      final snapshot = await container.read(mySpaceLayoutProvider.future);

      expect(snapshot.revision, 7);
      expect(snapshot.hasServerRow, isTrue);
      expect(snapshot.persistenceAvailable, isTrue);
    },
  );

  test(
    'add, move, resize, and remove save against monotonic revisions',
    () async {
      final backend = _Backend(fetchRow: null);
      final container = _container(backend);
      await container.read(mySpaceLayoutProvider.future);
      final notifier = container.read(mySpaceLayoutProvider.notifier);
      final added = MySpaceShelfDescriptor(
        id: 'custom_miniatures',
        type: MySpaceShelfType.miniatures,
        size: MySpaceShelfSize.compact,
      );

      await notifier.addShelf(added);
      await notifier.moveShelf(added.id, 0);
      await notifier.resizeShelf(added.id, MySpaceShelfSize.standard);
      await notifier.removeShelf(added.id);

      final snapshot = container.read(mySpaceLayoutProvider).requireValue;
      expect(snapshot.revision, 4);
      expect(snapshot.layout, MySpaceLayout.curatedDefault);
      expect(backend.expectedRevisions, [0, 1, 2, 3]);
    },
  );

  test(
    'premium failure rolls back optimistic UI and remains visible',
    () async {
      final backend = _Backend(
        fetchRow: null,
        saveFailure: const MySpaceLayoutException(
          kind: MySpaceLayoutFailureKind.premiumRequired,
          message: 'premium required',
        ),
      );
      final container = _container(backend);
      await container.read(mySpaceLayoutProvider.future);
      final before = container.read(mySpaceLayoutProvider).requireValue;

      await expectLater(
        container
            .read(mySpaceLayoutProvider.notifier)
            .addShelf(
              MySpaceShelfDescriptor(
                id: 'custom_studies',
                type: MySpaceShelfType.studyDiscovery,
                size: MySpaceShelfSize.compact,
              ),
            ),
        throwsA(
          isA<MySpaceLayoutException>().having(
            (error) => error.kind,
            'kind',
            MySpaceLayoutFailureKind.premiumRequired,
          ),
        ),
      );

      final after = container.read(mySpaceLayoutProvider).requireValue;
      expect(after.layout, before.layout);
      expect(after.revision, before.revision);
      expect(after.isSaving, isFalse);
      expect(after.failure, isA<MySpaceLayoutException>());
    },
  );

  test('revision conflict reloads the winning server layout', () async {
    final backend = _Backend(
      fetchRow: null,
      saveFailure: const MySpaceLayoutException(
        kind: MySpaceLayoutFailureKind.revisionConflict,
        message: 'conflict',
      ),
      conflictFetchRow: _row(revision: 9),
    );
    final container = _container(backend);
    await container.read(mySpaceLayoutProvider.future);

    await expectLater(
      container.read(mySpaceLayoutProvider.notifier).resetToDefault(),
      throwsA(isA<MySpaceLayoutException>()),
    );

    final snapshot = container.read(mySpaceLayoutProvider).requireValue;
    expect(snapshot.revision, 9);
    expect(snapshot.hasServerRow, isTrue);
    expect(snapshot.failure, isA<MySpaceLayoutException>());
  });
}

ProviderContainer _container(_Backend backend, {bool enabled = true}) {
  final container = ProviderContainer(
    overrides: [
      mySpacePersistenceEnabledProvider.overrideWithValue(enabled),
      mySpaceLayoutRepositoryProvider.overrideWithValue(
        MySpaceLayoutRepository(backend),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Map<String, dynamic> _row({required int revision}) => {
  'user_id': 'user-1',
  'schema_version': 1,
  'revision': revision,
  'shelves': MySpaceLayout.curatedDefault.toJson()['shelves'],
  'created_at': '2026-07-10T08:00:00.000Z',
  'updated_at': '2026-07-10T09:00:00.000Z',
};

final class _Backend implements MySpaceLayoutBackend {
  _Backend({this.fetchRow, this.saveFailure, this.conflictFetchRow});

  Map<String, dynamic>? fetchRow;
  final Object? saveFailure;
  final Map<String, dynamic>? conflictFetchRow;
  int fetchCalls = 0;
  int saveCalls = 0;
  final List<int> expectedRevisions = [];

  @override
  Future<Map<String, dynamic>?> fetchCurrentUserLayout() async {
    fetchCalls += 1;
    if (fetchCalls > 1 && conflictFetchRow != null) return conflictFetchRow;
    return fetchRow;
  }

  @override
  Future<Map<String, dynamic>> saveCurrentUserLayout({
    required Map<String, dynamic> layout,
    required int expectedRevision,
  }) async {
    saveCalls += 1;
    expectedRevisions.add(expectedRevision);
    final failure = saveFailure;
    if (failure != null) throw failure;
    final nextRevision = expectedRevision + 1;
    fetchRow = {
      'user_id': 'user-1',
      'schema_version': layout['schema_version'],
      'revision': nextRevision,
      'shelves': layout['shelves'],
      'created_at': '2026-07-10T08:00:00.000Z',
      'updated_at': '2026-07-10T09:00:00.000Z',
    };
    return fetchRow!;
  }
}
