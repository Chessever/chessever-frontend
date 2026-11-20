import 'dart:async';
import 'dart:convert';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart'
    show GameCardChessboard;
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:chessever2/screens/stories/story_pages.dart';
import 'package:chessever2/screens/stories/story_replay.dart';
import 'package:chessever2/screens/stories/story_row.dart';
import 'package:chessever2/screens/stories/story_seen_store.dart';
import 'package:chessever2/screens/stories/story_viewer.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:dio/dio.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart' show Bone;

/// A short game: the Scholar's mate.
const _pgn = '''[Event "Test"]
[White "Alpha"]
[Black "Beta"]
[Result "1-0"]

1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0''';

class _MemoryStorage implements StorySeenStorage {
  _MemoryStorage([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
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

String _seenRecord(Map<String, (String, int, bool)> records) => jsonEncode({
  for (final MapEntry(:key, :value) in records.entries)
    key: StorySeen(
      signature: value.$1,
      next: value.$2,
      seen: value.$3,
    ).toJson(),
});

class _Harness {
  _Harness(this.container, this.storage);

  final ProviderContainer container;
  final _MemoryStorage storage;

  StorySeenNotifier get seen => container.read(storySeenProvider.notifier);
}

Future<_Harness> _pumpRow(
  WidgetTester tester, {
  required List<Collection> collections,
  required Map<String, StoryBatch> batches,
  String? seen,
  CollectionsRepository? repository,
  Size size = const Size(393, 852),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final storage = _MemoryStorage(seen);
  final container = ProviderContainer(
    overrides: [
      // Read on every build, so a test can change the catalog under it.
      storyCollectionsProvider.overrideWith(
        (ref) async => List.of(collections),
      ),
      storyBatchProvider.overrideWith((ref, slug) async => batches[slug]!),
      storySeenStorageProvider.overrideWithValue(storage),
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
  return _Harness(container, storage);
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
        seen: _seenRecord({'a': (storySignature(a), 2, true)}),
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
      expect(find.byType(ListView), findsOneWidget);
      expect(find.byKey(const ValueKey('story_row_skeleton')), findsNothing);
      expect(find.byType(StoryCircleFace), findsNothing);
      final row = tester.renderObject<RenderBox>(
        find.byType(TodayStoryRow, skipOffstage: false),
      );
      expect(row.size.height, 0);
    });
  });

  group('seen', () {
    test('watching a game story marks a collection seen; new games make it '
        'unseen again, from its first story', () async {
      final storage = _MemoryStorage();
      final container = ProviderContainer(
        overrides: [storySeenStorageProvider.overrideWithValue(storage)],
      );
      addTearDown(container.dispose);
      container.read(storySeenProvider);
      await Future<void>.delayed(Duration.zero);
      final seen = container.read(storySeenProvider.notifier);
      final before = _collection('a', games: 3);
      final after = _collection('a', games: 4);
      expect(seen.isSeen('a', storySignature(before)), isFalse);

      // Moving past the See all story is not watching a game.
      seen.advanced('a', storySignature(before), from: 0, game: false);
      expect(seen.isSeen('a', storySignature(before)), isFalse);
      seen.advanced('a', storySignature(before), from: 1, game: true);
      expect(seen.isSeen('a', storySignature(before)), isTrue);
      expect(seen.resumeIndex('a', storySignature(before), 3), 2);
      expect(jsonDecode(storage.value!), contains('a'));

      // The collection gained a game: unseen, from the top.
      expect(storySignature(after), isNot(storySignature(before)));
      expect(seen.isSeen('a', storySignature(after)), isFalse);
      expect(seen.resumeIndex('a', storySignature(after), 4), 0);

      // Reaching the last story marks it too.
      seen.reachedLast('a', storySignature(after), 3);
      expect(seen.isSeen('a', storySignature(after)), isTrue);
    });

    testWidgets('half a game watched marks its collection seen even when the '
        'reader leaves; a game seen to its result moves the start on', (
      tester,
    ) async {
      final a = _collection('a');
      final harness = await _pumpRow(
        tester,
        collections: [a],
        batches: {'a': _batch('a', 3)},
      );
      final signature = storySignature(a);
      await _open(tester, 'a');
      expect(harness.seen.isSeen('a', signature), isFalse);
      await tester.pump(kStoryGameDuration * 0.55);
      expect(harness.seen.isSeen('a', signature), isTrue);
      // Left now, it opens on the same game again.
      expect(harness.seen.resumeIndex('a', signature, 3), 0);
      await tester.pump(kStoryGameDuration * 0.32);
      expect(_story('a0'), findsOneWidget);
      // Seen through to its result: it opens on the next one.
      expect(harness.seen.resumeIndex('a', signature, 3), 1);
      await tester.tap(find.byKey(const ValueKey('story_close')));
      await _settleClose(tester);
      expect(harness.seen.resumeIndex('a', signature, 3), 1);
    });

    testWidgets('a watched story turns the ring quiet; a changed collection '
        'turns it back', (tester) async {
      final a = _collection('a', games: 2);
      final catalog = [a];
      final harness = await _pumpRow(
        tester,
        collections: catalog,
        batches: {'a': _batch('a', 2)},
      );
      final unseen = StoryRowMetrics.unseenRing(tester.element(_circle('a')));
      expect(_ringColor(tester, 'a'), unseen);
      await _open(tester, 'a');
      expect(_story('a0'), findsOneWidget);
      await tester.pump(kStoryGameDuration);
      await tester.pump(const Duration(milliseconds: 16));
      expect(_story('a1'), findsOneWidget);
      expect(harness.seen.isSeen('a', storySignature(a)), isTrue);
      await tester.tap(find.byKey(const ValueKey('story_close')));
      await _settleClose(tester);
      expect(find.byType(CollectionStoryViewer), findsNothing);
      expect(_ringColor(tester, 'a'), AppColors.dark.dividerStrong);

      // The same collection with a new game: new again.
      catalog[0] = _collection('a', games: 3);
      harness.container.invalidate(storyCollectionsProvider);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(_ringColor(tester, 'a'), unseen);
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
        // The reader left it on its last game.
        seen: _seenRecord({'a': (storySignature(a), kStoryCap - 1, true)}),
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
      expect(harness.seen.isSeen('a', storySignature(a)), isFalse);
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
      expect(harness.seen.isSeen('b', storySignature(b)), isFalse);
      expect(harness.seen.isSeen('a', storySignature(a)), isTrue);
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
      // Asked again a few seconds later, the row comes back.
      await tester.pump(const Duration(seconds: 9));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
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
}
