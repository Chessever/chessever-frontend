import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/chessboard/widgets/player_first_row_detail_widget.dart';
import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/screens/feed/feed_screen.dart';
import 'package:chessever2/screens/feed/models/feed_entry.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/providers/feed_eval_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/screens/feed/puzzles/feed_puzzle.dart';
import 'package:chessever2/screens/feed/widgets/feed_live_board.dart';
import 'package:chessever2/screens/feed/widgets/feed_move_sound.dart';
import 'package:chessever2/screens/feed/widgets/feed_scrub.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _pgn = '1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0';

void main() {
  testWidgets(
    'Feed renders the playable clip, autoplays, and a tap toggles pause',
    (tester) async {
      final feed = await _pumpFeed(tester);

      // The board screen's interactive board, both players on the game
      // cards' own rows, and the one-line header: event and opening, never a
      // generic caption.
      expect(find.byType(FeedLiveBoard), findsOneWidget);
      expect(find.byType(Chessboard), findsOneWidget);
      expect(find.byType(PlayerFirstRowDetailWidget), findsNWidgets(2));
      expect(find.text('Brilliant finish'), findsNothing);
      expect(find.text('Test Open 2026'), findsOneWidget);
      expect(find.text('C20'), findsOneWidget);
      // The opening's name may give way to its code on a narrow line; it is
      // always in the button's label.
      expect(
        find.bySemanticsLabel(RegExp("C20 King's Pawn Game")),
        findsOneWidget,
      );
      expect(find.textContaining('Carlsen', findRichText: true), findsWidgets);
      expect(find.textContaining('Nakamura', findRichText: true), findsWidgets);
      expect(find.text('Start'), findsOneWidget);

      // Autoplay: the first move lands after the opening beat, with the
      // board's ordinary sound (it is unclassified).
      await tester.pump(const Duration(milliseconds: 500));
      expect(feed.sound.played, [('e4', null)]);

      // Tap the board on a square the side to move cannot play from (the
      // pawn on e4 is White's; Black is to move) → paused after the
      // double-tap window.
      final board = tester.getCenter(find.byType(FeedLiveBoard));
      await tester.tapAt(board);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('feed_paused')), findsOneWidget);

      // Paused means paused: time passes, the move does not.
      final pausedAt = feed.sound.played.length;
      await tester.pump(const Duration(seconds: 2));
      expect(feed.sound.played.length, pausedAt);
      expect(find.byKey(const ValueKey('feed_paused')), findsOneWidget);

      // Tap again → resumes and moves on.
      await tester.tapAt(board);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('feed_paused')), findsNothing);
      await tester.pump(const Duration(milliseconds: 700));
      expect(feed.sound.played.length, greaterThan(pausedAt));

      await _tearDown(tester);
    },
  );

  testWidgets('holding the right third plays at 2x until release', (
    tester,
  ) async {
    await _pumpFeed(tester);
    final rect = tester.getRect(find.byType(FeedLiveBoard));
    final gesture = await tester.startGesture(
      Offset(rect.right - 20, rect.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('2×'), findsOneWidget);

    await gesture.up();
    await tester.pump();
    expect(find.text('2×'), findsNothing);
    // A hold is not a tap: releasing it must not pause the clip.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('feed_paused')), findsNothing);

    await _tearDown(tester);
  });

  testWidgets('the clip ends on the result card and scrubs without a report', (
    tester,
  ) async {
    final feed = await _pumpFeed(tester);
    // Both player rows agree on whether the finished result may print.
    bool? rowsReveal() => tester
        .widgetList<PlayerFirstRowDetailWidget>(
          find.byType(PlayerFirstRowDetailWidget),
        )
        .map((row) => row.revealResult)
        .toSet()
        .single;
    // The replay opens on the first move: no outcome up front.
    expect(rowsReveal(), isFalse);

    // Seven plies plus the checkmate linger.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 700));
    }
    expect(find.byKey(const ValueKey('feed_end_card')), findsOneWidget);
    expect(rowsReveal(), isTrue);
    expect(find.text('Checkmate · Carlsen wins'), findsOneWidget);
    expect(find.text('Next game'), findsOneWidget);
    expect(feed.sfx.gameEnds, 1);
    // The mating move is classified brilliant: its class sound, not the
    // ordinary checkmate one.
    expect(feed.sound.played.last, ('Qxf7#', MoveClass.brilliant));

    // A touch on the bottom line is not yet a scrub: nothing moves until the
    // finger rests or travels sideways past the drag slop.
    final strip = tester.getRect(find.byType(FeedScrubStrip));
    final gesture = await tester.startGesture(strip.center);
    await tester.pump();
    expect(find.byType(FeedMoveBubble), findsNothing);
    expect(find.byKey(const ValueKey('feed_end_card')), findsOneWidget);

    // Drag it back to the start: no evals, so the move rides the thumb, and
    // nothing else is said about the missing report.
    await gesture.moveTo(Offset(strip.left + 17, strip.center.dy));
    await tester.pump();
    expect(find.byType(FeedMoveBubble), findsOneWidget);
    expect(find.textContaining('report'), findsNothing);
    expect(find.byKey(const ValueKey('feed_end_card')), findsNothing);
    expect(rowsReveal(), isFalse);

    await gesture.moveTo(Offset(strip.center.dx, strip.center.dy));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(find.byType(FeedMoveBubble), findsNothing);

    await _tearDown(tester);
  });

  testWidgets(
    "playing the game's move steps it on; any other move starts your line",
    (tester) async {
      final feed = await _pumpFeed(tester);
      final board = tester.getRect(find.byType(FeedLiveBoard));

      // Before the first beat: White to move. e2, then e4 — the game's move.
      await tester.tapAt(_squareCenter(board, 'e2'));
      await tester.pump(const Duration(milliseconds: 100));
      // A piece in hand holds autoplay: the opening beat passes, nothing plays.
      await tester.pump(const Duration(milliseconds: 600));
      expect(feed.sound.played, isEmpty);
      await tester.tapAt(_squareCenter(board, 'e4'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(feed.sound.played, [('e4', null)]);
      expect(find.byKey(const ValueKey('feed_back_to_game')), findsNothing);

      // Stepping by hand leaves autoplay waiting.
      await tester.pump(const Duration(seconds: 2));
      expect(feed.sound.played, hasLength(1));

      // Black answers e6 instead of the game's e5: the viewer's own line.
      await tester.tapAt(_squareCenter(board, 'e7'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(_squareCenter(board, 'e6'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(feed.sound.played.last, ('e6', null));
      expect(find.byKey(const ValueKey('feed_back_to_game')), findsOneWidget);
      expect(find.text('Your line'), findsOneWidget);

      // A stray tap on an empty square does not throw the line away.
      await tester.tapAt(_squareCenter(board, 'a5'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('feed_back_to_game')), findsOneWidget);
      expect(find.byKey(const ValueKey('feed_paused')), findsNothing);

      // The line steps like the game does: back to the fork, then on to
      // the viewer's move again; "Your line" is the fork itself.
      await tester.tap(find.bySemanticsLabel('Previous move'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.bySemanticsLabel('Next move'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(feed.sound.played.where((s) => s.$1 == 'e6'), hasLength(2));
      expect(find.byKey(const ValueKey('feed_back_to_game')), findsOneWidget);

      // Back to game: the line is gone and the game plays on (1... e5).
      await tester.tap(find.byKey(const ValueKey('feed_back_to_game')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('feed_back_to_game')), findsNothing);
      final before = feed.sound.played.length;
      await tester.pump(const Duration(milliseconds: 700));
      expect(feed.sound.played.length, before + 1);
      expect(feed.sound.played.last, ('e5', null));

      await _tearDown(tester);
    },
  );

  testWidgets('a swipe that starts on a piece pages the feed', (tester) async {
    await _pumpFeed(
      tester,
      games: [
        _scholarsMate(),
        _scholarsMate(id: 'g2'),
      ],
    );
    // The next post already stands under this one; the first board is ours.
    final board = tester.getRect(find.byType(FeedLiveBoard).first);

    // Swipe up from White's d-pawn: pieces move tap-tap, so the finger's
    // travel belongs to the feed.
    await tester.flingFrom(
      _squareCenter(board, 'd2'),
      const Offset(0, -240),
      1500,
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The next game sits where the first one was; no line was started.
    expect(tester.getRect(find.byType(FeedLiveBoard).last), board);
    expect(find.byKey(const ValueKey('feed_back_to_game')), findsNothing);

    await _tearDown(tester);
  });

  testWidgets('a swipe that stays on the page puts the piece back down', (
    tester,
  ) async {
    final feed = await _pumpFeed(tester);
    final board = tester.getRect(find.byType(FeedLiveBoard));

    // Touch the d-pawn and drag a little: the page snaps back, and the pawn
    // the touch picked up must not be left in hand, holding the clip. (The
    // page after the post, the tail, gives even a one-post feed room to
    // move, so the snap back is a real one.)
    await tester.dragFrom(_squareCenter(board, 'd2'), const Offset(0, -60));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.getRect(find.byType(FeedLiveBoard)), board);
    await tester.pump(const Duration(milliseconds: 500));
    // Nothing left in hand: the clip played on through the drag.
    expect(feed.sound.played, [('e4', null), ('e5', null)]);

    await _tearDown(tester);
  });

  testWidgets('Play puts a picked-up piece down and plays on', (tester) async {
    final feed = await _pumpFeed(tester);
    final board = tester.getRect(find.byType(FeedLiveBoard));

    // A piece in hand holds the clip: the opening beat passes, nothing plays.
    await tester.tapAt(_squareCenter(board, 'e2'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(feed.sound.played, isEmpty);

    await tester.tap(find.byKey(const ValueKey('feed_play_toggle')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(feed.sound.played, [('e4', null)]);

    await _tearDown(tester);
  });

  testWidgets('a resigned ending plays on: the king stands back up', (
    tester,
  ) async {
    final feed = await _pumpFeed(
      tester,
      games: [
        _scholarsMate(
          pgn: '1. e4 e5 2. Nf3 0-1',
          result: '0-1',
          status: GameStatus.blackWins,
        ),
      ],
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 700));
    }
    const card = ValueKey('feed_end_card');
    expect(find.byKey(card), findsOneWidget);
    final board = tester.getRect(find.byType(FeedLiveBoard));

    // A tap on the card moves it off the board; a tap on the board brings
    // it back.
    await tester.tapAt(
      tester.getTopLeft(find.byKey(card)) + const Offset(24, 20),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(card), findsNothing);
    await tester.tapAt(_squareCenter(board, 'd5'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(card), findsOneWidget);

    // White resigned with Black to move: touching the knight stands White's
    // king back up and hands the board over; the card steps aside.
    await tester.tapAt(_squareCenter(board, 'b8'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(card), findsNothing);
    await tester.tapAt(_squareCenter(board, 'c6'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(feed.sound.played.last, ('Nc6', null));
    expect(find.byKey(const ValueKey('feed_back_to_game')), findsOneWidget);

    // Back to game: the ending as it was, card and all.
    await tester.tap(find.byKey(const ValueKey('feed_back_to_game')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(card), findsOneWidget);

    await _tearDown(tester);
  });

  testWidgets('the move strip steps through the game', (tester) async {
    final feed = await _pumpFeed(tester);

    await tester.tap(find.bySemanticsLabel('Next move'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.bySemanticsLabel('Next move'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(feed.sound.played, [('e4', null), ('e5', null)]);

    // Stepped by hand: autoplay waits for Play.
    await tester.pump(const Duration(seconds: 2));
    expect(feed.sound.played, hasLength(2));
    await tester.tap(find.byKey(const ValueKey('feed_play_toggle')));
    await tester.pump(const Duration(milliseconds: 700));
    expect(feed.sound.played, hasLength(3));

    await _tearDown(tester);
  });

  testWidgets('a back button stands where the tabs keep the avatar', (
    tester,
  ) async {
    await _pumpFeed(tester, withDrawer: true);
    expect(find.byKey(const ValueKey('feed_sidebar_avatar')), findsNothing);
    expect(find.byKey(const ValueKey('feed_back')), findsOneWidget);
    expect(find.text('Feed'), findsOneWidget);
    // No stream titles: Feed is games and news, puzzles come later.
    expect(find.text('Puzzle'), findsNothing);
    await _tearDown(tester);
  });

  testWidgets('the header is one line: event and opening, no caption', (
    tester,
  ) async {
    await _pumpFeed(
      tester,
      games: [
        _scholarsMate(
          signal: const FeedSignal(
            FeedSignalKind.favorite,
            name: 'Fabiano Caruana',
          ),
        ),
      ],
    );
    final header = find.byKey(const ValueKey('feed_post_header'));
    expect(header, findsOneWidget);
    // One row, 44pt, every text on it single-line.
    expect(tester.getSize(header).height, 44);
    final texts = find.descendant(of: header, matching: find.byType(Text));
    final top = tester.getTopLeft(texts.first).dy;
    for (final element in texts.evaluate()) {
      final text = element.widget as Text;
      expect(text.maxLines, 1);
      expect(tester.getTopLeft(find.byWidget(text)).dy, closeTo(top, 1));
    }
    // The mark reads "Your favorite", the heart, the name; on a narrow line
    // it keeps the heart and the surname.
    expect(
      find.bySemanticsLabel('Your favorite Fabiano Caruana'),
      findsOneWidget,
    );
    expect(find.textContaining('Caruana'), findsOneWidget);
    expect(find.textContaining('Because you follow'), findsNothing);
    // Both the event and the opening are buttons.
    expect(find.bySemanticsLabel('Open event Test Open 2026'), findsOneWidget);
    expect(
      find.bySemanticsLabel("Open C20 King's Pawn Game in the board editor"),
      findsOneWidget,
    );
    await _tearDown(tester);
  });

  testWidgets('a tap on the header or a player row never pauses', (
    tester,
  ) async {
    await _pumpFeed(tester);
    // The event: no event route in the test app, so it says so.
    await tester.tap(find.byKey(const ValueKey('feed_header_event')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("Couldn't open this event"), findsOneWidget);
    expect(find.byKey(const ValueKey('feed_paused')), findsNothing);

    // The empty end of a player row (clear of the name): nothing happens.
    final row = tester.getRect(find.byKey(const ValueKey('feed_row_black')));
    await tester.tapAt(Offset(row.right - 8, row.center.dy));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('feed_paused')), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await _tearDown(tester);
  });

  testWidgets('a piece dragged while paused lands and pages nothing', (
    tester,
  ) async {
    final feed = await _pumpFeed(
      tester,
      games: [
        _scholarsMate(),
        _scholarsMate(id: 'g2'),
      ],
    );
    final board = tester.getRect(find.byType(FeedLiveBoard).first);

    // Pause before the first beat (the centre squares are empty).
    await tester.tapAt(board.center);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('feed_paused')), findsOneWidget);

    // Drag the g1 knight up to f3: the feed holds still under the piece.
    final gesture = await tester.startGesture(_squareCenter(board, 'g1'));
    await tester.pump();
    final to = _squareCenter(board, 'f3');
    final from = _squareCenter(board, 'g1');
    for (var i = 1; i <= 6; i++) {
      await gesture.moveTo(Offset.lerp(from, to, i / 6)!);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));

    expect(feed.sound.played.last, ('Nf3', null));
    expect(find.byKey(const ValueKey('feed_back_to_game')), findsOneWidget);
    expect(tester.getRect(find.byType(FeedLiveBoard).first), board);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.getRect(find.byType(FeedLiveBoard).first), board);
    await _tearDown(tester);
  });

  testWidgets('the post actions read Analyze, My Space, Share, Like', (
    tester,
  ) async {
    await _pumpFeed(tester);
    final xs = [
      for (final key in [
        'feed_analyze_button',
        'feed_space_button',
        'feed_share_button',
        'feed_like_button',
      ])
        tester.getCenter(find.byKey(ValueKey(key))).dx,
    ];
    for (var i = 1; i < xs.length; i++) {
      expect(xs[i], greaterThan(xs[i - 1]));
    }
    await _tearDown(tester);
  });

  group('eval bar follows the engine settings', () {
    testWidgets('shown by default, beside the board', (tester) async {
      await _pumpFeed(tester);
      expect(find.byKey(const ValueKey('feed_eval_bar')), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('hidden when the on-board gauge is off', (tester) async {
      await _pumpFeed(
        tester,
        engineSettings: const EngineSettings(showEngineGaugeOnBoard: false),
      );
      expect(find.byKey(const ValueKey('feed_eval_bar')), findsNothing);
      await _tearDown(tester);
    });

    testWidgets('hidden when the engine is off', (tester) async {
      await _pumpFeed(
        tester,
        engineSettings: const EngineSettings(showEngineAnalysis: false),
      );
      expect(find.byKey(const ValueKey('feed_eval_bar')), findsNothing);
      await _tearDown(tester);
    });

    testWidgets('no search while the clip plays; paused asks the engine', (
      tester,
    ) async {
      final engine = _RecordingEngine(cp: 150);
      await _pumpFeed(tester, engine: engine);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(engine.searched, isEmpty);

      // An empty square: a plain tap pauses.
      final board = tester.getRect(find.byType(FeedLiveBoard));
      await tester.tapAt(_squareCenter(board, 'a5'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('feed_paused')), findsOneWidget);
      expect(engine.searched, isNotEmpty);
      expect(find.text('+1.5'), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('a cached number never starts the engine', (tester) async {
      final engine = _RecordingEngine();
      await _pumpFeed(
        tester,
        engine: engine,
        cached: (fen) => CloudEval(
          fen: fen,
          knodes: 1,
          depth: 30,
          pvs: [Pv(moves: 'e2e4', cp: -40)],
        ),
      );
      final board = tester.getRect(find.byType(FeedLiveBoard));
      await tester.tapAt(_squareCenter(board, 'a5'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('feed_paused')), findsOneWidget);
      expect(engine.searched, isEmpty);
      expect(find.text('-0.4'), findsOneWidget);
      await _tearDown(tester);
    });
  });

  group('composeFeedEntries', () {
    final games = [for (var i = 1; i <= 12; i++) _scholarsMate(id: 'g$i')];
    final puzzles = [for (var i = 1; i <= 3; i++) _puzzle('p$i')];
    final news = [for (var i = 1; i <= 2; i++) _news(i)];

    List<String> keys(List<FeedEntry> entries) => [
      for (final entry in entries) entry.key,
    ];

    test('games alone stay games', () {
      final entries = composeFeedEntries(games: games.take(3).toList());
      expect(keys(entries), ['game:g1', 'game:g2', 'game:g3']);
    });

    test('a puzzle after every 4th game, news after every 6th', () {
      final entries = composeFeedEntries(
        games: games,
        puzzles: puzzles,
        news: news,
      );
      expect(keys(entries), [
        'game:g1',
        'game:g2',
        'game:g3',
        'game:g4',
        'puzzle:p1',
        'game:g5',
        'game:g6',
        'news:1',
        'game:g7',
        'game:g8',
        'puzzle:p2',
        'game:g9',
        'game:g10',
        'game:g11',
        'game:g12',
        'puzzle:p3',
        'news:2',
      ]);
    });

    test('late puzzles never move pages the viewer has reached', () {
      final first = composeFeedEntries(games: games.take(8).toList());
      // The viewer is on g5 (index 4): pages 0..5 are frozen.
      final later = composeFeedEntries(
        games: games.take(8).toList(),
        puzzles: puzzles,
        previous: first,
        frozenThrough: 5,
      );
      expect(keys(later).take(6), keys(first).take(6));
      expect(keys(later), [
        'game:g1',
        'game:g2',
        'game:g3',
        'game:g4',
        'game:g5',
        'game:g6',
        'game:g7',
        'game:g8',
        'puzzle:p1',
      ]);
    });

    test('an open slot right after the frozen prefix still fills', () {
      final first = composeFeedEntries(games: games.take(6).toList());
      final later = composeFeedEntries(
        games: games.take(6).toList(),
        puzzles: puzzles,
        previous: first,
        // Frozen through g4: its puzzle slot was empty then, and is open now.
        frozenThrough: 3,
      );
      expect(keys(later).sublist(0, 5), [
        'game:g1',
        'game:g2',
        'game:g3',
        'game:g4',
        'puzzle:p1',
      ]);
    });

    test('a refreshed feed drops the stale prefix', () {
      final first = composeFeedEntries(games: games.take(4).toList());
      final refreshed = composeFeedEntries(
        games: games.skip(4).take(2).toList(),
        previous: first,
        frozenThrough: 3,
      );
      expect(keys(refreshed), ['game:g5', 'game:g6']);
    });

    test('maps a page back to the games it follows', () {
      final entries = composeFeedEntries(
        games: games.take(5).toList(),
        puzzles: puzzles,
      );
      expect(feedGameIndexAt(entries, 3), 3);
      expect(feedGameIndexAt(entries, 4), 3); // the puzzle after g4
      expect(feedGameIndexAt(entries, 5), 4);
    });
  });
}

class _Feed {
  _Feed(this.sfx, this.sound);

  final _SilentSfx sfx;
  final _RecordingMoveSound sound;
}

Future<_Feed> _pumpFeed(
  WidgetTester tester, {
  List<FeedItem>? games,
  bool withDrawer = false,
  EngineSettings engineSettings = const EngineSettings(),
  _RecordingEngine? engine,
  CloudEval? Function(String fen)? cached,
  ThemeData? theme,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final sfx = _SilentSfx();
  final sound = _RecordingMoveSound(sfx);
  final items = games ?? [_scholarsMate()];

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        feedProvider.overrideWith(() => _FakeFeed(items)),
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
          () => _TestEngineSettings(engineSettings),
        ),
        eventNoSpoilersProvider.overrideWith(_MemoryNoSpoilers.new),
        feedCachedEvalProvider.overrideWith(
          (ref, fen) async => cached?.call(fen),
        ),
        feedEngineProvider.overrideWithValue(engine ?? _RecordingEngine()),
      ],
      child: MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              drawer: withDrawer ? const Drawer(child: Text('Sidebar')) : null,
              body: const FeedScreen(),
            );
          },
        ),
      ),
    ),
  );
  // Feed resolves, then the first clip lays out.
  await tester.pump();
  await tester.pump();
  return _Feed(sfx, sound);
}

/// Unmount inside the fake clock so no clip timer outlives the test.
Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

/// Centre of [name] on a White-at-the-bottom board occupying [board].
Offset _squareCenter(Rect board, String name) {
  final square = Square.fromName(name);
  final size = board.width / 8;
  return Offset(
    board.left + (square.file + 0.5) * size,
    board.top + (7 - square.rank + 0.5) * size,
  );
}

/// Scholar's mate, parsed move by move so every ply carries a real FEN/UCI.
/// The mate carries a brilliant verdict, as a report would give it.
FeedItem _scholarsMate({
  String id = 'feed-test-game',
  String pgn = _pgn,
  String result = '1-0',
  GameStatus status = GameStatus.whiteWins,
  FeedSignal? signal,
}) {
  final parsed = PgnGame.parsePgn(pgn);
  Position position = PgnGame.startingPosition(parsed.headers);
  final plies = <FeedPly>[FeedPly(fen: position.fen)];
  for (final node in parsed.moves.mainline()) {
    final move = position.parseSan(node.san)!;
    position = position.play(move);
    final mate = node.san.endsWith('#');
    plies.add(
      FeedPly(
        fen: position.fen,
        san: node.san,
        uci: move.uci,
        moveClass: mate ? MoveClass.brilliant : null,
        moment: mate
            ? const FeedMoment(
                type: FeedMomentType.checkmate,
                label: 'Checkmate',
                severity: 3,
              )
            : null,
      ),
    );
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
    pgn: pgn,
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
    signal: signal,
  );
}

FeedPuzzle _puzzle(String id) =>
    FeedPuzzle(id: id, fen: kInitialFEN, solution: const ['e2e4']);

FeedNews _news(int id) => FeedNews(
  id: id,
  title: 'News $id',
  summary: 'Summary',
  content: 'Body',
  publishedAt: DateTime(2026, 9, 20),
);

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

/// No audio plugin in tests: counts the result stingers instead.
class _SilentSfx implements FeedSfx {
  @override
  bool muted = false;

  @override
  bool boardSoundEnabled = true;

  @override
  Future<void> warmUp() async {}

  int gameEnds = 0;

  @override
  void playGameEnd(FeedItem item) => gameEnds++;

  @override
  void playSwipe() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Records every move sound the Feed asks for: (SAN, class).
class _RecordingMoveSound extends FeedMoveSound {
  _RecordingMoveSound(super.sfx);

  final List<(String, MoveClass?)> played = [];

  @override
  void play({required String san, MoveClass? moveClass, bool fast = false}) {
    played.add((san, moveClass));
  }
}

class _TestEngineSettings extends EngineSettingsNotifierNew {
  _TestEngineSettings(this.settings);

  final EngineSettings settings;

  @override
  Future<EngineSettings> build() async => settings;
}

/// No Spoilers double: never reads the local database.
class _MemoryNoSpoilers extends EventNoSpoilersController {
  _MemoryNoSpoilers(Ref ref, String tourId) : super(ref: ref, tourId: tourId);

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }
}

/// Stands in for Stockfish: records every search the Feed starts and
/// answers with [cp] (White's side) at once.
class _RecordingEngine extends FeedEngine {
  _RecordingEngine({this.cp = 150});

  final int cp;
  final List<String> searched = [];
  int cancels = 0;

  @override
  Future<CloudEval?> evaluate(
    String fen, {
    required EngineSettings settings,
    required void Function(List<Pv> pvs, int depth) onUpdate,
  }) async {
    searched.add(fen);
    return CloudEval(
      fen: fen,
      knodes: 1,
      depth: 20,
      pvs: [Pv(moves: 'e2e4', cp: cp)],
    );
  }

  @override
  Future<void> cancel() async => cancels++;
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
