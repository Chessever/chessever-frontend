import 'dart:async';

import 'package:chessever2/main.dart' show routeObserver;
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/game_stream_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/chessboard/provider/chess_board_screen_provider_new.dart';
import 'package:chessever2/screens/chessboard/view_model/chess_board_state_new.dart';
import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/screens/feed/feed_screen.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/providers/feed_eval_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/screens/feed/puzzles/feed_puzzle.dart';
import 'package:chessever2/screens/feed/widgets/feed_glyphs.dart';
import 'package:chessever2/screens/feed/widgets/feed_move_sound.dart';
import 'package:chessever2/screens/feed/widgets/feed_save.dart';
import 'package:chessever2/screens/feed/widgets/feed_scrub.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Save on a Feed post: the board screen's Save, beside Like. It opens the
/// board screen's own save sheet for the post's game, holds the clip while
/// the sheet is up, and shows when the game is already saved.
void main() {
  testWidgets('every game post has Save beside Like, after Share', (
    tester,
  ) async {
    await _pump(tester);
    final share = tester.getRect(_button('feed_share_button'));
    final save = tester.getRect(_button('feed_save_button'));
    final like = tester.getRect(_button('feed_like_button'));
    expect(save.left, greaterThanOrEqualTo(share.right - 0.5));
    expect(like.left, greaterThanOrEqualTo(save.right - 0.5));
    expect(save.center.dy, closeTo(like.center.dy, 0.5));
    expect(save.height, greaterThanOrEqualTo(44));
    expect(
      find.descendant(
        of: _button('feed_save_button'),
        matching: find.text('Save'),
      ),
      findsOneWidget,
    );
    expect(_saveGlyph(tester), FeedGlyphs.save);
    await _tearDown(tester);
  });

  testWidgets('Save opens the save sheet for the post\'s game, parsed on the '
      'board provider at its last move, and the clip holds until it closes', (
    tester,
  ) async {
    final feed = await _pump(tester);
    // Let the clip play a move or two first.
    await _frames(tester, 2500);
    final before = _progress(tester);
    expect(before, greaterThan(0));

    await tester.tap(_button('feed_save_button'));
    await tester.pump();
    await _untilOpened(tester, feed);
    expect(feed.sheets, hasLength(1));
    final opened = feed.sheets.single;
    expect(opened.params.game.gameId, 'g0');
    expect(opened.params.index, kFeedSaveBoardIndex);
    final game = opened.state.analysisState.game!;
    expect(game.mainline, hasLength(7));
    // On the game's last move, where the saved analysis opens.
    expect(opened.state.analysisState.currentMoveIndex, 6);
    expect(find.byKey(const ValueKey('fake_save_sheet')), findsOneWidget);

    // Held while the sheet is up.
    final held = _progress(tester);
    await _frames(tester, 3000);
    expect(_progress(tester), held);

    // Closed: it plays on from where it was.
    await tester.tap(find.byKey(const ValueKey('fake_save_sheet_close')));
    await tester.pump();
    await _frames(tester, 3000);
    expect(_progress(tester), greaterThan(held));
    await _tearDown(tester);
  });

  testWidgets('Save holds the clip itself, from the tap: while the game is '
      'still being read for the sheet, and while the sheet is up with no '
      'page over Feed to hold it', (tester) async {
    final gate = Completer<String?>();
    final feed = await _pump(tester, pgnGate: gate, observeRoutes: false);
    await _frames(tester, 2500);
    expect(_progress(tester), greaterThan(0));

    await tester.tap(_button('feed_save_button'));
    await tester.pump();
    final held = _progress(tester);
    // The board provider is still reading the game: no sheet yet, and the
    // clip does not play on under the viewer's wait.
    await _frames(tester, 3000);
    expect(feed.sheets, isEmpty);
    expect(_progress(tester), held);

    gate.complete(_pgn);
    await _untilOpened(tester, feed);
    expect(feed.sheets, hasLength(1));
    expect(feed.sheets.single.state.analysisState.game!.mainline, hasLength(7));
    // Feed is not told of the page over it here: only Save holds the clip.
    await _frames(tester, 3000);
    expect(_progress(tester), held);

    await tester.tap(find.byKey(const ValueKey('fake_save_sheet_close')));
    await tester.pump();
    await _frames(tester, 3000);
    expect(_progress(tester), greaterThan(held));
    await _tearDown(tester);
  });

  testWidgets('a saved game shows Saved, with the disk\'s tick', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, saved: true);
    expect(
      find.descendant(
        of: _button('feed_save_button'),
        matching: find.text('Saved'),
      ),
      findsOneWidget,
    );
    expect(_saveGlyph(tester), FeedGlyphs.saved);
    expect(
      tester.getSemantics(_button('feed_save_button')),
      isSemantics(
        label: 'Saved',
        isButton: true,
        hasSelectedState: true,
        isSelected: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
    await _tearDown(tester);
  });

  testWidgets('a save made in the sheet shows when the sheet closes', (
    tester,
  ) async {
    final feed = await _pump(tester, savesInSheet: true);
    expect(_saveGlyph(tester), FeedGlyphs.save);

    await tester.tap(_button('feed_save_button'));
    await _untilOpened(tester, feed);
    await tester.tap(find.byKey(const ValueKey('fake_save_sheet_close')));
    await tester.pump();
    await tester.pump();
    expect(_saveGlyph(tester), FeedGlyphs.saved);
    expect(
      find.descendant(
        of: _button('feed_save_button'),
        matching: find.text('Saved'),
      ),
      findsOneWidget,
    );
    expect(feed.lookups, greaterThanOrEqualTo(2));
    await _tearDown(tester);
  });

  testWidgets('back on Feed from a page over it (the board, say), the saved '
      'state is read again', (tester) async {
    final feed = await _pump(tester);
    await tester.pump();
    final lookups = feed.lookups;
    expect(_saveGlyph(tester), FeedGlyphs.save);

    // Analyze opens the board over Feed; the game is saved there.
    unawaited(
      Navigator.of(tester.element(find.byType(FeedScreen))).push(
        MaterialPageRoute<void>(builder: (_) => const Scaffold()),
      ),
    );
    await _frames(tester, 600);
    feed.saved = true;
    Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
    await _frames(tester, 600);

    expect(tester.takeException(), isNull);
    expect(feed.lookups, greaterThan(lookups));
    expect(_saveGlyph(tester), FeedGlyphs.saved);
    await _tearDown(tester);
  });

  testWidgets('a second tap while the sheet is being opened opens nothing '
      'more', (tester) async {
    final feed = await _pump(tester);
    await tester.tap(_button('feed_save_button'));
    await tester.tap(_button('feed_save_button'), warnIfMissed: false);
    await _untilOpened(tester, feed);
    await _frames(tester, 300);
    expect(feed.sheets, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('fake_save_sheet_close')));
    await tester.pump();
    await _tearDown(tester);
  });
}

