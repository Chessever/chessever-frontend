import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_reorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

}
