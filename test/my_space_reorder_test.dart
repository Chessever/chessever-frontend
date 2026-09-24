import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/my_space/models/space_auto_item.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/my_space_view.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_first_run_hint.dart';
import 'package:chessever2/screens/my_space/widgets/space_reorder.dart';
import 'package:chessever2/screens/my_space/widgets/space_section_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Store double: seeded in memory, never touches SQLite or Supabase. Moves
/// go through the real planner so the midpoint maths is what gets asserted.
class _FakeSpaceShortcuts extends SpaceShortcutsNotifier {
  _FakeSpaceShortcuts(this._seed);

  final List<SpaceShortcut> _seed;
  final moves = <(String, int)>[];

  List<SpaceShortcut> get _list => state.valueOrNull ?? const [];

  @override
  Future<List<SpaceShortcut>> build() async => _seed;

  @override
  Future<void> moveWithinSection(String key, int toIndex) async {
    moves.add((key, toIndex));
    final plan = SpaceShortcutsNotifier.planSectionMove(_list, key, toIndex);
    if (plan != null) state = AsyncData(plan.list);
  }

  @override
  Future<SpaceShortcut?> removeTarget(
    SpaceShortcutKind kind,
    String targetId,
  ) async {
    final key = SpaceShortcut.keyFor(kind, targetId);
    SpaceShortcut? hit;
    for (final s in _list) {
      if (s.key == key) hit = s;
    }
    state = AsyncData([
      for (final s in _list)
        if (s.key != key) s,
    ]);
    return hit;
  }

  @override
  Future<void> restore(SpaceShortcut item) async {
    state = AsyncData([item, ..._list]);
  }

  @override
  Future<void> moveToFront(String id) async {}

  @override
  Future<void> markOpened(String id) async {}
}

class _MemoryHintStore extends SpaceFirstRunHintStore {
  @override
  bool readRetired() => true;

  @override
  Future<void> writeRetired() async {}
}

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

