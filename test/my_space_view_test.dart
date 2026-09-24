import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/my_space/models/space_auto_item.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/my_space_view.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_door.dart';
import 'package:chessever2/screens/my_space/widgets/space_first_run_hint.dart';
import 'package:chessever2/screens/my_space/widgets/space_tile.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Store double: seeded in memory, never touches SQLite or Supabase (the real
/// notifier reads its cache in build(), which leaves timers pending in tests).
class _FakeSpaceShortcuts extends SpaceShortcutsNotifier {
  _FakeSpaceShortcuts(this._seed);

  final List<SpaceShortcut> _seed;

  List<SpaceShortcut> get _list => state.valueOrNull ?? const [];

  @override
  Future<List<SpaceShortcut>> build() async => _seed;

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

/// Device flag double: in memory, never touches SharedPreferences.
class _MemoryHintStore extends SpaceFirstRunHintStore {
  _MemoryHintStore({this.retired = false});

  bool retired;
  int writes = 0;

  @override
  bool readRetired() => retired;

  @override
  Future<void> writeRetired() async {
    writes++;
    retired = true;
  }
}

const _folder = SpaceShortcut(
  id: 'f',
  kind: SpaceShortcutKind.folder,
  targetId: 'folder-1',
  title: 'Najdorf prep',
  subtitle: '212 games',
  sortIndex: 5,
);

const _player = SpaceShortcut(
  id: 'p',
  kind: SpaceShortcutKind.player,
  targetId: '1503014',
  title: 'Carlsen, Magnus',
  params: {'fideId': 1503014, 'playerName': 'Carlsen, Magnus', 'rating': 2830},
  sortIndex: 4,
);

const _likes = SpaceShortcut(
  id: 'l',
  kind: SpaceShortcutKind.likes,
  targetId: 'me',
  title: 'Liked games',
  sortIndex: 3,
);

const _link = SpaceShortcut(
  id: 'k',
  kind: SpaceShortcutKind.link,
  targetId: 'https://chessever.com/events/olympiad',
  title: 'Olympiad hub',
  sortIndex: 2,
);

Future<void> _pumpSpace(
  WidgetTester tester,
  List<SpaceShortcut> seed, {
  _MemoryHintStore? hintStore,
  // Tall enough that every row is built without scrolling.
  Size size = const Size(390, 3200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        spaceShortcutsProvider.overrideWith(() => _FakeSpaceShortcuts(seed)),
        playerPhotoProvider.overrideWith((ref, fideId) async => null),
        // Rows show only their pins here: no mirror, no suggestions.
        spaceAutoRowProvider.overrideWith((ref, section) => SpaceAutoRow.empty),
        spaceHiddenAutoKeysProvider.overrideWith(_NoHiddenAutoKeys.new),
        spaceFirstRunHintStoreProvider.overrideWithValue(
          hintStore ?? _MemoryHintStore(),
        ),
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
  // Resolve the store, then let the first frame of every row land.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

/// Lets the door art's ticker, springs and any snack run out before teardown.
Future<void> _drain(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpWidget(const SizedBox.shrink());
}

/// Hidden suggestions double: in memory, never touches SharedPreferences.
class _NoHiddenAutoKeys extends SpaceHiddenAutoKeys {
  @override
  Set<String> build() => const <String>{};
}

void main() {
  testWidgets('every row renders its title and door, links only when filled', (
    tester,
  ) async {
    await _pumpSpace(tester, const [_folder, _player, _likes, _link]);

    for (final section in SpaceSection.values) {
      expect(
        find.textContaining(section.title),
        findsWidgets,
        reason: '${section.name} title',
      );
      expect(
        find.text(section.doorLabel),
        findsWidgets,
        reason: '${section.name} door',
      );
    }
    // One door per row, links included because it holds a shortcut.
    expect(find.byType(SpaceDoor), findsNWidgets(SpaceSection.values.length));

    // Tiles carry the stored copy.
    expect(find.text('Najdorf prep'), findsOneWidget);
    expect(find.text('212 games'), findsOneWidget);
    // "Carlsen, Magnus" stacks surname over given name, never cut mid-word.
    expect(find.text('Carlsen'), findsOneWidget);
    expect(find.text('Magnus'), findsOneWidget);
    expect(find.text('2830'), findsOneWidget);
    expect(find.text('Olympiad hub'), findsOneWidget);
    expect(find.byType(SpaceTile), findsNWidgets(4));
    expect(tester.takeException(), isNull);

    await _drain(tester);
  });

  testWidgets('an empty space still shows every row with a full-width door', (
    tester,
  ) async {
    await _pumpSpace(tester, const []);

    expect(find.text(SpaceSection.links.title), findsNothing);
    expect(
      find.byType(SpaceDoor),
      findsNWidgets(SpaceSection.values.length - 1),
    );
    // No "See all" on an empty row.
    expect(find.text('See all'), findsNothing);

    // Let the door-width spring land, then check it spans the page.
    await tester.pump(const Duration(seconds: 1));
    final doorWidth = tester.getSize(find.byType(SpaceDoor).first).width;
    expect(doorWidth, greaterThan(300));
    expect(tester.takeException(), isNull);

    await _drain(tester);
  });

  testWidgets('the first-run line leads an empty space, doors still below', (
    tester,
  ) async {
    await _pumpSpace(tester, const []);

    expect(find.text(kSpaceFirstRunHint), findsOneWidget);
    // It sits above the first row's title, and every door is still there.
    final firstTitle = find.text(SpaceSection.values.first.title).first;
    expect(
      tester.getTopLeft(find.text(kSpaceFirstRunHint)).dy,
      lessThan(tester.getTopLeft(firstTitle).dy),
    );
    expect(
      find.byType(SpaceDoor),
      findsNWidgets(SpaceSection.values.length - 1),
    );
    expect(tester.takeException(), isNull);

    await _drain(tester);
  });

  testWidgets('one thing added keeps the line', (tester) async {
    final store = _MemoryHintStore();
    await _pumpSpace(tester, const [_folder], hintStore: store);

    expect(find.text(kSpaceFirstRunHint), findsOneWidget);
    expect(store.retired, isFalse);

    await _drain(tester);
  });

  testWidgets('two things retire the line for good on this device', (
    tester,
  ) async {
    final store = _MemoryHintStore();
    await _pumpSpace(tester, const [_folder, _player], hintStore: store);

    expect(find.text(kSpaceFirstRunHint), findsNothing);
    expect(store.retired, isTrue);
    expect(store.writes, 1);
    await _drain(tester);

    // Emptied again later, the line stays gone.
    await _pumpSpace(tester, const [], hintStore: store);
    expect(find.text(kSpaceFirstRunHint), findsNothing);
    expect(find.byType(SpaceDoor), findsWidgets);

    await _drain(tester);
  });

  testWidgets('adding the second thing retires the line in place', (
    tester,
  ) async {
    final store = _MemoryHintStore();
    await _pumpSpace(tester, const [_folder], hintStore: store);
    expect(find.text(kSpaceFirstRunHint), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MySpaceView)),
    );
    await container.read(spaceShortcutsProvider.notifier).restore(_player);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text(kSpaceFirstRunHint), findsNothing);
    expect(find.text('Carlsen'), findsOneWidget);
    expect(store.retired, isTrue);
    expect(tester.takeException(), isNull);

    await _drain(tester);
  });

  testWidgets('a device that already retired the line never shows it', (
    tester,
  ) async {
    final store = _MemoryHintStore(retired: true);
    await _pumpSpace(tester, const [], hintStore: store);

    expect(find.text(kSpaceFirstRunHint), findsNothing);
    expect(find.byType(SpaceDoor), findsWidgets);
    expect(store.writes, 0);

    await _drain(tester);
  });

  testWidgets('removing down to one does not bring the line back', (
    tester,
  ) async {
    final store = _MemoryHintStore();
    await _pumpSpace(tester, const [_folder, _player], hintStore: store);
    expect(store.retired, isTrue);

    final grab = await tester.startGesture(
      tester.getCenter(find.text('Carlsen')),
    );
    // Held until the menu is up: only a held tile can be pulled out.
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 260));
    for (var i = 0; i < 6; i++) {
      await grab.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await grab.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Carlsen'), findsNothing);
    expect(find.text(kSpaceFirstRunHint), findsNothing);

    await _drain(tester);
  });

