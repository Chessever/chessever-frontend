import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/classification_fx/classification_fx.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/screens/feed/feed_screen.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/providers/feed_eval_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/screens/feed/puzzles/feed_puzzle.dart';
import 'package:chessever2/screens/feed/widgets/feed_move_sound.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/utils/audio_player_service.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Leaving Feed silences it at once: nothing Feed started may sound once the
/// viewer is on their way out (back button, back swipe, the app going away),
/// and a Feed that was only covered plays on from where it was.
void main() {
  testWidgets('the back button silences Feed before the page has gone', (
    tester,
  ) async {
    final feed = await _openFeed(tester);
    await _untilFirstMove(tester, feed);
    // The next move is due 650ms after the first: pop 200ms before it, so
    // it falls inside the pop transition.
    await tester.pump(const Duration(milliseconds: 450));
    final before = feed.sound.played.length;

    await tester.tap(find.byKey(const ValueKey('feed_back')));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(FeedScreen), findsNothing);
    expect(
      feed.sound.played.length,
      before,
      reason: 'a move sounded after Back',
    );
    expect(feed.sfx.hushes, greaterThan(0));
  });

  testWidgets(
    'a back swipe silences Feed while the finger is down; a cancelled one '
    'plays on from the same move',
    (tester) async {
      final feed = await _openFeed(tester);
      await _untilFirstMove(tester, feed);
      // An edge swipe is only taken once the page has fully arrived.
      final route = ModalRoute.of(tester.element(find.byType(FeedScreen)))!;
      for (var i = 0; i < 60 && !route.animation!.isCompleted; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(route.popGestureEnabled, isTrue);
      final before = feed.sound.played.length;
      final next = _plies[before];

      // The iOS edge swipe, held part-way across.
      final gesture = await tester.startGesture(const Offset(4, 300));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(
        feed.sound.played.length,
        before,
        reason: 'moves sounded during the back swipe',
      );

      // Let go near the edge: the swipe is cancelled and Feed stays.
      await gesture.moveTo(const Offset(4, 300));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(FeedScreen), findsOneWidget);
      expect(feed.sound.played.length, greaterThan(before));
      // Where it was: the move after the last one heard, not the game
      // starting over.
      expect(feed.sound.played[before].$1, next);

      await _closeAll(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets('the app going to the background silences Feed at once', (
    tester,
  ) async {
    final feed = await _openFeed(tester);
    await _untilFirstMove(tester, feed);
    final before = feed.sound.played.length;

    // Backgrounded: no frames are drawn, so nothing waits for a rebuild.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      feed.sound.played.length,
      before,
      reason: 'moves sounded in the background',
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(feed.sound.played.length, greaterThan(before));
    expect(feed.sound.played[before].$1, 'e5');

    await _closeAll(tester);
  });

  testWidgets('a page pushed over Feed silences it; back, it plays on', (
    tester,
  ) async {
    final feed = await _openFeed(tester);
    await _untilFirstMove(tester, feed);
    final before = feed.sound.played.length;

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Board screen')),
      ),
    );
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(feed.sound.played.length, before);

    navigator.pop();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(feed.sound.played.length, greaterThan(before));
    expect(feed.sound.played[before].$1, 'e5');

    await _closeAll(tester);
  });

  testWidgets('Back cuts a Feed sound that is still ringing, once, and '
      'nothing after', (tester) async {
    final output = _RecordingOutput();
    ClassificationSfx.output = output;
    addTearDown(() => ClassificationSfx.output = null);
    final stops = <Duration>[];
    // The real Feed sound path, down to the audio service's door: the
    // clip's move sounds tell FeedSfx they asked for a voice.
    final sfx = FeedSfx.forTesting(stopVoices: stops.add);
    await _openFeedWith(tester, sfx: sfx, sound: FeedMoveSound(sfx));
    for (var i = 0; i < 60 && output.sounds.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(output.sounds, [SfxType.move]);
    expect(stops, isEmpty, reason: 'cut while Feed was still seen');
    final heard = output.sounds.length;

    await tester.tap(find.byKey(const ValueKey('feed_back')));
    await tester.pump();
    // At once, not when the page has finished animating away.
    expect(stops, hasLength(1), reason: 'the ringing move was not cut');
    expect(stops.single.inMilliseconds, lessThanOrEqualTo(120));

    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(FeedScreen), findsNothing);
    // Disposing the screen hushes again; by then the next page may be
    // sounding, and that is not Feed's to cut.
    expect(stops, hasLength(1), reason: 'cut again once Feed had gone');
    expect(output.sounds.length, heard, reason: 'a sound after Back');
  });

  test('hush cuts only what Feed may still have ringing', () {
    final output = _RecordingOutput();
    ClassificationSfx.output = output;
    addTearDown(() => ClassificationSfx.output = null);
    final stops = <Duration>[];
    final sfx = FeedSfx.forTesting(stopVoices: stops.add);

    // Feed has asked for nothing: nothing of its own can be ringing.
    sfx.hush();
    expect(stops, isEmpty);

    // A stinger, then the viewer leaves: cut once.
    final game = _scholarsMate();
    sfx.playForPly(game.plies[1]);
    sfx.hush();
    expect(stops, hasLength(1));
    sfx.hush();
    expect(stops, hasLength(1), reason: 'a second hush cut again');

    // A page's own move sound counts the same.
    sfx.noteSounded();
    sfx.hush();
    expect(stops, hasLength(2));

    // Muted, Feed asks for nothing, so there is nothing to cut.
    sfx.muted = true;
    sfx.playSwipe();
    sfx.hush();
    expect(stops, hasLength(2));
  });

  test('a draw chime still waiting is dropped when Feed is hushed', () {
    final output = _RecordingOutput();
    ClassificationSfx.output = output;
    addTearDown(() => ClassificationSfx.output = null);
    final sfx = FeedSfx.forTesting();
    final drawn = _scholarsMate(result: '½-½', status: GameStatus.draw);

    // A move just sounded: the chime waits for its tail.
    sfx.playForPly(drawn.plies[1]);
    sfx.playGameEnd(drawn);
    expect(output.sounds, [SfxType.move]);

    sfx.hush();
    return Future<void>.delayed(const Duration(milliseconds: 600), () {
      expect(output.sounds, [SfxType.move], reason: 'the chime sounded');
    });
  });
}

