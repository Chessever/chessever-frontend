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
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/providers/feed_eval_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/screens/feed/puzzles/feed_puzzle.dart';
import 'package:chessever2/screens/feed/widgets/feed_clip.dart';
import 'package:chessever2/screens/feed/widgets/feed_move_sound.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Feed title: a tap goes back to the first post; on the first post it
/// runs the pull to refresh.
void main() {
  testWidgets('from far down, the title rides back to the first post and '
      'visits nothing on the way', (tester) async {
    final feed = await _pump(tester, games: 6);
    final top = tester.getRect(_pages).top;
    for (var i = 0; i < 4; i++) {
      await _fling(tester);
    }
    expect(_currentKey(tester), 'game:g4');
    final visits = feed.notifier.visible.length;
    final swipes = feed.sfx.swipes;

    await tester.tap(_title);
    // The post being left stops at once: the first post is the page.
    await tester.pump();
    expect(tester.widget<FeedClip>(_post('g0')).isCurrent, isTrue);
    expect(_currentKey(tester), 'game:g0');
    await _settle(tester);

    expect(tester.getRect(_post('g0')).top, closeTo(top, 0.5));
    // One swipe's sound, and only the first post reported as reached: the
    // posts passed on the way were not visits.
    expect(feed.sfx.swipes, swipes + 1);
    expect(feed.notifier.visible.skip(visits), [0]);
    // No refresh: that is the second tap's.
    expect(feed.notifier.refreshes, 0);
    await _tearDown(tester);
  });

  testWidgets('one page down, the title rides back the whole way', (
    tester,
  ) async {
    await _pump(tester, games: 3);
    final top = tester.getRect(_pages).top;
    await _fling(tester);
    await tester.tap(_title);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 120));
    // On its way: the first post coming down from above.
    final mid = tester.getRect(_post('g0')).top;
    expect(mid, lessThan(top));
    expect(mid, greaterThan(top - tester.getRect(_pages).height));
    await _settle(tester);
    expect(tester.getRect(_post('g0')).top, closeTo(top, 0.5));
    await _tearDown(tester);
  });

  testWidgets('on the first post, the title pulls to refresh: the page comes '
      'down with the rank, holds while it loads, then lands the new draw', (
    tester,
  ) async {
    final feed = await _pump(tester, games: 3, slowRefresh: true);
    final rest = tester.getRect(_pages).top;

    await tester.tap(_title);
    await _frames(tester, 700);
    expect(feed.notifier.refreshes, 1);
    // Held at the pull's hold, the rank lit and read out.
    expect(tester.getRect(_pages).top - rest, closeTo(56, 2));
    expect(find.bySemanticsLabel('Refreshing Feed'), findsOneWidget);
    // Still loading: it holds, and a second tap starts nothing.
    await tester.tap(_title);
    await _frames(tester, 600);
    expect(feed.notifier.refreshes, 1);
    expect(tester.getRect(_pages).top - rest, closeTo(56, 2));

    feed.notifier.land();
    await _settle(tester);
    expect(tester.getRect(_pages).top, closeTo(rest, 0.5));
    expect(find.bySemanticsLabel('Refreshing Feed'), findsNothing);
    expect(tester.getRect(_post('fresh0')).top, closeTo(rest, 0.5));
    expect(tester.widget<FeedClip>(_post('fresh0')).isCurrent, isTrue);
    expect(_currentKey(tester), 'game:fresh0');
    await _tearDown(tester);
  });

  testWidgets('a refresh that is ready at once is still seen: the page dips '
      'and rises', (tester) async {
    final feed = await _pump(tester, games: 2);
    final rest = tester.getRect(_pages).top;
    await tester.tap(_title);
    var lowest = 0.0;
    for (var t = 0; t < 1400; t += 16) {
      await tester.pump(const Duration(milliseconds: 16));
      final dy = tester.getRect(_pages).top - rest;
      if (dy > lowest) lowest = dy;
    }
    expect(feed.notifier.refreshes, 1);
    expect(lowest, greaterThan(40));
    expect(tester.getRect(_pages).top, closeTo(rest, 0.5));
    expect(_currentKey(tester), 'game:fresh0');
    await _tearDown(tester);
  });

  testWidgets('a touch that holds the ride and lets go on the way back still '
      'lands on the first post, reported as reached', (tester) async {
    final feed = await _pump(tester, games: 6);
    for (var i = 0; i < 3; i++) {
      await _fling(tester);
    }
    expect(_currentKey(tester), 'game:g3');
    final visits = feed.notifier.visible.length;

    await tester.tap(_title);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 150));
    // A finger comes down mid-ride and lifts without moving.
    final hold = await tester.startGesture(tester.getCenter(_pages));
    await tester.pump(const Duration(milliseconds: 120));
    await hold.up();
    await _settle(tester);

    final top = tester.getRect(_pages).top;
    expect(tester.getRect(_post('g0')).top, closeTo(top, 0.5));
    expect(_currentKey(tester), 'game:g0');
    expect(tester.widget<FeedClip>(_post('g0')).isCurrent, isTrue);
    // Reached once, when it came to rest there.
    expect(feed.notifier.visible.skip(visits), [0]);
    await _tearDown(tester);
  });

  testWidgets('a swipe that takes over the ride lands where it settles, and '
      'that post is the one reached', (tester) async {
    final feed = await _pump(tester, games: 6);
    for (var i = 0; i < 3; i++) {
      await _fling(tester);
    }
    final visits = feed.notifier.visible.length;

    await tester.tap(_title);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 120));
    // The viewer swipes on to the next post instead.
    final swipe = await tester.startGesture(tester.getCenter(_pages));
    for (var i = 0; i < 8; i++) {
      await swipe.moveBy(const Offset(0, -60));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await swipe.up();
    await _settle(tester);

    final top = tester.getRect(_pages).top;
    expect(tester.getRect(_post('g1')).top, closeTo(top, 0.5));
    expect(_currentKey(tester), 'game:g1');
    expect(tester.widget<FeedClip>(_post('g1')).isCurrent, isTrue);
    expect(tester.widget<FeedClip>(_post('g0')).isCurrent, isFalse);
    expect(feed.notifier.visible.skip(visits).last, 1);
    await _tearDown(tester);
  });

  testWidgets('the title\'s refresh swaps the post only once the page is down: '
      'the post being left goes down, the new one comes up', (tester) async {
    final feed = await _pump(tester, games: 2);
    final rest = tester.getRect(_pages).top;
    await tester.tap(_title);
    double? downAtSwap;
    for (var t = 0; t < 1400; t += 16) {
      await tester.pump(const Duration(milliseconds: 16));
      if (downAtSwap == null && feed.notifier.refreshes > 0) {
        downAtSwap = tester.getRect(_pages).top - rest;
      }
      if (feed.notifier.refreshes == 0) {
        // Until then the post on screen is the one the viewer was on.
        expect(find.byKey(const ValueKey('game:fresh0')), findsNothing);
      }
    }
    expect(feed.notifier.refreshes, 1);
    expect(downAtSwap, greaterThan(40));
    expect(tester.getRect(_pages).top, closeTo(rest, 0.5));
    expect(_currentKey(tester), 'game:fresh0');
    await _tearDown(tester);
  });

  testWidgets('the title is a button as tall as the bar\'s controls, and the '
      'bar keeps its height', (tester) async {
    await _pump(tester, games: 1);
    final title = tester.getRect(_title);
    expect(title.height, closeTo(HomeTopBarMetrics.controlExtent, 0.5));
    // As wide as its word: it does not stretch across the bar.
    expect(title.width, lessThan(120));
    expect(find.bySemanticsLabel('Feed'), findsOneWidget);
    final back = tester.getRect(find.byKey(const ValueKey('feed_back')));
    expect(title.center.dy, closeTo(back.center.dy, 0.5));
    await _tearDown(tester);
  });
}

