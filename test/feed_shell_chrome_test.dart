// Feed as the home shell holds it: the top bar and the bottom bar step away
// as the reader pages on and come back as they page back, on the same
// chrome as every other root. The posts never change size and are never
// under a bar at rest; as the bars move, each post is moved (never laid out
// again) so its centre stays on the centre of the room the bars leave.

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/screens/feed/feed_screen.dart';
import 'package:chessever2/screens/feed/models/feed_entry.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/providers/feed_entries_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_eval_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/screens/feed/puzzles/feed_puzzle.dart';
import 'package:chessever2/screens/feed/widgets/feed_centred_between_bars.dart';
import 'package:chessever2/screens/feed/widgets/feed_move_sound.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const Size _phone = Size(393, 852);
const double _statusBar = 59;
const double _homeIndicator = 34;
const double _bar = 56 + _homeIndicator;

final Finder _pages = find.byKey(const ValueKey('feed_pages'));

/// The shell's composition for Feed: the page runs under the bottom bar,
/// which slides over it; the region pages.
class _Shell extends StatefulWidget {
  const _Shell({required this.onController});

  final ValueChanged<ScrollChromeController> onController;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with SingleTickerProviderStateMixin {
  late final ScrollChromeController chrome = ScrollChromeController(
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    widget.onController(chrome);
  }

  @override
  void dispose() {
    chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBody: true,
      bottomNavigationBar: CollapsingChrome(
        controller: chrome,
        edge: VerticalDirection.down,
        overlay: true,
        child: const ColoredBox(
          key: ValueKey('bottom-bar'),
          color: Colors.black,
          child: SizedBox(height: _bar, width: double.infinity),
        ),
      ),
      body: ScrollChromeRegion(
        controller: chrome,
        paged: true,
        child: const FeedScreen(embedded: true),
      ),
    );
  }
}

Future<ScrollChromeController> _pump(
  WidgetTester tester, {
  bool reduceMotion = false,
}) async {
  tester.view
    ..physicalSize = _phone * 3
    ..devicePixelRatio = 3
    ..padding = const FakeViewPadding(
      top: _statusBar * 3,
      bottom: _homeIndicator * 3,
    )
    ..viewPadding = const FakeViewPadding(
      top: _statusBar * 3,
      bottom: _homeIndicator * 3,
    );
  addTearDown(tester.view.reset);
  final entries = [for (var i = 0; i < 4; i++) FeedGameEntry(_game('g$i'))];
  final sfx = _SilentSfx();
  late ScrollChromeController chrome;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        feedProvider.overrideWith(() => _FakeFeed(entries)),
        feedEntriesProvider.overrideWith(() => _FixedEntries(entries)),
        feedPuzzlesProvider.overrideWith((ref) async => const <FeedPuzzle>[]),
        feedNewsProvider.overrideWith((ref) async => const <FeedNews>[]),
        feedSfxProvider.overrideWithValue(sfx),
        feedMoveSoundProvider.overrideWithValue(FeedMoveSound(sfx)),
        boardSettingsProviderNew.overrideWith(_BoardSettings.new),
        likedGamesProvider.overrideWith(_NoLikes.new),
        spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
        currentUserProvider.overrideWithValue(null),
        subscriptionProvider.overrideWith((ref) => _FreeSubscription()),
        engineSettingsProviderNew.overrideWith(_Settings.new),
        eventNoSpoilersProvider.overrideWith(_MemoryNoSpoilers.new),
        feedCachedEvalProvider.overrideWith((ref, fen) async => null),
        feedEngineProvider.overrideWithValue(_NoEngine()),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            final shell = _Shell(onController: (c) => chrome = c);
            if (!reduceMotion) return shell;
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: shell,
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return chrome;
}

/// A second of frames: a page turn's spring and the bars' run their course.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

/// The current post's like button, which must never be under a bar at rest.
Rect _likeOnScreen(WidgetTester tester) {
  final likes = find.byKey(const ValueKey('feed_like_button'));
  for (final element in likes.evaluate()) {
    final box = element.renderObject! as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (rect.top >= 0 && rect.bottom <= _phone.height) return rect;
  }
  fail('no like button on screen');
}