Future<_FakeSpaceShortcuts> _pumpSpace(
  WidgetTester tester,
  List<SpaceShortcut> seed,
) async {
  tester.view.physicalSize = const Size(390, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final store = _FakeSpaceShortcuts(seed);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        spaceShortcutsProvider.overrideWith(() => store),
        playerPhotoProvider.overrideWith((ref, fideId) async => null),
        // Rows show only their pins here: no mirror, no suggestions.
        spaceAutoRowProvider.overrideWith((ref, section) => SpaceAutoRow.empty),
        spaceHiddenAutoKeysProvider.overrideWith(_NoHiddenAutoKeys.new),
        spaceFirstRunHintStoreProvider.overrideWithValue(_MemoryHintStore()),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              backgroundColor: context.colors.background,
              body: const MySpaceView(),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  return store;
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpWidget(const SizedBox.shrink());
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

/// Moves [gesture] by [total] in even steps, a frame apart.
Future<void> _slide(
  WidgetTester tester,
  TestGesture gesture,
  Offset total, {
  int steps = 12,
}) async {
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(total / steps.toDouble());
    await tester.pump(const Duration(milliseconds: 16));
  }
}

List<String> _playersOrder(_FakeSpaceShortcuts store) => [
  for (final s in store.state.valueOrNull ?? const <SpaceShortcut>[])
    if (s.section == SpaceSection.players) s.title,
];

double _x(WidgetTester tester, String title) =>
    tester.getTopLeft(find.text(title)).dx;

/// Hidden suggestions double: in memory, never touches SharedPreferences.
class _NoHiddenAutoKeys extends SpaceHiddenAutoKeys {
  @override
  Set<String> build() => const <String>{};
}

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

  testWidgets('grab and slide sideways reorders the rail and saves once', (
    tester,
  ) async {
    final store = await _pumpSpace(tester, [_a, _b, _c]);
    final pitch = _x(tester, _b.title) - _x(tester, _a.title);
    expect(pitch, greaterThan(0));

    final grab = await tester.startGesture(
      tester.getCenter(find.text(_a.title)),
    );
    await tester.pump(const Duration(milliseconds: 260));
    await _slide(tester, grab, Offset(pitch * 1.1, 0));
    // Neighbours make room before anything is written.
    expect(store.moves, isEmpty);
    await grab.up();
    await _settle(tester);

    expect(store.moves, [(_a.key, 1)]);
    expect(_playersOrder(store), [_b.title, _a.title, _c.title]);
    final moved = store.state.valueOrNull!.firstWhere((s) => s.key == _a.key);
    expect(moved.sortIndex, 2.5);
    expect(_x(tester, _a.title), greaterThan(_x(tester, _b.title)));
    expect(find.text('Open'), findsNothing);
    expect(find.text('Let go'), findsNothing);
    expect(tester.takeException(), isNull);

    await _drain(tester);
  });

  testWidgets('a long slide carries the tile to the end of the row', (
    tester,
  ) async {
    final store = await _pumpSpace(tester, [_a, _b, _c]);
    final pitch = _x(tester, _b.title) - _x(tester, _a.title);

    final grab = await tester.startGesture(
      tester.getCenter(find.text(_a.title)),
    );
    await tester.pump(const Duration(milliseconds: 260));
    await _slide(tester, grab, Offset(pitch * 2.2, 6), steps: 20);
    await grab.up();
    await _settle(tester);

    expect(store.moves, [(_a.key, 2)]);
    expect(_playersOrder(store), [_b.title, _c.title, _a.title]);
    expect(tester.takeException(), isNull);

    await _drain(tester);
  });

  testWidgets('pull up still removes in a row that can reorder', (
    tester,
  ) async {
    final store = await _pumpSpace(tester, [_a, _b, _c]);

    final grab = await tester.startGesture(
      tester.getCenter(find.text(_b.title)),
    );
    // Held until the menu is up: only a held tile can be pulled out.
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 260));
    for (var i = 0; i < 6; i++) {
      await grab.moveBy(const Offset(2, -30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Let go'), findsOneWidget);
    await grab.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(_b.title), findsNothing);
    expect(find.text('Removed from Players'), findsOneWidget);
    expect(store.moves, isEmpty);
    expect(tester.takeException(), isNull);

    await _drain(tester);
  });

  testWidgets('holding opens the menu; sliding on turns it into a drag', (
    tester,
  ) async {
    final store = await _pumpSpace(tester, [_a, _b, _c]);
    final pitch = _x(tester, _b.title) - _x(tester, _a.title);

    final press = await tester.startGesture(
      tester.getCenter(find.text(_a.title)),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Open'), findsOneWidget);
    // A player with a FIDE id has a public profile link to share.
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Copy link'), findsOneWidget);

    // The same finger, still down, slides on.
    await _slide(tester, press, Offset(pitch * 1.1, 0));
    await press.up();
    await _settle(tester);

    expect(find.text('Open'), findsNothing);
    expect(store.moves, [(_a.key, 1)]);
    expect(_playersOrder(store), [_b.title, _a.title, _c.title]);
    expect(tester.takeException(), isNull);

    await _drain(tester);
  });

  testWidgets('a held tile that does not move keeps its menu', (tester) async {
    final store = await _pumpSpace(tester, [_a, _b]);

    final press = await tester.startGesture(
      tester.getCenter(find.text(_a.title)),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    await press.moveBy(const Offset(4, 3));
    await tester.pump(const Duration(milliseconds: 16));
    await press.up();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Move to front'), findsNothing);
    expect(store.moves, isEmpty);

    // The menu still works after the finger lifts.
    await tester.tap(find.text('Remove from My Space'));
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(find.text(_a.title), findsNothing);
    expect(tester.takeException(), isNull);

    await _drain(tester);
  });

  testWidgets('screen readers move tiles with Move left / Move right', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final store = await _pumpSpace(tester, [_a, _b, _c]);

    Map<CustomSemanticsAction, VoidCallback> actionsOf(String title) {
      final semantics = tester.widget<Semantics>(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label == title &&
              w.properties.customSemanticsActions != null,
          // The last tile sits in the rail's cache, past the screen edge.
          skipOffstage: false,
        ),
      );
      return semantics.properties.customSemanticsActions!;
    }

    const left = CustomSemanticsAction(label: 'Move left');
    const right = CustomSemanticsAction(label: 'Move right');
    expect(actionsOf(_a.title).containsKey(left), isFalse);
    expect(actionsOf(_c.title).containsKey(right), isFalse);
    // What the hold menu offers is reachable without the gesture too.
    expect(
      actionsOf(_b.title).keys.map((a) => a.label),
      containsAll(<String>['Share', 'Copy link', 'Remove from My Space']),
    );

    actionsOf(_b.title)[right]!();
    await tester.pump();
    expect(store.moves, [(_b.key, 2)]);
    expect(_playersOrder(store), [_a.title, _c.title, _b.title]);

    handle.dispose();
    await _drain(tester);
  });

  testWidgets('one tile in a row cannot be dragged, only thrown out', (
    tester,
  ) async {
    final store = await _pumpSpace(tester, [_a]);

    final grab = await tester.startGesture(
      tester.getCenter(find.text(_a.title)),
    );
    await tester.pump(const Duration(milliseconds: 260));
    await _slide(tester, grab, const Offset(160, 0));
    await grab.up();
    await _settle(tester);

    expect(store.moves, isEmpty);
    expect(find.text(_a.title), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _drain(tester);
  });

  testWidgets('See all reorders in two dimensions', (tester) async {
    final store = await _pumpSpace(tester, [_a, _b, _c, _d]);

    await tester.tap(find.text('See all').first);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.byType(SpaceSectionScreen), findsOneWidget);

    Finder inGrid(String title) => find.descendant(
      of: find.byType(SpaceSectionScreen),
      matching: find.text(title),
    );

    // Drop the first tile on the third one's place.
    final from = tester.getCenter(inGrid(_a.title));
    final to = tester.getCenter(inGrid(_c.title));
    final grab = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 260));
    await _slide(tester, grab, to - from, steps: 16);
    await grab.up();
    await _settle(tester);

    expect(store.moves, [(_a.key, 2)]);
    expect(_playersOrder(store), [_b.title, _c.title, _a.title, _d.title]);
    expect(tester.takeException(), isNull);

    await _drain(tester);
  });
}