// --------------------------------------------------------------- harness

final Finder _pages = find.byKey(const ValueKey('feed_pages'));
final Finder _title = find.byKey(const ValueKey('feed_title'));

Finder _post(String id) =>
    find.byKey(ValueKey('game:$id'), skipOffstage: false);

String? _currentKey(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(FeedScreen)),
).read(feedCurrentEntryKeyProvider);

Future<void> _frames(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _fling(WidgetTester tester) async {
  await tester.fling(_pages, const Offset(0, -400), 1500);
  await _settle(tester);
}

class _Feed {
  _Feed(this.notifier, this.sfx);

  final _FakeFeed notifier;
  final _CountingSfx sfx;
}

Future<_Feed> _pump(
  WidgetTester tester, {
  required int games,
  bool slowRefresh = false,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final sfx = _CountingSfx();
  final feed = _FakeFeed([
    for (var i = 0; i < games; i++) _scholarsMate('g$i'),
  ], slowRefresh: slowRefresh);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
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
            return const FeedScreen();
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return _Feed(feed, sfx);
}

Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

const _pgn = '1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0';

FeedItem _scholarsMate(String id) {
  final parsed = PgnGame.parsePgn(_pgn);
  Position position = PgnGame.startingPosition(parsed.headers);
  final plies = <FeedPly>[FeedPly(fen: position.fen)];
  for (final node in parsed.moves.mainline()) {
    final move = position.parseSan(node.san)!;
    position = position.play(move);
    plies.add(FeedPly(fen: position.fen, san: node.san, uci: move.uci));
  }
  PlayerCard player(String name, int rating) => PlayerCard(
    name: name,
    federation: '',
    title: 'GM',
    rating: rating,
    countryCode: '',
    team: null,
  );
  return FeedItem(
    game: GamesTourModel(
      gameId: id,
      whitePlayer: player('Carlsen, Magnus', 2830),
      blackPlayer: player('Nakamura, Hikaru', 2802),
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.whiteWins,
      roundId: 'round-1',
      tourId: 'tour-1',
      pgn: _pgn,
      fen: plies.last.fen,
      eco: 'C20',
      openingName: "King's Pawn Game",
    ),
    plies: plies,
    reason: '',
    eventLabel: 'Test Open 2026',
    result: '1-0',
  );
}

/// A feed of [_items] that records what the screen reports reached. A
/// refresh deals two fresh games, at once or when [land] is called.
class _FakeFeed extends FeedNotifier {
  _FakeFeed(this._items, {this.slowRefresh = false});

  final List<FeedItem> _items;
  final bool slowRefresh;
  final List<int> visible = [];
  int refreshes = 0;
  Completer<void>? _landing;

  @override
  Future<List<FeedItem>> build() async => _items;

  @override
  Future<void> loadMore() async {}

  @override
  void onVisible(int index) => visible.add(index);

  @override
  FeedMore get more => FeedMore.exhausted;

  @override
  Future<void> refresh() async {
    refreshes++;
    if (slowRefresh) {
      final landing = _landing = Completer<void>();
      await landing.future;
    }
    state = AsyncData([_scholarsMate('fresh0'), _scholarsMate('fresh1')]);
  }

  void land() => _landing?.complete();
}

class _CountingSfx implements FeedSfx {
  int swipes = 0;

  @override
  bool muted = false;

  @override
  bool boardSoundEnabled = true;

  @override
  Future<void> warmUp() async {}

  @override
  void playSwipe() => swipes++;

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
    required EngineSettings settings,
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
