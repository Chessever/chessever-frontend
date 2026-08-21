import 'dart:async';

import 'package:chessever2/screens/tour_detail/provider/tour_detail_repo_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _MemoryTourSelectionStore implements TourSelectionStore {
  final values = <String, String>{};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}

class _BlockedTourSelectionStore extends _MemoryTourSelectionStore {
  final writeGate = Completer<void>();

  @override
  Future<void> setString(String key, String value) async {
    await writeGate.future;
    await super.setString(key, value);
  }
}

class _FailingTourSelectionStore implements TourSelectionStore {
  @override
  Future<String?> getString(String key) => Future<String?>.error('read failed');

  @override
  Future<void> remove(String key) => Future<void>.error('remove failed');

  @override
  Future<void> setString(String key, String value) =>
      Future<void>.error('write failed');
}

void main() {
  group('parsePersistedTourSelection', () {
    test('reads the JSON payload the repo writes', () {
      const raw = '{"tourId":"gVby6S8V","savedAt":"2026-08-19T12:00:00.000Z"}';
      final parsed = parsePersistedTourSelection(raw);
      expect(parsed, isNotNull);
      expect(parsed!.tourId, 'gVby6S8V');
      expect(parsed.savedAt.toUtc(), DateTime.utc(2026, 8, 19, 12));
    });

    test('accepts Map from jsonDecode, not only Map<String, dynamic>', () {
      const raw = '{"tourId":"tour-a","savedAt":"2026-08-19T12:00:00.000Z"}';
      expect(parsePersistedTourSelection(raw)?.tourId, 'tour-a');
    });

    test('rejects legacy plain-string values so they expire', () {
      expect(parsePersistedTourSelection('gVby6S8V'), isNull);
    });
  });

  group('isPersistedTourSelectionFresh', () {
    test('keeps a pick inside the 12-hour window', () {
      final savedAt = DateTime.utc(2026, 8, 19, 1);
      final selection = PersistedTourSelection(
        tourId: 'gVby6S8V',
        savedAt: savedAt,
      );
      expect(
        isPersistedTourSelectionFresh(
          selection,
          now: savedAt.add(const Duration(hours: 11, minutes: 59)),
        ),
        isTrue,
      );
    });

    test('expires a pick after 12 hours', () {
      final savedAt = DateTime.utc(2026, 8, 19, 1);
      final selection = PersistedTourSelection(
        tourId: 'gVby6S8V',
        savedAt: savedAt,
      );
      expect(
        isPersistedTourSelectionFresh(
          selection,
          now: savedAt.add(const Duration(hours: 12, minutes: 1)),
        ),
        isFalse,
      );
    });
  });

  test(
    'repository remembers an explicit group choice on immediate re-entry',
    () async {
      final store = _MemoryTourSelectionStore();
      final repo = TourDetailRepo(storage: store);

      await repo.saveSelectedTourId(groupEventId: 'event-1', tourId: 'group-b');

      expect(await repo.getSelectedTourId('event-1'), 'group-b');
    },
  );

  test(
    'immediate re-entry restores selection while Android write is pending',
    () async {
      final store = _BlockedTourSelectionStore();
      store.values['selected_tour_event-1'] =
          '{"tourId":"group-a","savedAt":"2026-08-21T08:00:00.000Z"}';
      final container = ProviderContainer(
        overrides: [tourSelectionStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final repo = container.read(tourDetailRepoProvider);

      final pendingWrite = repo.saveSelectedTourId(
        groupEventId: 'event-1',
        tourId: 'group-b',
      );

      expect(container.read(tourDetailRepoProvider), same(repo));
      expect(await repo.getSelectedTourId('event-1'), 'group-b');

      store.writeGate.complete();
      await pendingWrite;
    },
  );

  test(
    'same-session choice survives a transient Android storage failure',
    () async {
      final repo = TourDetailRepo(storage: _FailingTourSelectionStore());

      await expectLater(
        repo.saveSelectedTourId(groupEventId: 'event-1', tourId: 'group-b'),
        throwsA(anything),
      );

      expect(await repo.getSelectedTourId('event-1'), 'group-b');
    },
  );
}
