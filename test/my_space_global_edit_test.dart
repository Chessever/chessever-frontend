import 'dart:async';

import 'package:chessever2/screens/my_space/actions/space_edit_actions.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

SpaceShortcut _pin(String id, SpaceShortcutKind kind, double sort) =>
    SpaceShortcut(
      id: id,
      kind: kind,
      targetId: id,
      title: id,
      sortIndex: sort,
      params: {'source': 'retained-$id'},
    );

List<String> _keys(Iterable<SpaceShortcut> pins) =>
    pins.map((pin) => pin.key).toList();

final _event = _pin('event', SpaceShortcutKind.event, 4);
final _folder = _pin('folder', SpaceShortcutKind.folder, 3);
final _opening = _pin('opening', SpaceShortcutKind.opening, 2);
final _player = _pin('player', SpaceShortcutKind.player, 1);

/// The actual action only calls pin removal and restore. Its test store keeps
/// those local effects immediate while real SpacePendingDeletes delays writes.
class _PendingStore extends SpaceShortcutsNotifier {
  _PendingStore(this.seed);
  final List<SpaceShortcut> seed;
  final gate = Completer<void>();
  final pending = SpacePendingDeletes();
  final removed = <String>[];
  final restored = <String>[];
  final writes = <String>[];

  List<SpaceShortcut> get pins => state.valueOrNull ?? const [];

  @override
  Future<List<SpaceShortcut>> build() async => seed;

  @override
  Future<SpaceShortcut?> removeTarget(
    SpaceShortcutKind kind,
    String targetId,
  ) async {
    final key = SpaceShortcut.keyFor(kind, targetId);
    final pin = pins.where((pin) => pin.key == key).firstOrNull;
    if (pin == null) return null;
    removed.add(key);
    state = AsyncData([
      for (final pin in pins)
        if (pin.key != key) pin,
    ]);
    await pending.run(key, () => gate.future);
    return pin;
  }

  @override
  Future<void> restore(SpaceShortcut pin) async {
    if (pins.any((current) => current.key == pin.key)) return;
    restored.add(pin.key);
    state = AsyncData(SpaceShortcutsNotifier.inDisplayOrder([pin, ...pins]));
    await pending.settled(pin.key);
    writes.add(pin.key);
  }
}

