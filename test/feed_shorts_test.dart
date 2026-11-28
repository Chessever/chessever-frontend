// Shorts in Feed play in a few warm players the Feed screen holds, not in a
// web view each page makes and throws away: the next Short is cued before
// its page is reached, the last one is still there on the way back up, and
// a Short's cover stands where its video will play until the picture moves.

import 'dart:async';
import 'dart:convert';

import 'package:chessever2/main.dart' show routeObserver;
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
import 'package:chessever2/screens/feed/models/feed_short.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/providers/feed_entries_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_eval_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/screens/feed/puzzles/feed_puzzle.dart';
import 'package:chessever2/screens/feed/widgets/feed_move_sound.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/feed/widgets/feed_short_page.dart';
import 'package:chessever2/screens/feed/widgets/feed_short_player.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// A web view that is none: it records what its player asks of it and says
/// what a test has its page say.
class _Surface implements FeedShortSurface {
  _Surface(this._say, this._lost);

  final ValueChanged<String> _say;
  final VoidCallback _lost;

  /// Page loads asked for.
  int loads = 0;
  final List<String> scripts = [];
  bool closed = false;

  /// The web view cannot be made.
  bool broken = false;

  @override
  Future<void> load(String html, {required String baseUrl}) async {
    if (broken) throw StateError('no web view');
    expect(html, contains('window.chessShort='));
    expect(baseUrl, 'https://embed.test.example.com/');
    loads++;
  }

  @override
  Future<void> run(String script) async => scripts.add(script);

  @override
  Widget? get view =>
      loads == 0 ? null : SizedBox.expand(key: ValueKey<_Surface>(this));

  @override
  void dispose() => closed = true;

  /// The page posts [type].
  void say(String type, [Map<String, Object?> more = const {}]) =>
      _say(jsonEncode({'type': type, ...more}));

  /// The page's process ended.
  void die() => _lost();

  /// The page's last order, as `id,playing,sound`.
  String? get order => scripts.isEmpty
      ? null
      : RegExp(r'chessShort\((.*)\)$').firstMatch(scripts.last)?[1];
}

class _Surfaces {
  final List<_Surface> made = [];

  /// No web view can be made.
  bool broken = false;

  FeedShortSurface call({
    required Uri origin,
    required ValueChanged<String> onMessage,
    required VoidCallback onLost,
  }) {
    final surface = _Surface(onMessage, onLost)..broken = broken;
    made.add(surface);
    return surface;
  }

  List<_Surface> get open => [
    for (final surface in made)
      if (!surface.closed) surface,
  ];

  /// Every page comes up.
  void ready() {
    for (final surface in open) {
      if (surface.order == null) surface.say('ready');
    }
  }
}

final ImageProvider _pixel = MemoryImage(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA'
    '60e6kgAAAABJRU5ErkJggg==',
  ),
);

/// The Feed's players over [surfaces]; [none] with no site to play on.
FeedShortPlayers _players(_Surfaces surfaces, {bool none = false}) =>
    FeedShortPlayers(
      origin: none ? null : Uri.parse('https://embed.test.example.com'),
      surfaces: surfaces.call,
      supported: true,
      cover: (_) => _pixel,
      fallbackCover: (_) => _pixel,
    );

FeedShort _short(String id) => FeedShort.fromJson({
  'type': 'short',
  'id': id,
  'title': 'Opening Short',
  'channelName': 'Chess channel',
})!;

const _a = 'ShortAAAA01';
const _b = 'ShortBBBB02';
const _c = 'ShortCCCC03';
const _d = 'ShortDDDD04';

