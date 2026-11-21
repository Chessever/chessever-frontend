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
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart'
    show SearchHeaderMetrics;
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Feed tab's re-tap: from anywhere down the feed it rides back to the
/// first post on a spring, silently, visiting nothing on the way. Feed has
/// no title to tap and no speaker: a pushed Feed's bar holds only its back
/// chevron. Turning a page makes no sound.
void main() {
  testWidgets('from far down, the re-tap rides back to the first post and '
      'visits nothing on the way', (tester) async {
    final feed = await _pump(tester, games: 6);
    final top = tester.getRect(_pages).top;
    for (var i = 0; i < 4; i++) {
      await _fling(tester);
    }
    expect(_currentKey(tester), 'game:g4');
    final visits = feed.notifier.visible.length;
    final sounds = feed.sfx.sounds.length;

    _reTap(tester);
    // The post being left stops at once: the first post is the page.
    await tester.pump();
    expect(tester.widget<FeedClip>(_post('g0')).isCurrent, isTrue);
    expect(_currentKey(tester), 'game:g0');
    await _settle(tester);

    expect(tester.getRect(_post('g0')).top, closeTo(top, 0.5));
    // Silent (a clip that ends may sound its result, never the ride), and
    // only the first post reported as reached: the posts passed on the way
    // were not visits.
    expect(feed.sfx.sounds.skip(sounds).where((s) => s != 'end'), isEmpty);
    expect(feed.notifier.visible.skip(visits), [0]);
    // No refresh: that is the pull's.
    expect(feed.notifier.refreshes, 0);
    await _tearDown(tester);
  });

  testWidgets('one page down, the re-tap rides back the whole way', (
    tester,
  ) async {
    await _pump(tester, games: 3);
    final top = tester.getRect(_pages).top;
    await _fling(tester);
    _reTap(tester);
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

  testWidgets('turning a page makes no sound; what the last post had waiting '
      'is dropped', (tester) async {
    final feed = await _pump(tester, games: 3);
    final sounds = feed.sfx.sounds.length;
    final turns = feed.sfx.pageTurns;
    await tester.fling(_pages, const Offset(0, -400), 1500);
    // The page changes mid-swipe; nothing sounds for it, then or after.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(_currentKey(tester), 'game:g1');
    expect(feed.sfx.sounds.skip(sounds), isEmpty);
    expect(feed.sfx.pageTurns, turns + 1);
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

    _reTap(tester);
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

    _reTap(tester);
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

  testWidgets('a pushed Feed\'s bar holds only its back chevron: no title, '
      'no speaker', (tester) async {
    await _pump(tester, games: 1, pushed: true);
    expect(find.byKey(const ValueKey('feed_title')), findsNothing);
    expect(find.text('Feed'), findsNothing);
    expect(find.byKey(const ValueKey('feed_sound_toggle')), findsNothing);
    expect(find.bySemanticsLabel('Move sounds'), findsNothing);
    final back = tester.getRect(find.byKey(const ValueKey('feed_back')));
    // Every pushed page's back: the one chevron at the one x, from the
    // bar's own start edge, as tall as the bar's controls.
    final bar = tester.getRect(find.byType(HomeTopBarFrame));
    expect(
      back.center.dx - bar.left,
      closeTo(SearchHeaderMetrics.backGlyphCenter, 0.5),
    );
    expect(back.height, closeTo(HomeTopBarMetrics.controlExtent, 0.5));
    // The page starts under the bar.
    expect(tester.getRect(_pages).top, closeTo(bar.bottom, 0.5));
    await _tearDown(tester);
  });
}

void _reTap(WidgetTester tester) {
  ProviderScope.containerOf(tester.element(find.byType(FeedScreen)))
      .read(bottomNavBarReTapRequestProvider.notifier)
      .request(BottomNavBarItem.feed);
}

// --------------------------------------------------------------- harness

final Finder _pages = find.byKey(const ValueKey('feed_pages'));

Finder _post(String id) =>
    find.byKey(ValueKey('game:$id'), skipOffstage: false);

String? _currentKey(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(FeedScreen)),
).read(feedCurrentEntryKeyProvider);

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

/// Feed as the Feed tab ([FeedScreen.embedded]), or [pushed] over a page.
Future<_Feed> _pump(
  WidgetTester tester, {
  required int games,
  bool pushed = false,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final sfx = _CountingSfx();
  final feed = _FakeFeed([
    for (var i = 0; i < games; i++) _scholarsMate('g$i'),
  ]);
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
            return pushed
                ? const FeedScreen()
                : const FeedScreen(embedded: true);
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

/// A feed of [_items] that records what the screen reports reached and how
/// often it was refreshed.
class _FakeFeed extends FeedNotifier {
  _FakeFeed(this._items);

  final List<FeedItem> _items;
  final List<int> visible = [];
  int refreshes = 0;

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
    state = AsyncData([_scholarsMate('fresh0'), _scholarsMate('fresh1')]);
  }
}

/// Records every sound Feed asks for, and every page turn it reports.
class _CountingSfx implements FeedSfx {
  final List<String> sounds = [];
  int pageTurns = 0;

  @override
  bool muted = false;

  @override
  bool boardSoundEnabled = true;

  @override
  Future<void> warmUp() async {}

  @override
  void pageTurned() => pageTurns++;

  @override
  void playForPly(FeedPly ply, {bool fast = false}) => sounds.add('ply');

  @override
  void playGameEnd(FeedItem item) => sounds.add('end');

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