void main() {
  group('global visible order', () {
    test('moves a card across types and survives stored JSON reload', () {
      final plan = SpaceShortcutsNotifier.planVisibleMove(
        [_event, _folder, _opening, _player],
        _opening.key,
        [_opening.key, _event.key, _folder.key, _player.key],
      )!;
      expect(_keys(plan.list), [
        _opening.key,
        _event.key,
        _folder.key,
        _player.key,
      ]);
      expect(_keys(plan.changed), [_opening.key]);
      final restored = [
        for (final pin in plan.list) SpaceShortcut.fromJson(pin.toJson())!,
      ];
      expect(
        _keys(SpaceShortcutsNotifier.inDisplayOrder(restored)),
        _keys(plan.list),
      );
    });

    test(
      'hidden and concurrently added pins keep their relative positions',
      () {
        final hidden = _pin('hidden', SpaceShortcutKind.link, 3.8);
        final added = _pin('new', SpaceShortcutKind.game, 3.5);
        final list = [_event, hidden, added, _folder, _opening, _player];
        final plan = SpaceShortcutsNotifier.planVisibleMove(list, _player.key, [
          _event.key,
          _player.key,
          _folder.key,
          _opening.key,
        ])!;
        expect(_keys(plan.list), [
          _event.key,
          _player.key,
          hidden.key,
          added.key,
          _folder.key,
          _opening.key,
        ]);
        expect(_keys(plan.changed), [_player.key]);
        expect(
          _keys(plan.list.where((pin) => pin.key != _player.key)),
          _keys(list.where((pin) => pin.key != _player.key)),
        );
        expect(hidden.sortIndex, 3.8);
        expect(added.sortIndex, 3.5);
      },
    );

    test(
      'deleted neighbors are ignored and duplicate stale keys never return',
      () {
        final added = _pin('new', SpaceShortcutKind.game, 5);
        final plan = SpaceShortcutsNotifier.planVisibleMove(
          [added, _event, _opening, _player],
          _player.key,
          [_folder.key, _player.key, _event.key, _event.key, _opening.key],
        )!;
        expect(_keys(plan.list), [
          added.key,
          _player.key,
          _event.key,
          _opening.key,
        ]);
        expect(_keys(plan.changed), [_player.key]);
      },
    );

    test('a stale gesture never overwrites another concurrent reorder', () {
      final current = [
        _folder.copyWith(sortIndex: 5),
        _event,
        _opening,
        _player,
      ];
      final plan = SpaceShortcutsNotifier.planVisibleMove(
        current,
        _opening.key,
        [_opening.key, _event.key, _folder.key, _player.key],
      )!;
      // The other device moved Folder above Event during this gesture.
      expect(_keys(plan.list), [
        _folder.key,
        _opening.key,
        _event.key,
        _player.key,
      ]);
      expect(_keys(plan.changed), [_opening.key]);
    });

    test(
      'colliding sort values renumber while retaining hidden pins and data',
      () {
        final hidden = _pin('hidden', SpaceShortcutKind.link, 0);
        final list = [
          for (final (i, pin) in [_event, hidden, _folder, _opening].indexed)
            SpaceShortcut(
              id: pin.id,
              kind: pin.kind,
              targetId: pin.targetId,
              title: pin.title,
              params: pin.params,
              createdAt: DateTime(2026, 1, 10 - i),
            ),
        ];
        final plan = SpaceShortcutsNotifier.planVisibleMove(
          list,
          _opening.key,
          [_event.key, _opening.key, _folder.key],
        )!;
        expect(_keys(plan.list), [
          _event.key,
          _opening.key,
          hidden.key,
          _folder.key,
        ]);
        for (var i = 1; i < plan.list.length; i++) {
          expect(
            plan.list[i - 1].sortIndex,
            greaterThan(plan.list[i].sortIndex),
          );
        }
        for (final pin in plan.list) {
          final before = list.singleWhere((before) => before.key == pin.key);
          expect(pin.params, before.params);
          expect(pin.id, before.id);
          expect(pin.createdAt, before.createdAt);
        }
        expect(list.every((pin) => pin.sortIndex == 0), isTrue);
      },
    );

    test(
      'missing, unchanged and sole visible pins never move hidden neighbors',
      () {
        final hidden = _pin('hidden', SpaceShortcutKind.link, 3.5);
        final list = [_event, hidden, _folder];
        for (final order in [
          [_event.key, _folder.key],
          [_event.key],
          [_folder.key],
        ]) {
          expect(
            SpaceShortcutsNotifier.planVisibleMove(list, _event.key, order),
            isNull,
          );
        }
        expect(
          SpaceShortcutsNotifier.planVisibleMove(list, _opening.key, [
            _opening.key,
            _event.key,
          ]),
          isNull,
        );
      },
    );
  });

  group('queued sort persistence', () {
    test(
      'rapid drops serialize and queued writes use the latest sort value',
      () async {
        final queue = SpacePendingSortWrites();
        final entered = Completer<void>();
        final release = Completer<void>();
        var current = [_event];
        var remoteSort = _event.sortIndex;
        final sent = <double>[];
        Future<void> write(List<SpaceShortcut> rows) async {
          sent.add(rows.single.sortIndex);
          if (sent.length == 1) {
            entered.complete();
            await release.future;
          }
          remoteSort = rows.single.sortIndex;
        }

        Future<void> enqueue() => queue.run(
          keys: [_event.key],
          current: () => current,
          blocked: (_) => false,
          write: write,
        );
        final first = enqueue();
        await entered.future;
        current = [_event.copyWith(sortIndex: 8)];
        final second = enqueue();
        current = [_event.copyWith(sortIndex: 12)];
        final third = enqueue();
        expect(sent, [4]);
        release.complete();
        await Future.wait([first, second, third]);
        expect(sent, [4, 12, 12]);
        expect(remoteSort, 12);
      },
    );

    test(
      'a delete waits for prior writes and queued renumber cannot restore its pin',
      () async {
        final queue = SpacePendingSortWrites();
        final deletes = SpacePendingDeletes();
        final entered = Completer<void>();
        final release = Completer<void>();
        var current = [_event, _folder, _opening];
        final remote = {for (final pin in current) pin.key: pin.sortIndex};
        final operations = <String>[];
        final first = queue.run(
          keys: [_folder.key],
          current: () => current,
          blocked: deletes.contains,
          write: (rows) async {
            entered.complete();
            await release.future;
            for (final pin in rows) {
              remote[pin.key] = pin.sortIndex;
            }
            operations.add('first sort');
          },
        );
        await entered.future;
        final renumber = queue.run(
          keys: _keys(current),
          current: () => current,
          blocked: deletes.contains,
          write: (rows) async {
            expect(_keys(rows), [_event.key, _opening.key]);
            for (final pin in rows) {
              remote[pin.key] = pin.sortIndex;
            }
            operations.add('renumber');
          },
        );
        final sorted = queue.settled;
        current = [_event, _opening];
        final deleting = deletes.run(_folder.key, () async {
          await sorted;
          remote.remove(_folder.key);
          operations.add('delete');
        });
        expect(operations, isEmpty);
        release.complete();
        await Future.wait([first, renumber, deleting]);
        expect(operations, ['first sort', 'renumber', 'delete']);
        expect(remote.keys, isNot(contains(_folder.key)));
      },
    );

    test(
      'Undo pins waiting for deletion are skipped and failures do not stop later writes',
      () async {
        final queue = SpacePendingSortWrites();
        final first = queue.run(
          keys: [_event.key],
          current: () => [_event],
          blocked: (_) => false,
          write: (_) async => throw StateError('offline'),
        );
        final recovered = <String>[];
        final next = queue.run(
          keys: [_event.key, _folder.key],
          current: () => [_event, _folder],
          blocked: (key) => key == _folder.key,
          write: (rows) async => recovered.addAll(_keys(rows)),
        );
        await expectLater(first, throwsStateError);
        await next;
        await queue.settled;
        expect(recovered, [_event.key]);
      },
    );
  });

  testWidgets(
    'one bulk Undo restores pins across types before deletion completes',
    (tester) async {
      final store = _PendingStore([_event, _folder, _opening, _player]);
      int? removedCount;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [spaceShortcutsProvider.overrideWith(() => store)],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Consumer(
              builder: (context, ref, _) {
                ResponsiveHelper.init(context);
                ref.watch(spaceShortcutsProvider);
                return Scaffold(
                  body: TextButton(
                    onPressed: () => unawaited(
                      spaceRemovePinsSelected(
                        context: context,
                        ref: ref,
                        keys: {_folder.key, _opening.key, _player.key, 'gone'},
                      ).then((count) => removedCount = count),
                    ),
                    child: const Text('Remove selected'),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Remove selected'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(_keys(store.pins), [_event.key]);
      expect(store.removed, [_folder.key, _opening.key, _player.key]);
      expect(removedCount, isNull);
      expect(find.text('Removed 3 from My Space'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_keys(store.pins), [
        _event.key,
        _folder.key,
        _opening.key,
        _player.key,
      ]);
      expect(store.restored, [_folder.key, _opening.key, _player.key]);
      expect(store.writes, isEmpty);
      store.gate.complete();
      await tester.pump(const Duration(milliseconds: 100));
      expect(removedCount, 3);
      expect(store.writes, [_folder.key, _opening.key, _player.key]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );
}
