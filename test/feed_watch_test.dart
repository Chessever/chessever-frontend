import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/screens/feed/feed_screen.dart';
import 'package:chessever2/screens/feed/feed_visibility.dart';
import 'package:chessever2/screens/feed/providers/feed_entries_provider.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/providers/feed_eval_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/screens/feed/puzzles/feed_puzzle.dart';
import 'package:chessever2/screens/feed/widgets/feed_clip.dart';
import 'package:chessever2/screens/feed/widgets/feed_format.dart';
import 'package:chessever2/screens/feed/widgets/feed_move_sound.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Watch: the board's game opens Feed as its first post, and the feed
/// carries on after it as it is.
void main() {
  group('feedWatchItem', () {
    test('any game with moves plays, report or not', () {
      final item = feedWatchItem(_game('w1'), _pgn)!;
      expect(item.plyCount, 7);
      expect(item.plies.last.san, 'Qxf7#');
      expect(item.result, '1-0');
      expect(item.hasEvals, isFalse);
      expect(item.eventLabel, 'Test Open 2026');
      // Share and Save read the moves off the game; a Like saves the
      // board's own model, as a like on the board does.
      expect(item.game.pgn, _pgn);
      expect(item.game.isPgnDeferred, isFalse);
      expect(item.boardGame?.pgn, isNull);
      expect(item.boardGame?.gameId, 'w1');
    });

    test('a live game plays up to its last move, with no result', () {
      final item = feedWatchItem(
        _game('w1', status: GameStatus.ongoing),
        '[Event "Test Open 2026"]\n[Result "*"]\n\n1. e4 e5 2. Nf3 *',
      )!;
      expect(item.plyCount, 3);
      expect(item.result, isNull);
    });

    test('an archive game with no event in its PGN names the one the board '
        'shows', () {
      final item = feedWatchItem(
        _game(
          'a1',
          source: GameSource.gamebase,
          tourId: 'Tata Steel Masters 2026',
        ),
        '[Result "1-0"]\n\n1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0',
      )!;
      expect(item.eventLabel, 'Tata Steel Masters 2026');
    });

    test('a game with no move has nothing to watch', () {
      expect(
        feedWatchItem(
          _game('w1', status: GameStatus.ongoing),
          '[Event "Test Open 2026"]\n[Result "*"]\n\n*',
        ),
        isNull,
      );
      expect(feedWatchItem(_game('w1'), ''), isNull);
    });
  });

  group('No Spoilers on a Watch post', () {
    const pgn =
        '[Event "Test Open 2026"]\n[Result "1-0"]\n\n'
        '1. e4 {[%eval 0.3]} e5 {[%eval 0.3]} 2. Bc4 {[%eval 0.2]} '
        'Nc6 {[%eval 0.3]} 3. Qh5 {[%eval 0.1]} Nf6 {[%eval 9.0]} '
        '4. Qxf7# 1-0';

    test('hidden evaluation: no evals in the plies, no chart', () {
      final item = feedWatchItem(_game('s1'), pgn, hideEvaluation: true)!;
      expect(item.hideEvaluation, isTrue);
      expect(item.hasEvals, isFalse);
      expect(item.plies.any((p) => p.cp != null || p.mate != null), isFalse);
      // The result still shows: only the evaluation is held back.
      expect(item.result, '1-0');
      expect(feedResultStatus(item), GameStatus.whiteWins);
    });

    test('hidden result: no result, no "White wins", no fallen king', () {
      final item = feedWatchItem(_game('s2'), pgn, hideResult: true)!;
      expect(item.result, isNull);
      expect(feedResultStatus(item), GameStatus.unknown);
      expect(feedResultLabel(item), '');
      expect(
        item.plies.any((p) => p.moment?.type == FeedMomentType.gameEnd),
        isFalse,
      );
      // Share and Save still hand out the game as the board would.
      expect(item.game.pgn, pgn);
    });

    test('the PGN is cleaned only of what is hidden', () {
      expect(feedSpoilerFreePgn(pgn, evaluation: false, result: false), pgn);
      final clean = feedSpoilerFreePgn(pgn, evaluation: true, result: true);
      expect(clean.contains('%eval'), isFalse);
      expect(clean.contains('[Result "*"]'), isTrue);
      expect(clean.trim().endsWith('*'), isTrue);
      expect(clean.contains('Qxf7#'), isTrue);
    });
  });

  group('feedRecordedPgn', () {
    const recorded = '[Result "1-0"]\n\n1. e4 e5 2. Bc4 Nc6 1-0';
    test("moves the reader played past the game's end are not the game", () {
      expect(
        feedRecordedPgn(
          recorded,
          '[Result "1-0"]\n\n1. e4 e5 2. Bc4 Nc6 3. Qh5 *',
        ),
        recorded,
      );
    });
    test("a changed move, the same moves, or no recorded moves keep the "
        'board\'s', () {
      const changed = '[Result "*"]\n\n1. e4 e5 2. Nf3 Nc6 3. Bb5 *';
      expect(feedRecordedPgn(recorded, changed), changed);
      const same = '[Result "1-0"]\n\n1. e4 e5 2. Bc4 {!} Nc6 1-0';
      expect(feedRecordedPgn(recorded, same), same);
      const setUp = '[Result "*"]\n\n*';
      expect(feedRecordedPgn(setUp, changed), changed);
      expect(feedRecordedPgn(null, changed), changed);
    });
  });

  testWidgets('Watch opens on its game, then the feed as it is, without its '
      'own copy of that game', (tester) async {
    final feed = _FakeFeed(() async => [_post('g0'), _post('g1'), _post('g2')]);
    await _pump(tester, feed, lead: _post('g1'));

    // The lead, then g0 and g2, then the tail: g1 is not shown twice.
    expect(
      tester.widget<PageView>(_pages).childrenDelegate.estimatedChildCount,
      4,
    );
    expect(tester.widget<FeedClip>(_lead('g1')).isCurrent, isTrue);
    // The lead is not one of the feed's games: no visit is counted for it,
    // and Feed keeps the place the viewer had.
    expect(feed.visible, [-1]);
    expect(_currentKey(tester), isNull);

    await _fling(tester, up: true);
    expect(tester.widget<FeedClip>(_page('g0')).isCurrent, isTrue);
    expect(feed.visible.last, 0);
    expect(_currentKey(tester), 'game:g0');

    // g2 is the feed's third game, whatever this screen shows before it.
    await _fling(tester, up: true);
    expect(tester.widget<FeedClip>(_page('g2')).isCurrent, isTrue);
    expect(feed.visible.last, 2);
    expect(_currentKey(tester), 'game:g2');

    await _fling(tester, up: false);
    await _fling(tester, up: false);
    expect(tester.widget<FeedClip>(_lead('g1')).isCurrent, isTrue);
    expect(feed.visible.last, -1);
    expect(_currentKey(tester), 'game:g0');
    await _tearDown(tester);
  });

  testWidgets('Watch plays its game at once while the feed loads; no refresh '
      'until the feed is in, and a refresh drops the lead', (tester) async {
    final first = Completer<List<FeedItem>>();
    final feed = _FakeFeed(() => first.future);
    await _pump(tester, feed, lead: _post('w1'));

    expect(tester.widget<FeedClip>(_lead('w1')).isCurrent, isTrue);
    expect(
      find.bySemanticsLabel('Loading the next game', skipOffstage: false),
      findsOneWidget,
    );
    expect(feed.visible, isEmpty);
    // Nothing to replace yet: the title's refresh waits for the feed.
    await tester.tap(_title);
    await _settle(tester);
    expect(feed.refreshes, 0);

    first.complete([_post('g0'), _post('g1')]);
    await _settle(tester);
    expect(
      tester.widget<PageView>(_pages).childrenDelegate.estimatedChildCount,
      4,
    );
    expect(feed.visible, [-1]);
    expect(tester.widget<FeedClip>(_lead('w1')).isCurrent, isTrue);

    await tester.tap(_title);
    await _settle(tester);
    expect(feed.refreshes, 1);
    expect(_lead('w1'), findsNothing);
    expect(tester.widget<FeedClip>(_page('fresh0')).isCurrent, isTrue);
    expect(_currentKey(tester), 'game:fresh0');
    await _tearDown(tester);
  });

  testWidgets('a feed that did not load offers Try again under the lead', (
    tester,
  ) async {
    var attempts = 0;
    final feed = _FakeFeed(() async {
      attempts++;
      if (attempts == 1) throw StateError('offline');
      return [_post('g0')];
    });
    await _pump(tester, feed, lead: _post('w1'));
    expect(tester.widget<FeedClip>(_lead('w1')).isCurrent, isTrue);

    await _fling(tester, up: true);
    expect(find.text("More games didn't load."), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('feed_end_retry')));
    await _settle(tester);
    expect(attempts, 2);
    // The first page landed where the viewer waited for it.
    expect(tester.widget<FeedClip>(_page('g0')).isCurrent, isTrue);
    expect(feed.visible.last, 0);
    await _tearDown(tester);
  });

  testWidgets('Watch over Feed: Feed stays open until the last one closes, and '
      'a refresh in Watch starts the Feed under it on the new draw', (
    tester,
  ) async {
    final feed = _FakeFeed(() async => [_post('g0'), _post('g1'), _post('g2')]);
    await _pump(tester, feed);
    await _fling(tester, up: true);
    await _fling(tester, up: true);
    expect(_currentKey(tester), 'game:g2');

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(FeedScreen.watch(navigator.context, _post('w1')));
    await _settle(tester);
    expect(tester.widget<FeedClip>(_lead('w1')).isCurrent, isTrue);

    await tester.tap(_title.last);
    await _settle(tester);
    expect(feed.refreshes, 1);

    navigator.pop();
    await _settle(tester);
    expect(_read(tester, feedScreenOpenProvider), isTrue);
    // The Feed underneath is on the new draw's first post, and it is the
    // visit again.
    expect(tester.widget<FeedClip>(_page('fresh0')).isCurrent, isTrue);
    expect(tester.widget<PageView>(_pages).controller!.page, 0);
    expect(
      tester.getRect(_page('fresh0')).top,
      closeTo(tester.getRect(_pages).top, 0.5),
    );
    expect(feed.visible.last, 0);
    expect(_currentKey(tester), 'game:fresh0');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the lead offers what its board does, and Analyze goes back '
      'to that board', (tester) async {
    final feed = _FakeFeed(() async => [_post('g0')]);
    await _pump(tester, feed, home: const _Home());
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final lead = feedWatchItem(
      _game('w1'),
      _pgn,
      likeable: false,
      exportable: false,
    )!;
    unawaited(FeedScreen.watch(navigator.context, lead));
    await _settle(tester);

    Finder onPost(Finder page, String key) => find.descendant(
      of: page,
      matching: find.byKey(ValueKey(key), skipOffstage: false),
      skipOffstage: false,
    );
    // No Like where the board takes none, no Save where it keeps the moves
    // in; the feed's own posts keep both.
    expect(onPost(_lead('w1'), 'feed_like_button'), findsNothing);
    expect(onPost(_lead('w1'), 'feed_save_button'), findsNothing);
    expect(onPost(_lead('w1'), 'feed_share_button'), findsOneWidget);
    expect(onPost(_page('g0'), 'feed_like_button'), findsOneWidget);
    expect(onPost(_page('g0'), 'feed_save_button'), findsOneWidget);

    // Analyze: back to the board Watch came from, no second board.
    await tester.tap(onPost(_lead('w1'), 'feed_analyze_button'));
    await _settle(tester);
    expect(find.byType(FeedScreen), findsNothing);
    expect(find.byType(_Home), findsOneWidget);
    await _tearDown(tester);
  });

  testWidgets('the tail under the lead visits the last game on screen, never '
      "Feed's hidden copy of the lead", (tester) async {
    final feed = _FakeFeed(() async => [_post('g0'), _post('g1')]);
    await _pump(tester, feed, lead: _post('g1'));
    await _fling(tester, up: true);
    expect(feed.visible.last, 0);
    // The tail: g1 is Feed's last game, but it is the lead's copy and not on
    // screen; g0 is the last game the viewer reached.
    await _fling(tester, up: true);
    expect(
      find.text('No more games for now.', skipOffstage: false),
      findsOneWidget,
    );
    expect(feed.visible.last, 0);
    expect(_currentKey(tester), 'game:g0');
    await _tearDown(tester);
  });

  testWidgets("after a refresh, Feed's own copy of the lead's game is a new "
      'page, not the lead carried over', (tester) async {
    final live = feedWatchItem(
      _game('w1', status: GameStatus.ongoing),
      '[Event "Test Open 2026"]\n[Result "*"]\n\n1. e4 e5 2. Bc4 *',
    )!;
    final feed = _FakeFeed(
      () async => [_post('g0')],
      fresh: [_post('w1'), _post('fresh1')],
    );
    await _pump(tester, feed, lead: live);
    final leadPage = _lead('w1');
    expect(leadPage, findsOneWidget);
    final leadState = tester.state(leadPage);

    await tester.tap(_title);
    await _settle(tester);
    expect(feed.refreshes, 1);
    expect(leadPage, findsNothing);
    final post = tester.widget<FeedClip>(_page('w1'));
    expect(post.item.plyCount, 9);
    expect(post.isCurrent, isTrue);
    expect(identical(tester.state(_page('w1')), leadState), isFalse);
    await _tearDown(tester);
  });

  testWidgets('Watch leaves the playback Feed kept for its return alone', (
    tester,
  ) async {
    final feed = _FakeFeed(() async => [_post('g0')]);
    await _pump(tester, feed, home: const _Home());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(_Home)),
    );
    final store = container.read(feedClipResumeProvider);
    store.save(const FeedClipResume(entryKey: 'game:g5', ply: 3));

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(FeedScreen.watch(navigator.context, _post('w1')));
    await _settle(tester);
    expect(tester.widget<FeedClip>(_lead('w1')).isCurrent, isTrue);
    navigator.pop();
    await _settle(tester);

    expect(store.take('game:g5')?.ply, 3);
    await _tearDown(tester);
  });

  testWidgets("a page that brings only Feed's copy of the lead asks for the "
      'next one while the viewer waits on the tail', (tester) async {
    final feed = _FakeFeed(() async => [_post('g0')], next: FeedMore.open);
    await _pump(tester, feed, lead: _post('w1'));
    await _fling(tester, up: true);
    await _fling(tester, up: true);
    expect(
      find.bySemanticsLabel('Loading the next game', skipOffstage: false),
      findsOneWidget,
    );
    final asked = feed.loadMores;

    feed.append([_post('w1')]);
    await _settle(tester);
    expect(feed.loadMores, greaterThan(asked));

    // A page with a game of its own lands where the viewer waits.
    feed.append([_post('g2')]);
    await _settle(tester);
    expect(tester.widget<FeedClip>(_page('g2')).isCurrent, isTrue);
    await _tearDown(tester);
  });

  testWidgets('an ad left last by the hidden copy waits for the post after '
      'it', (tester) async {
    // A free viewer: Feed is [g0, g1, ad, w1]. Under the lead w1, Feed's copy
    // is hidden and the ad would end the list; an ad stands only between two
    // posts.
    final feed = _FakeFeed(() async => [_post('g0'), _post('g1'), _post('w1')]);
    await _pump(tester, feed, lead: _post('w1'), ads: true);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FeedScreen)),
    );
    expect(container.read(feedPagesProvider).map((page) => page.key), [
      'game:g0',
      'game:g1',
      'ad:game:g1',
      'game:w1',
    ]);
    // The lead, g0, g1, then the tail.
    expect(
      tester.widget<PageView>(_pages).childrenDelegate.estimatedChildCount,
      4,
    );
    await _tearDown(tester);
  });

  testWidgets("an archive copy of Feed's game hides Feed's own by its moves", (
    tester,
  ) async {
    final feed = _FakeFeed(() async => [_post('g0'), _post('g1'), _post('g2')]);
    final archive = feedWatchItem(
      _game('arch-1', source: GameSource.gamebase, tourId: 'Test Open 2026'),
      _pgnFor('g1'),
    )!;
    await _pump(tester, feed, lead: archive);
    // The lead, g0, g2, then the tail: g1 is the same game.
    expect(
      tester.widget<PageView>(_pages).childrenDelegate.estimatedChildCount,
      4,
    );
    expect(_page('g1'), findsNothing);
    await _tearDown(tester);
  });

  testWidgets('Watch closed over Feed leaves none of its playback for the Feed '
      'under it to resume', (tester) async {
    final feed = _FakeFeed(
      () async => [_post('g0'), _post('g1'), _post('g2'), _post('g3')],
    );
    await _pump(tester, feed);
    for (var i = 0; i < 3; i++) {
      await _fling(tester, up: true);
    }
    expect(_currentKey(tester), 'game:g3');
    final store = _read(tester, feedClipResumeProvider);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(FeedScreen.watch(navigator.context, _post('w1')));
    await _settle(tester);
    await _fling(tester, up: true);
    expect(tester.widget<FeedClip>(_page('g0').last).isCurrent, isTrue);
    navigator.pop();
    await _settle(tester);

    // Watch's g0 is no place the Feed underneath returns to.
    expect(store.take('game:g0'), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets("after a refresh, Analyze on Feed's own copy of the watched game "
      'goes back to the board too', (tester) async {
    final feed = _FakeFeed(
      () async => [_post('g0')],
      fresh: [_post('w1'), _post('fresh1')],
    );
    await _pump(tester, feed, home: const _Home());
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(FeedScreen.watch(navigator.context, _post('w1')));
    await _settle(tester);
    await tester.tap(_title);
    await _settle(tester);
    expect(feed.refreshes, 1);
    expect(tester.widget<FeedClip>(_page('w1')).isCurrent, isTrue);

    await tester.tap(
      find.descendant(
        of: _page('w1'),
        matching: find.byKey(const ValueKey('feed_analyze_button')),
      ),
    );
    await _settle(tester);
    expect(find.byType(FeedScreen), findsNothing);
    expect(find.byType(_Home), findsOneWidget);
    await _tearDown(tester);
  });

  testWidgets('Watch alone closes Feed when it closes', (tester) async {
    final feed = _FakeFeed(() async => [_post('g0')]);
    await _pump(tester, feed, home: const _Home());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(_Home)),
    );
    expect(container.read(feedScreenOpenProvider), isFalse);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(FeedScreen.watch(navigator.context, _post('w1')));
    await _settle(tester);
    expect(container.read(feedScreenOpenProvider), isTrue);

    navigator.pop();
    await _settle(tester);
    expect(container.read(feedScreenOpenProvider), isFalse);
    await _tearDown(tester);
  });
}

