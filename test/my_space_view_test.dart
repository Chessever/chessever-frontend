import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_builder_sheet.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/my_space_view.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_database.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'support/contrast_audit.dart';

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

final _folder = SpaceShortcut(
  id: 'f',
  kind: SpaceShortcutKind.folder,
  targetId: 'folder-1',
  title: 'Najdorf prep',
  subtitle: '212 games',
  sortIndex: 5,
  createdAt: DateTime(2026, 9, 20),
);

final _player = SpaceShortcut(
  id: 'p',
  kind: SpaceShortcutKind.player,
  targetId: '1503014',
  title: 'Carlsen, Magnus',
  params: const {'fideId': 1503014, 'playerName': 'Carlsen, Magnus'},
  sortIndex: 4,
  createdAt: DateTime(2026, 9, 24),
);

const _likes = SpaceShortcut(
  id: 'l',
  kind: SpaceShortcutKind.likes,
  targetId: 'me',
  title: 'Liked games',
  sortIndex: 3,
);

const _streak = SpaceShortcut(
  id: 's',
  kind: SpaceShortcutKind.streak,
  targetId: '1503014',
  title: 'Magnus Carlsen',
  sortIndex: 2,
);

Future<void> _pumpSpace(
  WidgetTester tester,
  List<SpaceShortcut> seed, {
  ThemeData? theme,
}) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        spaceShortcutsProvider.overrideWith(() => _FakeSpaceShortcuts(seed)),
        playerPhotoProvider.overrideWith((ref, fideId) async => null),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
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
}

/// Lets the art's ticker, springs and any snack run out before teardown.
Future<void> _drain(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  testWidgets('an empty space: the two tiles, My Database explaining how '
      'to fill it, and the Smart Event tile', (tester) async {
    await _pumpSpace(tester, const []);

    expect(find.text('My Likes'), findsOneWidget);
    expect(find.text('My Prep'), findsOneWidget);
    expect(find.text('My Database'), findsOneWidget);
    expect(find.text(kMyDatabaseEmptyText), findsOneWidget);
    expect(find.text('Build smart event'), findsOneWidget);
    expect(find.text('Openings you care about'), findsOneWidget);
    // Nothing of the old rows: no doors, no seeded defaults.
    expect(find.text('Add an opening'), findsNothing);
    expect(find.byType(SpaceDatabaseItem), findsNothing);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('saved things are listed newest first; My Likes and streak '
      'cards stay out', (tester) async {
    await _pumpSpace(tester, [_folder, _likes, _player, _streak]);

    expect(find.text(kMyDatabaseEmptyText), findsNothing);
    expect(find.byType(SpaceDatabaseItem), findsNWidgets(2));
    expect(find.text('Liked games'), findsNothing);
    expect(find.text('Magnus Carlsen'), findsNothing);
    final player = tester.getTopLeft(find.text('Carlsen, Magnus')).dy;
    final folder = tester.getTopLeft(find.text('Najdorf prep')).dy;
    expect(player, lessThan(folder));
    // A row says what the thing is.
    expect(find.text('Database · 212 games'), findsOneWidget);
    expect(find.text('Player'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  testWidgets('holding a saved row offers Remove from My Space, and takes '
      'it out', (tester) async {
    await _pumpSpace(tester, [_folder]);

    await tester.longPress(find.text('Najdorf prep'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Remove from My Space'), findsOneWidget);
    await tester.tap(find.text('Remove from My Space'));
    // The menu lets go of its lifted copy, then the row leaves.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('Najdorf prep'), findsNothing);
    expect(find.text(kMyDatabaseEmptyText), findsOneWidget);
    await _drain(tester);
  });

  testWidgets('Build smart event opens the builder in place', (tester) async {
    await _pumpSpace(tester, const []);

    await tester.tap(find.text('Build smart event'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SmartEventBuilder), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _drain(tester);
  });

  for (final light in [false, true]) {
    testWidgets('the page reads in ${light ? 'light' : 'dark'} mode', (
      tester,
    ) async {
      await _pumpSpace(tester, [
        _folder,
      ], theme: light ? AppTheme.lightTheme : AppTheme.darkTheme);
      final colors = light ? AppColors.light : AppColors.dark;
      final title = tester.widget<Text>(find.text('My Database'));
      expect(title.style!.color, colors.textPrimary);
      expectNoContrastMisses(
        auditTextContrast(tester, fallbackGround: colors.background),
        where: 'MySpaceView',
      );
      expect(tester.takeException(), isNull);
      await _drain(tester);
    });
  }
}
