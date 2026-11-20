import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart'
    show GameCardChessboard;
import 'package:chessever2/screens/chessboard/utils/pgn_comment_annotations.dart';
import 'package:chessever2/screens/chessboard/widgets/nag_display.dart'
    show getNagDisplay, nagInk;
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/feed/logic/feed_pgn.dart' show parseFlowPgn;
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:chessever2/screens/stories/story_pages.dart';
import 'package:chessever2/screens/stories/story_replay.dart';
import 'package:chessever2/screens/stories/story_row.dart';
import 'package:chessever2/screens/stories/story_row_prefs.dart';
import 'package:chessever2/screens/stories/story_seen_store.dart';
import 'package:chessever2/screens/stories/story_viewer.dart';
import 'package:chessever2/screens/settings/widgets/story_row_settings_body.dart';
import 'package:chessground/chessground.dart' show Arrow, Circle;
import 'package:flutter/services.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:dartchess/dartchess.dart'
    show Chess, Move, NormalMove, Position, Rank, Role, Side;
import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart' show Bone;

/// A short game: the Scholar's mate.
const _pgn = '''[Event "Test"]
[White "Alpha"]
[Black "Beta"]
[Result "1-0"]

1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0''';

/// The same game annotated: arrows, a marked square, words, glyphs, and the
/// machine commands a PGN tool leaves (clock, eval) that must never show.
const _annotatedPgn = '''[Event "Test"]
[White "Alpha"]
[Black "Beta"]
[Result "1-0"]

1. e4 e5 2. Bc4 Nc6 3. Qh5 { [%clk 0:05:00] [%cal Gh5f7,Rc4f7] [%csl Rf7] Threatening mate on f7. } 3... Nf6?? { [%eval 5.0] [%emt 0:00:03] Black misses the threat. } 4. Qxf7# 1-0''';

StoryBatch _annotatedBatch(String slug, int count) {
  final games = [for (var i = 0; i < count; i++) _game('$slug$i')];
  return StoryBatch(
    games: [for (final g in games) buildStoryGame(g, pgn: _annotatedPgn)],
    ordered: [for (final g in games) g.game],
    total: count,
  );
}

