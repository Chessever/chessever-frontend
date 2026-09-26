import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/analysis/chess_game.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/chessboard/widgets/heart_burst.dart';
import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/screens/feed/feed_screen.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/providers/feed_eval_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/screens/feed/puzzles/feed_puzzle.dart';
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/screens/feed/widgets/feed_live_board.dart';
import 'package:chessever2/screens/feed/widgets/feed_move_sound.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The Feed's Like button plays the board screen's heart: the double-tap's
/// burst and flight for a like, the heartbreak for an unlike.
void main() {
  testWidgets('Like plays the double-tap heart over the board, flies it into '
      'the button, and the button fills as it lands', (tester) async {
    final feed = await _pump(tester);
    final board = tester.getRect(find.byType(FeedLiveBoard));

    await tester.tap(_likeButton);
    await _frames(tester, 32);
    // The burst: a like, over the middle of the board.
    final burst = tester.widget<HeartBurst>(find.byType(HeartBurst));
    expect(burst.isUnlike, isFalse);
    // The board screen's heart, at its size: 55% of the board.
    expect(burst.heartSize, closeTo(board.width.clamp(160, 480) * 0.55, 0.01));
    final at = tester.getCenter(find.byType(HeartBurst));
    expect(at.dx, closeTo(board.center.dx, 1));
    expect(at.dy, closeTo(board.center.dy, 1));
    // Liked at once (the notifier's optimistic write), with the board
    // screen's thump...
    expect(feed.likes.toggles, 1);
    expect(_liked(tester), isTrue);
    expect(feed.haptics.first, 'HapticFeedbackType.mediumImpact');
    // ...while the button keeps its outline for the heart on its way.
    expect(_likeGlyph(tester), FeedGlyphs.heartOutline);

    // The burst hands over to the flight.
    await _frames(tester, 620);
    expect(find.byType(HeartBurst), findsNothing);
    expect(find.byType(FlyingHeart), findsOneWidget);
    // It leaves at the size the burst ended at, as on the board screen.
    expect(
      tester.widget<FlyingHeart>(find.byType(FlyingHeart)).startSize,
      closeTo(board.width * 0.55, 0.01),
    );
    expect(_likeGlyph(tester), FeedGlyphs.heartOutline);

    // It docks, within the board screen's 1650ms: the button fills, with
    // the "click into place".
    var flown = 652;
    while (find.byType(FlyingHeart).evaluate().isNotEmpty && flown < 1650) {
      expect(_likeGlyph(tester), FeedGlyphs.heartOutline);
      await _frames(tester, 16);
      flown += 16;
    }
    expect(find.byType(FlyingHeart), findsNothing);
    expect(_likeGlyph(tester), FeedGlyphs.heartFilled);
    expect(feed.haptics.last, 'HapticFeedbackType.selectionClick');
    await _tearDown(tester);
  });

  testWidgets('Like on a liked game plays the heartbreak and unlikes, with no '
      'flight and no haptic', (tester) async {
    final feed = await _pump(tester, liked: const {'g0'});
    expect(_likeGlyph(tester), FeedGlyphs.heartFilled);

    await tester.tap(_likeButton);
    await _frames(tester, 32);
    final burst = tester.widget<HeartBurst>(find.byType(HeartBurst));
    expect(burst.isUnlike, isTrue);
    expect(feed.likes.toggles, 1);
    expect(_liked(tester), isFalse);
    expect(_likeGlyph(tester), FeedGlyphs.heartOutline);

    await _frames(tester, 1000);
    expect(find.byType(HeartBurst), findsNothing);
    expect(find.byType(FlyingHeart), findsNothing);
    expect(feed.haptics, isNot(contains('HapticFeedbackType.mediumImpact')));
    await _tearDown(tester);
  });

  testWidgets('a quick second tap waits for the like to play out, then '
      'unlikes', (tester) async {
    final feed = await _pump(tester);
    await tester.tap(_likeButton);
    await _frames(tester, 300);
    // Mid-animation: neither a second heart nor an undo.
    await tester.tap(_likeButton);
    await _frames(tester, 32);
    expect(feed.likes.toggles, 1);
    expect(find.byType(HeartBurst), findsOneWidget);
    expect(_liked(tester), isTrue);

    // Played out (the board screen's 1650ms): the next tap is the unlike.
    await _frames(tester, 1400);
    await tester.tap(_likeButton);
    await _frames(tester, 32);
    expect(feed.likes.toggles, 2);
    expect(_liked(tester), isFalse);
    expect(tester.widget<HeartBurst>(find.byType(HeartBurst)).isUnlike, isTrue);
    await _tearDown(tester);
  });

  testWidgets('the heart docks as it reaches the button, at the glyph\'s '
      'size, not when its spring settles; a tap right then is the unlike', (
    tester,
  ) async {
    final feed = await _pump(tester);
    final glyph = tester.getRect(
      find.descendant(of: _likeButton, matching: find.byType(FeedGlyph)),
    );
    await tester.tap(_likeButton);
    var t = 0;
    int? flightFrom;
    Rect? lastFrame;
    while (_likeGlyph(tester) != FeedGlyphs.heartFilled && t < 2000) {
      final heart = _flyingHeart(tester);
      if (heart != null) {
        flightFrom ??= t;
        lastFrame = heart;
        // In flight, the button keeps its outline.
        expect(_likeGlyph(tester), FeedGlyphs.heartOutline);
      }
      await tester.pump(const Duration(milliseconds: 16));
      t += 16;
    }
    expect(flightFrom, isNotNull);
    // Docked as it reached the button: its spring is visually home some
    // 430ms in, where it would only settle (and call onArrived) past 850ms.
    expect(t - flightFrom!, inInclusiveRange(400, 500));
    expect(find.byType(FlyingHeart), findsNothing);
    // Its last frame sat on the glyph, at the glyph's own size: no jump,
    // no heart inside an outline.
    expect((lastFrame!.center - glyph.center).distance, lessThan(1.5));
    expect(lastFrame.width, closeTo(glyph.width, 0.5));
    expect(feed.haptics.last, 'HapticFeedbackType.selectionClick');

    // The viewer taps as the heart lands: the heartbreak, and the unlike.
    await tester.tap(_likeButton);
    await _frames(tester, 32);
    expect(feed.likes.toggles, 2);
    expect(_liked(tester), isFalse);
    expect(tester.widget<HeartBurst>(find.byType(HeartBurst)).isUnlike, isTrue);
    await _tearDown(tester);
  });

  testWidgets('an unlike tapped while the like is still being written plays '
      'at once, and is written after it', (tester) async {
    final feed = await _pump(tester, writeTime: const Duration(seconds: 2));
    await tester.tap(_likeButton);
    var t = 0;
    while (_likeGlyph(tester) != FeedGlyphs.heartFilled && t < 2000) {
      await tester.pump(const Duration(milliseconds: 16));
      t += 16;
    }
    // Landed, with the like's write still out.
    expect(feed.likes.writing, isTrue);

    await tester.tap(_likeButton);
    await _frames(tester, 32);
    expect(tester.widget<HeartBurst>(find.byType(HeartBurst)).isUnlike, isTrue);
    // The button says what the viewer asked for at once...
    expect(_likeGlyph(tester), FeedGlyphs.heartOutline);
    // ...while the unlike waits for the like (the notifier would drop it).
    expect(feed.likes.toggles, 1);

    await _frames(tester, 3000);
    expect(feed.likes.toggles, 2);
    expect(_liked(tester), isFalse);
    expect(_likeGlyph(tester), FeedGlyphs.heartOutline);
    expect(find.text("Couldn't update your like."), findsNothing);
    await _tearDown(tester);
  });

  testWidgets('a like the notifier rolls back without throwing is said so', (
    tester,
  ) async {
    final feed = await _pump(tester, rollsBack: true);
    await tester.tap(_likeButton);
    await _frames(tester, 1800);
    expect(feed.likes.toggles, 1);
    expect(_liked(tester), isFalse);
    expect(_likeGlyph(tester), FeedGlyphs.heartOutline);
    expect(find.text("Couldn't update your like."), findsOneWidget);
    await _tearDown(tester);
  });

  testWidgets('a double-tap on the board likes with the same heart, and on a '
      'liked game only plays it again', (tester) async {
    final feed = await _pump(tester);
    final board = tester.getRect(find.byType(FeedLiveBoard));
    // d4 stays empty the whole game.
    final square = Offset(
      board.left + 3.5 * board.width / 8,
      board.top + 4.5 * board.height / 8,
    );
    await tester.tapAt(square);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(square);
    await _frames(tester, 32);
    expect(
      tester.widget<HeartBurst>(find.byType(HeartBurst)).isUnlike,
      isFalse,
    );
    expect(tester.getCenter(find.byType(HeartBurst)).dx, closeTo(square.dx, 1));
    expect(feed.likes.toggles, 1);
    expect(_liked(tester), isTrue);

    // Played out, a second double-tap plays the heart and changes nothing.
    await _frames(tester, 1700);
    await tester.tapAt(square);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(square);
    await _frames(tester, 32);
    expect(
      tester.widget<HeartBurst>(find.byType(HeartBurst)).isUnlike,
      isFalse,
    );
    expect(feed.likes.toggles, 1);
    expect(_liked(tester), isTrue);
    await _tearDown(tester);
  });

  testWidgets('with reduced motion the heart does not fly: the button fills '
      'when the burst is done', (tester) async {
    await _pump(tester, reduceMotion: true);
    await tester.tap(_likeButton);
    await _frames(tester, 32);
    expect(find.byType(HeartBurst), findsOneWidget);
    await _frames(tester, 900);
    expect(find.byType(FlyingHeart), findsNothing);
    expect(_likeGlyph(tester), FeedGlyphs.heartFilled);
    await _tearDown(tester);
  });

  testWidgets('a like that fails rolls back to the outline and says so', (
    tester,
  ) async {
    final feed = await _pump(tester, failing: true);
    await tester.tap(_likeButton);
    await _frames(tester, 1800);
    expect(feed.likes.toggles, 1);
    expect(_liked(tester), isFalse);
    expect(_likeGlyph(tester), FeedGlyphs.heartOutline);
    expect(find.text("Couldn't update your like."), findsOneWidget);
    await _tearDown(tester);
  });
}

