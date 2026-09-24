import 'package:chessever2/repository/library/models/library_folder.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/library/providers/gamebase_database_games_provider.dart'
    show twicDatabaseTotalGamesProvider;
import 'package:chessever2/screens/library/providers/library_folders_provider.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart'
    show miniaturesTotalCountProvider;
import 'package:chessever2/screens/my_space/library/space_library_bridge.dart';
import 'package:chessever2/screens/my_space/models/space_auto_item.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/my_space_view.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/my_space/widgets/space_first_run_hint.dart';
import 'package:chessever2/screens/my_space/widgets/space_tile.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Store extends SpaceShortcutsNotifier {
  _Store(this._seed);

  final List<SpaceShortcut> _seed;
  final added = <SpaceShortcut>[];

  List<SpaceShortcut> get _list => state.valueOrNull ?? const [];

  @override
  Future<List<SpaceShortcut>> build() async => _seed;

  @override
  Future<bool> add(SpaceShortcut draft) async {
    if (_list.any((s) => s.key == draft.key)) return false;
    added.add(draft);
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

class _RetiredHint extends SpaceFirstRunHintStore {
  @override
  bool readRetired() => true;

  @override
  Future<void> writeRetired() async {}
}

LibraryFolder _folder(
  String id,
  String name, {
  String? parentId,
  bool liked = false,
  bool subscribed = false,
  String nodeType = LibraryFolder.nodeTypeDatabase,
}) => LibraryFolder(
  id: id,
  userId: 'u',
  name: name,
  color: '#000000',
  icon: 'db',
  orderIndex: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  parentId: parentId,
  isLikedGames: liked,
  isSubscribed: subscribed,
  nodeType: nodeType,
);

SpaceAutoItem _suggested(SpaceShortcut s) =>
    SpaceAutoItem(shortcut: s, origin: SpaceAutoOrigin.suggested);

final _carlsen = spacePlayerDraft(
  playerName: 'Carlsen, Magnus',
  fideId: 1503014,
  rating: 2830,
);
final _nakamura = spacePlayerDraft(
  playerName: 'Nakamura, Hikaru',
  fideId: 2016192,
  rating: 2800,
);

void main() {
  group('composeSpaceAutoRow', () {
    test('suggestions skip pinned, hidden, mirrored and repeated keys', () {
      final ding = spacePlayerDraft(playerName: 'Ding, Liren', fideId: 8603677);
      final row = composeSpaceAutoRow(
        trailing: [
          _suggested(_carlsen),
          _suggested(_nakamura),
          _suggested(_nakamura),
          _suggested(ding),
        ],
        pinned: {_carlsen.key},
        hidden: {ding.key},
        trailingCap: 5,
      );
      expect(row.trailing.map((a) => a.key), [_nakamura.key]);
    });

    test('suggestions stop at the cap', () {
      final many = [
        for (var i = 1; i <= 20; i++)
          _suggested(spacePlayerDraft(playerName: 'P$i', fideId: i)),
      ];
      expect(
        composeSpaceAutoRow(trailing: many, trailingCap: 12).trailing,
        hasLength(12),
      );
    });

    test('a mirrored tile stands in for its pin', () {
      final twic = spaceLibraryFolderDraft(kTwicFolder);
      final row = composeSpaceAutoRow(
        leading: [
          SpaceAutoItem(
            shortcut: twic,
            origin: SpaceAutoOrigin.library,
            folder: kTwicFolder,
          ),
        ],
        pinned: {twic.key},
      );
      expect(row.leading, hasLength(1));
      expect(row.hiddenPinKeys, contains(twic.key));
    });
  });

  test('the Library order is the Library tab\'s', () {
    final liked = _folder('liked', 'Liked Games', liked: true);
    final mine = _folder('mine', 'Najdorf prep');
    final shared = _folder('shared', 'Club book', subscribed: true);
    final order = spaceLibraryDisplayOrder([mine, liked, shared]);
    expect(order.map((f) => f.id), [
      'liked',
      kTwicBookId,
      kMiniaturesBookId,
      'mine',
      'shared',
    ]);
    expect(spaceLibraryDisplayOrder([]).map((f) => f.id), [
      kTwicBookId,
      kMiniaturesBookId,
    ]);
    // A liked-games destination pins as My Likes, the rest as themselves.
    expect(spaceLibraryFolderDraft(liked).key, 'likes:me');
    expect(spaceLibraryFolderDraft(mine).key, 'folder:mine');
    expect(
      spaceLibraryFolderDraft(kMiniaturesFolder).kind,
      SpaceShortcutKind.miniatures,
    );
    final folderNode = _folder(
      'f',
      'Prep',
      nodeType: LibraryFolder.nodeTypeFolder,
    );
    expect(spaceLibraryFolderDraft(folderNode).params['nodeType'], 'folder');
  });

  test('streaks have no row of their own; a pinned one lives in Players', () {
    expect(SpaceSection.values.map((s) => s.title), isNot(contains('Streaks')));
    expect(SpaceShortcutKind.streak.section, SpaceSection.players);
  });

  test('current events: live and upcoming, followed first', () {
    GroupEventCardModel event(String id, TourEventCategory c) =>
        GroupEventCardModel(
          id: id,
          title: 'Event $id',
          dates: 'Sep 20 - 28',
          maxAvgElo: 2700,
          timeUntilStart: '',
          tourEventCategory: c,
          timeControl: 'standard',
          endDate: null,
          startDate: null,
        );
    final drafts = spaceCurrentEventDrafts(
      [
        event('a', TourEventCategory.live),
        event('b', TourEventCategory.completed),
        event('c', TourEventCategory.upcoming),
        event('gamebase::x', TourEventCategory.live),
        event('d', TourEventCategory.ongoing),
      ],
      {'d'},
    );
    expect(drafts.map((d) => d.targetId), ['d', 'a', 'c']);
  });

  group('on the page', () {
    Future<_Store> pump(
      WidgetTester tester, {
      required Map<SpaceSection, SpaceAutoRow> rows,
      List<SpaceShortcut> pins = const [],
      ThemeData? theme,
    }) async {
      tester.view.physicalSize = const Size(390, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _Store(pins);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            spaceShortcutsProvider.overrideWith(() => store),
            playerPhotoProvider.overrideWith((ref, fideId) async => null),
            spaceFirstRunHintStoreProvider.overrideWithValue(_RetiredHint()),
            spaceHiddenAutoKeysProvider.overrideWith(_Hidden.new),
            spaceAutoRowProvider.overrideWith(
              (ref, section) => rows[section] ?? SpaceAutoRow.empty,
            ),
            twicDatabaseTotalGamesProvider.overrideWith((ref) async => 9400000),
            miniaturesTotalCountProvider.overrideWith((ref) async => 1200),
            folderAnalysisCountProvider.overrideWith((ref, id) async => 212),
            childLibraryFoldersProvider.overrideWith((ref, id) => const []),
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
      return store;
    }

    Future<void> drain(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpWidget(const SizedBox.shrink());
    }

    testWidgets('a suggestion is held for its menu, never carried or thrown', (
      tester,
    ) async {
      final store = await pump(
        tester,
        rows: {
          SpaceSection.players: SpaceAutoRow(
            trailing: [_suggested(_carlsen), _suggested(_nakamura)],
          ),
        },
      );
      expect(find.text('Carlsen'), findsOneWidget);
      expect(find.byType(SpaceTile), findsNWidgets(2));

      // A pull up after a hold is not a removal here.
      final grab = await tester.startGesture(
        tester.getCenter(find.text('Carlsen')),
      );
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump(const Duration(milliseconds: 260));
      for (var i = 0; i < 6; i++) {
        await grab.moveBy(const Offset(0, -30));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('Let go'), findsNothing);
      await grab.up();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // The long press opened the suggestion's own menu.
      expect(find.text('Pin to My Space'), findsOneWidget);
      expect(find.text('Hide'), findsOneWidget);
      expect(find.text('Remove from My Space'), findsNothing);
      expect(find.text('Move to front'), findsNothing);

      await tester.tap(find.text('Pin to My Space'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(store.added.map((s) => s.key), [_carlsen.key]);
      expect(find.text('Pinned to Players'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await drain(tester);
    });

    testWidgets('the Library row mirrors the tab, with its live counts', (
      tester,
    ) async {
      final mine = _folder('mine', 'Najdorf prep');
      await pump(
        tester,
        rows: {
          SpaceSection.library: composeSpaceAutoRow(
            leading: [
              for (final f in [kTwicFolder, mine])
                SpaceAutoItem(
                  shortcut: spaceLibraryFolderDraft(f),
                  origin: SpaceAutoOrigin.library,
                  folder: f,
                ),
            ],
          ),
        },
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('ChessEver'), findsOneWidget);
      expect(find.text('9.4M master games'), findsOneWidget);
      expect(find.text('Najdorf prep'), findsOneWidget);
      expect(find.text('212 games'), findsOneWidget);

      // The Library card's own actions, less its My Space row.
      final press = await tester.startGesture(
        tester.getCenter(find.text('Najdorf prep')),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await press.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Rename'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Add to My Space'), findsNothing);
      expect(tester.takeException(), isNull);
      await drain(tester);
    });

    testWidgets('light mode: mirrored and suggested tiles read on paper', (
      tester,
    ) async {
      await pump(
        tester,
        theme: AppTheme.lightTheme,
        rows: {
          SpaceSection.library: composeSpaceAutoRow(
            leading: [
              SpaceAutoItem(
                shortcut: spaceLibraryFolderDraft(kTwicFolder),
                origin: SpaceAutoOrigin.library,
                folder: kTwicFolder,
              ),
            ],
          ),
          SpaceSection.players: SpaceAutoRow(trailing: [_suggested(_carlsen)]),
        },
      );
      await tester.pump(const Duration(milliseconds: 50));
      final colors = AppColors.light;
      for (final text in ['ChessEver', 'Carlsen', 'Magnus', 'Add to Library']) {
        final style = tester.widget<Text>(find.text(text).first).style;
        final color = style?.color ?? colors.textPrimary;
        expect(
          wcagContrast(color, colors.surface),
          greaterThanOrEqualTo(4.5),
          reason: text,
        );
      }
      final count = tester.renderObject<RenderParagraph>(
        find.text('9.4M master games'),
      );
      final countColor = count.text.style?.color ?? colors.textPrimary;
      expect(
        wcagContrast(countColor, colors.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(tester.takeException(), isNull);
      await drain(tester);
    });
  });
}