class _MemoryStorage implements StorySeenStorage {
  _MemoryStorage([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

/// The row's preferences: a device copy and an account copy, both in
/// memory, counting what was written where.
class _RowStore implements StoryRowPrefsStore {
  _RowStore({this.local, this.account, this.id = 'reader-a'});

  String? local;
  Map<String, dynamic>? account;

  /// The signed-in reader, while [account] is there.
  String? id;
  int accountWrites = 0;
  final StreamController<void> changes = StreamController<void>.broadcast();

  @override
  String? readLocal() => local;

  @override
  Future<void> writeLocal(String value) async => local = value;

  @override
  Future<Map<String, dynamic>?> readAccount() async => account;

  @override
  String? accountId() => account == null ? null : id;

  @override
  Future<void> writeAccount(Map<String, Object?> value) async {
    accountWrites++;
    if (account != null) account = Map<String, dynamic>.of(value);
  }

  @override
  Stream<void> accountChanges() => changes.stream;
}

class _Board extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

/// Holds the open of a game at its first read until the test lets it go.
class _HeldRepository implements CollectionsRepository {
  final Completer<Collection> detail = Completer<Collection>();
  int reads = 0;

  @override
  VoidCallback holdFreshAccess(String slug) => () {};

  @override
  Future<Collection> fetchCollection(String slug) {
    reads++;
    return detail.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The games endpoint over [games], counting what it was asked.
class _PagedGamebase extends GamebaseRepository {
  _PagedGamebase(this.games) : super(Dio(), apiKey: 'test');

  final List<Map<String, dynamic>> games;
  final offsets = <int>[];
  final limits = <int>[];
  final withPgn = <bool>[];

  @override
  Future<CollectionGamesPage> getCollectionGames(
    String slug, {
    String? section,
    String? playerKey,
    String? eco,
    CollectionSearchQuery search = const CollectionSearchQuery(),
    bool includePgn = false,
    int limit = 100,
    int offset = 0,
    String? bearer,
    bool fresh = false,
  }) async {
    offsets.add(offset);
    limits.add(limit);
    withPgn.add(includePgn);
    return CollectionGamesPage.fromJson({
      'items': games.skip(offset).take(limit).toList(),
      'total': games.length,
      'limit': limit,
      'offset': offset,
    });
  }
}

Map<String, dynamic> _gameJson(String id, {String? playedOn}) => {
  'id': id,
  'white': {'name': 'White $id'},
  'black': {'name': 'Black $id'},
  'result': '1-0',
  'playedOn': ?playedOn,
  'pgn': _pgn,
};

Collection _collection(String slug, {int games = 3, String? version}) =>
    Collection(
      id: slug,
      slug: slug,
      kind: CollectionKind.event,
      title: 'Collection $slug',
      author: 'Author $slug',
      gameCount: games,
      contentVersion: version,
      access: CollectionAccess.free,
    );

CollectionGame _game(String id) => CollectionGame.fromPreviewCard(
  CollectionGameCard(
    id: id,
    white: const CollectionPlayerSide(
      name: 'Alpha, Ann',
      key: 'name:alpha',
      elo: 2700,
      title: 'GM',
      fed: 'NOR',
    ),
    black: const CollectionPlayerSide(
      name: 'Beta, Bo',
      key: 'name:beta',
      elo: 2650,
      title: 'IM',
      fed: 'USA',
    ),
    result: '1-0',
    event: 'Test Open',
    eco: 'C20',
    opening: "King's Pawn",
    finalFen:
        'r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4',
    lastMove: 'h5f7',
  ),
)!;

StoryBatch _batch(String slug, int count, {int? total}) {
  final games = [for (var i = 0; i < count; i++) _game('$slug$i')];
  return StoryBatch(
    games: [for (final g in games) buildStoryGame(g, pgn: _pgn)],
    ordered: [for (final g in games) g.game],
    total: total ?? count,
  );
}

/// A seen record (the device's document) where each collection's listed
/// stories are seen; [full] for those whose every story is.
String _seenRecord(Map<String, (Collection, List<String>, bool)> records) =>
    jsonEncode({
      'v': 2,
      'c': {
        for (final MapEntry(:key, :value) in records.entries)
          key: StorySeen(
            ids: value.$2,
            count: value.$1.gameCount,
            full: value.$3,
          ).toJson(),
      },
    });

/// Every story of [batches] seen, as the device would have recorded it.
String _allSeen(
  List<Collection> collections,
  Map<String, StoryBatch> batches,
) => _seenRecord({
  for (final c in collections)
    c.slug: (c, [for (final g in batches[c.slug]!.games) g.id], true),
});

class _Harness {
  _Harness(this.container, this.storage, this.rowStore);

  final ProviderContainer container;
  final _MemoryStorage storage;
  final _RowStore rowStore;

  StorySeenNotifier get seen => container.read(storySeenProvider.notifier);
  StoryRowPrefs get prefs => container.read(storyRowPrefsProvider);
}

/// The page the stories open a collection on, in tests.
class _CollectionPage extends StatelessWidget {
  const _CollectionPage(this.collection);

  final Collection collection;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('collection_page'),
    body: Center(child: Text('Page ${collection.slug}')),
  );
}

/// Today's top under test: the row, then a marker the list lays out under
/// it (so a test can see the list move).
Future<_Harness> _pumpRow(
  WidgetTester tester, {
  required List<Collection> collections,
  required Map<String, StoryBatch> batches,
  String? seen,
  CollectionsRepository? repository,
  Size size = const Size(393, 852),
  _RowStore? rowStore,
  DateTime Function()? clock,
  bool light = false,
  ThemeData? theme,
  Widget? below,
  bool settle = true,
  bool realCatalog = false,
  List<Override> overrides = const [],
  bool fixedBatches = true,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final storage = _MemoryStorage(seen);
  final store = rowStore ?? _RowStore();
  final container = ProviderContainer(
    overrides: [
      // Read on every build, so a test can change the catalog under it.
      // [realCatalog] reads it through the app's own catalog provider, as
      // Today's refreshes do.
      if (realCatalog)
        collectionsProvider.overrideWith((ref) async => List.of(collections))
      else
        storyCollectionsProvider.overrideWith(
          (ref) async => List.of(collections),
        ),
      if (fixedBatches)
        storyBatchProvider.overrideWith((ref, slug) async => batches[slug]!),
      ...overrides,
      storySeenStorageProvider.overrideWithValue(storage),
      storyRowPrefsStoreProvider.overrideWithValue(store),
      if (clock != null) storyClockProvider.overrideWithValue(clock),
      storyCollectionPageProvider.overrideWithValue(_CollectionPage.new),
      boardSettingsProviderNew.overrideWith(_Board.new),
      currentUserProvider.overrideWithValue(null),
      if (repository != null)
        collectionsRepositoryProvider.overrideWithValue(repository),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: theme ?? (light ? AppTheme.lightTheme : AppTheme.darkTheme),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: ListView(
                padding: const EdgeInsets.only(top: 80),
                children: [
                  const TodayStoryRow(gutter: 16),
                  below ?? const SizedBox(key: ValueKey('below'), height: 10),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
  return _Harness(container, storage, store);
}

Finder _circle(String slug) => find.byKey(ValueKey('story_circle_$slug'));

/// Pumps [duration] of time. A ticker started in the frame before counts
/// its time from its own first frame, so one short frame runs first.
Future<void> _run(WidgetTester tester, Duration duration) async {
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(duration);
}

Future<void> _open(WidgetTester tester, String slug) async {
  await tester.tap(_circle(slug));
  await tester.pump();
  // Out of the circle, then the story's first frame.
  await _run(tester, const Duration(milliseconds: 800));
  await tester.pump(const Duration(milliseconds: 16));
}

/// The way out: a frame for the circle to be measured, the shrink, and the
/// route leaving.
Future<void> _settleClose(WidgetTester tester) async {
  await tester.pump();
  await _run(tester, const Duration(milliseconds: 900));
  await tester.pump();
}

Finder _story(String id) => find.byKey(ValueKey('story_game_$id'));

/// [duration] of frames at 60Hz, as a phone draws them: a spring started in
/// one frame moves in the next ones.
Future<void> _frames(
  WidgetTester tester, [
  Duration duration = const Duration(milliseconds: 1200),
]) async {
  for (
    var t = Duration.zero;
    t < duration;
    t += const Duration(milliseconds: 16)
  ) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

GameCardChessboard _boardIn(WidgetTester tester, Finder face) =>
    tester.widget<GameCardChessboard>(
      find.descendant(
        of: face,
        matching: find.byKey(const ValueKey('story_board')),
      ),
    );

StoryProgressBars _barsIn(WidgetTester tester, Finder face) =>
    tester.widget<StoryProgressBars>(
      find.descendant(of: face, matching: find.byType(StoryProgressBars)),
    );

Color _ringColor(WidgetTester tester, String slug) {
  final ring = tester.widget<DecoratedBox>(
    find.descendant(
      of: _circle(slug),
      matching: find.byKey(const ValueKey('story_ring')),
    ),
  );
  return ((ring.decoration as BoxDecoration).border! as Border).top.color;
}

/// Taps the story at a share of the screen's width, clear of the header and
/// the action.
Future<void> _tapStory(WidgetTester tester, double share) async {
  final view = tester.view.physicalSize / tester.view.devicePixelRatio;
  await tester.tapAt(Offset(view.width * share, view.height * 0.5));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  group('stories data', () {
    test(
      'a collection\'s replays read only the pages that hold its stories',
      () async {
        final api = _PagedGamebase([
          for (var i = 0; i < 700; i++) _gameJson('g$i'),
        ]);
        final repository = CollectionsRepository(api, accessToken: () => null);
        final pgns = await repository.fetchPgnsOf('slug', {'g3', 'g250'});
        expect(pgns.keys, unorderedEquals(['g3', 'g250']));
        expect(pgns['g3'], _pgn);
        // Two pages of 200 of the four, with moves.
        expect(api.offsets, [0, 200]);
        expect(api.withPgn, everyElement(isTrue));
      },
    );

    test('with the browse order known, only the stretches holding the '
        'stories are read with their moves', () async {
      final ids = [for (var i = 0; i < 700; i++) 'g$i'];
      final api = _PagedGamebase([for (final id in ids) _gameJson(id)]);
      final repository = CollectionsRepository(api, accessToken: () => null);
      final pgns = await repository.fetchPgnsOf('slug', {
        'g3',
        'g250',
        'g253',
        'g600',
      }, order: ids);
      expect(pgns.keys, unorderedEquals(['g3', 'g250', 'g253', 'g600']));
      // Each with two games either side; g250 and g253 read together.
      expect(api.offsets, [1, 248, 598]);
      expect(api.limits, [5, 8, 5]);
      expect(api.withPgn, everyElement(isTrue));
    });

    test('a browse order gone stale since is caught by the page-by-page '
        'read', () async {
      final ids = [for (var i = 0; i < 700; i++) 'g$i'];
      final api = _PagedGamebase([for (final id in ids) _gameJson(id)]);
      final repository = CollectionsRepository(api, accessToken: () => null);
      // Ten games were added at the top since the browse read.
      final stale = ids.skip(10).toList();
      final pgns = await repository.fetchPgnsOf('slug', {
        'g250',
        'g300',
      }, order: stale);
      expect(pgns.keys, unorderedEquals(['g250', 'g300']));
      // The two stretches, then pages from the start until both are found.
      expect(api.offsets, [238, 288, 0, 200]);
    });

    test('stretches join when close, and never run past a page', () {
      final order = [for (var i = 0; i < 1000; i++) 'g$i'];
      expect(
        CollectionsRepository.pgnWindows(order, {'g0', 'g1', 'g9', 'g30'}),
        [(offset: 0, limit: 12), (offset: 28, limit: 5)],
      );
      final dense = {for (var i = 0; i < 500; i += 4) 'g$i'};
      final windows = CollectionsRepository.pgnWindows(order, dense);
      expect(
        windows.every((w) => w.limit <= CollectionsRepository.gamesPageSize),
        isTrue,
      );
      final covered = {
        for (final w in windows)
          for (var i = w.offset; i < w.offset + w.limit; i++) 'g$i',
      };
      expect(covered.containsAll(dense), isTrue);
    });

    test('stories follow the collection page: a book\'s latest game first, '
        'an event in its own order', () {
      CollectionGame dated(String id, String day) =>
          CollectionGame.fromPreviewCard(
            CollectionGameCard.fromJson(_gameJson(id, playedOn: day)),
          )!;
      final games = [
        dated('old', '2021-01-05'),
        dated('new', '2024-06-01'),
        dated('mid', '2022-03-10'),
      ];
      final contents = CollectionContents(sections: const [], games: games);
      expect(
        [for (final g in storyGameOrder(CollectionKind.book, contents)) g.id],
        ['new', 'mid', 'old'],
      );
      expect(
        [for (final g in storyGameOrder(CollectionKind.event, contents)) g.id],
        ['old', 'new', 'mid'],
      );
    });

    test('a game without moves holds its final position; a long one plays '
        'its last thirty plies', () {
      final still = buildStoryGame(_game('s'));
      expect(still.replay.moves, isFalse);
      expect(still.replay.fens.single, startsWith('r1bqkb1r/pppp1Qpp'));
      expect(still.replay.revealedAt(0), isTrue);

      final moves = [
        for (var i = 0; i < 20; i++)
          '${i + 1}. ${i.isEven ? 'Nf3 Nf6' : 'Ng1 Ng8'}',
      ].join(' ');
      final long = buildStoryGame(_game('l'), pgn: '[Result "*"]\n\n$moves *');
      expect(long.replay.plies, StoryReplay.maxPlies);
      // It opens on the position before those plies, a beat before the
      // first one plays, and every move has played by 80% of the story.
      expect(long.replay.stepAt(0), 0);
      expect(long.replay.stepAt(StoryReplay.windowStart), 1);
      expect(long.replay.stepAt(StoryReplay.windowEnd), StoryReplay.maxPlies);
      expect(long.replay.revealedAt(StoryReplay.windowEnd), isFalse);
      expect(long.replay.revealedAt(StoryReplay.revealAt), isTrue);
    });
  });

  group('the row', () {
    test('unseen collections come first, each group in catalog order', () {
      final all = [
        for (final s in ['a', 'b', 'c', 'd']) _collection(s),
      ];
      final ordered = orderStoryCollections(
        all,
        (c) => c.slug == 'a' || c.slug == 'c',
      );
      expect([for (final c in ordered) c.slug], ['b', 'd', 'a', 'c']);
    });

    testWidgets('lays the unseen circles first, in brand ink, the seen after '
        'them in a quiet ring', (tester) async {
      final a = _collection('a');
      final b = _collection('b');
      final c = _collection('c');
      await _pumpRow(
        tester,
        collections: [a, b, c],
        batches: {
          for (final s in ['a', 'b', 'c']) s: _batch(s, 2),
        },
        seen: _seenRecord({
          'a': (a, ['a0', 'a1'], true),
        }),
      );
      final xs = {
        for (final s in ['a', 'b', 'c']) s: tester.getTopLeft(_circle(s)).dx,
      };
      expect(xs['b']! < xs['c']!, isTrue);
      expect(xs['c']! < xs['a']!, isTrue);
      // The first circle starts on the page's gutter.
      expect(xs['b'], closeTo(16, 0.01));
      final colors = AppColors.dark;
      final unseen = StoryRowMetrics.unseenRing(tester.element(_circle('b')));
      expect(_ringColor(tester, 'b'), unseen);
      // A tonal step of the brand's blue, not its bright cyan.
      expect(unseen, isNot(colors.brand));
      expect(
        unseen.computeLuminance(),
        lessThan(colors.brand.computeLuminance()),
      );
      expect(_ringColor(tester, 'a'), colors.dividerStrong);
      final semantics = tester.getSemantics(_circle('a'));
      expect(semantics.label, contains('Collection a'));
      expect(semantics.label, contains('seen'));
    });

    testWidgets('waits as a skeleton of its own height: nothing moves when '
        'the collections land', (tester) async {
      final landing = Completer<List<Collection>>();
      tester.view.physicalSize = const Size(393 * 3, 852 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storyCollectionsProvider.overrideWith((ref) => landing.future),
            storySeenStorageProvider.overrideWithValue(_MemoryStorage()),
            storyRowPrefsStoreProvider.overrideWithValue(_RowStore()),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return const Scaffold(
                  body: Column(
                    children: [
                      TodayStoryRow(gutter: 16),
                      SizedBox(key: ValueKey('below'), height: 10),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('story_row_skeleton')), findsOneWidget);
      final waiting = tester.getTopLeft(find.byKey(const ValueKey('below')));
      landing.complete([_collection('a'), _collection('b')]);
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('story_row_skeleton')), findsNothing);
      expect(_circle('a'), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const ValueKey('below'))), waiting);
    });

    testWidgets('is hidden when there are no collections', (tester) async {
      await _pumpRow(tester, collections: const [], batches: const {});
      // The skeleton held its place while the catalog was read; it goes on
      // its spring, never growing first.
      final row = find.byType(TodayStoryRow, skipOffstage: false);
      var height = tester.getSize(row).height;
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final now = tester.getSize(row).height;
        expect(now, lessThanOrEqualTo(height + 0.01));
        height = now;
      }
      expect(find.byType(ListView), findsOneWidget);
      expect(find.byKey(const ValueKey('story_row_skeleton')), findsNothing);
      expect(find.byType(StoryCircleFace), findsNothing);
      expect(tester.getSize(row).height, 0);
    });
  });

  group('seen', () {
    Future<StorySeenNotifier> loaded(_MemoryStorage storage) async {
      final container = ProviderContainer(
        overrides: [storySeenStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      container.read(storySeenProvider);
      await Future<void>.delayed(Duration.zero);
      return container.read(storySeenProvider.notifier);
    }

    test('a story counts by its game: the ring is quiet once every story '
        'is seen, and the collection opens on its first unseen one', () async {
      final storage = _MemoryStorage();
      final seen = await loaded(storage);
      final a = _collection('a', games: 3);
      final batch = _batch('a', 3);
      expect(seen.isSeen(a), isFalse);
      expect(seen.resumeIndex(a, batch), 0);
      seen.markSeen(a, batch, 'a0');
      expect(seen.resumeIndex(a, batch), 1);
      // Skipped past a1, a2 seen: it opens on a1, still new.
      seen.markSeen(a, batch, 'a2');
      expect(seen.resumeIndex(a, batch), 1);
      expect(seen.isSeen(a), isFalse);
      seen.markSeen(a, batch, 'a1');
      expect(seen.isSeen(a), isTrue);
      // All seen: from the first again.
      expect(seen.resumeIndex(a, batch), 0);
      final saved = jsonDecode(storage.value!) as Map;
      expect(saved['v'], 2);
      expect((saved['c'] as Map)['a'], containsPair('i', ['a0', 'a1', 'a2']));
    });

    test('a batch read after the row was captured counts its own games, so '
        'the ring rests once they are all watched', () async {
      final seen = await loaded(_MemoryStorage());
      // The viewer kept the row it opened with (3 games); the catalog was
      // read again meanwhile and the stories now hold 5.
      final stale = _collection('a', games: 3);
      final fresh = _collection('a', games: 5);
      final read = _batch('a', 5);
      final batch = StoryBatch(
        games: read.games,
        ordered: read.ordered,
        total: read.total,
        gameCount: 5,
      );
      for (var i = 0; i < 5; i++) {
        seen.markSeen(stale, batch, 'a$i');
      }
      expect(seen.isSeen(fresh), isTrue);
    });

    test('a book that gains games opens on its new ones, and only they are '
        'new', () async {
      final seen = await loaded(_MemoryStorage());
      final before = Collection(
        id: 'b',
        slug: 'b',
        kind: CollectionKind.book,
        title: 'Book',
        gameCount: 3,
      );
      final old = _batch('b', 3);
      for (final g in old.games) {
        seen.markSeen(before, old, g.id);
      }
      expect(seen.isSeen(before), isTrue);
      // Two games added: a book lists its latest first.
      final after = Collection(
        id: 'b',
        slug: 'b',
        kind: CollectionKind.book,
        title: 'Book',
        gameCount: 5,
      );
      final games = [
        for (final id in ['n0', 'n1', 'b0', 'b1', 'b2']) _game(id),
      ];
      final grown = StoryBatch(
        games: [for (final g in games) buildStoryGame(g, pgn: _pgn)],
        ordered: [for (final g in games) g.game],
        total: 5,
      );
      expect(seen.isSeen(after), isFalse);
      expect(seen.resumeIndex(after, grown), 0);
      expect(seen.seenIn(after, grown), {'b0', 'b1', 'b2'});
      seen.markSeen(after, grown, 'n0');
      expect(seen.resumeIndex(after, grown), 1);
      seen.markSeen(after, grown, 'n1');
      expect(seen.isSeen(after), isTrue);
    });

    test('an event past its stories that gains games later in its rounds '
        'stays seen: none of them is a new story', () {
      expect(storyGainedGames(CollectionKind.event, kStoryCap, 40), isFalse);
      expect(storyGainedGames(CollectionKind.event, 8, 12), isTrue);
      expect(storyGainedGames(CollectionKind.book, 40, 41), isTrue);
      expect(storyGainedGames(CollectionKind.book, 41, 41), isFalse);
    });

    test('a record from before games were kept by id: a ring 39.0.1 had '
        'quieted (after one story) stays quiet; a lit one keeps the stories '
        'moved past', () async {
      final a = _collection('a', games: 3);
      final b = _collection('b', games: 3);
      final c = _collection('c', games: 20);
      final d = _collection('d', games: 3);
      final legacy = jsonEncode({
        'a': {'s': '3:', 'n': 2, 'v': true},
        // 39.0.1 quieted the ring after the first story.
        'b': {'s': '3:', 'n': 0, 'v': true},
        'c': {'s': '20:', 'n': kStoryCap, 'v': true},
        'd': {'s': '3:', 'n': 1, 'v': false},
      });
      final seen = await loaded(_MemoryStorage(legacy));
      expect(seen.isSeen(a), isTrue);
      expect(seen.isSeen(b), isTrue);
      expect(seen.isSeen(c), isTrue);
      expect(seen.isSeen(d), isFalse);
      // Read with their stories: a and b hold every one, d its first.
      expect(seen.seenIn(a, _batch('a', 3)), {'a0', 'a1', 'a2'});
      expect(seen.seenIn(b, _batch('b', 3)), {'b0', 'b1', 'b2'});
      expect(seen.resumeIndex(d, _batch('d', 3)), 1);
      seen.reconcile(b, _batch('b', 3));
      expect(seen.state!['b']!.ids, ['b0', 'b1', 'b2']);
      expect(seen.state!['b']!.full, isTrue);
      expect(seen.state!['b']!.legacyNext, isNull);
      seen.reconcile(d, _batch('d', 3));
      expect(seen.state!['d']!.ids, ['d0']);
      // A quiet collection that really got new games: new again.
      expect(seen.isSeen(_collection('a', games: 4)), isFalse);
      expect(seen.isSeen(_collection('b', games: 4)), isFalse);
    });

    test('stories read before the catalog grew never count the new games '
        'as seen', () async {
      final seen = await loaded(_MemoryStorage());
      Collection book(int games) => Collection(
        id: 'k',
        slug: 'k',
        kind: CollectionKind.book,
        title: 'Book',
        gameCount: games,
      );
      // The batch was read with 3 games; the catalog has 5 since.
      final games = [for (var i = 0; i < 3; i++) _game('k$i')];
      final stale = StoryBatch(
        games: [for (final g in games) buildStoryGame(g, pgn: _pgn)],
        ordered: [for (final g in games) g.game],
        total: 3,
        gameCount: 3,
      );
      for (final g in stale.games) {
        seen.markSeen(book(5), stale, g.id);
      }
      seen.reconcile(book(5), stale);
      expect(seen.state!['k']!.count, 3);
      expect(seen.isSeen(book(5)), isFalse);
      // Read again with the new games first: they are where it opens.
      final fresh = [
        for (final id in ['new0', 'new1', 'k0', 'k1', 'k2']) _game(id),
      ];
      final grown = StoryBatch(
        games: [for (final g in fresh) buildStoryGame(g, pgn: _pgn)],
        ordered: [for (final g in fresh) g.game],
        total: 5,
        gameCount: 5,
      );
      expect(seen.resumeIndex(book(5), grown), 0);
      expect(seen.seenIn(book(5), grown), {'k0', 'k1', 'k2'});
    });

    testWidgets('a story on screen for a beat is seen, and so is one tapped '
        'past: skimming moves the place on, and the collection opens on the '
        'next unseen story', (tester) async {
      final a = _collection('a', games: 4);
      final batch = _batch('a', 4);
      final harness = await _pumpRow(
        tester,
        collections: [a],
        batches: {'a': batch},
      );
      await _open(tester, 'a');
      expect(harness.seen.seenIn(a, batch), isEmpty);
      final face = find.byKey(const ValueKey('story_page_a'));
      final started = _barsIn(tester, face).progress.value;
      expect(started * kStoryGameDuration.inMilliseconds, lessThan(200));
      await tester.pump(const Duration(milliseconds: 800));
      expect(harness.seen.seenIn(a, batch), isEmpty);
      await tester.pump(const Duration(milliseconds: 600));
      expect(harness.seen.seenIn(a, batch), {'a0'});
      expect(harness.seen.resumeIndex(a, batch), 1);
      // Tapped past at once, a1 still counts: it was shown.
      await _tapStory(tester, 0.8);
      expect(_story('a1'), findsOneWidget);
      await _tapStory(tester, 0.8);
      expect(_story('a2'), findsOneWidget);
      expect(harness.seen.seenIn(a, batch), {'a0', 'a1'});
      // Back is not on past: a2 shown a moment and left is not seen.
      await _tapStory(tester, 0.1);
      expect(_story('a1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('story_close')));
      await _settleClose(tester);
      expect(harness.seen.seenIn(a, batch), {'a0', 'a1'});
      expect(harness.seen.resumeIndex(a, batch), 2);
      // Opened again, it resumes on the first story not seen.
      await _open(tester, 'a');
      expect(_story('a2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('story_close')));
      await _settleClose(tester);
    });

    testWidgets('the ring goes quiet once every story is watched; new games '
        'turn it back, and the circle opens on the first of them', (
      tester,
    ) async {
      var a = Collection(
        id: 'a',
        slug: 'a',
        kind: CollectionKind.book,
        title: 'Book a',
        gameCount: 2,
        access: CollectionAccess.free,
      );
      final catalog = [a];
      final batches = {'a': _batch('a', 2)};
      final harness = await _pumpRow(
        tester,
        collections: catalog,
        batches: batches,
      );
      final unseen = StoryRowMetrics.unseenRing(tester.element(_circle('a')));
      expect(_ringColor(tester, 'a'), unseen);
      await _open(tester, 'a');
      expect(_story('a0'), findsOneWidget);
      await tester.pump(kStoryGameDuration);
      await tester.pump(const Duration(milliseconds: 16));
      expect(_story('a1'), findsOneWidget);
      // One of two seen: still new.
      expect(harness.seen.isSeen(a), isFalse);
      await tester.pump(kStoryGameDuration * 0.6);
      expect(harness.seen.isSeen(a), isTrue);
      await tester.tap(find.byKey(const ValueKey('story_close')));
      await _settleClose(tester);
      expect(find.byType(CollectionStoryViewer), findsNothing);
      expect(_ringColor(tester, 'a'), AppColors.dark.dividerStrong);

      // A new game, the book's latest: new again, and it opens on it.
      a = Collection(
        id: 'a',
        slug: 'a',
        kind: CollectionKind.book,
        title: 'Book a',
        gameCount: 3,
        access: CollectionAccess.free,
      );
      catalog[0] = a;
      final games = [
        for (final id in ['new', 'a0', 'a1']) _game(id),
      ];
      batches['a'] = StoryBatch(
        games: [for (final g in games) buildStoryGame(g, pgn: _pgn)],
        ordered: [for (final g in games) g.game],
        total: 3,
      );
      harness.container.invalidate(storyCollectionsProvider);
      harness.container.invalidate(storyBatchProvider('a'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_ringColor(tester, 'a'), unseen);
      await _open(tester, 'a');
      expect(_story('new'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('story_close')));
      await _settleClose(tester);
    });
  });

  group('the viewer', () {
    testWidgets('a tap on the right two thirds is the next story, on the '
        'left third the previous one', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 3)},
      );
      await _open(tester, 'a');
      expect(_story('a0'), findsOneWidget);
      await _tapStory(tester, 0.8);
      expect(_story('a1'), findsOneWidget);
      await _tapStory(tester, 0.5);
      expect(_story('a2'), findsOneWidget);
      await _tapStory(tester, 0.15);
      expect(_story('a1'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a story moves on by itself when its bar is full, and the '
        'board has landed on the final position by then', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 2)},
      );
      await _open(tester, 'a');
      final replay = _batch('a', 2).games.first.replay;
      expect(replay.plies, 7);
      await tester.pump(kStoryGameDuration * StoryReplay.revealAt);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('story_result_white')), findsOneWidget);
      // The result reads by tone, not a bright colour: the win in the ink,
      // the loss a quieter step.
      final colors = tester.element(_story('a0')).colors;
      Color? resultColor(String key) =>
          tester.widget<Text>(find.byKey(ValueKey(key))).style?.color;
      expect(resultColor('story_result_white'), colors.textPrimary);
      expect(resultColor('story_result_black'), colors.textSecondary);
      await tester.pump(
        kStoryGameDuration * (1 - StoryReplay.revealAt) -
            const Duration(milliseconds: 300),
      );
      expect(_story('a0'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 16));
      expect(_story('a1'), findsOneWidget);
    });

    testWidgets('holding a story pauses it and hides its chrome; letting go '
        'resumes it', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 2)},
      );
      await _open(tester, 'a');
      final hold = await tester.startGesture(
        const Offset(393 * 0.6, 852 * 0.5),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await _run(tester, const Duration(milliseconds: 400));
      final header = find.ancestor(
        of: find.byKey(const ValueKey('story_close')),
        matching: find.byType(FadeTransition),
      );
      expect(
        tester.widget<FadeTransition>(header.first).opacity.value,
        lessThan(0.05),
      );
      await tester.pump(const Duration(seconds: 12));
      expect(_story('a0'), findsOneWidget);
      await hold.up();
      await _run(tester, const Duration(milliseconds: 400));
      expect(_story('a0'), findsOneWidget);
      expect(
        tester.widget<FadeTransition>(header.first).opacity.value,
        greaterThan(0.95),
      );
      await tester.pump(kStoryGameDuration);
      await tester.pump(const Duration(milliseconds: 16));
      expect(_story('a1'), findsOneWidget);
    });

    testWidgets('a short drag down springs back; a long one closes', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 2)},
      );
      await _open(tester, 'a');
      final full = tester.getRect(find.byKey(const ValueKey('story_surface')));
      expect(full, const Rect.fromLTWH(0, 0, 393, 852));
      await tester.timedDragFrom(
        const Offset(196, 400),
        const Offset(0, 60),
        const Duration(milliseconds: 600),
      );
      await _run(tester, const Duration(milliseconds: 900));
      expect(find.byType(CollectionStoryViewer), findsOneWidget);
      expect(tester.getRect(find.byKey(const ValueKey('story_surface'))), full);

      final drag = await tester.startGesture(const Offset(196, 300));
      for (var i = 0; i < 12; i++) {
        await drag.moveBy(const Offset(0, 25));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final dragged = tester.getRect(
        find.byKey(const ValueKey('story_surface')),
      );
      // It follows the finger, smaller as it goes.
      expect(dragged.center.dy, greaterThan(full.center.dy + 200));
      expect(dragged.width, lessThan(full.width));
      await drag.up();
      await _settleClose(tester);
      expect(find.byType(CollectionStoryViewer), findsNothing);
    });

    testWidgets('after a collection\'s last story the next collection turns '
        'in; after the last collection the viewer closes', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a', games: 1), _collection('b', games: 1)],
        batches: {'a': _batch('a', 1), 'b': _batch('b', 1)},
      );
      await _open(tester, 'a');
      expect(_story('a0'), findsOneWidget);
      await tester.pump(kStoryGameDuration);
      // Mid-turn both faces are on screen.
      await _run(tester, const Duration(milliseconds: 150));
      expect(find.byKey(const ValueKey('story_page_a')), findsOneWidget);
      expect(find.byKey(const ValueKey('story_page_b')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.byKey(const ValueKey('story_page_a')), findsNothing);
      expect(_story('b0'), findsOneWidget);
      await _run(tester, kStoryGameDuration);
      await _settleClose(tester);
      expect(find.byType(CollectionStoryViewer), findsNothing);
    });

    testWidgets('a collection with more games than its stories ends in See '
        'all', (tester) async {
      final a = _collection('a', games: 20);
      await _pumpRow(
        tester,
        collections: [a],
        batches: {'a': _batch('a', kStoryCap, total: 20)},
        // The reader has seen every game but the last.
        seen: _seenRecord({
          'a': (a, [for (var i = 0; i < kStoryCap - 1; i++) 'a$i'], false),
        }),
      );
      await _open(tester, 'a');
      expect(_story('a${kStoryCap - 1}'), findsOneWidget);
      await _tapStory(tester, 0.8);
      expect(find.byKey(const ValueKey('story_see_all')), findsOneWidget);
      expect(find.text('See all 20 games'), findsOneWidget);
      expect(find.byKey(const ValueKey('story_open_game')), findsNothing);
      // See all runs its own, shorter time, then the viewer moves on.
      await tester.pump(kStorySeeAllDuration);
      await _settleClose(tester);
      expect(find.byType(CollectionStoryViewer), findsNothing);
    });

    testWidgets('Open game pauses the story while the game opens and resumes '
        'it when the reader is back', (tester) async {
      final repository = _HeldRepository();
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 3)},
        repository: repository,
      );
      await _open(tester, 'a');
      await tester.tap(find.byKey(const ValueKey('story_open_game')));
      await tester.pump();
      expect(repository.reads, 1);
      // While the game is on its way, taps do not change the story: the
      // reader comes back to the one they opened it from.
      await _tapStory(tester, 0.8);
      expect(_story('a0'), findsOneWidget);
      await _tapStory(tester, 0.15);
      expect(_story('a0'), findsOneWidget);
      await tester.pump(const Duration(seconds: 12));
      expect(_story('a0'), findsOneWidget);
      repository.detail.completeError(StateError('offline'));
      await tester.pump();
      await _run(tester, const Duration(milliseconds: 300));
      // The failure is told over the stories, in words for people.
      expect(
        find.text("Couldn't open this game. Please try again."),
        findsOneWidget,
      );
      expect(_story('a0'), findsOneWidget);
      await tester.pump(kStoryGameDuration);
      await tester.pump(const Duration(milliseconds: 16));
      expect(_story('a1'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('grows out of the circle over a page that stays, and shrinks '
        'back into it', (tester) async {
      final harness = await _pumpRow(
        tester,
        collections: [_collection('a'), _collection('b')],
        batches: {'a': _batch('a', 2), 'b': _batch('b', 2)},
      );
      final circle = tester.getRect(
        find.descendant(of: _circle('b'), matching: find.byType(StoryCover)),
      );
      await tester.tap(_circle('b'));
      await tester.pump();
      // The first frame is the circle itself.
      expect(
        tester.getRect(find.byKey(const ValueKey('story_surface'))),
        rectMoreOrLessEquals(circle, epsilon: 0.5),
      );
      // Not a page route: Today, which leaves the tree under a page, stays
      // under the viewer, and is told it is covered instead.
      final route = ModalRoute.of(
        tester.element(find.byType(CollectionStoryViewer)),
      );
      expect(route, isNot(isA<PageRoute<dynamic>>()));
      await _run(tester, const Duration(milliseconds: 800));
      expect(harness.container.read(storyViewerOpenProvider), isTrue);
      // Kept, behind the viewer, which hides it from painting a beat after
      // it settles.
      expect(_circle('b'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byKey(const ValueKey('story_circle_b'), skipOffstage: false),
        findsOneWidget,
      );
      expect(_circle('b'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('story_close')));
      final surface = find.byKey(const ValueKey('story_surface'));
      Rect? last;
      for (var i = 0; i < 90 && surface.evaluate().isNotEmpty; i++) {
        last = tester.getRect(surface);
        await tester.pump(const Duration(milliseconds: 16));
      }
      // Its last frame sits on the circle it came from.
      expect(last, rectMoreOrLessEquals(circle, epsilon: 1));
      await tester.pump();
      expect(find.byType(CollectionStoryViewer), findsNothing);
      expect(harness.container.read(storyViewerOpenProvider), isFalse);
    });

    testWidgets('the face turning away holds its last frame through the '
        'whole turn: its board and its bars never jump', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a', games: 1), _collection('b', games: 1)],
        batches: {'a': _batch('a', 1), 'b': _batch('b', 1)},
      );
      await _open(tester, 'a');
      final last = _batch('a', 1).games.single.replay.fens.last;
      final pages = tester
          .widget<PageView>(find.byKey(const ValueKey('story_pages')))
          .controller!;
      final face = find.byKey(const ValueKey('story_page_a'));
      // The bar fills and the cube turns to b by itself.
      await tester.pump(kStoryGameDuration);
      var pastHalf = 0;
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (face.evaluate().isEmpty) break;
        expect(_boardIn(tester, face).fen, last);
        expect(_barsIn(tester, face).progress.value, 1);
        if ((pages.page ?? 0) > 0.5) pastHalf++;
      }
      expect(pastHalf, greaterThan(3));
      expect(_story('b0'), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      await _settleClose(tester);
    });

    testWidgets('a turn dragged past half way and back keeps each face on '
        'the frame it was on, and the story goes on from there', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        collections: [_collection('a'), _collection('b')],
        batches: {'a': _batch('a', 2), 'b': _batch('b', 2)},
      );
      await _open(tester, 'a');
      await tester.pump(kStoryGameDuration * 0.4);
      final face = find.byKey(const ValueKey('story_page_a'));
      final fen = _boardIn(tester, face).fen;
      final share = _barsIn(tester, face).progress.value;
      final swipe = await tester.startGesture(const Offset(330, 520));
      for (var i = 0; i < 12; i++) {
        await swipe.moveBy(const Offset(-22, 0));
        await tester.pump(const Duration(milliseconds: 16));
        expect(_boardIn(tester, face).fen, fen);
      }
      // Past half way: b is the active face now, a holds its frame.
      final pages = tester
          .widget<PageView>(find.byKey(const ValueKey('story_pages')))
          .controller!;
      expect(pages.page, greaterThan(0.5));
      expect(_barsIn(tester, face).progress.value, share);
      for (var i = 0; i < 12; i++) {
        await swipe.moveBy(const Offset(22, 0));
        await tester.pump(const Duration(milliseconds: 16));
        expect(_boardIn(tester, face).fen, fen);
      }
      await swipe.up();
      await _run(tester, const Duration(milliseconds: 800));
      expect(_story('a0'), findsOneWidget);
      // It goes on from where it was, not from its start.
      expect(_barsIn(tester, face).progress.value, greaterThan(share));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('grows out of a circle cut by the screen\'s edge where it '
        'stands; the row comes round to it only behind the full screen, '
        'and the viewer lands back in it', (tester) async {
      final slugs = ['a', 'b', 'c', 'd', 'e', 'f'];
      await _pumpRow(
        tester,
        collections: [for (final s in slugs) _collection(s)],
        batches: {for (final s in slugs) s: _batch(s, 2)},
      );
      Finder cover() => find.descendant(
        of: _circle('e'),
        matching: find.byType(StoryCover),
        skipOffstage: false,
      );
      final cut = tester.getRect(cover());
      expect(cut.right, greaterThan(393));
      final row = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(TodayStoryRow),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tapAt(Offset(cut.left + 16, cut.center.dy));
      await tester.pump();
      final surface = find.byKey(const ValueKey('story_surface'));
      expect(tester.getRect(surface), rectMoreOrLessEquals(cut, epsilon: 0.5));
      // The row holds still all the way in: it shows around the surface.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(row.position.pixels, 0);
      }
      // Settled, a beat later it hides the row: only now does it move.
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(row.position.pixels, greaterThan(0));

      await tester.tap(find.byKey(const ValueKey('story_close')));
      Rect? last;
      for (var i = 0; i < 90 && surface.evaluate().isNotEmpty; i++) {
        last = tester.getRect(surface);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump();
      expect(find.byType(CollectionStoryViewer), findsNothing);
      final whole = tester.getRect(cover());
      expect(whole.right, lessThanOrEqualTo(393));
      expect(last, rectMoreOrLessEquals(whole, epsilon: 1));
    });

    testWidgets('closed before it fills the screen, the viewer lands back in '
        'the cut circle it grew out of', (tester) async {
      final slugs = ['a', 'b', 'c', 'd', 'e'];
      await _pumpRow(
        tester,
        collections: [for (final s in slugs) _collection(s)],
        batches: {for (final s in slugs) s: _batch(s, 2)},
      );
      final cut = tester.getRect(
        find.descendant(of: _circle('e'), matching: find.byType(StoryCover)),
      );
      await tester.tapAt(Offset(cut.left + 16, cut.center.dy));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      // Android back, mid-open.
      await tester.binding.handlePopRoute();
      final surface = find.byKey(const ValueKey('story_surface'));
      Rect? last;
      for (var i = 0; i < 90 && surface.evaluate().isNotEmpty; i++) {
        last = tester.getRect(surface);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump();
      expect(find.byType(CollectionStoryViewer), findsNothing);
      expect(last, rectMoreOrLessEquals(cut, epsilon: 1));
    });

    testWidgets('a second tap on the growing surface is not a story tap', (
      tester,
    ) async {
      final a = _collection('a');
      final harness = await _pumpRow(
        tester,
        collections: [a],
        batches: {'a': _batch('a', 3)},
      );
      final circle = tester.getCenter(_circle('a'));
      await tester.tapAt(circle);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(circle);
      await tester.pump();
      await _run(tester, const Duration(milliseconds: 800));
      expect(_story('a0'), findsOneWidget);
      expect(harness.seen.isSeen(a), isFalse);
      // Once in place, taps are stories' again.
      await _tapStory(tester, 0.8);
      expect(_story('a1'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('fits a phone on its side, opened that way or turned while '
        'watching', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a', games: 20)],
        batches: {'a': _batch('a', 2, total: 20)},
        size: const Size(852, 393),
      );
      await _open(tester, 'a');
      expect(tester.takeException(), isNull);
      void fits() {
        final board = tester.getRect(find.byKey(const ValueKey('story_board')));
        final caption = tester.getRect(
          find.byKey(const ValueKey('story_caption')),
        );
        final action = tester.getRect(
          find.byKey(const ValueKey('story_open_game')),
        );
        final header = tester.getRect(
          find.byKey(const ValueKey('story_header_cover')),
        );
        final view = tester.view.physicalSize / 3;
        expect(board.top, greaterThan(header.bottom));
        expect(caption.bottom, lessThanOrEqualTo(action.top));
        expect(action.bottom, lessThanOrEqualTo(view.height));
        expect(board.width, closeTo(board.height, 0.01));
        final line = tester.renderObject<RenderParagraph>(
          find.byKey(const ValueKey('story_caption')),
        );
        // The event and opening line reads whole, clear of the board.
        expect(line.didExceedMaxLines, isFalse);
        expect(line.textSize.width, lessThanOrEqualTo(line.size.width + 0.5));
        expect(caption.overlaps(board), isFalse);
        final rows = [
          for (final e in find.byType(StoryPlayerRow).evaluate())
            tester.getRect(find.byWidget(e.widget)),
        ];
        expect(rows, hasLength(2));
        if (view.width > view.height) {
          // On its side: the board as tall as the space, the players beside
          // it level with its top and bottom edges, the line between them,
          // with room for a whole name.
          expect(board.height, greaterThan(200));
          expect(rows.first.top, closeTo(board.top, 0.5));
          expect(rows.last.bottom, closeTo(board.bottom, 0.5));
          for (final row in rows) {
            expect(row.left, greaterThan(board.right));
            expect(row.width, greaterThanOrEqualTo(StoryGameLayout.minSide));
          }
          expect(caption.top, greaterThan(rows.first.bottom));
          expect(caption.bottom, lessThan(rows.last.top));
          // The group sits centred on the page.
          final group = board.expandToInclude(rows.first);
          expect(group.center.dx, closeTo(view.width / 2, 1));
        } else {
          // Upright: centred under the board, the rows on its width.
          expect(caption.center.dx, closeTo(board.center.dx, 0.5));
          for (final row in rows) {
            expect(row.width, closeTo(board.width, 0.5));
          }
        }
        // The action's chevron keeps clear of the story.
        final chevron = tester.getRect(
          find.byIcon(Icons.keyboard_arrow_up_rounded),
        );
        final storyBottom = [
          caption.bottom,
          board.bottom,
          for (final row in rows) row.bottom,
        ].reduce((a, b) => a > b ? a : b);
        expect(chevron.top - storyBottom, greaterThanOrEqualTo(12));
        expect(chevron.height, greaterThanOrEqualTo(20));
      }

      fits();
      // Turned to portrait and back, mid-story.
      for (final size in [const Size(393, 852), const Size(852, 393)]) {
        tester.view.physicalSize = size * 3;
        ResponsiveHelper.initFromSize(size);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
        fits();
      }
      // The See all story fits too.
      await _tapStory(tester, 0.8);
      await _tapStory(tester, 0.8);
      expect(find.byKey(const ValueKey('story_see_all')), findsOneWidget);
      expect(tester.takeException(), isNull);
      final button = tester.getRect(
        find.byKey(const ValueKey('story_see_all_button')),
      );
      expect(button.bottom, lessThanOrEqualTo(393));
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('at the largest text size the line under the board is whole', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 2)},
      );
      await _open(tester, 'a');
      final caption = tester.renderObject<RenderParagraph>(
        find.byKey(const ValueKey('story_caption')),
      );
      // Its box is as tall as its line: no letter is cut at the bottom (the
      // test font's wide glyphs may still fade it at the end, as a long
      // line does).
      expect(caption.textSize.height, greaterThan(20));
      expect(
        caption.size.height,
        greaterThanOrEqualTo(caption.textSize.height),
      );
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('the bars, the header and the board share the page\'s '
        'gutter', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 2)},
      );
      await _open(tester, 'a');
      final bars = tester.getRect(find.byKey(const ValueKey('story_bars')));
      final cover = tester.getRect(
        find.byKey(const ValueKey('story_header_cover')),
      );
      final board = tester.getRect(find.byKey(const ValueKey('story_board')));
      expect(bars.left, 16);
      expect(bars.right, 393 - 16);
      expect(cover.left, 16);
      expect(board.left, 16);
      expect(board.right, 393 - 16);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a held story dragged down goes, as from rest; let go short, '
        'it springs back and plays on', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 2)},
      );
      await _open(tester, 'a');
      final surface = find.byKey(const ValueKey('story_surface'));
      final full = tester.getRect(surface);