/// The room the bars leave a post when [shown] of them is on screen (1 all
/// of it, 0 none): from under the top bar's band (the status bar's strip
/// always stays) to over the bottom bar (the home indicator always stays).
({double top, double bottom}) _room(double shown, double header) => (
  top: _statusBar + shown * (header - _statusBar),
  bottom: _phone.height - (_homeIndicator + shown * (_bar - _homeIndicator)),
);

/// Every post built (the one in view and its neighbours): its laid-out box
/// and where it is drawn, both in screen coordinates.
List<({Rect laidOut, Rect drawn})> _posts(WidgetTester tester) => [
  for (final element in find.byType(FeedCentredBetweenBars).evaluate())
    if (element.renderObject case final RenderFeedCentredBetweenBars box
        when box.attached && box.hasSize)
      (
        laidOut: box.localToGlobal(Offset.zero) & box.size,
        drawn: box.child!.localToGlobal(Offset.zero) & box.child!.size,
      ),
];

/// Every post built keeps one size, and is drawn centred in the room the
/// bars leave at [shown], measured from its own page's top.
void _expectCentred(
  WidgetTester tester, {
  required double shown,
  required double header,
  required Size post,
}) {
  final room = _room(shown, header);
  final posts = _posts(tester);
  expect(posts, isNotEmpty);
  for (final p in posts) {
    for (final size in [p.laidOut.size, p.drawn.size]) {
      expect(size.width, closeTo(post.width, 0.01));
      expect(size.height, closeTo(post.height, 0.01), reason: 'one size');
    }
    // The page this post sits on starts a bar's band above its laid-out
    // box: the post is laid out clear of the bars as they stand shown.
    final pageTop = p.laidOut.top - header;
    expect(
      p.drawn.center.dy - pageTop,
      closeTo((room.top + room.bottom) / 2, 0.5),
      reason: 'drawn centred in the room the bars leave (shown $shown)',
    );
  }
}

