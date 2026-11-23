// The harness both free-parity suites read stories through: the app's own
// providers over a collections server as gamebase answers after the
// stories' read (PR #118), a reader who is a guest, free or Premium, and
// the chooser and the board recorded instead of shown.
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/chessboard/widgets/chess_board_from_fen_new.dart'
    show GameCardChessboard;
import 'package:chessever2/screens/chessboard/widgets/evaluation_bar_widget.dart'
    show EvaluationBarWidget;
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/feed/providers/feed_eval_provider.dart'
    show feedCachedEvalProvider;
import 'package:chessever2/screens/for_you/discovery/data/discovery_repository.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/models/report_game_type.dart';
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:chessever2/screens/stories/story_pages.dart';
import 'package:chessever2/screens/stories/story_row_prefs.dart';
import 'package:chessever2/screens/stories/story_seen_store.dart';
import 'package:chessever2/screens/stories/story_viewer.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'memory_story_row_store.dart';

// ------------------------------------------------------------- the games

/// A Botvinnik line as a book annotates it: words, arrows, glyphs and the
/// engine's numbers on its moves.
const botvinnikPgn = '''[Event "Alternative before Main Line"]
[White "Botvinnik / 9.Bg3 (Underestimated Line)"]
[Black "?"]
[ECO "D44"]
[Result "*"]

1. d4 d5 2. c4 c6 3. Nf3 Nf6 4. Nc3 e6 5. Bg5 dxc4 6. e4 b5 7. e5 h6 8. Bh4 g5 9. Bg3 { [%eval 0.3] The underestimated line: the bishop keeps watching e5. } 9... Nd5 { [%eval 0.3] } 10. Be2 Bb7 11. O-O Nd7 12. Nd2 h5 13. h4 g4 14. Nde4 { [%eval 0.6] } 14... Be7 15. Nd6+! { [%eval 0.9] [%cal Ge4d6,Gd6f7] The knight lands with check: the dark squares are White's. } 15... Bxd6 16. exd6 Qb6 17. Bxg4!? { [%eval 0.7] [%csl Rg4] A piece for two pawns and the open h-file. } 17... hxg4 18. h5 O-O-O { [%eval 0.4] Black's king runs to the queenside, etc. } 19. h6 Rh7 20. Qxg4 { [%eval 0.8] } 20... c5 21. Rfe1 cxd4 22. Ne4 Kb8 { [%eval 1.1] etc. } 23. Nc5 *''';

/// The same line's sibling chapter, with words of its own.
const sidelinePgn = '''[Event "Alternative before Main Line"]
[White "Botvinnik / 9.ef6 (Underestimated Line)"]
[Black "?"]
[ECO "D44"]
[Result "*"]

1. d4 d5 2. c4 c6 3. Nf3 Nf6 4. Nc3 e6 5. Bg5 dxc4 6. e4 b5 7. e5 h6 8. Bh4 g5 9. exf6 { [%eval 0.2] The piece comes back at once. } 9... gxh4 { [%eval 0.2] } 10. Ne5 { [%eval 0.4] [%cal Ge5f7] Eyeing f7. } 10... Qxf6 11. Qf3!? { [%eval 0.3] The queen joins with tempo on a8. } 11... Bb7 12. Be2 { [%eval 0.3] A calm developing move, etc. } *''';

/// A report's PGN: evaluations on every move, its verdict codes, and the
/// engine's line beside the missed win (mate on f7, missed).
const missedPgn = '''[Event "Round 2: A - B"]
[BroadcastName "Club Championship"]
[White "Alpha"]
[Black "Beta"]
[Result "1/2-1/2"]

1. e4 \$247 { [%eval 0.2] } 1... e5 \$247 { [%eval 0.2] } 2. Bc4 { [%eval 0.1] } 2... Nc6 { [%eval 0.1] } 3. Qh5 { [%eval 0.0] } 3... Nf6 \$4 \$246 { [%eval #1] } ( 3... g6 4. Qf3 Nf6 ) 4. Qf3 \$4 \$243 { [%eval 0.1] } ( 4. Qxf7# ) 4... Be7 { [%eval 0.1] } 1/2-1/2''';

final now = DateTime(2026, 11, 23, 10);