// --------------------------------------------------------------- harness

final Finder _likeButton = find.byKey(const ValueKey('feed_like_button'));

/// The svg the Like button draws now.
String _likeGlyph(WidgetTester tester) => tester
    .widget<FeedGlyph>(
      find.descendant(of: _likeButton, matching: find.byType(FeedGlyph)),
    )
    .svg;

/// Where the flying heart's head is drawn now, or null when none flies.
Rect? _flyingHeart(WidgetTester tester) {
  final hearts = find.descendant(
    of: find.byType(FlyingHeart),
    matching: find.byType(Positioned),
  );
  if (hearts.evaluate().isEmpty) return null;
  // The head is painted last, over its trail.
  final head = tester.widgetList<Positioned>(hearts).last;
  return Rect.fromLTWH(head.left!, head.top!, head.width!, head.height!);
}

bool _liked(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(FeedScreen)),
).read(isGameLikedProvider('g0'));

Future<void> _frames(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

class _Feed {
  _Feed(this.likes, this.haptics);

  final _MemoryLikes likes;
  final List<String> haptics;
}

Future<_Feed> _pump(
  WidgetTester tester, {
  Set<String> liked = const {},
  bool reduceMotion = false,
  bool failing = false,
  bool rollsBack = false,
  Duration writeTime = Duration.zero,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final haptics = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments as String);
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

  final sfx = _SilentSfx();
  final likes = _MemoryLikes(
    liked,
    failing: failing,
    rollsBack: rollsBack,
    writeTime: writeTime,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        feedProvider.overrideWith(() => _FakeFeed([_scholarsMate()])),
        feedPuzzlesProvider.overrideWith((ref) async => const <FeedPuzzle>[]),
        feedNewsProvider.overrideWith((ref) async => const <FeedNews>[]),
        feedSfxProvider.overrideWithValue(sfx),
        feedMoveSoundProvider.overrideWithValue(_QuietMoveSound(sfx)),
        boardSettingsProviderNew.overrideWith(_TestBoardSettings.new),
        likedGamesProvider.overrideWith(() => likes),
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
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(disableAnimations: reduceMotion),
              child: const Scaffold(body: FeedScreen()),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return _Feed(likes, haptics);
}

Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
}

const _pgn = '1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0';

FeedItem _scholarsMate() {
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
      gameId: 'g0',
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

/// Likes in memory. The toggle is optimistic like the real one, takes
/// [writeTime] to land, and, as the real one does, drops a toggle for a game
/// whose write is still out. With [failing] it rolls back and throws; with
/// [rollsBack] it rolls back and answers with the old state, as the real
/// one does on an error.
class _MemoryLikes extends LikedGamesNotifier {
  _MemoryLikes(
    this.initial, {
    this.failing = false,
    this.rollsBack = false,
    this.writeTime = Duration.zero,
  });

  final Set<String> initial;
  final bool failing;
  final bool rollsBack;
  final Duration writeTime;
  int toggles = 0;
  bool writing = false;

  @override
  Future<List<SavedAnalysis>> build() async => [
    for (final id in initial) _like(id),
  ];

  @override
  Future<bool> toggle(GamesTourModel game) async {
    if (writing) return isLiked(game.likeId);
    writing = true;
    toggles++;
    try {
      final before = List<SavedAnalysis>.of(state.valueOrNull ?? const []);
      final list = List<SavedAnalysis>.of(before);
      final i = list.indexWhere((a) => a.sourceGameId == game.likeId);
      final liking = i < 0;
      if (liking) {
        list.add(_like(game.likeId));
      } else {
        list.removeAt(i);
      }
      state = AsyncData(list);
      if (failing || rollsBack) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        state = AsyncData(before);
        if (failing) throw StateError('offline');
        return !liking;
      }
      if (writeTime > Duration.zero) await Future<void>.delayed(writeTime);
      return liking;
    } finally {
      writing = false;
    }
  }
}

SavedAnalysis _like(String id) {
  final at = DateTime(2026, 9, 20);
  return SavedAnalysis(
    id: 'like-$id',
    userId: 'user',
    title: id,
    sourceGameId: id,
    chessGame: ChessGame.fromPgn(id, '1. e4 e5 *'),
    analysisState: const {},
    variationComments: const {},
    lastViewedPosition: -1,
    tags: const [],
    isFavorite: false,
    createdAt: at,
    updatedAt: at,
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

class _SilentSfx implements FeedSfx {
  @override
  bool muted = false;

  @override
  bool boardSoundEnabled = true;

  @override
  Future<void> warmUp() async {}

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