void main() {
  testWidgets('paging on sends both bars away and back; every post keeps '
      'one size and stays centred in the room they leave', (tester) async {
    final chrome = await _pump(tester);
    // Measured where the bar is: the pages' own context has had the status
    // bar's inset spent on them.
    final header = HomeTopBarMetrics.headerExtent(
      tester.element(find.byType(FeedScreen)),
    );
    final page = tester.getSize(_pages);
    // The pages run edge to edge under both bars.
    expect(page, _phone);
    final post = Size(_phone.width, _phone.height - header - _bar);

    // At rest the post is exactly the room between the bars: its actions
    // stand clear of the bottom bar and answer taps.
    expect(chrome.value, 1);
    _expectCentred(tester, shown: 1, header: header, post: post);
    final current = _posts(tester).firstWhere((p) => p.laidOut.top >= 0);
    expect(current.drawn.top, closeTo(header, 0.5));
    expect(current.drawn.bottom, closeTo(_phone.height - _bar, 0.5));
    var like = _likeOnScreen(tester);
    expect(like.bottom, lessThanOrEqualTo(_phone.height - _bar + 0.5));
    expect(
      find.byKey(const ValueKey('feed_like_button')).hitTestable(),
      findsOneWidget,
    );

    // Page on: the bars leave on their spring. In every frame the pages and
    // the posts keep one size, and each post's centre rides the centre of
    // the room the bars leave, on the bars' own value.
    await tester.fling(_pages, const Offset(0, -320), 1500);
    final seen = <double>{};
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getSize(_pages), page);
      seen.add(chrome.value);
      _expectCentred(tester, shown: chrome.value, header: header, post: post);
    }
    // The bars went the whole way, through the frames between.
    expect(chrome.value, 0);
    expect(seen.any((v) => v > 0.05 && v < 0.95), isTrue);
    final position = tester.state<ScrollableState>(
      find.descendant(of: _pages, matching: find.byType(Scrollable)).first,
    );
    expect(
      position.position.pixels,
      moreOrLessEquals(_phone.height, epsilon: 0.01),
    );
    expect(
      tester.getRect(find.byType(HomeTopBarFrame)).height,
      closeTo(_statusBar, 0.5),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('bottom-bar'))).dy,
      closeTo(_phone.height, 0.5),
    );
    // With the bars away, the post is framed in the middle of the screen,
    // clear of the status bar and the home indicator, and still answers
    // where it is drawn.
    final away = _room(0, header);
    final shownPost = _posts(tester).firstWhere(
      (p) => p.drawn.center.dy > 0 && p.drawn.center.dy < _phone.height,
    );
    expect(shownPost.drawn.top, greaterThanOrEqualTo(away.top - 0.5));
    expect(shownPost.drawn.bottom, lessThanOrEqualTo(away.bottom + 0.5));
    like = _likeOnScreen(tester);
    expect(like.bottom, lessThanOrEqualTo(away.bottom + 0.5));
    expect(
      find.byKey(const ValueKey('feed_like_button')).hitTestable(),
      findsOneWidget,
    );

    // Page back, from the post's header line (the board's centre may hold
    // a piece by now, and a drag there moves it): the bars come back and
    // the post settles where it stood, clear of them.
    await tester.flingFrom(
      Offset(_phone.width / 2, header + 20),
      const Offset(0, 320),
      1500,
    );
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getSize(_pages), page);
      _expectCentred(tester, shown: chrome.value, header: header, post: post);
    }
    expect(position.position.pixels, moreOrLessEquals(0, epsilon: 0.01));
    expect(chrome.value, 1);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('bottom-bar'))).dy,
      closeTo(_phone.height - _bar, 0.5),
    );
    like = _likeOnScreen(tester);
    expect(like.bottom, lessThanOrEqualTo(_phone.height - _bar + 0.5));
    await _tearDown(tester);
  });

  testWidgets('a pull back short of a turn brings the bars back; the post '
      'springs back to its place, centred between them', (tester) async {
    final chrome = await _pump(tester);
    final header = HomeTopBarMetrics.headerExtent(
      tester.element(find.byType(FeedScreen)),
    );
    final post = Size(_phone.width, _phone.height - header - _bar);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: _pages, matching: find.byType(Scrollable)).first,
        )
        .position;
    for (var i = 0; i < 2; i++) {
      await tester.flingFrom(
        Offset(_phone.width / 2, header + 20),
        const Offset(0, -320),
        1500,
      );
      await _frames(tester);
    }
    expect(chrome.value, 0);
    expect(position.pixels, moreOrLessEquals(2 * _phone.height, epsilon: 0.01));
    _expectCentred(tester, shown: 0, header: header, post: post);

    // A short pull back from the post's header line, far from turning the
    // page: the reader who wanted the bars gets them, and the post springs
    // back to its page, moving with them.
    final gesture = await tester.startGesture(
      Offset(_phone.width / 2, header + 20),
    );
    await gesture.moveBy(const Offset(0, 20));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      _expectCentred(tester, shown: chrome.value, header: header, post: post);
    }
    expect(chrome.value, 1);
    expect(position.pixels, moreOrLessEquals(2 * _phone.height, epsilon: 0.01));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('bottom-bar'))).dy,
      closeTo(_phone.height - _bar, 0.5),
    );
    // At rest under the bars, the post's actions are clear of them and
    // still answer.
    expect(
      _likeOnScreen(tester).bottom,
      lessThanOrEqualTo(_phone.height - _bar + 0.5),
    );
    expect(
      find.byKey(const ValueKey('feed_like_button')).hitTestable(),
      findsOneWidget,
    );
    await _tearDown(tester);
  });

  testWidgets('re-tapping the Feed tab rides home to the first post, with '
      'the bars back', (tester) async {
    final chrome = await _pump(tester);
    final header = HomeTopBarMetrics.headerExtent(
      tester.element(find.byType(FeedScreen)),
    );
    final post = Size(_phone.width, _phone.height - header - _bar);
    for (var i = 0; i < 2; i++) {
      await tester.flingFrom(
        Offset(_phone.width / 2, header + 20),
        const Offset(0, -320),
        1500,
      );
      await _frames(tester);
    }
    expect(chrome.value, 0);
    final position = tester
        .state<ScrollableState>(
          find.descendant(of: _pages, matching: find.byType(Scrollable)).first,
        )
        .position;
    expect(position.pixels, moreOrLessEquals(2 * _phone.height, epsilon: 0.01));
    // As every root's re-tap does: the bars back, and the page back to its
    // top.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FeedScreen)),
    );
    final feed = container.read(feedProvider.notifier) as _FakeFeed;
    container
        .read(bottomNavBarReTapRequestProvider.notifier)
        .request(BottomNavBarItem.feed);
    await _frames(tester);
    expect(position.pixels, moreOrLessEquals(0, epsilon: 0.01));
    expect(chrome.value, 1);
    _expectCentred(tester, shown: 1, header: header, post: post);

    // On the first post already, a re-tap reloads nothing: the bar's
    // contract on every root (no pull-to-refresh, no reload), so a stray
    // tap never replaces the post being watched.
    container
        .read(bottomNavBarReTapRequestProvider.notifier)
        .request(BottomNavBarItem.feed);
    await _frames(tester);
    expect(feed.refreshes, 0);
    expect(position.pixels, moreOrLessEquals(0, epsilon: 0.01));
    expect(chrome.value, 1);
    await _tearDown(tester);
  });

  testWidgets('reduced motion: the bars stay and no post ever moves', (
    tester,
  ) async {
    final chrome = await _pump(tester, reduceMotion: true);
    final header = HomeTopBarMetrics.headerExtent(
      tester.element(find.byType(FeedScreen)),
    );
    final post = Size(_phone.width, _phone.height - header - _bar);
    await tester.flingFrom(
      Offset(_phone.width / 2, header + 20),
      const Offset(0, -320),
      1500,
    );
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(chrome.value, 1);
      _expectCentred(tester, shown: 1, header: header, post: post);
    }
    await _tearDown(tester);
  });

  test('the travel centres a post between the bars', () {
    // Shown: a 80pt band under a 59pt status bar, a 90pt bottom bar over a
    // 34pt home indicator. Away: the strips alone.
    final travel = FeedCentredBetweenBars.travelFor(
      shown: const EdgeInsets.only(top: 139, bottom: 90),
      away: const EdgeInsets.only(top: 59, bottom: 34),
    );
    // The room gains 80 at the top and 56 at the bottom: its centre rises
    // by 12.
    expect(travel, -12);
  });
}