// --------------------------------------------------------------- harness

class _Feed {
  _Feed(this.sfx, this.sound);

  final _SilentSfx sfx;
  final _RecordingMoveSound sound;
}

/// A home page with a button that opens Feed the way Discovery does, on a
/// navigator the app's route observer watches.
Future<_Feed> _openFeed(WidgetTester tester) async {
  final sfx = _SilentSfx();
  final sound = _RecordingMoveSound(sfx);
  await _openFeedWith(tester, sfx: sfx, sound: sound);
  return _Feed(sfx, sound);
}

/// [_openFeed] with the given sound sinks.
Future<void> _openFeedWith(
  WidgetTester tester, {
  required FeedSfx sfx,
  required FeedMoveSound sound,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        feedProvider.overrideWith(() => _FakeFeed([_scholarsMate()])),
        feedPuzzlesProvider.overrideWith((ref) async => const <FeedPuzzle>[]),
        feedNewsProvider.overrideWith((ref) async => const <FeedNews>[]),
        feedSfxProvider.overrideWithValue(sfx),
        feedMoveSoundProvider.overrideWithValue(sound),
        boardSettingsProviderNew.overrideWith(_TestBoardSettings.new),
        likedGamesProvider.overrideWith(_NoLikes.new),
        spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
        currentUserProvider.overrideWithValue(null),
        subscriptionProvider.overrideWith((ref) => _FreeSubscription()),
        engineSettingsProviderNew.overrideWith(
          () => _TestEngineSettings(const EngineSettings()),
        ),
        eventNoSpoilersProvider.overrideWith(_MemoryNoSpoilers.new),
        feedCachedEvalProvider.overrideWith((ref, fen) async => null),
        feedEngineProvider.overrideWithValue(_RecordingEngine()),
      ],
      child: MaterialApp(
        navigatorObservers: [routeObserver],
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => FeedScreen.open(context),
                  child: const Text('Open Feed'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open Feed'));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(find.byType(FeedScreen), findsOneWidget);
}

Future<void> _untilFirstMove(WidgetTester tester, _Feed feed) async {
  for (var i = 0; i < 60 && feed.sound.played.isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(feed.sound.played, [('e4', null)]);
}

/// Unmounts inside the fake clock so no clip timer outlives the test.
Future<void> _closeAll(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

const _pgn = '1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0';

/// The game's moves in order, as the clip sounds them.
const _plies = ['e4', 'e5', 'Bc4', 'Nc6', 'Qh5', 'Nf6', 'Qxf7#'];

FeedItem _scholarsMate({
  String id = 'feed-test-game',
  String result = '1-0',
  GameStatus status = GameStatus.whiteWins,
}) {
  final parsed = PgnGame.parsePgn(_pgn);
  Position position = PgnGame.startingPosition(parsed.headers);
  final plies = <FeedPly>[FeedPly(fen: position.fen)];
  for (final node in parsed.moves.mainline()) {
    final move = position.parseSan(node.san)!;
    position = position.play(move);
    plies.add(FeedPly(fen: position.fen, san: node.san, uci: move.uci));
  }
  final game = GamesTourModel(
    gameId: id,
    whitePlayer: PlayerCard(
      name: 'Carlsen, Magnus',
      federation: '',
      title: 'GM',
      rating: 2830,
      countryCode: '',
      team: null,
    ),
    blackPlayer: PlayerCard(
      name: 'Nakamura, Hikaru',
      federation: '',
      title: 'GM',
      rating: 2802,
      countryCode: '',
      team: null,
    ),
    whiteTimeDisplay: '--:--',
    blackTimeDisplay: '--:--',
    whiteClockCentiseconds: 0,
    blackClockCentiseconds: 0,
    gameStatus: status,
    roundId: 'round-1',
    tourId: 'tour-1',
    pgn: _pgn,
    fen: plies.last.fen,
    eco: 'C20',
    openingName: "King's Pawn Game",
  );
  return FeedItem(
    game: game,
    plies: plies,
    reason: 'Brilliant finish',
    eventLabel: 'Test Open 2026',
    result: result,
  );
}

class _FakeFeed extends FeedNotifier {
  _FakeFeed(this._items);

  final List<FeedItem> _items;

  @override
  Future<List<FeedItem>> build() async => _items;

  @override
  Future<void> loadMore() async {}

  @override
  void onVisible(int index) {}
}

/// No audio plugin in tests: counts the stingers and the hushes instead.
class _SilentSfx implements FeedSfx {
  @override
  bool muted = false;

  @override
  bool boardSoundEnabled = true;

  @override
  Future<void> warmUp() async {}

  int gameEnds = 0;
  int hushes = 0;

  @override
  void playGameEnd(FeedItem item) => gameEnds++;

  @override
  void playSwipe() {}

  @override
  void hush() => hushes++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _RecordingMoveSound extends FeedMoveSound {
  _RecordingMoveSound(super.sfx);

  final List<(String, MoveClass?)> played = [];

  @override
  void play({required String san, MoveClass? moveClass, bool fast = false}) {
    played.add((san, moveClass));
  }
}

class _RecordingOutput implements ClassificationSfxOutput {
  final List<SfxType> sounds = [];

  @override
  void playOrdinary(SfxType type) => sounds.add(type);

  @override
  void playClassification(SfxType type, {SfxType? fallback}) =>
      sounds.add(type);

  @override
  Future<void> warmUp() async {}
}

class _TestEngineSettings extends EngineSettingsNotifierNew {
  _TestEngineSettings(this.settings);

  final EngineSettings settings;

  @override
  Future<EngineSettings> build() async => settings;
}

class _MemoryNoSpoilers extends EventNoSpoilersController {
  _MemoryNoSpoilers(Ref ref, String tourId) : super(ref: ref, tourId: tourId);

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

class _RecordingEngine extends FeedEngine {
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