// --------------------------------------------------------------- harness

final Finder _pages = find.byKey(const ValueKey('feed_pages'));
final Finder _title = find.byKey(const ValueKey('feed_title'));

Finder _page(String id) =>
    find.byKey(ValueKey('game:$id'), skipOffstage: false);

/// Watch's lead: a page of its own, apart from Feed's copy of the game.
Finder _lead(String id) =>
    find.byKey(ValueKey('watch:game:$id'), skipOffstage: false);

T _read<T>(WidgetTester tester, ProviderListenable<T> provider) =>
    ProviderScope.containerOf(
      tester.element(find.byType(FeedScreen).first),
    ).read(provider);

String? _currentKey(WidgetTester tester) =>
    _read(tester, feedCurrentEntryKeyProvider);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _fling(WidgetTester tester, {required bool up}) async {
  await tester.fling(_pages.last, Offset(0, up ? -400 : 400), 1500);
  await _settle(tester);
}

Future<void> _pump(
  WidgetTester tester,
  _FakeFeed feed, {
  FeedItem? lead,
  Widget? home,
  bool ads = false,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final sfx = _QuietSfx();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        feedAdsAvailableProvider.overrideWithValue(ads),
        feedProvider.overrideWith(() => feed),
        feedPuzzlesProvider.overrideWith((ref) async => const <FeedPuzzle>[]),
        feedNewsProvider.overrideWith((ref) async => const <FeedNews>[]),
        feedSfxProvider.overrideWithValue(sfx),
        feedMoveSoundProvider.overrideWithValue(_QuietMoveSound(sfx)),
        boardSettingsProviderNew.overrideWith(_TestBoardSettings.new),
        likedGamesProvider.overrideWith(_NoLikes.new),
        spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
        currentUserProvider.overrideWithValue(null),
        subscriptionProvider.overrideWith((ref) => _FreeSubscription()),
        engineSettingsProviderNew.overrideWith(_TestEngineSettings.new),
        eventNoSpoilersProvider.overrideWith(_MemoryNoSpoilers.new),
        feedCachedEvalProvider.overrideWith((ref, fen) async => null),
        feedEngineProvider.overrideWithValue(_NoEngine()),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return home ?? FeedScreen(lead: lead);
          },
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

const _pgn =
    '[Event "Test Open 2026"]\n[Result "1-0"]\n\n'
    '1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0';

GamesTourModel _game(
  String id, {
  GameStatus status = GameStatus.whiteWins,
  GameSource source = GameSource.supabase,
  String tourId = 'tour-1',
}) {
  PlayerCard player(String name, int rating) => PlayerCard(
    name: name,
    federation: '',
    title: 'GM',
    rating: rating,
    countryCode: '',
    team: null,
  );
  return GamesTourModel(
    gameId: id,
    source: source,
    whitePlayer: player('Carlsen, Magnus', 2830),
    blackPlayer: player('Nakamura, Hikaru', 2802),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: status,
    roundId: 'round-1',
    tourId: tourId,
    eco: 'C20',
    openingName: "King's Pawn Game",
  );
}

/// A finished game as Feed or Watch would hold it. Each id plays its own
/// moves: Watch tells Feed's copy of its game by them too.
FeedItem _post(String id) => feedWatchItem(_game(id), _pgnFor(id))!;

const _openers = ['a3', 'a4', 'b3', 'h3', 'h4', 'Na3'];
const _replies = ['a6', 'a5', 'h6', 'b6'];
final Map<String, int> _postOrder = {};

/// A scholar's mate after a quiet first move pair of its own, per [id].
String _pgnFor(String id) {
  final i = _postOrder.putIfAbsent(id, () => _postOrder.length);
  final opener = _openers[i % _openers.length];
  final reply = _replies[(i ~/ _openers.length) % _replies.length];
  return '[Event "Test Open 2026"]\n[Result "1-0"]\n\n'
      '1. $opener $reply 2. e4 e5 3. Bc4 Nc6 4. Qh5 Nf6 5. Qxf7# 1-0';
}

/// A feed whose first page is [_load], recording the games the screen
/// reports reached and the pages it asks for. A refresh deals [fresh] (two
/// fresh games by default) at once; [append] lands a page.
class _FakeFeed extends FeedNotifier {
  _FakeFeed(this._load, {this.fresh, this.next = FeedMore.exhausted});

  final Future<List<FeedItem>> Function() _load;
  final List<FeedItem>? fresh;
  final FeedMore next;
  final List<int> visible = [];
  int refreshes = 0;
  int loadMores = 0;

  @override
  Future<List<FeedItem>> build() => _load();

  @override
  Future<void> loadMore() async => loadMores++;

  @override
  void onVisible(int index) => visible.add(index);

  @override
  FeedMore get more => next;

  @override
  Future<void> refresh() async {
    refreshes++;
    state = AsyncData(fresh ?? [_post('fresh0'), _post('fresh1')]);
  }

  void append(List<FeedItem> items) =>
      state = AsyncData([...state.requireValue, ...items]);
}

class _QuietSfx implements FeedSfx {
  @override
  bool muted = false;

  @override
  bool boardSoundEnabled = true;

  @override
  Future<void> warmUp() async {}

  @override
  void playSwipe() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _QuietMoveSound extends FeedMoveSound {
  _QuietMoveSound(super.sfx);

  @override
  void play({required String san, MoveClass? moveClass, bool fast = false}) {}
}

class _TestEngineSettings extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();
}

class _MemoryNoSpoilers extends EventNoSpoilersController {
  _MemoryNoSpoilers(Ref ref, String tourId) : super(ref: ref, tourId: tourId);

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

class _NoEngine extends FeedEngine {
  @override
  Future<CloudEval?> evaluate(
    String fen, {
    required void Function(List<Pv> pvs, int depth) onUpdate,
  }) async => null;

  @override
  Future<void> cancel() async {}
}

class _TestBoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _NoLikes extends LikedGamesNotifier {
  @override
  Future<List<SavedAnalysis>> build() async => const [];
}

class _NoShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

class _FreeSubscription extends SubscriptionNotifier {
  _FreeSubscription() : super() {
    state = SubscriptionState(isSubscribed: false, isLoading: false);
  }

  @override
  set state(SubscriptionState value) =>
      super.state = value.copyWith(isSubscribed: false, isLoading: false);
}
