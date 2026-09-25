import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart'
    show playerPhotoProvider;
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/my_space/defaults/space_defaults.dart';
import 'package:chessever2/screens/my_space/models/space_auto_item.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_players_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/sheets/space_add_sheet.dart';
import 'package:chessever2/screens/my_space/sheets/space_add_sources.dart'
    show SpaceAddSources, kSpaceSheetAddedLabel;
import 'package:chessever2/screens/my_space/widgets/space_first_run_hint.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Store extends SpaceShortcutsNotifier {
  _Store([this.initial = const []]);

  final List<SpaceShortcut> initial;
  final added = <String>[];

  List<SpaceShortcut> get _list => state.valueOrNull ?? const [];

  @override
  Future<List<SpaceShortcut>> build() async => initial;

  @override
  Future<bool> add(SpaceShortcut draft) async {
    if (_list.any((s) => s.key == draft.key)) return false;
    added.add(draft.key);
    state = AsyncData([draft.copyWith(sortIndex: 99), ..._list]);
    return true;
  }

  @override
  Future<SpaceShortcut?> removeTarget(
    SpaceShortcutKind kind,
    String targetId,
  ) async {
    final key = SpaceShortcut.keyFor(kind, targetId);
    final hit = _list.where((s) => s.key == key).firstOrNull;
    state = AsyncData([
      for (final s in _list)
        if (s.key != key) s,
    ]);
    return hit;
  }

  @override
  Future<void> markOpened(String id) async {}
}

class _Hidden extends SpaceHiddenAutoKeys {
  @override
  Set<String> build() => const <String>{};
}

/// Hidden keys in memory, seeded.
class _HiddenSeeded extends SpaceHiddenAutoKeys {
  _HiddenSeeded(this.seed);

  final Set<String> seed;

  @override
  Set<String> build() => seed;

  @override
  void hide(String key) => state = {...state, key};

  @override
  void unhide(String key) => state = {...state}..remove(key);
}

/// The follows, and a tally of every write that would unfollow one.
class _Favorites extends FavoritePlayersNotifierNew {
  _Favorites(this.seed);

  final List<FavoritePlayer> seed;
  int writes = 0;

  @override
  Future<List<FavoritePlayer>> build() async => seed;

  @override
  Future<void> removeFavorite(
    String playerName, {
    String? fideId,
    String? memorialSourceIdentity,
  }) async => writes++;

  @override
  Future<bool> toggleFavorite({
    String? fideId,
    required String playerName,
    String? countryCode,
    int? rating,
    String? title,
    String? gamebasePlayerId,
    String? memorialSourceIdentity,
    String? memorialRouteId,
  }) async {
    writes++;
    return false;
  }
}

class _Visits extends SpacePlayerVisits {
  @override
  Map<String, int> build() => const <String, int>{};
}