CollectionGameCard storyCard(
  String id,
  String white,
  String pgn, {
  DateTime? updated,
}) => CollectionGameCard(
  id: id,
  white: CollectionPlayerSide(name: white, key: 'name:$id'),
  black: const CollectionPlayerSide(name: '?', key: 'name:?'),
  event: 'Alternative before Main Line',
  eco: 'D44',
  opening: 'Semi-Slav, Botvinnik',
  finalFen: 'rnbqkb1r/p4p2/2p1pP2/1p6/2pP3p/2N2N2/PP3PPP/R2QKB1R w KQkq - 0 10',
  updatedAt: updated ?? DateTime(2026, 11, 22, 17, 34),
  hasAnnotations: true,
  commentCount: 5,
  pgn: pgn,
);

final bookCards = [
  storyCard('latest', 'Botvinnik / 9.Bg3 (Underestimated Line)', botvinnikPgn),
  storyCard(
    'sideline',
    'Botvinnik / 9.ef6 (Underestimated Line)',
    sidelinePgn,
    updated: DateTime(2026, 11, 20),
  ),
];

Collection storyCollection(
  String slug, {
  required CollectionKind kind,
  required CollectionAccess access,
  bool? locked,
}) => Collection(
  id: slug,
  slug: slug,
  kind: kind,
  title: kind == CollectionKind.book
      ? 'Complete Botvinnik Repertoire For Black'
      : 'Botvinnik Memorial 2026',
  author: 'GM Firat Burak',
  gameCount: bookCards.length,
  contentVersion: 'v-$slug',
  updatedAt: now.subtract(const Duration(hours: 1)),
  access: access,
  contentLocked: locked,
);

/// A reader: a guest (an anonymous session, no account), free (signed in,
/// no Premium) or Premium. The server keeps a Premium collection's full
/// games from a guest and a free reader alike.
enum Tier { guest, free, premium }

/// The account [tier] reads as: a guest's anonymous session, a signed-in
/// free reader, a subscriber.
AppUser readerOf(Tier tier) => switch (tier) {
  Tier.guest => AppUser(
    id: 'guest-session',
    createdAt: DateTime(2026, 11, 1),
    isAnonymous: true,
  ),
  Tier.free => AppUser(
    id: 'free-reader',
    email: 'free@example.com',
    createdAt: DateTime(2026, 1, 1),
  ),
  Tier.premium => AppUser(
    id: 'premium-reader',
    email: 'premium@example.com',
    createdAt: DateTime(2026, 1, 1),
  ),
};

/// The collections server as gamebase answers after the stories' read
/// (PR #118): the stories' games and their PGNs for every reader alike,
/// the full games only for an entitled one.
class StoryServer implements CollectionsRepository {
  StoryServer({required this.entitled, this.collection});

  /// Whether this reader may read the full games now (Premium, or a reward
  /// watched); flipped by a test's chooser.
  bool Function() entitled;
  final Collection? collection;

  final storyReads = <String>[];
  final pgnReads = <Set<String>>[];
  int playableReads = 0;

  @override
  Future<List<CollectionGameCard>?> fetchStoryGames(
    String slug, {
    required String day,
  }) async {
    storyReads.add('$slug@$day');
    return bookCards;
  }

  @override
  Future<Map<String, String>> fetchPgnsOf(
    String slug,
    Set<String> ids, {
    List<String>? order,
  }) async {
    pgnReads.add(ids);
    if (!entitled()) {
      throw const CollectionsRequestException(
        'This book is part of ChessEver Premium',
        statusCode: 403,
        code: 'premium_required',
      );
    }
    return {
      for (final card in bookCards)
        if (ids.contains(card.id)) card.id: card.pgn!,
    };
  }

  @override
  VoidCallback holdFreshAccess(String slug) => () {};

  @override
  Future<Collection> fetchCollection(String slug) async {
    final c = collection!;
    return storyCollection(
      c.slug,
      kind: c.kind,
      access: c.access,
      locked: c.isPremium ? !entitled() : null,
    );
  }

