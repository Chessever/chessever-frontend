import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/provider/current_eval_provider.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The collection screen's Games tab: games under the section tree's
/// headers (a round and its date; a book's parts, chapters and intros).

class _FakeCollections extends CollectionsRepository {
  _FakeCollections({required this.detail, required this.games})
    : super(GamebaseRepository(Dio(), apiKey: 'test'));

  final Collection detail;
  final List<CollectionGame> games;

  @override
  Future<Collection> fetchCollection(String slug) async => detail;

  @override
  Future<List<CollectionGame>> fetchGames(String slug) async => games;

  @override
  Future<List<CollectionPlayer>> fetchPlayers(String slug) async => const [];
}

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription() : super(SubscriptionState(isSubscribed: false));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _EngineSettings extends AsyncNotifier<EngineSettings>
    implements EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoSpoilers extends EventNoSpoilersController {
  _NoSpoilers({required super.ref, required super.tourId});

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

CloudEval _eval(String fen) => CloudEval(
  fen: fen,
  knodes: 0,
  depth: 20,
  pvs: [Pv(moves: 'e2e4', cp: 40)],
  requestedMultiPv: 1,
);

const _pgn = '''[Event "Casual"]
[White "Nimzowitsch, Aron"]
[Black "Systemsson, Max"]
[Result "1-0"]

1. e4 e5 2. Nf3 Nc6 3. Bb5 1-0''';

CollectionGame _game(String id, {String? sectionId, int orderIndex = 0}) {
  return CollectionGame.fromCard(
    CollectionGameCard(
      id: id,
      sectionId: sectionId,
      orderIndex: orderIndex,
      white: const CollectionPlayerSide(
        name: 'Nimzowitsch, Aron',
        key: 'name:nimzowitsch, aron',
      ),
      black: const CollectionPlayerSide(
        name: 'Systemsson, Max',
        key: 'name:systemsson, max',
      ),
      pgn: _pgn,
    ),
  )!;
}

class _NoShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

Future<void> _pump(WidgetTester tester, _FakeCollections repo) async {
  tester.view.physicalSize = const Size(390, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      collectionsRepositoryProvider.overrideWithValue(repo),
      subscriptionProvider.overrideWith((ref) => _Subscription()),
      boardSettingsProviderNew.overrideWith(_BoardSettings.new),
      engineSettingsProviderNew.overrideWith(_EngineSettings.new),
      eventNoSpoilersProvider.overrideWith(
        (ref, tourId) => _NoSpoilers(ref: ref, tourId: tourId),
      ),
      gameCardEvalWithStockfishFallbackProvider.overrideWith(
        (ref, fen) async => _eval(fen),
      ),
      gameCardEvalCacheOnlyProvider.overrideWith(
        (ref, fen) async => _eval(fen),
      ),
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
            return CollectionScreen(collection: repo.detail);
          },
        ),
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Game cards leave short timers behind; take the tree down and let them run.
Future<void> _teardown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

Finder _rich(String text) => find.textContaining(text, findRichText: true);

void main() {
  testWidgets('holding a collection card offers Open and Add to My Space, '
      'with the collection itself as the draft', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const collection = Collection(
      id: 'c9',
      slug: 'zurich-1953',
      kind: CollectionKind.book,
      title: 'Zurich 1953',
      gameCount: 210,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return const Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(16),
                  child: CollectionCard(collection: collection),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    final draft = collectionSpaceDraft(collection);
    expect(draft.kind, SpaceShortcutKind.collection);
    expect(draft.targetId, 'c9');
    expect(draft.section, SpaceSection.library);

    await tester.longPress(find.byType(CollectionCard));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Add to My Space'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an event lists its games under dated rounds, in order', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeCollections(
        detail: Collection(
          id: 'c1',
          slug: 'us-championship-2025',
          kind: CollectionKind.event,
          title: 'US Championship 2025',
          gameCount: 3,
          sections: [
            CollectionSection(
              id: 'r1',
              kind: CollectionSectionKind.round,
              label: 'Round 1',
              startsOn: DateTime(2025, 10, 2),
              orderIndex: 1,
            ),
            const CollectionSection(
              id: 'r2',
              kind: CollectionSectionKind.round,
              label: 'Round 2',
              orderIndex: 2,
            ),
          ],
        ),
        games: [
          _game('a', sectionId: 'r1'),
          _game('b', sectionId: 'r2'),
          _game('u'),
        ],
      ),
    );

    expect(find.text('Round 1'), findsOneWidget);
    expect(find.text('Oct 2, 2025'), findsOneWidget);
    expect(find.text('Round 2'), findsOneWidget);
    expect(find.text('Other games'), findsOneWidget);
    final y = [
      for (final t in ['Round 1', 'Round 2', 'Other games'])
        tester.getTopLeft(find.text(t)).dy,
    ];
    expect(y, orderedEquals([...y]..sort()));
    await _teardown(tester);
  });

  testWidgets('a book shows parts, numbered chapters and their intros', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeCollections(
        detail: const Collection(
          id: 'c2',
          slug: 'my-system',
          kind: CollectionKind.book,
          title: 'My System',
          gameCount: 2,
          sections: [
            CollectionSection(
              id: 'p1',
              kind: CollectionSectionKind.part,
              label: 'Part I',
              number: 'I',
              title: 'The Elements',
              orderIndex: 1,
              children: [
                CollectionSection(
                  id: 'ch7',
                  parentId: 'p1',
                  kind: CollectionSectionKind.chapter,
                  label: 'Chapter 7',
                  number: '7',
                  title: 'The Pin',
                  intro: 'A pinned piece cannot move.\n\nExploit it.',
                  orderIndex: 1,
                ),
              ],
            ),
            CollectionSection(
              id: 'empty',
              kind: CollectionSectionKind.chapter,
              label: 'Chapter 8',
              title: 'Nothing here yet',
              orderIndex: 2,
            ),
          ],
        ),
        games: [_game('a', sectionId: 'ch7'), _game('b', sectionId: 'ch7')],
      ),
    );

    expect(_rich('The Elements'), findsOneWidget);
    expect(_rich('Part I'), findsOneWidget);
    expect(_rich('7  The Pin'), findsOneWidget);
    expect(find.text('A pinned piece cannot move.'), findsOneWidget);
    expect(find.text('Exploit it.'), findsOneWidget);
    expect(_rich('Nothing here yet'), findsNothing);
    expect(find.text('Other games'), findsNothing);
    await _teardown(tester);
  });

  testWidgets('a collection without sections lists games with no headers', (
    tester,
  ) async {
    await _pump(
      tester,
      _FakeCollections(
        detail: const Collection(
          id: 'c3',
          slug: 'flat',
          kind: CollectionKind.event,
          title: 'Flat',
        ),
        games: [_game('a'), _game('b')],
      ),
    );
    expect(find.text('Other games'), findsNothing);
    await _teardown(tester);
  });
}