// --------------------------------------------------------------- harness

/// Until the sheet is up: the board provider has parsed the game and the
/// sheet's route is on screen.
Future<void> _untilOpened(WidgetTester tester, _Feed feed) async {
  for (var i = 0; i < 20 && feed.sheets.isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Finder _button(String key) => find.byKey(ValueKey(key));

String _saveGlyph(WidgetTester tester) => tester
    .widget<FeedGlyph>(
      find.descendant(
        of: _button('feed_save_button'),
        matching: find.byType(FeedGlyph),
      ),
    )
    .svg;

double _progress(WidgetTester tester) =>
    tester.widget<FeedScrubStrip>(find.byType(FeedScrubStrip).first).progress;

Future<void> _frames(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

class _Opened {
  _Opened(this.state, this.params);

  final ChessBoardStateNew state;
  final ChessBoardProviderParams params;
}

class _Feed {
  final List<_Opened> sheets = [];
  bool saved = false;
  int lookups = 0;
}

Future<_Feed> _pump(
  WidgetTester tester, {
  bool saved = false,
  bool savesInSheet = false,
  Completer<String?>? pgnGate,
  bool observeRoutes = true,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );

  final feed = _Feed()..saved = saved;
  final sfx = _SilentSfx();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // With a gate the post's game carries no PGN, so the board provider
        // reads it, and waits on the gate.
        feedProvider.overrideWith(
          () => _FakeFeed([_scholarsMate(pgn: pgnGate == null ? _pgn : '')]),
        ),
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
        // The board provider the sheet is built on, off the network.
        gameRepositoryProvider.overrideWithValue(
          _StaticGames(_pgn, gate: pgnGate),
        ),
        gamebaseRepositoryProvider.overrideWithValue(_NoGamebase()),
        gameStreamRepositoryProvider.overrideWithValue(_NoStreams()),
        chessBoardPersistenceEnabledProvider.overrideWithValue(false),
        // The viewer's library, and the sheet, stood in for.
        feedGameSavedProvider.overrideWith((ref, likeId) async {
          feed.lookups++;
          return feed.saved;
        }),
        feedSaveSheetProvider.overrideWithValue(({
          required BuildContext context,
          required ChessBoardStateNew state,
          required ChessBoardProviderParams params,
        }) async {
          feed.sheets.add(_Opened(state, params));
          await Navigator.of(context).push(
            PageRouteBuilder<void>(
              opaque: false,
              pageBuilder: (context, _, _) => Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(
                  key: const ValueKey('fake_save_sheet'),
                  height: 300,
                  child: Center(
                    child: TextButton(
                      key: const ValueKey('fake_save_sheet_close'),
                      onPressed: () {
                        if (savesInSheet) feed.saved = true;
                        Navigator.of(context).pop();
                      },
                      child: const Text('Close'),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
      child: MaterialApp(
        // Feed pauses under a page pushed over it, as in the app.
        navigatorObservers: observeRoutes ? [routeObserver] : const [],
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return const Scaffold(body: FeedScreen());
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return feed;
}

Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 2));
}

const _pgn = '1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0';

FeedItem _scholarsMate({String pgn = _pgn}) {
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
      pgn: pgn,
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

class _StaticGames implements GameRepository {
  _StaticGames(this.pgn, {this.gate});

  final String pgn;

  /// When set, the PGN arrives when the test completes it.
  final Completer<String?>? gate;

  @override
  Future<String?> getGamePgn(String gameId) async => gate?.future ?? pgn;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoGamebase extends GamebaseRepository {
  _NoGamebase() : super(Dio(), baseUrl: 'http://localhost', apiKey: 'test');

  @override
  Future<GamebaseGameWithPgn?> getGameWithPgn(String id) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoStreams extends GameStreamRepository {
  @override
  Stream<Map<String, dynamic>?> subscribeToGameUpdates(String gameId) =>
      const Stream.empty();

  @override
  Stream<String?> subscribeToPgn(String gameId) => const Stream.empty();

  @override
  Stream<String?> subscribeToLastMove(String gameId) => const Stream.empty();

  @override
  Stream<String?> subscribeToFen(String gameId) => const Stream.empty();

  @override
  Stream<String?> subscribeToStatus(String gameId) => const Stream.empty();
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