  @override
  Future<List<CollectionGame>> fetchPlayableGames(String slug) async {
    playableReads++;
    if (collection!.isPremium && !entitled()) {
      throw const CollectionsRequestException(
        'This book is part of ChessEver Premium',
        statusCode: 403,
        code: 'premium_required',
      );
    }
    return [for (final card in bookCards) CollectionGame.fromCard(card)!];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The Reports' Missed Chance topic, as the database answers anyone.
class MissedReports implements DiscoveryRepository {
  @override
  Future<AnalyzedGamesPage> fetchAnalyzedGamesPage({
    int pageSize = 30,
    AnalyzedGamesCursor? after,
    DateTime? since,
    DateTime? until,
    ReportGameType? gameType,
  }) async => AnalyzedGamesPage(
    items: [
      CollectionGame.fromCard(
        CollectionGameCard(
          id: 'missed-1',
          white: const CollectionPlayerSide(name: 'Alpha', key: 'name:a'),
          black: const CollectionPlayerSide(name: 'Beta', key: 'name:b'),
          result: '1/2-1/2',
          pgn: missedPgn,
        ),
      )!.game,
    ],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------- harness

class MemoryStorySeen implements StorySeenStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

class DefaultBoard extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class StubCollectionPage extends StatelessWidget {
  const StubCollectionPage(this.collection, {super.key});

  final Collection collection;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: const ValueKey('collection_page'),
    body: Center(child: Text('Page ${collection.slug}')),
  );
}

class QuietStorySounds extends StoryPuzzleSounds {
  @override
  void move({required String san, MoveClass? moveClass}) {}

  @override
  void warmUp() {}
}

/// What a test sees of the chooser and of what opened behind it.
class Opens {
  Opens(Tier tier) : user = StateProvider<AppUser?>((ref) => readerOf(tier));

  /// Whether the reader holds access now (a subscription, or a reward).
  final granted = StateProvider<bool>((ref) => false);

  /// The signed-in account (a guest's anonymous one included); a chooser
  /// that signs a guest in changes it.
  final StateProvider<AppUser?> user;

  /// The chooser's answer when it is shown: a watched ad (true) or Not now.
  bool rewardWatched = false;

  /// The account a guest signs in to on the chooser's Upgrade before the
  /// purchase, when they do: the guest's own made permanent (same id), or
  /// another one.
  AppUser? signsInAs;
  int chooserShown = 0;
  final boards = <(List<String>, int, Map<String, int>)>[];
}

/// The overrides that read a [collection]'s stories through the app's own
/// providers from [server], for a reader of [tier].
List<Override> readerOverrides({
  required Tier tier,
  required Collection collection,
  required StoryServer server,
  required Opens opens,
}) => [
  collectionContentsProvider.overrideWith(
    (ref, slug) async => CollectionContents(
      sections: const [],
      games: [
        for (final card in bookCards) CollectionGame.fromPreviewCard(card)!,
      ],
    ),
  ),
  collectionDetailProvider.overrideWith(
    (ref, slug) async => storyCollection(
      collection.slug,
      kind: collection.kind,
      access: collection.access,
      locked: collection.isPremium ? tier != Tier.premium : null,
    ),
  ),
  collectionsRepositoryProvider.overrideWithValue(server),
  currentUserProvider.overrideWith((ref) => ref.watch(opens.user)),
  discoveryRepositoryProvider.overrideWithValue(MissedReports()),
  storyAnalyzerProvider.overrideWithValue(
    (jobs) async => analyzeStoryJobs(jobs),
  ),
  premiumAccessProvider.overrideWith((ref) => ref.watch(opens.granted)),
  storyPremiumChooserProvider.overrideWithValue((context, collection) async {
    opens.chooserShown++;
    final container = ProviderScope.containerOf(context, listen: false);
    if (opens.signsInAs case final account?) {
      // Upgrade: a guest signs in first, then subscribes.
      container.read(opens.user.notifier).state = account;
      container.read(opens.granted.notifier).state = true;
      return true;
    }
    if (opens.rewardWatched) {
      container.read(opens.granted.notifier).state = true;
    }
    return opens.rewardWatched;
  }),
  storyBoardOpenerProvider.overrideWithValue((
    context,
    ref, {
    required games,
    required index,
    required moves,
  }) async {
    opens.boards.add(([for (final g in games) g.gameId], index, moves));
  }),
];

/// The repaint boundary around the stories, for a render.
const kParityCapture = ValueKey('parity_capture');

Future<(ProviderContainer, StoryServer, Opens)> pumpStories(
  WidgetTester tester, {
  required Tier tier,
  required Collection collection,
  bool light = false,
  List<Override> extra = const [],
}) async {
  tester.view.physicalSize = const Size(393, 852) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final opens = Opens(tier);
  late final ProviderContainer container;
  final server = StoryServer(
    entitled: () => container.read(premiumAccessProvider),
    collection: collection,
  );
  container = ProviderContainer(
    overrides: [
      ...readerOverrides(
        tier: tier,
        collection: collection,
        server: server,
        opens: opens,
      ),
      storySeenStorageProvider.overrideWithValue(MemoryStorySeen()),
      storyRowPrefsStoreProvider.overrideWithValue(MemoryStoryRowStore()),
      storyClockProvider.overrideWithValue(() => now),
      storyCollectionPageProvider.overrideWithValue(
        (collection) => StubCollectionPage(collection),
      ),
      feedCachedEvalProvider.overrideWith((ref, fen) async => null),
      boardSettingsProviderNew.overrideWith(DefaultBoard.new),
      storyPuzzleSoundsProvider.overrideWithValue(QuietStorySounds()),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  if (tier == Tier.premium) {
    container.read(opens.granted.notifier).state = true;
  }
  await tester.pumpWidget(
    RepaintBoundary(
      key: kParityCapture,
      child: UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: Center(
                  child: TextButton(
                    key: const ValueKey('open_stories'),
                    onPressed: () => openCollectionStories(
                      context,
                      collections: [collection],
                      initialIndex: 0,
                    ),
                    child: const Text('Stories'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('open_stories')));
  await tester.pump();
  // The batch reads through fake async: let it land, then the surface grow.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 16));
  return (container, server, opens);
}

/// Everything a page shows: which position of which game, the move, the
/// label, the words, the arrows, the board, the evaluation, the bars, and
/// every string drawn.
Map<String, Object?> pageOf(WidgetTester tester) {
  final frame = tester.widget<StoryFrameView>(find.byType(StoryFrameView));
  final segment = frame.frame.position;
  final bars = tester.widget<CustomPaint>(
    find.descendant(
      of: find.byKey(const ValueKey('story_bars')),
      matching: find.byType(CustomPaint),
    ),
  );
  final board = find.byKey(const ValueKey('story_board'));
  final eval = find.byKey(const ValueKey('story_eval_bar'));
  final bar = eval.evaluate().isEmpty
      ? null
      : tester.widget<EvaluationBarWidget>(eval);
  return {
    'frame': frame.frame.id,
    'bars': (bars.painter as dynamic).count,
    'fenBefore': segment.fenBefore,
    'fenAfter': segment.fenAfter,
    'san': segment.san,
    'number': segment.isStill ? null : segment.number,
    'label': segment.label,
    'comment': segment.comment,
    'shapes': segment.shapes.map((s) => '$s').toList()..sort(),
    'puzzle': segment.puzzle?.answerSan,
    'evalBefore': '${segment.evalBefore}',
    'evalAfter': '${segment.evalAfter}',
    'board': board.evaluate().isEmpty
        ? null
        : tester.widget<GameCardChessboard>(board).fen,
    'bar': bar == null ? null : '${bar.evaluation}/${bar.mate}',
    'drawn': [
      for (final text in tester.widgetList<RichText>(
        find.descendant(
          of: find.byKey(const ValueKey('story_viewer')),
          matching: find.byType(RichText),
        ),
      ))
        text.text.toPlainText(),
    ],
  };
}

/// Every page of the stories, stepping on with a tap beside the board.
Future<List<Map<String, Object?>>> everyPage(WidgetTester tester) async {
  final pages = <Map<String, Object?>>[];
  for (var guard = 0; guard < 20; guard++) {
    if (find.byType(StoryFrameView).evaluate().isEmpty) break;
    // Let the move land and the words settle on every page alike.
    await tester.pump(const Duration(milliseconds: 900));
    final page = pageOf(tester);
    if (pages.isNotEmpty && pages.last['frame'] == page['frame']) break;
    pages.add(page);
    final header = tester.getRect(find.byKey(const ValueKey('story_close')));
    final frame = tester.getRect(find.byType(StoryFrameView));
    await tester.tapAt(Offset(393 * 0.85, (header.bottom + frame.top) / 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
  }
  return pages;
}

Future<List<Map<String, Object?>>> watch(
  WidgetTester tester,
  Tier tier,
  Collection collection, {
  bool light = false,
}) async {
  await pumpStories(tester, tier: tier, collection: collection, light: light);
  final pages = await everyPage(tester);
  // Unmount between readers: nothing of one carries to the other.
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  return pages;
}

Future<void> tapAction(WidgetTester tester, String key) async {
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pump();
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

final book = storyCollection(
  'complete-botvinnik-repertoire-for-black',
  kind: CollectionKind.book,
  access: CollectionAccess.premium,
);

final premiumEvent = storyCollection(
  'botvinnik-memorial-2026',
  kind: CollectionKind.event,
  access: CollectionAccess.premium,
);

final freeEvent = storyCollection(
  'botvinnik-memorial-open',
  kind: CollectionKind.event,
  access: CollectionAccess.free,
);