// ------------------------------------------------------------------ fakes

FeedItem _game(String id) {
  const pgn = '1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0';
  final parsed = PgnGame.parsePgn(pgn);
  Position position = PgnGame.startingPosition(parsed.headers);
  final plies = <FeedPly>[FeedPly(fen: position.fen, cp: 0)];
  for (final node in parsed.moves.mainline()) {
    final move = position.parseSan(node.san)!;
    position = position.play(move);
    plies.add(
      FeedPly(
        fen: position.fen,
        san: node.san,
        uci: move.uci,
        cp: plies.length * 15,
      ),
    );
  }
  PlayerCard player(String name, int rating) => PlayerCard(
    name: name,
    federation: 'NOR',
    title: 'GM',
    rating: rating,
    countryCode: 'NOR',
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
      pgn: pgn,
      fen: plies.last.fen,
      eco: 'C20',
      openingName: "King's Pawn Game",
      timeControl: 'rapid',
    ),
    plies: plies,
    reason: '',
    eventLabel: 'Test Open 2026',
    result: '1-0',
  );
}

class _FixedEntries extends FeedEntriesNotifier {
  _FixedEntries(this._entries);

  final List<FeedEntry> _entries;

  @override
  List<FeedEntry> build() => _entries;

  @override
  void markSeen(int index) {}
}

class _FakeFeed extends FeedNotifier {
  _FakeFeed(this._entries);

  final List<FeedEntry> _entries;

  @override
  Future<List<FeedItem>> build() async => [
    for (final entry in _entries)
      if (entry is FeedGameEntry) entry.item,
  ];

  @override
  Future<void> loadMore() async {}

  @override
  void onVisible(int index) {}

  /// Fresh draws asked for.
  int refreshes = 0;

  @override
  Future<void> refresh() async => refreshes++;
}

class _Settings extends EngineSettingsNotifierNew {
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

class _BoardSettings extends BoardSettingsNotifierNew {
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

class _SilentSfx implements FeedSfx {
  @override
  bool muted = true;

  @override
  bool boardSoundEnabled = false;

  @override
  Future<void> warmUp() async {}

  @override
  void playGameEnd(FeedItem item) {}

  @override
  void playSwipe() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