void main() {
  group('which Shorts hold a player', () {
    final pages = <FeedEntry>[
      FeedGameEntry(_game('g0')),
      FeedShortEntry(_short(_a)),
      FeedGameEntry(_game('g2')),
      FeedShortEntry(_short(_b)),
      FeedGameEntry(_game('g4')),
      FeedGameEntry(_game('g5')),
      FeedShortEntry(_short(_c)),
      FeedGameEntry(_game('g7')),
    ];

    test('the page in view first, then the next, the last, and further on', () {
      expect(feedShortsNear(pages, 0), [_a, _b]);
      expect(feedShortsNear(pages, 1), [_a, _b]);
      // The Short just left stays ahead of one three pages on.
      expect(feedShortsNear(pages, 2), [_b, _a, _c]);
      // On a Short: the one three pages on comes before the one two back.
      expect(feedShortsNear(pages, 3), [_b, _c, _a]);
      expect(feedShortsNear(pages, 5), [_c, _b]);
      expect(feedShortsNear(pages, 7), [_c]);
    });

    test('none near: none held', () {
      expect(feedShortsNear([FeedGameEntry(_game('g0'))], 0), isEmpty);
      expect(feedShortsNear(const [], 0), isEmpty);
    });
  });

  group("the players' page", () {
    final html = feedShortPlayerHtml(
      Uri.parse('https://embed.test.example.com'),
    );

    test('is one player for many Shorts, named for the site it plays on', () {
      expect(html, contains('var site="https://embed.test.example.com";'));
      expect(html, contains('origin:site'));
      expect(html, contains('window.chessShort=function(id,on,snd)'));
      expect(html, contains('player.cueVideoById(want)'));
      expect(html, contains('player.loadVideoById(want)'));
      expect(html, contains('https://www.youtube.com/iframe_api'));
      expect(html, isNot(contains('__SITE__')));
    });

    test('never starts by itself, plays inline, and is told when sound is '
        'refused', () {
      expect(html, contains('autoplay:0'));
      expect(html, contains('playsinline:1'));
      expect(html, contains('onAutoplayBlocked:onBlocked'));
      // Refused with sound, it plays muted rather than not at all.
      expect(html, contains('if(sound&&!quiet){quiet=true;play();return;}'));
      // Out of view it never plays.
      expect(html, contains('if(!active){try{player.pauseVideo();}'));
    });
  });

  group('the players', () {
    test('the Short in view plays and the next is cued, each in its own '
        'player', () {
      fakeAsync((async) {
        final surfaces = _Surfaces();
        final pool = _players(surfaces)..hold([_a, _b], current: _a);
        async.flushMicrotasks();
        expect(surfaces.made, hasLength(2));
        expect(surfaces.made.map((surface) => surface.loads), [1, 1]);
        // Nothing is asked of a page before it is up.
        expect(surfaces.made[0].order, isNull);
        surfaces.ready();
        expect(surfaces.made[0].order, '"$_a",true,true');
        expect(surfaces.made[1].order, '"$_b",false,true');
        expect(pool.playerFor(_a)!.active, isTrue);
        expect(pool.playerFor(_b)!.active, isFalse);
        pool.dispose();
      });
    });

    test('going back up finds the last Short where it stopped: nothing is '
        'loaded again', () {
      fakeAsync((async) {
        final surfaces = _Surfaces();
        final pool = _players(surfaces)..hold([_a, _b], current: _a);
        async.flushMicrotasks();
        surfaces.ready();
        final first = surfaces.made[0];
        final second = surfaces.made[1];
        first.say('playing', {'id': _a});

        // On to the next Short: the first only stops.
        pool.hold([_b, _a], current: _b);
        expect(first.order, '"$_a",false,true');
        expect(second.order, '"$_b",true,true');
        expect(first.closed, isFalse);

        // And back.
        pool.hold([_a, _b], current: _a);
        expect(first.order, '"$_a",true,true');
        expect(second.order, '"$_b",false,true');
        expect(surfaces.made, hasLength(2));
        expect(surfaces.made.map((surface) => surface.loads), [1, 1]);
        pool.dispose();
      });
    });

    test('a Short further down starts in a player that is already up', () {
      fakeAsync((async) {
        final surfaces = _Surfaces();
        final pool = _players(surfaces)..hold([_a], current: _a);
        async.flushMicrotasks();
        surfaces.ready();
        final surface = surfaces.made.single;

        // Paged on past it, a new Short ahead: the same page takes it.
        pool.hold([_c]);
        expect(surface.order, '"$_c",false,true');
        expect(surface.loads, 1);
        expect(surfaces.made, hasLength(1));
        expect(pool.playerFor(_c), isNotNull);
        expect(pool.playerFor(_a), isNull);
        pool.dispose();
      });
    });

    test('never more than three web views; one stays warm through a run of '
        'boards', () {
      fakeAsync((async) {
        final surfaces = _Surfaces();
        final pool = _players(surfaces)..hold([_a, _b, _c, _d], current: _a);
        async.flushMicrotasks();
        surfaces.ready();
        expect(surfaces.made, hasLength(3));
        expect(pool.playerFor(_d), isNull);

        pool.hold(const []);
        expect(surfaces.open, hasLength(1));
        final warm = surfaces.open.single;
        expect(warm.order, 'null,false,true');

        pool.hold([_d]);
        expect(warm.order, '"$_d",false,true');
        expect(warm.loads, 1);
        expect(surfaces.made, hasLength(3));
        pool.dispose();
        expect(surfaces.open, isEmpty);
      });
    });

    test('the Short in view always has a player, whatever else is near', () {
      fakeAsync((async) {
        final surfaces = _Surfaces();
        final pool = _players(surfaces)..hold([_a, _b, _c], current: _d);
        async.flushMicrotasks();
        expect(pool.playerFor(_d), isNotNull);
        expect(pool.playerFor(_c), isNull);
        pool.dispose();
      });
    });

    test('a Short stops the moment the Feed is not seen, and plays on when '
        'it is again', () {
      fakeAsync((async) {
        final surfaces = _Surfaces();
        final pool = _players(surfaces)..hold([_a], current: _a);
        async.flushMicrotasks();
        surfaces.ready();
        final surface = surfaces.made.single;
        expect(surface.order, '"$_a",true,true');

        pool.seen = false;
        expect(surface.order, '"$_a",false,true');
        expect(pool.playerFor(_a)!.active, isFalse);
        pool.seen = true;
        expect(surface.order, '"$_a",true,true');
        pool.dispose();
      });
    });

    test('an order is given once: said again it would start a Short the '
        'viewer paused', () {
      fakeAsync((async) {
        final surfaces = _Surfaces();
        final pool = _players(surfaces)..hold([_a], current: _a);
        async.flushMicrotasks();
        surfaces.ready();
        final surface = surfaces.made.single;
        expect(surface.scripts, hasLength(1));

        pool
          ..hold([_a], current: _a)
          ..hold([_a, _b], current: _a);
        expect(surface.scripts, hasLength(1));
        pool.dispose();
      });
    });

    test('sound refused: the next Short starts muted, until the viewer '
        'unmutes one', () {
      fakeAsync((async) {
        final surfaces = _Surfaces();
        final pool = _players(surfaces)..hold([_a, _b], current: _a);
        async.flushMicrotasks();
        surfaces.ready();
        expect(pool.startMuted, isFalse);
        surfaces.made[0].say('sound', {'id': _a, 'on': false});
        expect(pool.startMuted, isTrue);

        pool.hold([_b, _a], current: _b);
        expect(surfaces.made[1].order, '"$_b",true,false');

        surfaces.made[1].say('sound', {'id': _b, 'on': true});
        expect(pool.startMuted, isFalse);
        pool.hold([_a, _b], current: _a);
        expect(surfaces.made[0].order, '"$_a",true,true');
        pool.dispose();
      });
    });

    test('a Short YouTube will not play gives its player to the next', () {
      fakeAsync((async) {
        final surfaces = _Surfaces();
        final pool = _players(surfaces)..hold([_a, _b], current: _a);
        async.flushMicrotasks();
        surfaces.ready();
        surfaces.made[0].say('error', {'id': _a, 'code': 150});
        expect(pool.cannotPlay(_a), isTrue);
        expect(pool.playerFor(_a), isNull);
        expect(pool.cannotPlay(_b), isFalse);
        expect(pool.playerFor(_b), isNotNull);

        // It is not given a player again.
        pool.hold([_a, _b], current: _a);
        expect(pool.playerFor(_a), isNull);
        pool.dispose();
      });
    });

    test('a page that died is loaded again and takes up where it was; one '
        'that keeps dying is left, then tried again for the next Short', () {
      fakeAsync((async) {
        final surfaces = _Surfaces();
        final pool = _players(surfaces)..hold([_a], current: _a);
        async.flushMicrotasks();
        surfaces.ready();
        final surface = surfaces.made.single;
        surface.say('playing', {'id': _a});
        expect(pool.playerFor(_a)!.showing, isTrue);

        surface.die();
        expect(pool.playerFor(_a)!.showing, isFalse);
        async.elapse(const Duration(seconds: 2));
        expect(surface.loads, 2);
        final before = surface.scripts.length;
        surface.say('ready');
        // The page is new: it is told again what it held.
        expect(surface.scripts, hasLength(before + 1));
        expect(surface.order, '"$_a",true,true');

        // Again, after a longer wait; a third time it is left alone.
        surface.die();
        async.elapse(const Duration(seconds: 2));
        expect(surface.loads, 2);
        async.elapse(const Duration(seconds: 2));
        expect(surface.loads, 3);
        surface.die();
        expect(pool.playerFor(_a)!.down, isTrue);
        async.elapse(const Duration(minutes: 1));
        expect(surface.loads, 3);

        pool.hold([_b], current: _b);
        async.flushMicrotasks();
        expect(pool.playerFor(_b)!.down, isFalse);
        expect(surface.loads, 4);
        pool.dispose();
      });
    });

    test('a web view that cannot be made is tried again, then given up on', () {
      fakeAsync((async) {
        final surfaces = _Surfaces()..broken = true;
        final pool = _players(surfaces)..hold([_a], current: _a);
        async.flushMicrotasks();
        expect(pool.playerFor(_a)!.down, isFalse);
        async.elapse(const Duration(seconds: 10));
        expect(pool.playerFor(_a)!.down, isTrue);
        expect(pool.playerFor(_a)!.view, isNull);
        expect(surfaces.made, hasLength(1));
        pool.dispose();
      });
    });

    test('short of memory: only the Short playing keeps its web view', () {
      fakeAsync((async) {
        final surfaces = _Surfaces();
        final pool = _players(surfaces)..hold([_a, _b, _c], current: _a);
        async.flushMicrotasks();
        surfaces.ready();
        pool.trim();
        expect(surfaces.open, [surfaces.made[0]]);
        expect(pool.playerFor(_a), isNotNull);
        expect(pool.playerFor(_b), isNull);

        // They come back as their pages are reached.
        pool.hold([_b, _a], current: _b);
        async.flushMicrotasks();
        expect(pool.playerFor(_b), isNotNull);
        pool.dispose();
      });
    });

    test('with no site to play on, no web view is made', () {
      fakeAsync((async) {
        final surfaces = _Surfaces();
        final pool = _players(surfaces, none: true)..hold([_a], current: _a);
        async.flushMicrotasks();
        expect(pool.supported, isFalse);
        expect(surfaces.made, isEmpty);
        pool.dispose();
      });
    });
  });

  group("a Short's page", () {
    Future<void> pumpPage(
      WidgetTester tester,
      FeedShortPlayers pool, {
      VoidCallback? onOpened,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedShortPage(
              short: _short(_a),
              players: pool,
              onOpened: onOpened ?? () {},
            ),
          ),
        ),
      );
    }

    Future<void> close(WidgetTester tester, FeedShortPlayers pool) async {
      await tester.pumpWidget(const SizedBox.shrink());
      pool.dispose();
    }

    double opacityOf(WidgetTester tester, _Surface surface) => tester
        .widget<AnimatedOpacity>(
          find.ancestor(
            of: find.byKey(ValueKey<_Surface>(surface)),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    bool ignores(WidgetTester tester, _Surface surface) => tester
        .widget<IgnorePointer>(
          find
              .ancestor(
                of: find.byKey(ValueKey<_Surface>(surface)),
                matching: find.byType(IgnorePointer),
              )
              .first,
        )
        .ignoring;

    final waiting = find.byKey(const ValueKey('feed_short_waiting'));

    testWidgets('its cover stands where the video will play until the '
        'picture moves; then the player is let through', (tester) async {
      final surfaces = _Surfaces();
      final pool = _players(surfaces);
      await pumpPage(tester, pool);
      // No player yet: the cover alone, never a black page.
      expect(find.byType(FeedShortCover), findsOneWidget);
      final cover = tester.getSize(
        find.descendant(
          of: find.byType(FeedShortCover),
          matching: find.byType(AspectRatio),
        ),
      );
      expect(cover.width / cover.height, closeTo(9 / 16, 0.001));
      expect(cover.height, tester.getSize(find.byType(FeedShortPage)).height);

      pool.hold([_a], current: _a);
      await tester.pump();
      final surface = surfaces.made.single;
      // The web view is in the tree, drawn but unseen, and takes no touch.
      expect(opacityOf(tester, surface), closeTo(0.01, 0.001));
      expect(opacityOf(tester, surface), greaterThan(0));
      expect(ignores(tester, surface), isTrue);
      // A Short that starts at once never shows a spinner.
      expect(waiting, findsNothing);
      await tester.pump(const Duration(milliseconds: 900));
      expect(waiting, findsOneWidget);

      surface
        ..say('ready')
        ..say('playing', {'id': _a});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacityOf(tester, surface), 1);
      expect(ignores(tester, surface), isFalse);
      expect(waiting, findsNothing);
      await close(tester, pool);
    });

    testWidgets('left behind it keeps its picture for the turn, then shows '
        'its cover again; back in view it waits for the picture', (
      tester,
    ) async {
      final surfaces = _Surfaces();
      final pool = _players(surfaces)..hold([_a], current: _a);
      await pumpPage(tester, pool);
      await tester.pump();
      final surface = surfaces.made.single
        ..say('ready')
        ..say('playing', {'id': _a});
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacityOf(tester, surface), 1);

      pool.hold([_a]);
      await tester.pump(const Duration(milliseconds: 300));
      expect(opacityOf(tester, surface), 1);
      expect(ignores(tester, surface), isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      expect(opacityOf(tester, surface), closeTo(0.01, 0.001));

      pool.hold([_a], current: _a);
      await tester.pump();
      expect(opacityOf(tester, surface), closeTo(0.01, 0.001));
      surface.say('playing', {'id': _a});
      await tester.pump();
      expect(opacityOf(tester, surface), 1);
      await close(tester, pool);
    });

    testWidgets('counts as watched after four seconds of playing in view, '
        'once', (tester) async {
      final surfaces = _Surfaces();
      final pool = _players(surfaces)..hold([_a], current: _a);
      var opened = 0;
      await pumpPage(tester, pool, onOpened: () => opened++);
      await tester.pump();
      final surface = surfaces.made.single..say('ready');

      surface.say('playing', {'id': _a});
      await tester.pump(const Duration(milliseconds: 3900));
      expect(opened, 0);
      // A stop starts the count over.
      surface.say('idle', {'id': _a, 'state': 3});
      await tester.pump(const Duration(seconds: 1));
      expect(opened, 0);
      surface.say('playing', {'id': _a});
      await tester.pump(const Duration(milliseconds: 3900));
      expect(opened, 0);
      await tester.pump(const Duration(milliseconds: 200));
      expect(opened, 1);

      // Played on, left and come back to: still once.
      await tester.pump(const Duration(seconds: 10));
      pool.hold([_a]);
      await tester.pump(const Duration(seconds: 1));
      pool.hold([_a], current: _a);
      surface.say('playing', {'id': _a});
      await tester.pump(const Duration(seconds: 10));
      expect(opened, 1);
      await close(tester, pool);
    });

    testWidgets('out of view it is never counted as watched', (tester) async {
      final surfaces = _Surfaces();
      final pool = _players(surfaces)..hold([_a], current: _a);
      var opened = 0;
      await pumpPage(tester, pool, onOpened: () => opened++);
      await tester.pump();
      final surface = surfaces.made.single
        ..say('ready')
        ..say('playing', {'id': _a});
      await tester.pump(const Duration(seconds: 2));
      pool.hold([_a]);
      await tester.pump(const Duration(seconds: 10));
      expect(opened, 0);
      // Another Short's news is not this one's.
      surface.say('playing', {'id': _b});
      await tester.pump(const Duration(seconds: 10));
      expect(opened, 0);
      await close(tester, pool);
    });

    testWidgets('a Short that has not started in six seconds is shown as '
        'its player stands', (tester) async {
      final surfaces = _Surfaces();
      final pool = _players(surfaces)..hold([_a], current: _a);
      await pumpPage(tester, pool);
      await tester.pump();
      final surface = surfaces.made.single..say('ready');
      await tester.pump(const Duration(milliseconds: 5900));
      expect(opacityOf(tester, surface), closeTo(0.01, 0.001));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacityOf(tester, surface), 1);
      expect(ignores(tester, surface), isFalse);
      expect(waiting, findsNothing);
      await close(tester, pool);
    });

    testWidgets('a Short YouTube will not play says so', (tester) async {
      final surfaces = _Surfaces();
      final pool = _players(surfaces)..hold([_a], current: _a);
      await pumpPage(tester, pool);
      await tester.pump();
      surfaces.made.single
        ..say('ready')
        ..say('error', {'id': _a, 'code': 100});
      await tester.pump();
      expect(find.bySemanticsLabel('Short unavailable'), findsOneWidget);
      expect(find.byType(FeedShortCover), findsNothing);
      await close(tester, pool);
    });

    testWidgets('with no site to play on it says so, and makes no web view', (
      tester,
    ) async {
      final surfaces = _Surfaces();
      final pool = _players(surfaces, none: true)..hold([_a], current: _a);
      await pumpPage(tester, pool);
      await tester.pump();
      expect(find.bySemanticsLabel('Short unavailable'), findsOneWidget);
      expect(surfaces.made, isEmpty);
      await close(tester, pool);
    });
  });

  group('in the Feed', () {
    testWidgets('a Short is cued before its page, plays when reached, stops '
        'when passed and plays on, not loaded again, on the way back up', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(393 * 3, 852 * 3)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final entries = <FeedEntry>[
        FeedGameEntry(_game('g0')),
        FeedShortEntry(_short(_a)),
        FeedGameEntry(_game('g2')),
        FeedGameEntry(_game('g3')),
      ];
      final surfaces = _Surfaces();
      final feed = _FakeFeed(entries);
      final sfx = _SilentSfx();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedShortPlayersBuilderProvider.overrideWithValue(
              () => _players(surfaces),
            ),
            feedProvider.overrideWith(() => feed),
            feedEntriesProvider.overrideWith(() => _FixedEntries(entries)),
            feedPuzzlesProvider.overrideWith(
              (ref) async => const <FeedPuzzle>[],
            ),
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
            navigatorObservers: [routeObserver],
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return const FeedScreen(embedded: true);
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // On the first post the Short after it already has its player, cued.
      final surface = surfaces.made.single;
      expect(surface.loads, 1);
      surface.say('ready');
      expect(surface.order, '"$_a",false,true');
      expect(feed.shortsSeen, isEmpty);

      final pages = find.byKey(const ValueKey('feed_pages'));
      Future<void> turn(double dy) async {
        await tester.fling(pages, Offset(0, dy), 1500);
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      // Reached: it plays, and is reported as seen.
      await turn(-320);
      expect(surface.order, '"$_a",true,true');
      expect(feed.shortsSeen, [_a]);
      surface.say('playing', {'id': _a});
      await tester.pump(const Duration(milliseconds: 4100));
      expect(feed.shortsOpened, [_a]);

      // Passed: it stops, and keeps its web view.
      await turn(-320);
      expect(surface.order, '"$_a",false,true');
      expect(surface.closed, isFalse);

      // Back up: the same page plays on. Nothing was made or loaded again.
      await turn(320);
      expect(surface.order, '"$_a",true,true');
      expect(surfaces.made, hasLength(1));
      expect(surface.loads, 1);
      expect(feed.shortsOpened, [_a]);

      // A route over the Feed stops it at once.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const SizedBox.expand()),
        ),
      );
      expect(surface.order, '"$_a",false,true');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(surface.order, '"$_a",true,true');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      expect(surface.closed, isTrue);
    });
  });
}

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
}

class _FakeFeed extends FeedNotifier {
  _FakeFeed(this._entries);

  final List<FeedEntry> _entries;

  /// What the Feed's own record of Shorts was told.
  final List<String> shortsSeen = [];
  final List<String> shortsOpened = [];

  @override
  Future<List<FeedItem>> build() async => [
    for (final entry in _entries)
      if (entry is FeedGameEntry) entry.item,
  ];

  @override
  Future<void> loadMore() async {}

  @override
  void onVisible(int index) {}

  @override
  void noteShortVisible(String id) => shortsSeen.add(id);

  @override
  void noteShortOpened(String id) => shortsOpened.add(id);
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
  dynamic noSuchMethod(Invocation invocation) => null;
}
