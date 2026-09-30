import 'package:chessever2/screens/my_space/actions/space_edit_actions.dart'
    show spaceStoreIndexFor;
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_database.dart'
    show spaceEventsEditOrder;
import 'package:chessever2/screens/my_space/widgets/space_edit_grid.dart'
    show SpaceEditItem, spaceEditBand, spaceEditPreviewOrder, spaceEditRows;
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:chessever2/screens/my_space/widgets/space_reorder.dart';
import 'package:flutter_test/flutter_test.dart';

SpaceShortcut _playerTile(String id, String name, double sort) => SpaceShortcut(
  id: id,
  kind: SpaceShortcutKind.player,
  targetId: id,
  title: name,
  params: {'playerName': name},
  sortIndex: sort,
);

final _a = _playerTile('101', 'Alpha', 4);
final _b = _playerTile('102', 'Bravo', 3);
final _c = _playerTile('103', 'Charlie', 2);
final _d = _playerTile('104', 'Delta', 1);

void main() {
  group('planSectionMove', () {
    test('lands between its new neighbours at their midpoint', () {
      final plan = SpaceShortcutsNotifier.planSectionMove(
        [_a, _b, _c, _d],
        _a.key,
        2,
      )!;
      expect(plan.list.map((s) => s.title), [
        _b.title,
        _c.title,
        _a.title,
        _d.title,
      ]);
      expect(plan.changed, hasLength(1));
      expect(plan.changed.single.sortIndex, 1.5);
    });

    test('front takes the global top + 1, end the last value - 1', () {
      final folder = SpaceShortcut(
        id: 'f',
        kind: SpaceShortcutKind.folder,
        targetId: 'f',
        title: 'Prep',
        sortIndex: 9,
      );
      final front = SpaceShortcutsNotifier.planSectionMove(
        [folder, _a, _b, _c],
        _c.key,
        0,
      )!;
      expect(front.changed.single.sortIndex, 10);

      final end = SpaceShortcutsNotifier.planSectionMove(
        [_a, _b, _c],
        _a.key,
        2,
      )!;
      expect(end.changed.single.sortIndex, _c.sortIndex - 1);
    });

    test('colliding neighbours renumber the section only', () {
      final flat = [
        for (final s in [_a, _b, _c, _d]) s.copyWith(sortIndex: 0),
      ];
      final folder = SpaceShortcut(
        id: 'f',
        kind: SpaceShortcutKind.folder,
        targetId: 'f',
        title: 'Prep',
      );
      final plan = SpaceShortcutsNotifier.planSectionMove(
        [...flat, folder],
        _d.key,
        1,
      )!;
      final players = [
        for (final s in plan.list)
          if (s.section == SpaceSection.players) s,
      ];
      expect(players.map((s) => s.title), [
        _a.title,
        _d.title,
        _b.title,
        _c.title,
      ]);
      for (var i = 1; i < players.length; i++) {
        expect(players[i - 1].sortIndex, greaterThan(players[i].sortIndex));
      }
      expect(plan.changed.map((s) => s.section).toSet(), {
        SpaceSection.players,
      });
    });

    test('nothing to do for a single tile or the same place', () {
      expect(SpaceShortcutsNotifier.planSectionMove([_a], _a.key, 0), isNull);
      expect(
        SpaceShortcutsNotifier.planSectionMove([_a, _b], _a.key, 0),
        isNull,
      );
    });
  });

  group('preview order', () {
    test('keeps the drag order and slots in anything that arrived', () {
      final order = [_c.key, _a.key, _b.key];
      final out = spacePreviewOrder([_d, _a, _b], order);
      expect(out.map((s) => s.title), [_d.title, _a.title, _b.title]);
    });

    test('nearest slot holds its place inside the hysteresis', () {
      const centers = [Offset(0, 0), Offset(100, 0), Offset(200, 0)];
      expect(
        spaceNearestSlot(centers, const Offset(55, 0), 0, hysteresis: 12),
        0,
      );
      expect(
        spaceNearestSlot(centers, const Offset(60, 0), 0, hysteresis: 12),
        1,
      );
      expect(
        spaceNearestSlot(centers, const Offset(190, 0), 0, hysteresis: 12),
        2,
      );
    });
  });

  group('Edit', () {
    test('a drag holds its preview order through store changes', () {
      // The store added "x" and dropped "c" while the finger was down.
      expect(
        spaceEditPreviewOrder(['x', 'a', 'b', 'd'], ['b', 'a', 'c', 'd']),
        ['x', 'b', 'a', 'd'],
      );
      expect(spaceEditPreviewOrder(['a', 'b'], null), ['a', 'b']);
    });

    test('a dropped card lands in the store beside its new neighbour', () {
      final row = [_a, _b, _c, _d];
      // Alpha dropped after Charlie: after Charlie in the row without it.
      final to = spaceStoreIndexFor(row, _a.key, [
        _b.key,
        _c.key,
        _a.key,
        _d.key,
      ]);
      expect(to, 2);
      final plan = SpaceShortcutsNotifier.planSectionMove(row, _a.key, to)!;
      expect(plan.list.map((s) => s.title), [
        'Bravo',
        'Charlie',
        'Alpha',
        'Delta',
      ]);
      // To the front, and to the end.
      expect(spaceStoreIndexFor(row, _d.key, [_d.key, _a.key]), 0);
      expect(
        spaceStoreIndexFor(row, _a.key, [_b.key, _c.key, _d.key, _a.key]),
        3,
      );
    });

    test('Edit keeps the page\'s runs: live events first, each run in '
        'store order', () {
      final order = spaceEventsEditOrder([_a, _b, _c, _d], {_c.key});
      expect(
        [for (final o in order) o.pin.key],
        [_c.key, _a.key, _b.key, _d.key],
      );
      expect([for (final o in order) o.band], [0, 1, 1, 1]);
      // Nothing live: one run, in store order.
      final flat = spaceEventsEditOrder([_a, _b], const {});
      expect([for (final o in flat) o.pin.key], [_a.key, _b.key]);
    });

    test('a card moves among its own run only', () {
      final bands = {'l': 0, 'a': 1, 'b': 1, 'c': 1, 'x': 2};
      expect(spaceEditBand(['l', 'a', 'b', 'c', 'x'], bands, 'b'), [
        'a',
        'b',
        'c',
      ]);
      expect(spaceEditBand(['l', 'a'], bands, 'l'), ['l']);
    });

    test('a drop within a run lands in the store beside its neighbour in '
        'that run, so the page shows it where it was dropped', () {
      // Store: Alpha, Bravo, Charlie (live), Delta. The page: Charlie first,
      // then Alpha, Bravo, Delta. Delta dropped at the top of its run.
      final row = [_a, _b, _c, _d];
      final run = [_d.key, _a.key, _b.key];
      final to = spaceStoreIndexFor(row, _d.key, run);
      final plan = SpaceShortcutsNotifier.planSectionMove(row, _d.key, to)!;
      final page = spaceEventsEditOrder(plan.list, {_c.key});
      expect(
        [for (final o in page) o.pin.title],
        ['Charlie', 'Delta', 'Alpha', 'Bravo'],
      );
    });

    test('the grid\'s rows: a run starts its own row, a wide card stands '
        'alone', () {
      SpaceEditItem item(String key, int band, {bool wide = false}) =>
          SpaceEditItem(
            key: key,
            label: key,
            band: band,
            wide: wide,
            builder: (_, _) => const SizedBox(),
          );
      final items = {
        for (final i in [
          item('a', 0),
          item('b', 0),
          item('c', 0),
          item('m', 1, wide: true),
          item('n', 1, wide: true),
          item('x', 2),
        ])
          i.key: i,
      };
      expect(spaceEditRows(['a', 'b', 'c', 'm', 'n', 'x'], items, 2), [
        ['a', 'b'],
        ['c'],
        ['m'],
        ['n'],
        ['x'],
      ]);
      expect(spaceEditRows(['a', 'b', 'c'], items, 1), [
        ['a'],
        ['b'],
        ['c'],
      ]);
    });
  });
}