/// No country picked: the sheet's Players list is the follows alone.
class _NoCountry extends StateNotifier<AsyncValue<Country>>
    implements SelectedCountryNotifier {
  _NoCountry() : super(const AsyncValue.loading());

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

FavoritePlayer _follow(String name, int fide) => FavoritePlayer(
  id: 'fav-$fide',
  userId: 'u1',
  fideId: '$fide',
  playerName: name,
  metadata: const {'title': 'GM'},
  createdAt: DateTime(2026, 7, 1),
  updatedAt: DateTime(2026, 7, 1),
);

class _RetiredHint extends SpaceFirstRunHintStore {
  @override
  bool readRetired() => true;

  @override
  Future<void> writeRetired() async {}
}

/// The sheet alone, on a phone, over a My Space that holds [pinned].
Future<_Store> _pumpSheet(
  WidgetTester tester, {
  List<SpaceShortcut> pinned = const [],
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final store = _Store(pinned);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [spaceShortcutsProvider.overrideWith(() => store)],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return const Scaffold(
              body: SpaceAddSheet(section: SpaceSection.openings),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return store;
}

/// The add toggle on the row titled [title].
Finder _toggleOf(String title) => find.descendant(
  of: find
      .ancestor(of: find.text(title), matching: find.byType(GestureDetector))
      .first,
  matching: find.byType(SpaceAddToggle),
);

/// The sheet's own list (the search field scrolls too).
Finder get _sheetList => find
    .descendant(
      of: find.byType(SpaceAddSources),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  testWidgets('openings not in My Space lead, the added ones follow, '
      'marked as added', (tester) async {
    final seeded = SpaceShortcutsNotifier.planSeed(const [], spaceSeedDrafts());
    await _pumpSheet(tester, pinned: seeded);

    // New options first: the defaults are in, so the next line leads.
    final lead = kSpacePopularOpenings.first.tileName;
    expect(find.text('Popular at 2700+'), findsOneWidget);
    expect(find.text(lead), findsOneWidget);
    expect(find.bySemanticsLabel('Save $lead to My Space'), findsOneWidget);

    // The two defaults sit under their own label, after every new line,
    // each already checked.
    await tester.scrollUntilVisible(
      find.text(kSpaceDefaultOpenings.last.tileName),
      300,
      scrollable: _sheetList,
    );
    await tester.pump(const Duration(milliseconds: 100));
    final label = tester.getTopLeft(find.text(kSpaceSheetAddedLabel)).dy;
    final lastNew = kSpacePopularOpenings.last.tileName;
    expect(tester.getTopLeft(find.text(lastNew)).dy, lessThan(label));
    for (final o in kSpaceDefaultOpenings) {
      expect(tester.getTopLeft(find.text(o.tileName)).dy, greaterThan(label));
      expect(
        find.bySemanticsLabel('Remove ${o.tileName} from My Space'),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a removed default is a new option again, and re-adds', (
    tester,
  ) async {
    // Only the Rossolimo is left; the QGD Three Knights was removed.
    final seeded = SpaceShortcutsNotifier.planSeed(
      const [],
      spaceSeedDrafts(),
    ).where((s) => s.title != kSpaceDefaultOpenings.first.tileName).toList();
    final store = await _pumpSheet(tester, pinned: seeded);

    final removed = kSpaceDefaultOpenings.first;
    final lead = find.text(removed.tileName);
    expect(lead, findsOneWidget);
    expect(
      tester.getTopLeft(lead).dy,
      lessThan(
        tester.getTopLeft(find.text(kSpacePopularOpenings.first.tileName)).dy,
      ),
    );

    // Adding it keeps it where it is, now checked: the order holds while
    // the sheet is open.
    final before = tester.getTopLeft(lead);
    await tester.tap(_toggleOf(removed.tileName));
    await tester.pump(const Duration(milliseconds: 300));
    expect(store.added, [spaceEliteOpeningDraft(removed)!.key]);
    expect(
      find.bySemanticsLabel('Remove ${removed.tileName} from My Space'),
      findsOneWidget,
    );
    expect(tester.getTopLeft(lead), before);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('rows hold at 360dp and 1.3x text', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _Store();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          spaceShortcutsProvider.overrideWith(() => store),
          spaceFirstRunHintStoreProvider.overrideWithValue(_RetiredHint()),
          spaceHiddenAutoKeysProvider.overrideWith(_Hidden.new),
          spaceAutoRowProvider.overrideWith((ref, s) => SpaceAutoRow.empty),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 780),
              textScaler: TextScaler.linear(1.3),
            ),
            child: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return const Scaffold(
                  body: SpaceAddSheet(section: SpaceSection.openings),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Popular at 2700+'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  group('Databases', () {
    LibraryFolder folder(String id, String name, {bool liked = false}) =>
        LibraryFolder(
          id: id,
          userId: 'u1',
          name: name,
          color: '#000000',
          icon: 'db',
          orderIndex: 0,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          isLikedGames: liked,
          nodeType: LibraryFolder.nodeTypeDatabase,
        );

    Future<_Store> pumpLibrary(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _Store();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            spaceShortcutsProvider.overrideWith(() => store),
            libraryFolderAuthenticatedUserIdProvider.overrideWith(
              (ref) => 'u1',
            ),
            libraryFoldersStreamProvider.overrideWith(
              (ref) => Stream.value([
                folder('liked', 'Liked Games', liked: true),
                folder('db-1', 'Najdorf prep'),
              ]),
            ),
            subscribedBooksProvider.overrideWith(
              (ref) async => const <LibraryFolder>[],
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: Consumer(
                    builder: (context, ref, _) => Center(
                      child: TextButton(
                        onPressed: () => showSpaceAddSheet(
                          context,
                          ref,
                          SpaceSection.library,
                        ),
                        child: const Text('open'),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      return store;
    }

    testWidgets('lists the Library to save (not Liked Games, which has its '
        'own tile) and saves a database', (tester) async {
      final store = await pumpLibrary(tester);

      expect(find.text('Your Library'), findsOneWidget);
      expect(find.text('Najdorf prep'), findsOneWidget);
      expect(find.text('ChessEver'), findsOneWidget);
      expect(find.text('Miniatures'), findsOneWidget);
      expect(find.text('My Likes'), findsNothing);
      expect(find.text('Liked Games'), findsNothing);

      await tester.tap(_toggleOf('Najdorf prep'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(store.added, ['folder:db-1']);

      // Done closes the sheet; one snack says where it went, with Undo.
      await tester.tap(find.text('Done'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Added Najdorf prep to My Space'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('a followed player taken out of My Space comes back from the '
      'sheet\'s Following list as the follow it is; one shown leaves it; '
      'neither ever unfollows', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final carlsen = _follow('Carlsen, Magnus', 1503014);
    final gukesh = _follow('Gukesh D', 46616543);
    final store = _Store();
    final favorites = _Favorites([carlsen, gukesh]);
    final hidden = spaceHiddenFavoriteKey(gukesh);
    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          spaceShortcutsProvider.overrideWith(() => store),
          favoritePlayersProviderNew.overrideWith(() => favorites),
          spaceHiddenAutoKeysProvider.overrideWith(
            () => _HiddenSeeded({hidden}),
          ),
          spacePlayerVisitsProvider.overrideWith(_Visits.new),
          currentUserProvider.overrideWithValue(null),
          countryDropdownProvider.overrideWith((ref) => _NoCountry()),
          spaceCountryTopPlayersProvider.overrideWith((ref) async => const []),
          playerPhotoProvider.overrideWith((ref, fideId) async => null),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              container = ProviderScope.containerOf(context);
              return const Scaffold(
                body: SpaceAddSheet(section: SpaceSection.players),
              );
            },
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    List<String> shown() => [
      for (final e in container.read(spacePlayersProvider) ?? const [])
        e.shortcut.title,
    ];
    expect(shown(), ['Carlsen, Magnus']);
    expect(find.text('Following'), findsOneWidget);
    expect(find.bySemanticsLabel('Add Gukesh D'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Remove Carlsen, Magnus from My Space'),
      findsOneWidget,
    );

    // Back: the follow shows again, with no pin made for it.
    await tester.tap(_toggleOf('Gukesh D'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(spaceHiddenAutoKeysProvider), isNot(contains(hidden)));
    expect(shown(), ['Carlsen, Magnus', 'Gukesh D']);
    expect(store.added, isEmpty);
    expect(
      find.bySemanticsLabel('Remove Gukesh D from My Space'),
      findsOneWidget,
    );

    // Out: hidden here, still followed.
    await tester.tap(_toggleOf('Carlsen, Magnus'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(shown(), ['Gukesh D']);
    expect(favorites.writes, 0);
    expect(favorites.state.valueOrNull, hasLength(2));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