      var hold = await tester.startGesture(const Offset(196, 400));
      await tester.pump(const Duration(milliseconds: 300));
      for (var i = 0; i < 3; i++) {
        await hold.moveBy(const Offset(0, 12));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await hold.up();
      await _run(tester, const Duration(milliseconds: 900));
      expect(tester.getRect(surface), full);
      await tester.pump(kStoryGameDuration);
      await tester.pump(const Duration(milliseconds: 16));
      expect(_story('a1'), findsOneWidget);

      hold = await tester.startGesture(const Offset(196, 400));
      await tester.pump(const Duration(milliseconds: 300));
      for (var i = 0; i < 12; i++) {
        await hold.moveBy(const Offset(0, 25));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final dragged = tester.getRect(surface);
      expect(dragged.center.dy, greaterThan(full.center.dy + 150));
      expect(dragged.width, lessThan(full.width));
      await hold.up();
      await _settleClose(tester);
      expect(find.byType(CollectionStoryViewer), findsNothing);
    });

    testWidgets('the cover flies from the circle into the header\'s circle '
        'and back, a circle all the way, never stretched or faded', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        collections: [_collection('a'), _collection('b')],
        batches: {'a': _batch('a', 2), 'b': _batch('b', 2)},
      );
      final circle = tester.getRect(
        find.descendant(of: _circle('b'), matching: find.byType(StoryCover)),
      );
      await tester.tap(_circle('b'));
      await tester.pump();
      final flight = find.byKey(const ValueKey('story_flight'));
      expect(
        tester.getRect(flight),
        rectMoreOrLessEquals(circle, epsilon: 0.5),
      );
      Rect? landing;
      for (var i = 0; i < 60 && flight.evaluate().isNotEmpty; i++) {
        final rect = tester.getRect(flight);
        expect(rect.width, closeTo(rect.height, 0.01));
        landing = rect;
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(flight, findsNothing);
      final header = find.byKey(const ValueKey('story_header_cover'));
      expect(landing, rectMoreOrLessEquals(tester.getRect(header), epsilon: 1));
      expect(
        tester
            .widget<Opacity>(
              find.ancestor(of: header, matching: find.byType(Opacity)).first,
            )
            .opacity,
        1,
      );

      // On the way out it takes off from the header's circle.
      await tester.tap(find.byKey(const ValueKey('story_close')));
      await tester.pump();
      await tester.pump();
      expect(
        tester.getRect(flight),
        rectMoreOrLessEquals(tester.getRect(header), epsilon: 1),
      );
      await _settleClose(tester);
      expect(find.byType(CollectionStoryViewer), findsNothing);
    });

    testWidgets('tells the page under when it hides it: filling the screen, '
        'or with a game opened from it', (tester) async {
      final repository = _HeldRepository();
      final harness = await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 3)},
        repository: repository,
      );
      bool covers() => harness.container.read(storyViewerCoversProvider);
      await tester.tap(_circle('a'));
      await tester.pump();
      await _run(tester, const Duration(milliseconds: 600));
      // Growing: the page still shows around it.
      expect(covers(), isFalse);
      // A game opened before the surface settles hides it all the same.
      await tester.tap(find.byKey(const ValueKey('story_open_game')));
      await tester.pump();
      expect(covers(), isTrue);
      repository.detail.completeError(StateError('offline'));
      await tester.pump();
      await _run(tester, const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 1));
      // Back, and settled over the page.
      expect(covers(), isTrue);
      final drag = await tester.startGesture(const Offset(196, 300));
      await drag.moveBy(const Offset(0, 30));
      await tester.pump();
      await drag.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 16));
      expect(covers(), isFalse);
      await drag.moveBy(const Offset(0, 300));
      await drag.up();
      await _settleClose(tester);
      expect(find.byType(CollectionStoryViewer), findsNothing);
      expect(covers(), isFalse);
      expect(harness.container.read(storyViewerOpenProvider), isFalse);
    });

    testWidgets('exposes next, previous, pause and close to a screen reader', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 3)},
      );
      await _open(tester, 'a');
      final node = tester.getSemantics(
        find.byKey(const ValueKey('story_viewer')),
      );
      final labels = [
        for (final id
            in node.getSemanticsData().customSemanticsActionIds ??
                const <int>[])
          CustomSemanticsAction.getAction(id)!.label,
      ];
      expect(
        labels,
        containsAll([
          'Next story',
          'Previous story',
          'Pause stories',
          'Close stories',
        ]),
      );
      expect(node.label, contains('story 1 of 3'));
      handle.dispose();
    });

    testWidgets('closed mid-turn, the cube swings back to the face being '
        'closed: its cover flies home, and the next collection is neither '
        'shown nor marked seen', (tester) async {
      final a = _collection('a', games: 1);
      final b = _collection('b', games: 1);
      final harness = await _pumpRow(
        tester,
        collections: [a, b],
        batches: {'a': _batch('a', 1), 'b': _batch('b', 1)},
      );
      await _open(tester, 'a');
      final pager = find.byKey(const ValueKey('story_pages'));
      PageController pages() => tester.widget<PageView>(pager).controller!;
      // The bar fills and the cube starts to turn to b by itself.
      await tester.pump(kStoryGameDuration);
      for (var i = 0; i < 60 && (pages().page ?? 0) < 0.2; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final at = pages().page!;
      expect(at, inInclusiveRange(0.2, 0.5));
      // Android back, mid-turn.
      await tester.binding.handlePopRoute();
      final flight = find.byKey(const ValueKey('story_flight'));
      final surface = find.byKey(const ValueKey('story_surface'));
      Rect? last;
      var page = at;
      for (var i = 0; i < 90 && surface.evaluate().isNotEmpty; i++) {
        if (pager.evaluate().isNotEmpty) {
          final now = pages().page!;
          // Never further on: it only swings back.
          expect(now, lessThanOrEqualTo(page + 1e-6));
          page = now;
        }
        if (flight.evaluate().isNotEmpty) {
          final cover = tester.widget<StoryCoverImage>(
            find.descendant(of: flight, matching: find.byType(StoryCoverImage)),
          );
          expect(cover.collection.slug, 'a');
        }
        last = tester.getRect(surface);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump();
      expect(find.byType(CollectionStoryViewer), findsNothing);
      expect(page, lessThan(at));
      final home = tester.getRect(
        find.descendant(of: _circle('a'), matching: find.byType(StoryCover)),
      );
      expect(last, rectMoreOrLessEquals(home, epsilon: 1));
      expect(harness.seen.isSeen(b), isFalse);
      expect(harness.seen.isSeen(a), isTrue);
    });

    testWidgets('a drag down that starts while the surface is still growing '
        'moves it as far as the finger, and a gentle flick does not close '
        'it', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 2)},
      );
      final surface = find.byKey(const ValueKey('story_surface'));
      await tester.tap(_circle('a'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      // Still about the circle's size.
      expect(tester.getRect(surface).width, lessThan(200));
      var drag = await tester.startGesture(tester.getRect(surface).center);
      await drag.moveBy(const Offset(0, 20));
      // Frames with no time passing: only the drag moves the surface.
      await tester.pump();
      final before = tester.getRect(surface).center.dy;
      await drag.moveBy(const Offset(0, 12));
      await tester.pump();
      expect(tester.getRect(surface).center.dy - before, closeTo(12, 0.5));
      await drag.moveBy(const Offset(0, 30));
      await tester.pump();
      expect(tester.getRect(surface).center.dy - before, closeTo(42, 0.5));
      await drag.up();
      await _run(tester, const Duration(milliseconds: 1200));
      expect(find.byType(CollectionStoryViewer), findsOneWidget);

      // A gentle flick (500pt/s, short of the 800 that closes) at the very
      // start of another open.
      await tester.tap(find.byKey(const ValueKey('story_close')));
      await _settleClose(tester);
      expect(find.byType(CollectionStoryViewer), findsNothing);
      await tester.tap(_circle('a'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      drag = await tester.createGesture();
      await drag.down(tester.getRect(surface).center);
      for (var i = 1; i <= 8; i++) {
        await drag.moveBy(
          const Offset(0, 8),
          timeStamp: Duration(milliseconds: 16 * i),
        );
      }
      await drag.up(timeStamp: const Duration(milliseconds: 16 * 9));
      await _run(tester, const Duration(milliseconds: 1200));
      expect(find.byType(CollectionStoryViewer), findsOneWidget);
      expect(tester.getRect(surface), const Rect.fromLTWH(0, 0, 393, 852));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a finger that comes down while the surface grows and stays '
        'holds the story; letting go plays it', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 2)},
      );
      final surface = find.byKey(const ValueKey('story_surface'));
      await tester.tap(_circle('a'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final hold = await tester.startGesture(tester.getRect(surface).center);
      await _run(tester, const Duration(milliseconds: 900));
      final face = find.byKey(const ValueKey('story_page_a'));
      expect(tester.getRect(surface), const Rect.fromLTWH(0, 0, 393, 852));
      expect(_barsIn(tester, face).progress.value, 0);
      await tester.pump(const Duration(seconds: 3));
      expect(_barsIn(tester, face).progress.value, 0);
      await hold.up();
      await _run(tester, const Duration(milliseconds: 800));
      expect(_barsIn(tester, face).progress.value, greaterThan(0.05));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a swipe on past the last collection closes the stories; a '
        'short pull does not', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a'), _collection('b')],
        batches: {'a': _batch('a', 2), 'b': _batch('b', 2)},
      );
      await _open(tester, 'b');
      // A short pull, past the touch slop by a little.
      var swipe = await tester.startGesture(const Offset(330, 520));
      for (var i = 0; i < 3; i++) {
        await swipe.moveBy(const Offset(-10, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await swipe.up();
      await _run(tester, const Duration(milliseconds: 600));
      expect(find.byType(CollectionStoryViewer), findsOneWidget);
      expect(_story('b0'), findsOneWidget);

      swipe = await tester.startGesture(const Offset(330, 520));
      for (var i = 0; i < 6; i++) {
        await swipe.moveBy(const Offset(-20, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await swipe.up();
      await _settleClose(tester);
      expect(find.byType(CollectionStoryViewer), findsNothing);
    });

    testWidgets('a story still loading holds the exact place of the story '
        'that lands, upright and on its side', (tester) async {
      for (final size in [const Size(393, 852), const Size(852, 393)]) {
        final pending = Completer<StoryBatch>();
        tester.view.physicalSize = size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final container = ProviderContainer(
          overrides: [
            storyCollectionsProvider.overrideWith(
              (ref) async => [_collection('a')],
            ),
            storyBatchProvider.overrideWith((ref, slug) => pending.future),
            storySeenStorageProvider.overrideWithValue(_MemoryStorage()),
            boardSettingsProviderNew.overrideWith(_Board.new),
            currentUserProvider.overrideWithValue(null),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  return Scaffold(
                    body: ListView(
                      padding: const EdgeInsets.only(top: 80),
                      children: const [TodayStoryRow(gutter: 16)],
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await _open(tester, 'a');
        expect(find.byKey(const ValueKey('story_skeleton')), findsOneWidget);
        expect(tester.takeException(), isNull);
        final bones = [
          for (final e in find.byWidgetPredicate((w) => w is Bone).evaluate())
            tester.getRect(find.byWidget(e.widget)),
        ]..sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
        final boardBone = bones.first;
        pending.complete(_batch('a', 2));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        final board = tester.getRect(find.byKey(const ValueKey('story_board')));
        expect(board, rectMoreOrLessEquals(boardBone, epsilon: 0.5));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      }
    });

    testWidgets('games that fail to load: a short line in words for people '
        'and Try again; a collection still loading is a skeleton a tap '
        'moves past', (tester) async {
      tester.view.physicalSize = const Size(393, 852) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      var fail = true;
      final pending = Completer<StoryBatch>();
      final container = ProviderContainer(
        overrides: [
          storyCollectionsProvider.overrideWith(
            (ref) async => [
              _collection('a'),
              _collection('b'),
              _collection('c'),
            ],
          ),
          storyBatchProvider.overrideWith((ref, slug) async {
            if (slug == 'a' && fail) throw StateError('500 raw failure');
            if (slug == 'b') return pending.future;
            return _batch(slug, 2);
          }),
          storySeenStorageProvider.overrideWithValue(_MemoryStorage()),
          boardSettingsProviderNew.overrideWith(_Board.new),
          currentUserProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: ListView(
                    padding: const EdgeInsets.only(top: 80),
                    children: const [TodayStoryRow(gutter: 16)],
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await _open(tester, 'a');
      expect(find.byKey(const ValueKey('story_retry')), findsOneWidget);
      expect(find.textContaining('500 raw failure'), findsNothing);
      fail = false;
      await tester.tap(find.byKey(const ValueKey('story_retry_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_story('a0'), findsOneWidget);

      // On to b, whose games never arrive: its skeleton, then a tap goes on.
      await _tapStory(tester, 0.8);
      await _tapStory(tester, 0.8);
      await _run(tester, const Duration(milliseconds: 1200));
      expect(find.byKey(const ValueKey('story_skeleton')), findsOneWidget);
      await _tapStory(tester, 0.8);
      await _run(tester, const Duration(milliseconds: 1200));
      expect(_story('c0'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('story_close')));
      await _settleClose(tester);
      expect(find.byType(CollectionStoryViewer), findsNothing);
    });
  });

  group('robustness', () {
    test('a remembered place is held inside a batch that got shorter', () {
      expect(clampStoryIndex(7, 3), 2);
      expect(clampStoryIndex(-1, 3), 0);
      expect(clampStoryIndex(4, 0), 0);
      expect(clampStoryIndex(1, 3), 1);
    });

    testWidgets('a failed catalog read comes back on its own', (tester) async {
      tester.view.physicalSize = const Size(393, 852) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      var reads = 0;
      final container = ProviderContainer(
        overrides: [
          storyCollectionsProvider.overrideWith((ref) async {
            reads++;
            if (reads == 1) throw StateError('offline');
            return [_collection('a')];
          }),
          storyBatchProvider.overrideWith((ref, slug) async => _batch(slug, 2)),
          storySeenStorageProvider.overrideWithValue(_MemoryStorage(null)),
          boardSettingsProviderNew.overrideWith(_Board.new),
          currentUserProvider.overrideWithValue(null),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: ListView(children: const [TodayStoryRow(gutter: 16)]),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // Offline: no row, and no error on the page.
      expect(_circle('a'), findsNothing);
      // Asked again a few seconds later, the row comes back on its spring.
      await tester.pump(const Duration(seconds: 9));
      await tester.pump();
      await _run(tester, const Duration(milliseconds: 600));
      expect(reads, greaterThanOrEqualTo(2));
      expect(_circle('a'), findsOneWidget);
    });

    testWidgets('a sideways swipe while Open game is on its way keeps the '
        'collection', (tester) async {
      final repository = _HeldRepository();
      await _pumpRow(
        tester,
        collections: [_collection('a'), _collection('b')],
        batches: {'a': _batch('a', 3), 'b': _batch('b', 3)},
        repository: repository,
      );
      await _open(tester, 'a');
      await tester.tap(find.byKey(const ValueKey('story_open_game')));
      await tester.pump();
      await tester.drag(
        find.byKey(const ValueKey('story_pages')),
        const Offset(-300, 0),
      );
      await _run(tester, const Duration(milliseconds: 600));
      expect(_story('a0'), findsOneWidget);
      expect(_story('b0'), findsNothing);
      repository.detail.completeError(StateError('offline'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 12));
    });
  });

  group('annotations', () {
    test('an annotated game runs on its schedule: each move\'s words, '
        'glyphs and arrows at its own step, the commands gone', () {
      final replay = StoryReplay.fromPgn(_annotatedPgn)!;
      expect(replay.annotated, isTrue);
      expect(replay.plies, 7);
      final qh5 = replay.noteAt(5)!;
      expect(qh5.number, '3.');
      expect(qh5.san, 'Qh5');
      expect(qh5.comment, 'Threatening mate on f7.');
      expect(qh5.shapes, hasLength(3));
      expect(
        qh5.shapes.whereType<Arrow>().map(
          (a) => '${a.orig.name}${a.dest.name}',
        ),
        unorderedEquals(['h5f7', 'c4f7']),
      );
      expect(qh5.shapes.whereType<Circle>().single.orig.name, 'f7');
      final nf6 = replay.noteAt(6)!;
      expect(nf6.number, '3…');
      expect(nf6.nags, [4]);
      expect(nf6.comment, 'Black misses the threat.');
      // Only the move just played draws: the next one clears the arrows.
      expect(nf6.shapes, isEmpty);
      expect(replay.noteAt(7)!.annotated, isFalse);
      // No command reaches the words.
      for (final note in replay.notes) {
        expect(note?.comment ?? '', isNot(contains('%')));
      }
      // The schedule: its steps in order, the bar exactly its length.
      final total = replay.scheduledDuration!;
      expect(total, greaterThan(const Duration(seconds: 8)));
      expect(total, lessThan(const Duration(seconds: 35)));
      for (var step = 1; step <= replay.plies; step++) {
        expect(replay.startOf(step), greaterThan(replay.startOf(step - 1)));
        expect(replay.stepAt(replay.startOf(step) + 1e-6), step);
      }
      // Words held long enough to read: the commented moves hold longest.
      double hold(int step) =>
          (replay.startOf(step + 1) - replay.startOf(step)) *
          total.inMicroseconds /
          1e6;
      expect(hold(5), closeTo(StoryReplay.dwellOf(qh5), 1e-6));
      expect(hold(5), greaterThan(hold(1) * 5));
      expect(replay.revealShare, greaterThan(replay.startOf(7)));
    });

    test('a longer comment holds longer; a game without annotations keeps '
        'the plain replay', () {
      final short = StoryReplay.fromPgn(_annotatedPgn)!;
      final long = StoryReplay.fromPgn(
        _annotatedPgn.replaceFirst(
          'Threatening mate on f7.',
          'Threatening mate on f7, and the knight on c6 cannot cover it: '
              'only a queen move or g6 holds, and both lose material.',
        ),
      )!;
      expect(long.scheduledDuration!, greaterThan(short.scheduledDuration!));
      final plain = StoryReplay.fromPgn(_pgn)!;
      expect(plain.annotated, isFalse);
      expect(plain.scheduledDuration, isNull);
      expect(plain.notes, isEmpty);
      expect(_batch('a', 1).durationOf(0), kStoryGameDuration);
      expect(_annotatedBatch('a', 1).durationOf(0), short.scheduledDuration);
    });

    test('a long annotated game opens later, so its commented moments fit '
        'the story', () {
      final moves = StringBuffer();
      for (var i = 0; i < 60; i++) {
        moves.write('${i + 1}. ${i.isEven ? 'Nf3 Nf6' : 'Ng1 Ng8'} ');
      }
      moves.write('61. Nf3 { The decisive manoeuvre begins. } Nf6 ');
      moves.write('62. Ng1 { And it ends here. } *');
      final replay = StoryReplay.fromPgn('[Result "*"]\n\n$moves')!;
      expect(replay.annotated, isTrue);
      expect(
        replay.scheduledDuration!.inMilliseconds,
        lessThanOrEqualTo(35000),
      );
      // Started after the game's first move, both comments inside.
      expect(replay.plies, lessThan(124));
      final words = [for (final n in replay.notes) n?.comment];
      expect(words, contains('The decisive manoeuvre begins.'));
      expect(words, contains('And it ends here.'));
    });

    testWidgets('the story shows each move\'s notes and arrows at its ply, '
        'clears them on the next, and moves on as its schedule ends', (
      tester,
    ) async {
      final batch = _annotatedBatch('a', 2);
      await _pumpRow(
        tester,
        collections: [_collection('a', games: 2)],
        batches: {'a': batch},
      );
      await _open(tester, 'a');
      final replay = batch.games.first.replay;
      final total = replay.scheduledDuration!;
      final face = find.byKey(const ValueKey('story_page_a'));
      Future<void> seek(double share) async {
        final now = _barsIn(tester, face).progress.value;
        await tester.pump(total * (share - now));
        await tester.pump(const Duration(milliseconds: 16));
      }

      String moveLine() => tester
          .widget<Text>(find.byKey(const ValueKey('story_note_move')))
          .textSpan!
          .toPlainText();

      // On Qh5: its arrows on the board, its words under it.
      await seek((replay.startOf(5) + replay.startOf(6)) / 2);
      expect(_boardIn(tester, face).shapes, replay.noteAt(5)!.shapes);
      expect(_boardIn(tester, face).shapes, hasLength(3));
      expect(moveLine(), '3. Qh5');
      expect(find.text('Threatening mate on f7.'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('0:05:00'), findsNothing);

      // On Nf6??: the arrows gone, its glyph in the blunder's colour.
      await seek((replay.startOf(6) + replay.startOf(7)) / 2);
      await tester.pump(const Duration(milliseconds: 400));
      expect(_boardIn(tester, face).shapes, isEmpty);
      expect(moveLine(), '3… Nf6??');
      expect(find.text('Black misses the threat.'), findsOneWidget);
      expect(find.text('Threatening mate on f7.'), findsNothing);
      final glyph = tester
          .widget<Text>(find.byKey(const ValueKey('story_note_move')))
          .textSpan!;
      final colors = <Color?>[];
      glyph.visitChildren((span) {
        if (span is TextSpan && span.text == '??') {
          colors.add(span.style?.color);
        }
        return true;
      });
      final element = tester.element(face);
      expect(colors, [storyGlyphInk(element, getNagDisplay(4)!)]);

      // The bar runs the schedule: still on this story a beat before its
      // end, on the next one a beat after.
      await seek(1 - 0.02);
      expect(_story('a0'), findsOneWidget);
      await tester.pump(total * 0.04);
      await tester.pump(const Duration(milliseconds: 16));
      expect(_story('a1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('story_close')));
      await _settleClose(tester);
    });

    testWidgets('long words wrap to the room under the board and fade at '
        'their end, the room never changing', (tester) async {
      final words = List.filled(
        40,
        'The bishop sacrifice opens the king.',
      ).join(' ');
      final pgn = _annotatedPgn.replaceFirst('Threatening mate on f7.', words);
      final game = buildStoryGame(_game('l0'), pgn: pgn);
      final batch = StoryBatch(games: [game], ordered: [game.game], total: 1);
      await _pumpRow(
        tester,
        collections: [_collection('l', games: 1)],
        batches: {'l': batch},
      );
      await _open(tester, 'l');
      final room = find.byKey(const ValueKey('story_note_room'));
      final before = tester.getRect(room);
      final face = find.byKey(const ValueKey('story_page_l'));
      final total = game.replay.scheduledDuration!;
      final now = _barsIn(tester, face).progress.value;
      final target = (game.replay.startOf(5) + game.replay.startOf(6)) / 2;
      await tester.pump(total * (target - now));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.getRect(room), before);
      final comment = find.byKey(const ValueKey('story_note_comment'));
      final texts = tester
          .widgetList<Text>(
            find.descendant(of: comment, matching: find.byType(Text)),
          )
          .toList();
      // One paragraph, centred like the lines above it, cut after its lines
      // and its last line fading downward.
      expect(texts, hasLength(1));
      expect(texts.single.textAlign, TextAlign.center);
      expect(texts.single.maxLines, greaterThan(1));
      expect(
        find.descendant(
          of: comment,
          matching: find.byKey(const ValueKey('story_note_comment_fade')),
        ),
        findsOneWidget,
      );
      expect(
        tester.getRect(comment).bottom,
        lessThanOrEqualTo(before.bottom + 0.5),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('story_close')));
      await _settleClose(tester);
    });

    testWidgets('every story keeps the notes\' room, so the board stands in '
        'one place from a plain game to an annotated one', (tester) async {
      final plain = buildStoryGame(_game('m0'), pgn: _pgn);
      final noted = buildStoryGame(_game('m1'), pgn: _annotatedPgn);
      await _pumpRow(
        tester,
        collections: [_collection('m', games: 2)],
        batches: {
          'm': StoryBatch(
            games: [plain, noted],
            ordered: [plain.game, noted.game],
            total: 2,
          ),
        },
      );
      await _open(tester, 'm');
      final board = tester.getRect(find.byKey(const ValueKey('story_board')));
      expect(find.byKey(const ValueKey('story_notes')), findsNothing);
      await _tapStory(tester, 0.8);
      expect(_story('m1'), findsOneWidget);
      expect(find.byKey(const ValueKey('story_notes')), findsOneWidget);
      expect(tester.getRect(find.byKey(const ValueKey('story_board'))), board);
      await tester.tap(find.byKey(const ValueKey('story_close')));
      await _settleClose(tester);
    });
  });

  group('notes room', () {
    for (final kind in [CollectionKind.event, CollectionKind.book]) {
      testWidgets(
        'an ${kind.name} of plain games keeps its story centred, with no '
        'empty band under it',
        (tester) async {
          final c = Collection(
            id: 'p',
            slug: 'p',
            kind: kind,
            title: 'Plain',
            gameCount: 2,
            access: CollectionAccess.free,
          );
          await _pumpRow(
            tester,
            collections: [c],
            batches: {'p': _batch('p', 2)},
          );
          await _open(tester, 'p');
          expect(find.byKey(const ValueKey('story_note_room')), findsNothing);
          final board = tester.getRect(
            find.byKey(const ValueKey('story_board')),
          );
          expect(board.width, closeTo(393 - 32, 0.5));
          await tester.tap(find.byKey(const ValueKey('story_close')));
          await _settleClose(tester);
        },
      );
    }
  });

  group('notes beside the board', () {
    testWidgets('on a phone on its side an annotated story sets its notes '
        'between the players, inside the board\'s height', (tester) async {
      final batch = _annotatedBatch('s', 1);
      await _pumpRow(
        tester,
        collections: [_collection('s', games: 1)],
        batches: {'s': batch},
        size: const Size(852, 393),
      );
      await _open(tester, 's');
      expect(tester.takeException(), isNull);
      final replay = batch.games.single.replay;
      final face = find.byKey(const ValueKey('story_page_s'));
      final now = _barsIn(tester, face).progress.value;
      await tester.pump(
        replay.scheduledDuration! *
            ((replay.startOf(5) + replay.startOf(6)) / 2 - now),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      final board = tester.getRect(find.byKey(const ValueKey('story_board')));
      final move = tester.getRect(
        find.byKey(const ValueKey('story_note_move')),
      );
      final rows = [
        for (final e in find.byType(StoryPlayerRow).evaluate())
          tester.getRect(find.byWidget(e.widget)),
      ];
      expect(move.left, greaterThan(board.right));
      expect(move.top, greaterThan(rows.first.bottom));
      expect(move.bottom, lessThan(rows.last.top));
      expect(find.text('Threatening mate on f7.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('story_close')));
      await _settleClose(tester);
    });
  });

  group('the way to the collection', () {
    for (final via in ['header', 'View collection']) {
      testWidgets('$via opens the collection\'s page over the stories, which '
          'wait and play on once the reader is back', (tester) async {
        final harness = await _pumpRow(
          tester,
          collections: [_collection('a')],
          batches: {'a': _batch('a', 3)},
        );
        await _open(tester, 'a');
        await tester.pump(kStoryGameDuration * 0.2);
        final face = find.byKey(const ValueKey('story_page_a'));
        final at = _barsIn(tester, face).progress.value;
        await tester.tap(
          find.byKey(
            ValueKey(
              via == 'header' ? 'story_header_open' : 'story_view_collection',
            ),
          ),
        );
        await tester.pump();
        await _run(tester, const Duration(milliseconds: 600));
        expect(find.byKey(const ValueKey('collection_page')), findsOneWidget);
        expect(find.text('Page a'), findsOneWidget);
        // Today under it is told it is covered: its streams stop.
        expect(harness.container.read(storyViewerCoversProvider), isTrue);
        await tester.pump(const Duration(seconds: 12));
        Navigator.of(
          tester.element(find.byKey(const ValueKey('collection_page'))),
        ).pop();
        await tester.pump();
        await _run(tester, const Duration(milliseconds: 600));
        expect(find.byKey(const ValueKey('collection_page')), findsNothing);
        // The same story, from where it was.
        expect(_story('a0'), findsOneWidget);
        final back = _barsIn(tester, face).progress.value;
        expect(back, greaterThanOrEqualTo(at));
        expect(back, lessThan(at + 0.15));
        await tester.pump(kStoryGameDuration * 0.3);
        expect(_barsIn(tester, face).progress.value, greaterThan(back + 0.2));
        await tester.tap(find.byKey(const ValueKey('story_close')));
        await _settleClose(tester);
      });
    }

    testWidgets('the actions sit on the story\'s edges, on one baseline, '
        'each a 44pt target', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 2)},
      );
      await _open(tester, 'a');
      final board = tester.getRect(find.byKey(const ValueKey('story_board')));
      final view = tester.getRect(
        find.byKey(const ValueKey('story_view_collection')),
      );
      final open = tester.getRect(
        find.byKey(const ValueKey('story_open_game')),
      );
      expect(view.left, closeTo(board.left, 0.5));
      expect(open.right, closeTo(board.right, 0.5));
      expect(view.height, greaterThanOrEqualTo(44));
      expect(open.height, greaterThanOrEqualTo(44));
      final labels = [
        tester.getRect(find.text('View collection')),
        tester.getRect(find.text('Open game')),
      ];
      expect(labels.first.bottom, closeTo(labels.last.bottom, 0.5));
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('edge pull', () {
    late List<String> haptics;

    setUp(() => haptics = []);

    void listenHaptics(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add('${call.arguments}');
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
    }

    Finder row() => find.byType(TodayStoryRow, skipOffstage: false);

    /// Pulls the row by [dx] in steps from [from], as a finger does.
    Future<TestGesture> pull(
      WidgetTester tester,
      Offset from,
      double dx,
    ) async {
      final gesture = await tester.startGesture(from);
      final steps = (dx.abs() / 12).ceil();
      for (var i = 0; i < steps; i++) {
        await gesture.moveBy(Offset(dx / steps, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      return gesture;
    }

    double fill(WidgetTester tester) {
      final mark = find.byKey(const ValueKey('story_row_pull_mark'));
      if (mark.evaluate().isEmpty) return 0;
      final paint = tester.widget<CustomPaint>(
        find.descendant(of: mark, matching: find.byType(CustomPaint)),
      );
      return (paint.painter! as StoryPullMarkPainter).progress;
    }

    testWidgets('a pull short of the trigger springs back: nothing goes', (
      tester,
    ) async {
      listenHaptics(tester);
      final harness = await _pumpRow(
        tester,
        collections: [
          for (final s in ['a', 'b', 'c']) _collection(s),
        ],
        batches: {
          for (final s in ['a', 'b', 'c']) s: _batch(s, 2),
        },
      );
      final full = tester.getSize(row()).height;
      final gesture = await pull(tester, tester.getCenter(_circle('b')), 90);
      expect(fill(tester), inExclusiveRange(0.2, 1.0));
      await gesture.up();
      await _run(tester, const Duration(milliseconds: 900));
      expect(harness.prefs.dismissal, isNull);
      expect(tester.getSize(row()).height, full);
      expect(fill(tester), 0);
      expect(haptics, isEmpty);
      expect(find.text('Undo'), findsNothing);
    });

    for (final end in [false, true]) {
      testWidgets('past the trigger at the ${end ? 'last' : 'first'} circle '
          'it arms with a haptic; letting go puts the row away on its '
          'spring, and Undo brings it back', (tester) async {
        listenHaptics(tester);
        final slugs = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
        final harness = await _pumpRow(
          tester,
          collections: [for (final s in slugs) _collection(s)],
          batches: {for (final s in slugs) s: _batch(s, 2)},
        );
        final scroll = tester.state<ScrollableState>(
          find.descendant(of: row(), matching: find.byType(Scrollable)),
        );
        if (end) {
          scroll.position.jumpTo(scroll.position.maxScrollExtent);
          await tester.pump();
        }
        final full = tester.getSize(row()).height;
        final below = tester.getTopLeft(find.byKey(const ValueKey('below')));
        final gesture = await pull(
          tester,
          const Offset(196, 80 + 40),
          end ? -260 : 260,
        );
        expect(fill(tester), 1);
        expect(haptics, ['HapticFeedbackType.selectionClick']);
        // The mark sits at the end pulled, in the room the pull opened.
        final mark = tester.getRect(
          find.byKey(const ValueKey('story_row_pull_mark')),
        );
        if (end) {
          expect(mark.left, greaterThan(393 / 2));
        } else {
          expect(mark.right, lessThan(393 / 2));
        }
        await gesture.up();
        await tester.pump();
        expect(harness.prefs.dismissal, isNotNull);
        // Away on its spring: the list under it moves up with it, a little
        // each frame, never a jump.
        var height = tester.getSize(row()).height;
        var moves = 0;
        for (var i = 0; i < 90; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          final now = tester.getSize(row()).height;
          expect(now, lessThanOrEqualTo(height + 0.01));
          expect(height - now, lessThan(full * 0.25));
          if (now < height) moves++;
          height = now;
        }
        expect(moves, greaterThan(8));
        expect(height, 0);
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('below'))).dy,
          closeTo(below.dy - full, 0.5),
        );
        // The way back, and where the choice lives.
        expect(find.textContaining('Settings'), findsOneWidget);
        await tester.tap(find.text('Undo'));
        await tester.pump();
        await _run(tester, const Duration(milliseconds: 1200));
        expect(harness.prefs.dismissal, isNull);
        expect(tester.getSize(row()).height, closeTo(full, 0.01));
        await tester.pump(const Duration(seconds: 5));
      });
    }

    testWidgets('a fling that carries the row past its end never puts it '
        'away', (tester) async {
      listenHaptics(tester);
      final slugs = ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'];
      final harness = await _pumpRow(
        tester,
        collections: [for (final s in slugs) _collection(s)],
        batches: {for (final s in slugs) s: _batch(s, 2)},
      );
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: row(), matching: find.byType(Scrollable)),
      );
      scroll.position.jumpTo(200);
      await tester.pump();
      await tester.flingFrom(
        const Offset(196, 80 + 40),
        const Offset(120, 0),
        5000,
      );
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(scroll.position.pixels, 0);
      expect(harness.prefs.dismissal, isNull);
      expect(haptics, isEmpty);
      expect(_circle('a'), findsOneWidget);
    });
  });

  group('lifecycle', () {
    final day = DateTime(2026, 11, 20, 10);

    testWidgets('put away, the row stays away until a new collection comes; '
        'then it is back, the new one first', (tester) async {
      final catalog = [_collection('a'), _collection('b')];
      final batches = {
        'a': _batch('a', 2),
        'b': _batch('b', 2),
        'n': _batch('n', 2),
      };
      final harness = await _pumpRow(
        tester,
        collections: catalog,
        batches: batches,
        clock: () => day,
      );
      harness.container
          .read(storyRowPrefsProvider.notifier)
          .dismiss(List.of(catalog));
      await tester.pump();
      await _frames(tester);
      final row = find.byType(TodayStoryRow, skipOffstage: false);
      expect(tester.getSize(row).height, 0);
      // Read again with nothing new: still away.
      harness.container.invalidate(storyCollectionsProvider);
      await tester.pump();
      await _frames(tester);
      expect(tester.getSize(row).height, 0);
      // A new collection: back, first.
      catalog.add(_collection('n'));
      harness.container.invalidate(storyCollectionsProvider);
      await tester.pump();
      await _frames(tester);
      expect(tester.getSize(row).height, greaterThan(50));
      expect(harness.prefs.dismissal, isNull);
      final xs = {
        for (final s in ['a', 'b', 'n']) s: tester.getTopLeft(_circle(s)).dx,
      };
      expect(xs['n']! < xs['a']!, isTrue);
      expect(xs['a']! < xs['b']!, isTrue);
    });

    testWidgets('with every story seen the row stays the rest of the day; '
        'the next day it is away from the first frame', (tester) async {
      final catalog = [_collection('a'), _collection('b')];
      final batches = {'a': _batch('a', 2), 'b': _batch('b', 2)};
      final store = _RowStore();
      final seen = _allSeen(catalog, batches);
      var harness = await _pumpRow(
        tester,
        collections: catalog,
        batches: batches,
        seen: seen,
        rowStore: store,
        clock: () => day,
      );
      final row = find.byType(TodayStoryRow, skipOffstage: false);
      await tester.pump();
      expect(tester.getSize(row).height, greaterThan(50));
      expect(harness.prefs.allSeenDay, '2026-11-20');
      // Later the same day: still there.
      await tester.pumpWidget(const SizedBox());
      harness = await _pumpRow(
        tester,
        collections: catalog,
        batches: batches,
        seen: seen,
        rowStore: store,
        clock: () => day.add(const Duration(hours: 12)),
      );
      expect(tester.getSize(row).height, greaterThan(50));
      // The next day: away from the first frame, no skeleton, nothing
      // moving.
      await tester.pumpWidget(const SizedBox());
      await _pumpRow(
        tester,
        collections: catalog,
        batches: batches,
        seen: seen,
        rowStore: store,
        clock: () => day.add(const Duration(days: 1)),
        settle: false,
      );
      for (var i = 0; i < 40; i++) {
        expect(tester.getSize(row).height, 0);
        expect(find.byKey(const ValueKey('story_row_skeleton')), findsNothing);
        await tester.pump(const Duration(milliseconds: 16));
      }
    });

    testWidgets('a row put away on another day never flashes on launch', (
      tester,
    ) async {
      final catalog = [_collection('a'), _collection('b')];
      final store = _RowStore(
        local: StoryRowPrefs(
          dismissal: StoryRowDismissal.of(day, storyCatalogSnapshot(catalog)),
          updatedAt: day.millisecondsSinceEpoch,
        ).encodeLocal(),
      );
      await _pumpRow(
        tester,
        collections: catalog,
        batches: {'a': _batch('a', 2), 'b': _batch('b', 2)},
        rowStore: store,
        clock: () => day.add(const Duration(days: 3)),
        settle: false,
      );
      final row = find.byType(TodayStoryRow, skipOffstage: false);
      for (var i = 0; i < 40; i++) {
        expect(tester.getSize(row).height, 0);
        expect(find.byKey(const ValueKey('story_row_skeleton')), findsNothing);
        await tester.pump(const Duration(milliseconds: 16));
      }
    });

    test('the rule, case by case', () {
      final a = _collection('a', games: 3);
      final event = _collection('e', games: 40);
      const today = '2026-11-20';
      StoryRowDecision decide(
        StoryRowPrefs prefs,
        List<Collection> catalog, {
        bool seen = true,
      }) => decideStoryRow(
        prefs: prefs,
        catalog: catalog,
        isSeen: (_) => seen,
        today: today,
      );

      // When new: something unseen shows it; all seen shows it today only.
      expect(decide(const StoryRowPrefs(), [a], seen: false).shows, isTrue);
      final first = decide(const StoryRowPrefs(), [a]);
      expect(first.shows, isTrue);
      expect(first.allSeenDay, today);
      expect(
        decide(const StoryRowPrefs(allSeenDay: '2026-11-19'), [a]).shows,
        isFalse,
      );
      // Always: whatever was seen.
      expect(
        decide(
          const StoryRowPrefs(
            mode: StoryRowMode.always,
            allSeenDay: '2026-11-19',
          ),
          [a],
        ).shows,
        isTrue,
      );
      // Off: never.
      expect(
        decide(const StoryRowPrefs(mode: StoryRowMode.off), [
          a,
        ], seen: false).shows,
        isFalse,
      );
      // Put away: until something new, in every mode but Off.
      for (final mode in [StoryRowMode.whenNew, StoryRowMode.always]) {
        final away = StoryRowPrefs(
          mode: mode,
          dismissal: StoryRowDismissal.of(
            day,
            storyCatalogSnapshot([a, event]),
          ),
        );
        expect(decide(away, [a, event], seen: false).shows, isFalse);
        // An event growing past its stories is nothing new to show.
        expect(
          decide(away, [a, _collection('e', games: 48)], seen: false).shows,
          isFalse,
        );
        final grown = decide(away, [_collection('a', games: 4), event]);
        expect(grown.shows, isTrue);
        expect(grown.fresh, {'a'});
        expect(grown.returning, isTrue);
        expect(grown.clearDismissal, isTrue);
      }
      expect(storyRowExpected(const StoryRowPrefs(), today), isTrue);
      expect(
        storyRowExpected(const StoryRowPrefs(allSeenDay: today), today),
        isTrue,
      );
      expect(
        storyRowExpected(const StoryRowPrefs(allSeenDay: '2026-11-19'), today),
        isFalse,
      );
      expect(
        storyRowExpected(
          const StoryRowPrefs(
            mode: StoryRowMode.always,
            allSeenDay: '2026-11-19',
          ),
          today,
        ),
        isTrue,
      );
    });
  });

  group('settings', () {
    test('the choice is kept on the device and the account, and the newer '
        'copy wins', () async {
      final store = _RowStore(account: {});
      var container = ProviderContainer(
        overrides: [storyRowPrefsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      expect(container.read(storyRowPrefsProvider).mode, StoryRowMode.whenNew);
      await container
          .read(storyRowPrefsProvider.notifier)
          .setMode(StoryRowMode.always);
      await Future<void>.delayed(Duration.zero);
      expect(jsonDecode(store.local!), containsPair('m', 'always'));
      expect(store.account, containsPair('m', 'always'));
      expect(store.accountWrites, greaterThanOrEqualTo(1));

      // Another launch reads the device's copy at once.
      container.dispose();
      container = ProviderContainer(
        overrides: [storyRowPrefsStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      expect(container.read(storyRowPrefsProvider).mode, StoryRowMode.always);

      // Changed on another device since: the account's copy wins.
      store.account = {'m': 'off', 'u': DateTime(2030).millisecondsSinceEpoch};
      store.changes.add(null);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(storyRowPrefsProvider).mode, StoryRowMode.off);
      expect(jsonDecode(store.local!), containsPair('m', 'off'));

      // A choice made signed out reaches a fresh account on sign in.
      final signedOut = _RowStore();
      final other = ProviderContainer(
        overrides: [storyRowPrefsStoreProvider.overrideWithValue(signedOut)],
      );
      addTearDown(other.dispose);
      await other
          .read(storyRowPrefsProvider.notifier)
          .setMode(StoryRowMode.off);
      signedOut.account = {};
      await other.read(storyRowPrefsProvider.notifier).pull();
      expect(signedOut.account, containsPair('m', 'off'));
    });

    testWidgets('Settings › Collection stories: Off takes the row away on '
        'its spring, Always brings it back', (tester) async {
      final catalog = [_collection('a'), _collection('b')];
      final batches = {'a': _batch('a', 2), 'b': _batch('b', 2)};
      final harness = await _pumpRow(
        tester,
        collections: catalog,
        batches: batches,
        below: const Padding(
          key: ValueKey('below'),
          padding: EdgeInsets.all(16),
          child: StoryRowSettingsBody(),
        ),
      );
      final row = find.byType(TodayStoryRow, skipOffstage: false);
      final full = tester.getSize(row).height;
      expect(find.text('When new'), findsOneWidget);

      Future<void> choose(String label) async {
        await tester.tap(find.text('Collection stories'));
        await tester.pump();
        await _run(tester, const Duration(milliseconds: 600));
        await tester.tap(find.text(label).last);
        await tester.pump();
      }

      await choose('Off');
      var height = tester.getSize(row).height;
      var frames = 0;
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final now = tester.getSize(row).height;
        expect(now, lessThanOrEqualTo(height + 0.01));
        if (now < height) frames++;
        height = now;
      }
      expect(frames, greaterThan(8));
      expect(height, 0);
      expect(harness.prefs.mode, StoryRowMode.off);
      expect(find.text('Off'), findsOneWidget);
      expect(jsonDecode(harness.rowStore.local!), containsPair('m', 'off'));

      // Everything seen and the day over: Always still shows it.
      await choose('Always');
      await _run(tester, const Duration(milliseconds: 1200));
      expect(tester.getSize(row).height, closeTo(full, 0.01));
      expect(harness.prefs.mode, StoryRowMode.always);
    });

    testWidgets('Off never reads the catalog, and the pull does nothing', (
      tester,
    ) async {
      var reads = 0;
      tester.view.physicalSize = const Size(393, 852) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final store = _RowStore(
        local: const StoryRowPrefs(mode: StoryRowMode.off).encodeLocal(),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storyCollectionsProvider.overrideWith((ref) async {
              reads++;
              return [_collection('a')];
            }),
            storySeenStorageProvider.overrideWithValue(_MemoryStorage()),
            storyRowPrefsStoreProvider.overrideWithValue(store),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return const Scaffold(body: TodayStoryRow(gutter: 16));
              },
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(reads, 0);
      expect(_circle('a'), findsNothing);
      expect(find.byKey(const ValueKey('story_row_skeleton')), findsNothing);
    });
  });

  group('review: edges of the pull and the notes', () {
    Finder row() => find.byType(TodayStoryRow, skipOffstage: false);

    /// Moves [gesture] (or a new one from [from]) by [dx], as a finger does.
    Future<TestGesture> drag(
      WidgetTester tester,
      double dx, {
      Offset from = const Offset(196, 120),
      TestGesture? gesture,
    }) async {
      final g = gesture ?? await tester.startGesture(from);
      final steps = (dx.abs() / 12).ceil();
      for (var i = 0; i < steps; i++) {
        await g.moveBy(Offset(dx / steps, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      return g;
    }

    testWidgets('armed, then taken back under the trigger, or back into the '
        'row: letting go keeps the row', (tester) async {
      final slugs = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
      final harness = await _pumpRow(
        tester,
        collections: [for (final s in slugs) _collection(s)],
        batches: {for (final s in slugs) s: _batch(s, 2)},
      );
      final full = tester.getSize(row()).height;
      var g = await drag(tester, 260);
      g = await drag(tester, -150, gesture: g);
      await g.up();
      await _run(tester, const Duration(milliseconds: 900));
      expect(harness.prefs.dismissal, isNull);
      expect(tester.getSize(row()).height, full);
      g = await drag(tester, 260);
      g = await drag(tester, -400, gesture: g);
      await g.up();
      await _run(tester, const Duration(milliseconds: 900));
      expect(harness.prefs.dismissal, isNull);
      expect(find.text('Undo'), findsNothing);
    });

    for (final end in [false, true]) {
      testWidgets('a row too short to scroll still puts away from its '
          '${end ? 'last' : 'first'} circle', (tester) async {
        final harness = await _pumpRow(
          tester,
          collections: [_collection('a'), _collection('b')],
          batches: {'a': _batch('a', 2), 'b': _batch('b', 2)},
        );
        final g = await drag(tester, end ? -260 : 260);
        await g.up();
        await tester.pump();
        expect(harness.prefs.dismissal, isNotNull);
        await _run(tester, const Duration(seconds: 6));
      });
    }

    testWidgets('put away, then a book gains games: back, the book first, '
        'and it keeps leading', (tester) async {
      Collection book(int games) => Collection(
        id: 'bk',
        slug: 'bk',
        kind: CollectionKind.book,
        title: 'Book',
        gameCount: games,
        access: CollectionAccess.free,
      );
      final catalog = [_collection('a'), _collection('b'), book(20)];
      final harness = await _pumpRow(
        tester,
        collections: catalog,
        batches: {
          'a': _batch('a', 2),
          'b': _batch('b', 2),
          'bk': _batch('bk', kStoryCap, total: 20),
        },
      );
      harness.container
          .read(storyRowPrefsProvider.notifier)
          .dismiss(List.of(catalog));
      await tester.pump();
      await _frames(tester);
      expect(tester.getSize(row()).height, 0);
      catalog[2] = book(21);
      harness.container.invalidate(storyCollectionsProvider);
      await tester.pump();
      await _frames(tester);
      expect(harness.prefs.dismissal, isNull);
      expect(tester.getSize(row()).height, greaterThan(50));
      for (var i = 0; i < 2; i++) {
        expect(
          tester.getTopLeft(_circle('bk')).dx,
          lessThan(tester.getTopLeft(_circle('a')).dx),
        );
        harness.container.invalidate(storyCollectionsProvider);
        await tester.pump();
        await _frames(tester, const Duration(milliseconds: 300));
      }
    });

    test('malformed arrows and squares are skipped, never thrown', () {
      final replay = StoryReplay.fromPgn(
        '[Event "T"]\n\n1. e4 { [%cal Gz9a1,Ge2,Xe2e4,,  Gd2d4 ,GE2E4] '
        '[%csl Rz9,R,Rd4x,Yh8] [%cal] ok } e5 *',
      )!;
      final shapes = replay.noteAt(1)!.shapes;
      expect(shapes.whereType<Arrow>().length, 2);
      expect(shapes.whereType<Circle>().length, 1);
      expect(replay.noteAt(1)!.comment, 'ok');
    });
  });
  group('second review: notes, pacing, lifecycle, accounts', () {
    final day = DateTime(2026, 11, 20, 10);
    Finder row() => find.byType(TodayStoryRow, skipOffstage: false);

    for (final width in [393.0, 360.0]) {
      testWidgets('long words at ${width.round()}pt stay one paragraph: '
          'every line whole and centred, the last one too, drawn with the '
          'page\'s own letter spacing', (tester) async {
        const words =
            'Black has given up the exchange and a pawn, but with his bishop '
            'and his pawns, now pointing at the white king, he finds that his '
            'king is safe while White\'s pieces stand far from the action; the '
            'knight on b5 will never get back in time, and the rook on a1 has '
            'no open file to use. Every tempo counts from here on.';
        final pgn = _annotatedPgn.replaceFirst(
          'Threatening mate on f7.',
          words,
        );
        final game = buildStoryGame(_game('w0'), pgn: pgn);
        final batch = StoryBatch(games: [game], ordered: [game.game], total: 1);
        // The page's text carries its own tracking (Material's body style
        // does); set wide here so a measure made without it shows.
        final base = AppTheme.darkTheme;
        await _pumpRow(
          tester,
          collections: [_collection('w', games: 1)],
          batches: {'w': batch},
          size: Size(width, 852),
          theme: base.copyWith(
            textTheme: base.textTheme.copyWith(
              bodyMedium: (base.textTheme.bodyMedium ?? const TextStyle())
                  .copyWith(letterSpacing: 1.5),
            ),
          ),
        );
        await _open(tester, 'w');
        final face = find.byKey(const ValueKey('story_page_w'));
        final total = game.replay.scheduledDuration!;
        final now = _barsIn(tester, face).progress.value;
        final target = (game.replay.startOf(5) + game.replay.startOf(6)) / 2;
        await tester.pump(total * (target - now));
        await tester.pump(const Duration(milliseconds: 400));
        final comment = find.byKey(const ValueKey('story_note_comment'));
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: comment, matching: find.byType(RichText)),
        );
        // The words run over: one paragraph cut after its lines (never a
        // line cut out of its middle), centred to its last line.
        expect(paragraph.text.toPlainText(), words);
        final lines = paragraph.maxLines!;
        expect(lines, greaterThan(1));
        expect(paragraph.textAlign, TextAlign.center);
        expect(paragraph.overflow, TextOverflow.clip);
        // Its last line is a line of the paragraph like the others: as
        // wide as the words it holds, centred in the room.
        final room = paragraph.size.width;
        // The words drawn: up to the end of the last line laid out.
        final shownEnd = paragraph
            .getPositionForOffset(
              Offset(room - 0.5, paragraph.textSize.height - 0.5),
            )
            .offset;
        expect(shownEnd, lessThan(words.length));
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: shownEnd),
        );
        final lineTops = <double>{for (final b in boxes) b.top.roundToDouble()};
        expect(lineTops, hasLength(lines));
        final lastTop = lineTops.reduce(math.max);
        final last = boxes.where((b) => b.top.roundToDouble() == lastTop);
        final left = last.map((b) => b.left).reduce(math.min);
        final right = last.map((b) => b.right).reduce(math.max);
        expect(right - left, lessThan(room - 4));
        expect(left, closeTo(room - right, 2));
        // The fade sits on it.
        expect(
          find.descendant(
            of: comment,
            matching: find.byKey(const ValueKey('story_note_comment_fade')),
          ),
          findsOneWidget,
        );
        // Drawn with the page's own letter spacing, as measured.
        final spacing = DefaultTextStyle.of(
          tester.element(comment),
        ).style.letterSpacing;
        expect(spacing, 1.5);
        expect(paragraph.text.style?.letterSpacing, spacing);
        await tester.tap(find.byKey(const ValueKey('story_close')));
        await _settleClose(tester);
      });
    }

    test('a note on the game\'s last move holds as long as its words need, '
        'not just the end\'s beat', () {
      const words =
          'White resigned here: the passed pawn costs a rook, and nothing '
          'else holds the position together.';
      final replay = StoryReplay.fromPgn(
        '[Result "0-1"]\n\n1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 { $words } 0-1',
      )!;
      final total = replay.scheduledDuration!.inMicroseconds / 1e6;
      final note = replay.noteAt(replay.plies)!;
      expect(note.comment, words);
      final dwell = StoryReplay.dwellOf(note);
      expect(dwell, greaterThan(StoryReplay.tail * 2));
      final lastHold = total - replay.startOf(replay.plies) * total;
      expect(lastHold, greaterThanOrEqualTo(dwell - 1e-6));
      // A plain last move keeps the end's beat.
      final plain = StoryReplay.fromPgn(
        '[Result "0-1"]\n\n1. e4 { Open. } e5 2. Nf3 Nc6 3. Bb5 a6 0-1',
      )!;
      final plainTotal = plain.scheduledDuration!.inMicroseconds / 1e6;
      expect(
        plainTotal - plain.startOf(plain.plies) * plainTotal,
        greaterThanOrEqualTo(StoryReplay.tail - 1e-6),
      );
    });

    testWidgets('the move line steps through plain moves at once and settles '
        'only into an annotated one', (tester) async {
      final batch = _annotatedBatch('t', 1);
      await _pumpRow(
        tester,
        collections: [_collection('t', games: 1)],
        batches: {'t': batch},
      );
      await _open(tester, 't');
      final replay = batch.games.single.replay;
      final total = replay.scheduledDuration!;
      final face = find.byKey(const ValueKey('story_page_t'));
      double opacity() => tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.byKey(const ValueKey('story_note_move')),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;
      Future<void> to(double share) async {
        final now = _barsIn(tester, face).progress.value;
        await tester.pump(total * (share - now));
      }

      // Each plain move, the frame it lands: full ink, no pulse.
      for (final step in [2, 3, 4]) {
        await to(replay.startOf(step) - 0.004);
        await to(replay.startOf(step) + 0.002);
        expect(replay.stepAt(_barsIn(tester, face).progress.value), step);
        expect(opacity(), 1);
      }
      // The annotated move settles in.
      await to(replay.startOf(5) - 0.004);
      await to(replay.startOf(5) + 0.002);
      expect(opacity(), lessThan(0.9));
      await tester.pump(const Duration(milliseconds: 400));
      expect(opacity(), closeTo(1, 0.01));
      await tester.tap(find.byKey(const ValueKey('story_close')));
      await _settleClose(tester);
    });

    for (final light in [false, true]) {
      testWidgets('every glyph reads on the story\'s '
          '${light ? 'paper' : 'dark page'}', (tester) async {
        late BuildContext context;
        await tester.pumpWidget(
          MaterialApp(
            theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
            home: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        );
        final page = context.colors.background;
        var checked = 0;
        for (var nag = 1; nag < 256; nag++) {
          final display = getNagDisplay(nag);
          if (display == null) continue;
          final ink = storyGlyphInk(context, display);
          if (light) {
            expect(ink, nagInk(context, display));
          } else {
            expect(wcagContrast(ink, page), greaterThanOrEqualTo(4.5));
            // The same hue, only lighter.
            final hue = HSLColor.fromColor(display.color);
            final lifted = HSLColor.fromColor(ink);
            if (hue.saturation > 0.05) {
              expect(lifted.hue, closeTo(hue.hue, 1.5));
            }
            expect(
              lifted.lightness,
              greaterThanOrEqualTo(hue.lightness - 1e-6),
            );
          }
          checked++;
        }
        expect(checked, greaterThan(5));
      });
    }

    for (final end in [false, true]) {
      testWidgets('the pull mark never sits nearer the screen\'s edge than '
          'the page\'s gutter, nor over the ${end ? 'last' : 'first'} '
          'circle', (tester) async {
        final slugs = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
        await _pumpRow(
          tester,
          collections: [for (final s in slugs) _collection(s)],
          batches: {for (final s in slugs) s: _batch(s, 2)},
        );
        final scroll = tester.state<ScrollableState>(
          find.descendant(of: row(), matching: find.byType(Scrollable)),
        );
        if (end) {
          scroll.position.jumpTo(scroll.position.maxScrollExtent);
          await tester.pump();
        }
        final gesture = await tester.startGesture(const Offset(196, 120));
        var seen = 0;
        for (var i = 0; i < 26; i++) {
          await gesture.moveBy(Offset(end ? -10 : 10, 0));
          await tester.pump(const Duration(milliseconds: 16));
          final mark = find.byKey(const ValueKey('story_row_pull_mark'));
          if (mark.evaluate().isEmpty) continue;
          seen++;
          final rect = tester.getRect(mark);
          final circle = tester.getRect(_circle(end ? 'g' : 'a'));
          if (end) {
            expect(393 - rect.right, greaterThanOrEqualTo(16 - 0.01));
            expect(rect.left, greaterThan(circle.right + 2));
          } else {
            expect(rect.left, greaterThanOrEqualTo(16 - 0.01));
            expect(rect.right, lessThan(circle.left - 2));
          }
        }
        expect(seen, greaterThan(5));
        await gesture.moveBy(Offset(end ? 260 : -260, 0));
        await gesture.up();
        await _run(tester, const Duration(milliseconds: 900));
      });
    }

    testWidgets('left unopened, the row stands three days, then steps away '
        'from the first frame until something new comes, which leads it', (
      tester,
    ) async {
      final catalog = [_collection('a'), _collection('b')];
      final batches = {
        'a': _batch('a', 2),
        'b': _batch('b', 2),
        'n': _batch('n', 2),
      };
      final store = _RowStore();
      for (var d = 0; d < kStoryRowIdleDays; d++) {
        await tester.pumpWidget(const SizedBox());
        final harness = await _pumpRow(
          tester,
          collections: catalog,
          batches: batches,
          rowStore: store,
          clock: () => day.add(Duration(days: d, hours: d)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.getSize(row()).height, greaterThan(50));
        expect(harness.prefs.run!.days, d + 1);
      }
      // The next day: away from the first frame, no skeleton, no jump.
      await tester.pumpWidget(const SizedBox());
      final harness = await _pumpRow(
        tester,
        collections: catalog,
        batches: batches,
        rowStore: store,
        clock: () => day.add(const Duration(days: kStoryRowIdleDays)),
        settle: false,
      );
      for (var i = 0; i < 40; i++) {
        expect(tester.getSize(row()).height, 0);
        expect(find.byKey(const ValueKey('story_row_skeleton')), findsNothing);
        await tester.pump(const Duration(milliseconds: 16));
      }
      // Read again with nothing new: still away.
      harness.container.invalidate(storyCollectionsProvider);
      await tester.pump();
      await _frames(tester, const Duration(milliseconds: 600));
      expect(tester.getSize(row()).height, 0);
      // A new collection: back on its spring, first, with a new stretch.
      catalog.add(_collection('n'));
      harness.container.invalidate(storyCollectionsProvider);
      await tester.pump();
      await _frames(tester);
      expect(tester.getSize(row()).height, greaterThan(50));
      expect(
        tester.getTopLeft(_circle('n')).dx,
        lessThan(tester.getTopLeft(_circle('a')).dx),
      );
      expect(harness.prefs.run!.days, 1);
      // It keeps leading through later reads.
      harness.container.invalidate(storyCollectionsProvider);
      await tester.pump();
      await _frames(tester, const Duration(milliseconds: 300));
      expect(
        tester.getTopLeft(_circle('n')).dx,
        lessThan(tester.getTopLeft(_circle('a')).dx),
      );
    });

    testWidgets('opening a story starts the count of idle days again', (
      tester,
    ) async {
      final catalog = [_collection('a'), _collection('b')];
      final batches = {'a': _batch('a', 2), 'b': _batch('b', 2)};
      final store = _RowStore(
        local: StoryRowPrefs(
          run: StoryRowRun(
            since: storyCatalogSnapshot(catalog),
            days: kStoryRowIdleDays,
            day: storyDayKey(day),
          ),
        ).encodeLocal(),
      );
      // Its last day: there today.
      var harness = await _pumpRow(
        tester,
        collections: catalog,
        batches: batches,
        rowStore: store,
        clock: () => day,
      );
      expect(tester.getSize(row()).height, greaterThan(50));
      await _open(tester, 'a');
      await tester.tap(find.byKey(const ValueKey('story_close')));
      await _settleClose(tester);
      expect(harness.prefs.run!.days, 0);
      // The next day it is still there: the count began again.
      await tester.pumpWidget(const SizedBox());
      harness = await _pumpRow(
        tester,
        collections: catalog,
        batches: batches,
        rowStore: store,
        clock: () => day.add(const Duration(days: 1)),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.getSize(row()).height, greaterThan(50));
      expect(harness.prefs.run!.days, 1);
    });

    test('the stretch, case by case', () {
      final a = _collection('a', games: 3);
      final b = _collection('b', games: 3);
      const today = '2026-11-20';
      const yesterday = '2026-11-19';
      StoryRowDecision decide(StoryRowPrefs prefs, List<Collection> catalog) =>
          decideStoryRow(
            prefs: prefs,
            catalog: catalog,
            isSeen: (_) => false,
            today: today,
          );
      StoryRowRun run(int days, String on) =>
          StoryRowRun(since: storyCatalogSnapshot([a, b]), days: days, day: on);

      // A first look starts a stretch.
      final first = decide(const StoryRowPrefs(), [a, b]);
      expect(first.shows, isTrue);
      expect(first.run!.days, 1);
      expect(first.run!.day, today);
      // A new day on Today counts once.
      final second = decide(StoryRowPrefs(run: run(1, yesterday)), [a, b]);
      expect(second.shows, isTrue);
      expect(second.run, run(2, today));
      expect(
        decide(StoryRowPrefs(run: run(2, today)), [a, b]).run,
        run(2, today),
      );
      // Its last day stands to its end; the day after, it is away.
      expect(decide(StoryRowPrefs(run: run(3, today)), [a, b]).shows, isTrue);
      final over = StoryRowPrefs(run: run(3, yesterday));
      expect(decide(over, [a, b]).shows, isFalse);
      expect(storyRowExpected(over, today), isFalse);
      expect(
        storyRowExpected(StoryRowPrefs(run: run(3, today)), today),
        isTrue,
      );
      // Something new: back, that first, a new stretch.
      final back = decide(over, [_collection('a', games: 4), b]);
      expect(back.shows, isTrue);
      expect(back.returning, isTrue);
      expect(back.fresh, {'a'});
      expect(back.run!.days, 1);
      // Something new while it stands: its days start again, no reorder.
      final renewed = decide(StoryRowPrefs(run: run(2, yesterday)), [
        a,
        b,
        _collection('n'),
      ]);
      expect(renewed.returning, isFalse);
      expect(renewed.run!.days, 1);
      // Always and Off take no notice of it.
      expect(
        decide(
          StoryRowPrefs(mode: StoryRowMode.always, run: run(3, yesterday)),
          [a, b],
        ).shows,
        isTrue,
      );
      expect(
        storyRowExpected(
          StoryRowPrefs(mode: StoryRowMode.always, run: run(3, yesterday)),
          today,
        ),
        isTrue,
      );
      // Everything seen: no stretch is counted.
      expect(
        decideStoryRow(
          prefs: StoryRowPrefs(run: run(1, yesterday)),
          catalog: [a, b],
          isSeen: (_) => true,
          today: today,
        ).run,
        isNull,
      );
      // Kept on the device, read back the same.
      final kept = StoryRowPrefs.decodeLocal(
        StoryRowPrefs(run: run(2, yesterday), owner: 'reader-a').encodeLocal(),
      );
      expect(kept.run, run(2, yesterday));
      expect(kept.owner, 'reader-a');
    });

    test('a choice made under one account never reaches another signing in '
        'on the same device; each account keeps its own', () async {
      final store = _RowStore(account: {}, id: 'reader-a');
      final container = ProviderContainer(
        overrides: [
          storyRowPrefsStoreProvider.overrideWithValue(store),
          storyClockProvider.overrideWithValue(() => day),
        ],
      );
      addTearDown(container.dispose);
      Future<void> settle() async {
        for (var i = 0; i < 4; i++) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      final notifier = container.read(storyRowPrefsProvider.notifier);
      await settle();
      await notifier.setMode(StoryRowMode.always);
      notifier.dismiss([_collection('a')]);
      await settle();
      expect(container.read(storyRowPrefsProvider).owner, 'reader-a');
      expect(store.account, containsPair('m', 'always'));
      expect(store.account!['d'], isNotNull);

      // Another reader signs in on this device; their account is empty.
      store.account = {};
      store.id = 'reader-b';
      final writes = store.accountWrites;
      store.changes.add(null);
      await settle();
      var prefs = container.read(storyRowPrefsProvider);
      expect(prefs.mode, StoryRowMode.whenNew);
      expect(prefs.dismissal, isNull);
      expect(prefs.owner, 'reader-b');
      expect(store.account, isEmpty);
      expect(store.accountWrites, writes);
      expect(jsonDecode(store.local!), containsPair('o', 'reader-b'));

      // Their own choice is theirs.
      await notifier.setMode(StoryRowMode.off);
      await settle();
      expect(store.account, containsPair('m', 'off'));

      // The first reader back: their own choice from their account, even
      // though the device's copy is newer.
      store.account = {'m': 'always', 'u': 1};
      store.id = 'reader-a';
      store.changes.add(null);
      await settle();
      prefs = container.read(storyRowPrefsProvider);
      expect(prefs.mode, StoryRowMode.always);
      expect(prefs.owner, 'reader-a');
      expect(store.account, containsPair('m', 'always'));
    });
  });

  group('third review: schedule, places, refreshes, account', () {
    final day = DateTime(2026, 11, 20, 10);

    /// A game of [plies] knight shuffles with [notes] (by ply) as comments.
    String shuffle(int plies, Map<int, String> notes) {
      final pgn = StringBuffer('[Result "*"]\n\n');
      for (var ply = 1; ply <= plies; ply++) {
        final white = ply.isOdd;
        final out = ((ply - 1) ~/ 2).isEven;
        if (white) pgn.write('${(ply + 1) ~/ 2}. ');
        pgn.write(white ? (out ? 'Nf3 ' : 'Ng1 ') : (out ? 'Nf6 ' : 'Ng8 '));
        if (notes[ply] case final note?) pgn.write('{ $note } ');
      }
      pgn.write('*');
      return pgn.toString();
    }

    int plyOf(StoryMoveNote note) =>
        (note.moveNumber - 1) * 2 + (note.white ? 1 : 2);

    double seconds(StoryReplay replay) =>
        replay.scheduledDuration!.inMicroseconds / 1e6;

    /// Seconds the board holds each step, from the first move on.
    List<double> holds(StoryReplay replay) {
      final total = seconds(replay);
      return [
        for (var step = 1; step <= replay.plies; step++)
          ((step == replay.plies ? 1.0 : replay.startOf(step + 1)) -
                  replay.startOf(step)) *
              total,
      ];
    }

    /// The schedule reads in order, ends on the game's last move, and every
    /// jump of the board crosses a cut stretch, never a move or two.
    void expectSound(StoryReplay replay, int plies) {
      expect(seconds(replay), lessThanOrEqualTo(StoryReplay.maxScheduled));
      for (var step = 1; step <= replay.plies; step++) {
        expect(replay.startOf(step), greaterThan(replay.startOf(step - 1)));
      }
      expect(plyOf(replay.noteAt(replay.plies)!), plies);
      final cut =
          StoryReplay.stretchMax -
          StoryReplay.followPlies -
          StoryReplay.leadPlies;
      for (var step = 2; step <= replay.plies; step++) {
        final gap =
            plyOf(replay.noteAt(step)!) - plyOf(replay.noteAt(step - 1)!);
        expect(gap == 1 || gap > cut, isTrue, reason: 'step $step');
      }
    }

    test(
      'a long game whose notes come early keeps every one of them: its '
      'quiet ending is a few moves and the result, not most of the story',
      () {
        final replay = StoryReplay.fromPgn(
          shuffle(120, {
            for (var p = 1; p <= 10; p++) p: 'Develops with tempo.',
          }),
        )!;
        expectSound(replay, 120);
        final words = [
          for (final n in replay.notes)
            if (n?.comment != null) n!.comment,
        ];
        expect(words, hasLength(10));
        // The plain moves take a few seconds of the story, no more.
        var plain = 0.0;
        final steps = holds(replay);
        for (var step = 1; step <= replay.plies; step++) {
          if (!replay.noteAt(step)!.annotated) plain += steps[step - 1];
        }
        expect(plain, lessThan(6));
      },
    );

    test('more notes than the story holds: the run with the most of them, '
        'then the result, the board jumping only across a cut', () {
      const note =
          'A long thought about the position that runs on for a while, '
          'about ninety characters long.';
      final replay = StoryReplay.fromPgn(
        shuffle(120, {for (var p = 1; p <= 10; p++) p: note}),
      )!;
      expectSound(replay, 120);
      final shown = [
        for (final n in replay.notes)
          if (n?.comment != null) n!,
      ];
      final dwell = StoryReplay.dwellOf(shown.first);
      // As many as fit beside the opening beat and the end's hold.
      final fit =
          ((StoryReplay.maxScheduled - StoryReplay.leadIn - StoryReplay.tail) /
                  dwell)
              .floor();
      expect(shown.length, greaterThanOrEqualTo(fit - 1));
      // Consecutive moments: a run, not scattered picks.
      for (var i = 1; i < shown.length; i++) {
        expect(plyOf(shown[i]) - plyOf(shown[i - 1]), 1);
      }
    });

    test('notes spread over a long game: every moment kept, the quiet '
        'stretches between them cut to the moves around them', () {
      final replay = StoryReplay.fromPgn(
        shuffle(120, {
          5: 'Early idea.',
          9: 'Another one.',
          60: 'The middlegame turns.',
          61: 'The reply.',
          110: 'Into the ending.',
        }),
      )!;
      expectSound(replay, 120);
      expect(
        [
          for (final n in replay.notes)
            if (n?.comment != null) plyOf(n!),
        ],
        [5, 9, 60, 61, 110],
      );
      expect(replay.plies, lessThan(60));
    });

    test('a note the four lines fill holds long enough to read at about 17 '
        'characters a second; a short one holds a beat', () {
      StoryMoveNote note(int chars) => StoryMoveNote(
        san: 'e4',
        moveNumber: 1,
        white: true,
        comment: 'x' * chars,
      );
      expect(StoryReplay.dwellOf(note(200)), greaterThanOrEqualTo(200 / 18));
      expect(StoryReplay.dwellOf(note(200)), StoryReplay.noteMax);
      expect(StoryReplay.dwellOf(note(600)), StoryReplay.noteMax);
      expect(StoryReplay.dwellOf(note(20)), closeTo(2.5, 0.01));
    });

    test('an arrow from a square to itself is never drawn; a command left '
        'open, or with brackets inside, never reaches the words', () {
      final shapes = pgnCommentShapes(['[%cal Ge2e2,Gd2d4] [%csl Ge2]']);
      expect(
        shapes.whereType<Arrow>().map((a) => '${a.orig.name}${a.dest.name}'),
        ['d2d4'],
      );
      expect(shapes.whereType<Circle>(), hasLength(1));
      expect(pgnCommentProse(['Good. [%cal Ge2e4']), 'Good.');
      expect(pgnCommentProse(['a [%evp 1,2,[3]] b']), 'a b');
      expect(pgnCommentProse(['[%clk 0:01:00] [%cal Ge2e4']), isNull);
      // ChessBase's diagram marker is layout, never words.
      expect(pgnCommentProse(['[#]']), isNull);
      expect(pgnCommentProse(['[#] A quiet move.']), 'A quiet move.');
      expect(pgnCommentProse(['Strong. [%eval 0.5] Wins.']), 'Strong. Wins.');
    });

    testWidgets('stories read again while one plays (new games ahead of '
        'it): the reader stays on their game, its bar runs on, and the new '
        'game is not counted seen', (tester) async {
      final batches = {'b': _batch('b', 3)};
      final harness = await _pumpRow(
        tester,
        collections: [_collection('b')],
        batches: batches,
      );
      await _open(tester, 'b');
      expect(_story('b0'), findsOneWidget);
      final face = find.byKey(const ValueKey('story_page_b'));
      await _run(tester, const Duration(seconds: 3));
      final before = _barsIn(tester, face).progress.value;
      expect(before, greaterThan(0.3));
      final fresh = _batch('new', 1).games.single;
      final old = batches['b']!;
      batches['b'] = StoryBatch(
        games: [fresh, ...old.games],
        ordered: [fresh.game, ...old.ordered],
        total: 4,
      );
      harness.container.invalidate(storyBatchProvider('b'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(_story('b0'), findsOneWidget);
        expect(_story('new0'), findsNothing);
      }
      final bars = _barsIn(tester, face);
      expect(bars.index, 1);
      expect(bars.progress.value, greaterThanOrEqualTo(before));
      final batch = harness.container.read(storyBatchProvider('b')).value!;
      final seen = harness.seen.seenIn(_collection('b'), batch);
      expect(seen, contains('b0'));
      expect(seen, isNot(contains('new0')));
      await tester.tap(find.byKey(const ValueKey('story_close')));
      await _settleClose(tester);
    });

    testWidgets('the same game on a new run (a Premium unlock turning its '
        'final position into a replay) starts again, its bar the new '
        'schedule', (tester) async {
      final still = buildStoryGame(_game('p0'));
      expect(still.replay.annotated, isFalse);
      final batches = {
        'p': StoryBatch(games: [still], ordered: [still.game], total: 1),
      };
      final harness = await _pumpRow(
        tester,
        collections: [_collection('p', games: 1)],
        batches: batches,
      );
      await _open(tester, 'p');
      final face = find.byKey(const ValueKey('story_page_p'));
      await _run(tester, const Duration(seconds: 3));
      expect(_barsIn(tester, face).progress.value, greaterThan(0.3));
      final unlocked = buildStoryGame(_game('p0'), pgn: _annotatedPgn);
      batches['p'] = StoryBatch(
        games: [unlocked],
        ordered: [unlocked.game],
        total: 1,
      );
      harness.container.invalidate(storyBatchProvider('p'));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 16));
      final bar = _barsIn(tester, face).progress as AnimationController;
      expect(bar.duration, unlocked.replay.scheduledDuration);
      expect(bar.value, lessThan(0.01));
      expect(_story('p0'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('story_close')));
      await _settleClose(tester);
    });

    Future<void> background(WidgetTester tester) async {
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
    }

    Future<void> resume(WidgetTester tester) async {
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await _frames(tester, const Duration(milliseconds: 700));
    }

    testWidgets('back on Today after a while, the catalog is read again: a '
        'collection that arrived shows, and a row put away comes back with '
        'it first; a short trip away reads nothing', (tester) async {
      var now = day;
      final catalog = [_collection('a'), _collection('b')];
      final harness = await _pumpRow(
        tester,
        collections: catalog,
        batches: {
          for (final s in ['a', 'b', 'n']) s: _batch(s, 2),
        },
        clock: () => now,
        realCatalog: true,
      );
      expect(_circle('a'), findsOneWidget);
      harness.container.read(storyRowPrefsProvider.notifier).dismiss([
        ...catalog,
      ]);
      await _frames(tester, const Duration(milliseconds: 1200));
      final row = find.byType(TodayStoryRow, skipOffstage: false);
      expect(tester.getSize(row).height, 0);
      catalog.insert(0, _collection('n'));

      // Back after two minutes: the catalog stands.
      await background(tester);
      now = day.add(const Duration(minutes: 2));
      await resume(tester);
      expect(tester.getSize(row).height, 0);

      // Back after a while: read again, and what arrived brings it back.
      await background(tester);
      now = day.add(kStoryCatalogStale + const Duration(minutes: 1));
      await resume(tester);
      expect(tester.getSize(row).height, greaterThan(50));
      expect(_circle('n'), findsOneWidget);
      expect(
        tester.getTopLeft(_circle('n')).dx,
        lessThan(tester.getTopLeft(_circle('a')).dx),
      );
      expect(harness.prefs.dismissal, isNull);
    });

    testWidgets('Today\'s pull to refresh reads the catalog again; with the '
        'row Off it reads nothing', (tester) async {
      var reads = 0;
      final catalog = [_collection('a')];
      late WidgetRef refresher;
      final harness = await _pumpRow(
        tester,
        collections: catalog,
        batches: {
          for (final s in ['a', 'n']) s: _batch(s, 2),
        },
        realCatalog: false,
        overrides: [
          collectionsProvider.overrideWith((ref) async {
            reads++;
            return List.of(catalog);
          }),
        ],
        below: Consumer(
          builder: (context, ref, _) {
            refresher = ref;
            return const SizedBox(key: ValueKey('below'), height: 10);
          },
        ),
      );
      // The row's own catalog here is the harness's; Today's refresh reads
      // the app's.
      final listen = harness.container.listen(collectionsProvider, (_, _) {});
      addTearDown(listen.close);
      await tester.pump();
      final first = reads;
      refreshStoryCatalog(refresher);
      await tester.pump();
      expect(reads, first + 1);
      await harness.container
          .read(storyRowPrefsProvider.notifier)
          .setMode(StoryRowMode.off);
      await tester.pump();
      refreshStoryCatalog(refresher);
      await tester.pump();
      expect(reads, first + 1);
    });

    testWidgets('a catalog that counts more games than a collection\'s '
        'stories were read with reads those stories again', (tester) async {
      final reads = <String, int>{};
      final catalog = [_collection('a', games: 2), _collection('b', games: 2)];
      final batches = {
        for (final s in ['a', 'b']) s: _batch(s, 2),
      };
      await _pumpRow(
        tester,
        collections: catalog,
        batches: batches,
        fixedBatches: false,
        overrides: [
          collectionGamesProvider.overrideWith((ref, slug) async {
            reads[slug] = (reads[slug] ?? 0) + 1;
            return const <CollectionGame>[];
          }),
          storyBatchProvider.overrideWith((ref, slug) async {
            // Kept warm after the viewer lets it go, as the app's are.
            ref.keepAlive();
            await ref.watch(collectionGamesProvider(slug).future);
            final batch = batches[slug]!;
            return StoryBatch(
              games: batch.games,
              ordered: batch.ordered,
              total: batch.total,
              gameCount: 2,
            );
          }),
        ],
      );
      // The stories of a are read (opened, then kept warm).
      await _open(tester, 'a');
      await tester.tap(find.byKey(const ValueKey('story_close')));
      await _settleClose(tester);
      expect(reads['a'], 1);
      // The catalog now counts a third game in a.
      catalog[0] = _collection('a', games: 3);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TodayStoryRow)),
      );
      container.invalidate(storyCollectionsProvider);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(reads['a'], 2);
      // Read ahead while a played, and as many games as the catalog says.
      expect(reads['b'], 1);
    });

    test('the account keeps only the pull-away\'s time, fingerprint and '
        'total, a few bytes whatever the catalog; the device keeps the '
        'snapshot', () async {
      final store = _RowStore(account: {});
      final container = ProviderContainer(
        overrides: [
          storyRowPrefsStoreProvider.overrideWithValue(store),
          storyClockProvider.overrideWithValue(() => day),
        ],
      );
      addTearDown(container.dispose);
      final catalog = [
        for (var i = 0; i < 300; i++) _collection('collection-$i', games: i),
      ];
      container.read(storyRowPrefsProvider.notifier).dismiss(catalog);
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final kept = store.account!['d'] as Map;
      expect(kept.keys.toSet(), {'t', 'f', 'g'});
      expect(jsonEncode(kept).length, lessThan(60));
      final local = StoryRowPrefs.decodeLocal(store.local);
      expect(local.dismissal!.snapshot, storyCatalogSnapshot(catalog));
    });

    test('a pull-away made on another device: the same catalog (or a '
        'smaller one) keeps the row away and becomes this device\'s '
        'snapshot; a catalog that grew brings it back', () {
      final a = _collection('a', games: 3);
      final b = _collection('b', games: 5);
      final made = StoryRowDismissal.of(day, storyCatalogSnapshot([a, b]));
      // As the account carries it: no snapshot.
      final remote = StoryRowDismissal.fromJson(made.toAccountJson())!;
      expect(remote.snapshot, isNull);
      expect(remote.sameAs(made), isTrue);
      StoryRowDecision decide(List<Collection> catalog) => decideStoryRow(
        prefs: StoryRowPrefs(dismissal: remote),
        catalog: catalog,
        isSeen: (_) => false,
        today: '2026-11-20',
      );
      final same = decide([a, b]);
      expect(same.shows, isFalse);
      expect(same.adoptSnapshot, storyCatalogSnapshot([a, b]));
      final smaller = decide([a]);
      expect(smaller.shows, isFalse);
      expect(smaller.adoptSnapshot, storyCatalogSnapshot([a]));
      final grown = decide([a, b, _collection('n', games: 2)]);
      expect(grown.shows, isTrue);
      expect(grown.returning, isTrue);
      expect(grown.clearDismissal, isTrue);
      // With its own snapshot, the device tells exactly what is new.
      final adopted = decideStoryRow(
        prefs: StoryRowPrefs(
          dismissal: remote.withSnapshot(storyCatalogSnapshot([a, b])),
        ),
        catalog: [a, b, _collection('n', games: 2)],
        isSeen: (_) => false,
        today: '2026-11-20',
      );
      expect(adopted.fresh, {'n'});
    });

    testWidgets('the pull mark answers from the pull\'s first points, '
        'growing with the room it opens to its full size', (tester) async {
      final slugs = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
      await _pumpRow(
        tester,
        collections: [for (final s in slugs) _collection(s)],
        batches: {for (final s in slugs) s: _batch(s, 2)},
      );
      final gesture = await tester.startGesture(const Offset(196, 120));
      final sizes = <double>[];
      final fills = <double>[];
      for (var i = 0; i < 26; i++) {
        await gesture.moveBy(const Offset(10, 0));
        await tester.pump(const Duration(milliseconds: 16));
        final mark = find.byKey(const ValueKey('story_row_pull_mark'));
        if (mark.evaluate().isEmpty) continue;
        sizes.add(tester.getSize(mark).width);
        fills.add(
          (tester
                      .widget<CustomPaint>(
                        find.descendant(
                          of: mark,
                          matching: find.byType(CustomPaint),
                        ),
                      )
                      .painter!
                  as StoryPullMarkPainter)
              .progress,
        );
      }
      expect(sizes, isNotEmpty);
      // In view while the pull is still early.
      expect(fills.first, lessThan(0.3));
      for (var i = 1; i < sizes.length; i++) {
        expect(sizes[i], greaterThanOrEqualTo(sizes[i - 1] - 0.01));
      }
      expect(sizes.last, StoryRowMetrics.pullMark);
      await gesture.moveBy(const Offset(-260, 0));
      await gesture.up();
      await _run(tester, const Duration(milliseconds: 900));
    });
  });

  group('review: break attempts', () {
    /// A random legal game of up to [plies] plies, its moves annotated at
    /// random: words of random length, glyphs, clocks, arrows and squares.
    String randomPgn(math.Random rng, int plies, double density, int words) {
      Position pos = Chess.initial;
      final out = StringBuffer('[Event "Fuzz"]\n[Result "*"]\n\n');
      for (var ply = 0; ply < plies && !pos.isGameOver; ply++) {
        final moves = <Move>[];
        pos.legalMoves.forEach((from, tos) {
          final pawn = pos.board.pieceAt(from)?.role == Role.pawn;
          for (final to in tos.squares) {
            final last = to.rank == Rank.first || to.rank == Rank.eighth;
            moves.add(
              NormalMove(
                from: from,
                to: to,
                promotion: pawn && last ? Role.queen : null,
              ),
            );
          }
        });
        final (next, san) = pos.makeSan(moves[rng.nextInt(moves.length)]);
        if (pos.turn == Side.white) out.write('${pos.fullmoves}. ');
        out.write('$san ');
        if (rng.nextDouble() < density) {
          if (rng.nextInt(6) == 0) out.write('\$${1 + rng.nextInt(6)} ');
          out.write('{ ');
          if (rng.nextBool()) out.write('[%clk 0:05:00] ');
          out.write(List.filled(rng.nextInt(words + 1), 'word').join(' '));
          if (rng.nextInt(4) == 0) out.write(' [%cal Ge2e4,Rd1d8]');
          if (rng.nextInt(5) == 0) out.write(' [%csl Gd4]');
          out.write(' } ');
        }
        pos = next;
      }
      return '$out*';
    }

    test('random annotated games: every schedule ends on the result, within '
        'its bounds, each step on its own move and each note held its '
        'dwell', () {
      final rng = math.Random(7);
      var annotated = 0;
      for (var i = 0; i < 300; i++) {
        final pgn = randomPgn(
          rng,
          1 + rng.nextInt(320),
          [0.0, 0.01, 0.05, 0.2, 0.6, 1.0][rng.nextInt(6)],
          [0, 3, 20, 80][rng.nextInt(4)],
        );
        final game = parseFlowPgn(pgn, maxPlies: 1000);
        final replay = StoryReplay.fromPgn(pgn);
        if (game == null || game.moves.isEmpty) {
          expect(replay, isNull, reason: pgn);
          continue;
        }
        final r = replay!;
        expect(r.fens.last, game.moves.last.after.fen, reason: pgn);
        expect(r.stepAt(0), 0, reason: pgn);
        expect(r.stepAt(1), r.plies, reason: pgn);
        if (!r.annotated) continue;
        annotated++;
        final total = r.scheduledDuration!.inMicroseconds / 1e6;
        expect(total, lessThanOrEqualTo(StoryReplay.maxScheduled + 1e-6));
        expect(total, greaterThanOrEqualTo(StoryReplay.minScheduled - 1e-6));
        expect(r.revealShare, inInclusiveRange(r.startOf(r.plies), 1.0));
        var previous = -1.0;
        for (var s = 0; s <= r.plies; s++) {
          expect(r.startOf(s), greaterThanOrEqualTo(previous), reason: pgn);
          previous = r.startOf(s);
          expect(r.stepAt(r.startOf(s) + 1e-9), s, reason: pgn);
          if (s == 0) continue;
          final note = r.noteAt(s)!;
          final move = game.moves.firstWhere((m) => m.after.fen == r.fens[s]);
          expect(note.san, move.san, reason: 'step $s of $pgn');
          if (s < r.plies && note.annotated) {
            final hold = (r.startOf(s + 1) - r.startOf(s)) * total;
            expect(
              hold,
              greaterThanOrEqualTo(StoryReplay.dwellOf(note) - 1e-6),
              reason: 'step $s of $pgn',
            );
          }
        }
      }
      expect(annotated, greaterThan(100));
    });

    testWidgets('the header tapped while the viewer still grows opens '
        'nothing; once open it opens the collection', (tester) async {
      await _pumpRow(
        tester,
        collections: [_collection('a')],
        batches: {'a': _batch('a', 3)},
      );
      await tester.tap(_circle('a'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 60));
      final header = find.byKey(const ValueKey('story_header_open'));
      if (header.evaluate().isNotEmpty) {
        await tester.tap(header, warnIfMissed: false);
      }
      await tester.pump();
      await _run(tester, const Duration(milliseconds: 900));
      expect(find.byKey(const ValueKey('collection_page')), findsNothing);
      final face = find.byKey(const ValueKey('story_page_a'));
      final at = _barsIn(tester, face).progress.value;
      await tester.pump(const Duration(seconds: 1));
      expect(_barsIn(tester, face).progress.value, greaterThan(at));
      await tester.tap(header);
      await tester.pump();
      await _run(tester, const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('collection_page')), findsOneWidget);
      Navigator.of(
        tester.element(find.byKey(const ValueKey('collection_page'))),
      ).pop();
      await tester.pump();
      await _run(tester, const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const ValueKey('story_close')));
      await _settleClose(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('armed, back under, armed again: one pull-away with a haptic '
        'at each arming; a second pull while the row folds away does '
        'nothing more', (tester) async {
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add('${call.arguments}');
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final slugs = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
      final harness = await _pumpRow(
        tester,
        collections: [for (final s in slugs) _collection(s)],
        batches: {for (final s in slugs) s: _batch(s, 2)},
      );
      final gesture = await tester.startGesture(const Offset(196, 80 + 40));
      Future<void> move(TestGesture g, double dx, int steps) async {
        for (var i = 0; i < steps; i++) {
          await g.moveBy(Offset(dx, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      await move(gesture, 12, 22);
      expect(haptics, ['HapticFeedbackType.selectionClick']);
      await move(gesture, -12, 12);
      await move(gesture, 12, 12);
      expect(haptics, hasLength(2));
      expect(harness.prefs.dismissal, isNull);
      await gesture.up();
      await tester.pump();
      expect(harness.prefs.dismissal, isNotNull);
      final first = harness.prefs.dismissal;
      await _frames(tester, const Duration(milliseconds: 200));
      final again = await tester.startGesture(const Offset(196, 80 + 20));
      await move(again, 12, 22);
      await again.up();
      await _frames(tester);
      expect(harness.prefs.dismissal, same(first));
      expect(find.text('Undo'), findsOneWidget);
      expect(
        tester.getSize(find.byType(TodayStoryRow, skipOffstage: false)).height,
        0,
      );
      await tester.pump(const Duration(seconds: 8));
    });
  });
}