  testWidgets('holding a tile opens its menu; Remove throws it out with Undo', (
    tester,
  ) async {
    await _pumpSpace(tester, const [_folder, _player]);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Najdorf prep')),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Remove from My Space'), findsOneWidget);
    // Already first in its row, so there is nothing to move to the front of.
    expect(find.text('Move to front'), findsNothing);

    await tester.tap(find.text('Remove from My Space'));
    // The focus menu closes on a spring and leaves the tree the frame after.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Najdorf prep'), findsNothing);
    expect(find.text('Removed from Library'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Najdorf prep'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _drain(tester);
  });

  testWidgets('hold and pull up removes a tile; a swipe or a paused one does '
      'not', (tester) async {
    await _pumpSpace(tester, const [_folder, _player]);

    // Moving straight away is a page scroll, never a removal.
    final flick = await tester.startGesture(
      tester.getCenter(find.text('Carlsen')),
    );
    for (var i = 0; i < 6; i++) {
      await flick.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await flick.up();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Carlsen'), findsOneWidget);
    expect(find.text('Removed from Players'), findsNothing);

    // Neither is a scroll that paused on the tile first, however fast the
    // flick after it: the tile grabs the pointer but not the removal.
    final paused = await tester.startGesture(
      tester.getCenter(find.text('Carlsen')),
    );
    await tester.pump(const Duration(milliseconds: 260));
    for (var i = 0; i < 4; i++) {
      await paused.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 8));
    }
    expect(find.text('Let go'), findsNothing);
    await paused.up();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Carlsen'), findsOneWidget);
    expect(find.text('Removed from Players'), findsNothing);
    expect(find.text('Open'), findsNothing);

    // Held until the menu is up, pulling past the threshold throws it out.
    final grab = await tester.startGesture(
      tester.getCenter(find.text('Carlsen')),
    );
    await tester.pump(const Duration(milliseconds: 260));
    await tester.pump(const Duration(milliseconds: 260));
    expect(find.text('Open'), findsOneWidget);
    for (var i = 0; i < 6; i++) {
      await grab.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Let go'), findsOneWidget);
    await grab.up();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Carlsen'), findsNothing);
    expect(find.text('Removed from Players'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _drain(tester);
  });

  testWidgets('a scroll that pauses on a tile still scrolls the page', (
    tester,
  ) async {
    await _pumpSpace(tester, const [
      _folder,
      _player,
    ], size: const Size(390, 700));
    final page = tester.state<ScrollableState>(
      find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    expect(page.position.maxScrollExtent, greaterThan(0));
    expect(page.position.pixels, 0);

    final press = await tester.startGesture(
      tester.getCenter(find.text('Carlsen')),
    );
    await tester.pump(const Duration(milliseconds: 260));
    for (var i = 0; i < 6; i++) {
      await press.moveBy(const Offset(0, -20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    // The page follows the finger from where it first touched down.
    expect(page.position.pixels, closeTo(120, 0.5));
    expect(find.text('Let go'), findsNothing);
    await press.up();
    await tester.pump(const Duration(milliseconds: 600));

    expect(page.position.pixels, greaterThanOrEqualTo(120));
    expect(find.text('Removed from Players'), findsNothing);
    expect(find.text('Open'), findsNothing);
    expect(tester.takeException(), isNull);

    await _drain(tester);
  });
}
