import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show GestureSettings;

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
import 'package:chessever2/screens/feed/widgets/feed_live_board.dart';
import 'package:chessever2/screens/feed/widgets/feed_move_sound.dart';
import 'package:chessever2/screens/feed/widgets/feed_scrub.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/feed/widgets/feed_states.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The page after the last post (the tail) and the scrub line.
void main() {
  group('the tail', () {
    testWidgets('every post is a page of its own: nothing of the next one '
        'shows under it', (tester) async {
      await _pump(tester, games: 2);
      final pages = tester.getRect(_pages);
      final post = tester.getRect(_post('g0'));
      expect(post.top, closeTo(pages.top, 0.5));
      expect(post.bottom, closeTo(pages.bottom, 0.5));
      // The next post stands wholly below the screen.
      final next = find.byKey(const ValueKey('game:g1'), skipOffstage: false);
      expect(
        tester.getRect(next).top,
        greaterThanOrEqualTo(pages.bottom - 0.5),
      );
      await _tearDown(tester);
    });

    testWidgets('after the last post, the next post as a skeleton, on the '
        "post's own geometry", (tester) async {
      await _pump(tester, games: 1);
      final pages = tester.getRect(_pages);
      final board = tester.getRect(find.byType(FeedLiveBoard));
      await _fling(tester);

      final tail = tester.getRect(_tail);
      expect(
        find.descendant(of: _tail, matching: find.byType(FeedSkeletonPost)),
        findsOneWidget,
      );
      // The whole page, and its board exactly where a post's board stands.
      expect(tail.top, closeTo(pages.top, 0.5));
      expect(tail.bottom, closeTo(pages.bottom, 0.5));
      final squares = tester.getRect(
        find.descendant(
          of: _tail,
          matching: find.byKey(const ValueKey('feed_skeleton_board')),
        ),
      );
      expect(squares.top, closeTo(board.top, 0.5));
      expect(squares.width, closeTo(board.width, 0.5));
      await _tearDown(tester);
    });

    testWidgets('lets the last post settle at the top like every other', (
      tester,
    ) async {
      await _pump(tester, games: 3);
      final top = tester.getRect(_pages).top;
      await _fling(tester);
      await _fling(tester);

      expect(tester.getRect(_post('g2')).top, closeTo(top, 0.5));
      expect(tester.widget<FeedClip>(_post('g2')).isCurrent, isTrue);
      expect(_currentKey(tester), 'game:g2');
      await _tearDown(tester);
    });

    testWidgets('landed on, asks for more and becomes the post in place', (
      tester,
    ) async {
      final arrives = Completer<void>();
      final feed = await _pump(tester, games: 1, adds: arrives.future);
      final pages = tester.getRect(_pages);
      await _fling(tester);

      // On the skeleton: more is asked for; the remembered page is still
      // the last post, not a key that belongs to no page.
      expect(feed.loads, greaterThan(0));
      expect(_currentKey(tester), 'game:g0');
      expect(
        tester
            .widget<FeedClip>(
              find.byKey(const ValueKey('game:g0'), skipOffstage: false),
            )
            .isCurrent,
        isFalse,
      );
      // It is the page: top to bottom, no slice of the post before it.
      expect(tester.getRect(_tail).top, closeTo(pages.top, 0.5));
      expect(tester.getRect(_tail).bottom, closeTo(pages.bottom, 0.5));
      // A fling past it springs back: the skeleton stays the page.
      await _fling(tester);
      expect(tester.getRect(_tail).top, closeTo(pages.top, 0.5));

      arrives.complete();
      await _settle(tester);
      // The post stands where the skeleton stood, and it is the page the
      // viewer is on.
      expect(tester.getRect(_post('more0')).top, closeTo(pages.top, 0.5));
      expect(tester.widget<FeedClip>(_post('more0')).isCurrent, isTrue);
      expect(_currentKey(tester), 'game:more0');
      // And a new tail stands under it, off the screen.
      expect(
        tester
            .getRect(
              find.byKey(const ValueKey('feed:tail'), skipOffstage: false),
            )
            .top,
        closeTo(pages.bottom, 0.5),
      );
      await _tearDown(tester);
    });

    testWidgets('at the end of the feed, one line and Refresh, centred on a '
        'page of their own', (tester) async {
      await _pump(tester, games: 2, more: FeedMore.exhausted);
      final pages = tester.getRect(_pages);
      await _fling(tester);
      // The last post fills its page: no note squeezed under it.
      expect(find.text('No more games for now.'), findsNothing);
      await _fling(tester);

      final line = tester.getRect(find.text('No more games for now.'));
      final refresh = tester.getRect(
        find.byKey(const ValueKey('feed_end_refresh')),
      );
      expect(line.center.dx, closeTo(pages.center.dx, 1));
      expect(refresh.center.dx, closeTo(pages.center.dx, 1));
      // The pair stands in the middle of the page.
      final middle = (line.top + refresh.bottom) / 2;
      expect(middle, closeTo(pages.center.dy, 1));
      expect(refresh.height, greaterThanOrEqualTo(44));
      // Nothing was written for a page that is not a post.
      expect(_currentKey(tester), 'game:g1');
      await _tearDown(tester);
    });

    testWidgets("the end note's Refresh draws afresh, on the first page", (
      tester,
    ) async {
      final feed = await _pump(tester, games: 2, more: FeedMore.exhausted);
      final top = tester.getRect(_pages).top;
      await _fling(tester);
      await _fling(tester);

      await tester.tap(find.byKey(const ValueKey('feed_end_refresh')));
      await _settle(tester);
      expect(feed.refreshes, 1);
      expect(tester.getRect(_post('fresh0')).top, closeTo(top, 0.5));
      expect(tester.widget<FeedClip>(_post('fresh0')).isCurrent, isTrue);
      expect(_currentKey(tester), 'game:fresh0');
      // A fresh draw can load more again: after its last post, the
      // skeleton is back.
      await _fling(tester);
      await _fling(tester);
      expect(
        find.descendant(of: _tail, matching: find.byType(FeedSkeletonPost)),
        findsOneWidget,
      );
      await _tearDown(tester);
    });

    testWidgets('a load that failed says so, and Try again asks again', (
      tester,
    ) async {
      final feed = await _pump(tester, games: 2, more: FeedMore.stalled);
      await _fling(tester);
      await _fling(tester);
      expect(find.text("More games didn't load."), findsOneWidget);

      final before = feed.loads;
      await tester.tap(find.byKey(const ValueKey('feed_end_retry')));
      await tester.pump();
      expect(feed.loads, before + 1);
      await _tearDown(tester);
    });

    testWidgets('while a retry is loading, the last game counts down to '
        'nothing, and a failed retry says so again', (tester) async {
      late _RetryingFeed feed;
      final pumped = await _pump(
        tester,
        games: 2,
        more: FeedMore.stalled,
        makeFeed: (items, more) => feed = _RetryingFeed(items, more),
      );
      await _fling(tester);
      await _fling(tester);
      // A slow retry: longer than a countdown would run.
      feed.hold = true;
      await tester.tap(find.byKey(const ValueKey('feed_end_retry')));
      await tester.pump();
      // Back to the last game, which plays to its end.
      await tester.fling(_pages, const Offset(0, 400), 1500);
      await _settle(tester);
      expect(_currentKey(tester), 'game:g1');
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 700));
      }
      final card = find.byKey(const ValueKey('feed_end_card'));
      expect(card, findsOneWidget);
      expect(find.text('Next game'), findsNothing);
      await tester.pump(const Duration(milliseconds: 5500));
      expect(tester.widget<FeedClip>(_post('g1')).isCurrent, isTrue);

      final heard = pumped.sound.played.length;
      feed.fail();
      await _settle(tester);
      expect(tester.widget<FeedClip>(_post('g1')).isCurrent, isTrue);
      expect(card, findsOneWidget);
      expect(
        pumped.sound.played.skip(heard),
        isEmpty,
        reason: 'the finished game replayed',
      );
      // Landing on the tail asks again; this time it fails at once.
      feed.hold = false;
      await _fling(tester);
      expect(find.text("More games didn't load."), findsOneWidget);
      await _tearDown(tester);
    });

    testWidgets('counted on to a skeleton that never fills, the page says '
        'why and offers Try again; the game stays quiet', (tester) async {
      late _RetryingFeed feed;
      final pumped = await _pump(
        tester,
        games: 2,
        makeFeed: (items, more) =>
            feed = _RetryingFeed(items, more)..hold = true,
      );
      await _fling(tester);
      expect(_currentKey(tester), 'game:g1');
      // The game ends and its countdown carries the viewer onto the
      // skeleton of the next post.
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 700));
      }
      await tester.pump(const Duration(seconds: 5));
      await _settle(tester);
      final g1 = find.byKey(const ValueKey('game:g1'), skipOffstage: false);
      expect(tester.widget<FeedClip>(g1).isCurrent, isFalse);
      expect(
        find.descendant(of: _tail, matching: find.byType(FeedSkeletonPost)),
        findsOneWidget,
      );

      final heard = pumped.sound.played.length;
      feed.fail();
      await _settle(tester);
      expect(find.text("More games didn't load."), findsOneWidget);
      expect(find.byKey(const ValueKey('feed_end_retry')), findsOneWidget);
      expect(tester.widget<FeedClip>(g1).isCurrent, isFalse);
      expect(pumped.sound.played.skip(heard), isEmpty);
      await _tearDown(tester);
    });

    testWidgets('where a post fills the screen, the note is a page of its '
        'own as well', (tester) async {
      await _pump(
        tester,
        games: 1,
        more: FeedMore.exhausted,
        size: const Size(393, 600),
      );
      final pages = tester.getRect(_pages);
      expect(
        tester.getRect(find.byType(FeedClip)).bottom,
        closeTo(pages.bottom, 0.5),
      );

      await _fling(tester);
      final line = tester.getRect(find.text('No more games for now.'));
      expect(pages.contains(line.center), isTrue);
      expect(line.center.dx, closeTo(pages.center.dx, 1));
      expect(_currentKey(tester), 'game:g0');
      await _tearDown(tester);
    });

    testWidgets('the end note\'s action is as wide as its word, on every '
        'screen', (tester) async {
      for (final size in const [
        Size(393, 852),
        Size(430, 932),
        Size(412, 915),
        Size(820, 1180),
        Size(375, 667),
      ]) {
        await _pump(tester, games: 1, more: FeedMore.exhausted, size: size);
        final pages = tester.getRect(_pages);
        await _fling(tester);
        final note = find.byKey(const ValueKey('feed_end_refresh'));
        expect(pages.contains(tester.getRect(note).center), isTrue);
        final action = tester.getRect(note);
        expect(action.height, greaterThanOrEqualTo(44), reason: '$size');
        // "Refresh" and its padding, never a bar across the page.
        expect(action.width, lessThan(140), reason: '$size');
        await _tearDown(tester);
      }
    });

    testWidgets('on the last post of a feed that has ended, the result card '
        'offers Replay alone and never moves on', (tester) async {
      final feed = await _pump(tester, games: 2, more: FeedMore.exhausted);
      await _fling(tester);
      expect(_currentKey(tester), 'game:g1');
      for (var i = 0; i < 14; i++) {
        await tester.pump(const Duration(milliseconds: 700));
      }
      final card = find.byKey(const ValueKey('feed_end_card'));
      expect(card, findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('Replay')),
        findsOneWidget,
      );
      expect(find.text('Next game'), findsNothing);
      // No countdown runs towards a game that is not there.
      final loads = feed.loads;
      await tester.pump(const Duration(seconds: 6));
      expect(_currentKey(tester), 'game:g1');
      expect(feed.loads, loads);
      expect(card, findsOneWidget);
      await _tearDown(tester);
    });
  });

  group('the scrub line', () {
    testWidgets('is a 44pt target beside the playback button', (tester) async {
      await _pump(tester, games: 1);
      final strip = tester.getRect(find.byType(FeedScrubStrip));
      expect(strip.height, 44);
      expect(strip.width, lessThan(tester.getRect(_pages).width));
      expect(
        tester
            .widget<FeedScrubStrip>(find.byType(FeedScrubStrip).first)
            .progress,
        closeTo(0 / 7, 0.001),
      );

      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester
            .widget<FeedScrubStrip>(find.byType(FeedScrubStrip).first)
            .progress,
        closeTo(1 / 7, 0.001),
      );
      await _tearDown(tester);
    });

    testWidgets('a tap jumps to that move and the game plays on from it', (
      tester,
    ) async {
      final feed = await _pump(tester, games: 1);
      final strip = tester.getRect(find.byType(FeedScrubStrip));
      final counter = tester.getRect(
        find.byKey(const ValueKey('feed_scrub_play_toggle')),
      );
      // The track runs from the board's left edge to just before the
      // counter; its middle is ply 4 of 7 (2... Nc6).
      final left = strip.left + 16;
      final right =
          counter.right - _counterWidth(tester) - FeedScrubStrip.counterGap;
      await tester.tapAt(Offset((left + right) / 2, strip.center.dy));
      await tester.pump();
      expect(
        tester
            .widget<FeedScrubStrip>(find.byType(FeedScrubStrip).first)
            .progress,
        closeTo(4 / 7, 0.001),
      );
      expect(feed.sound.played.last, ('Nc6', null));

      // Plays on: the next move comes on its own.
      await tester.pump(const Duration(milliseconds: 700));
      expect(feed.sound.played.last, ('Qh5', null));
      await _tearDown(tester);
    });

    testWidgets('a vertical swipe that starts on it pages the feed', (
      tester,
    ) async {
      await _pump(tester, games: 2);
      final top = tester.getRect(_pages).top;
      final strip = tester.getRect(find.byType(FeedScrubStrip).first);
      await tester.flingFrom(strip.center, const Offset(0, -300), 1500);
      await _settle(tester);
      expect(tester.getRect(_post('g1')).top, closeTo(top, 0.5));
      expect(_currentKey(tester), 'game:g1');
      await _tearDown(tester);
    });

    testWidgets('ticks once for every move a scrub crosses', (tester) async {
      var ticks = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate' &&
              call.arguments == 'HapticFeedbackType.selectionClick') {
            ticks++;
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
      await _pump(tester, games: 1);
      final strip = tester.getRect(find.byType(FeedScrubStrip));
      final counter = tester.getRect(
        find.byKey(const ValueKey('feed_scrub_play_toggle')),
      );
      final left = strip.left + 16;
      final right =
          counter.right - _counterWidth(tester) - FeedScrubStrip.counterGap;

      // From the start of the track to its end in short steps, before the
      // clip has played its first move: seven moves crossed.
      final gesture = await tester.startGesture(Offset(left, strip.center.dy));
      for (var x = left + 6; x <= right + 6; x += 6) {
        await gesture.moveTo(Offset(x, strip.center.dy));
        await tester.pump(const Duration(milliseconds: 8));
      }
      expect(
        tester
            .widget<FeedScrubStrip>(find.byType(FeedScrubStrip).first)
            .progress,
        closeTo(7 / 7, 0.001),
      );
      await gesture.up();
      await tester.pump();
      expect(ticks, 7);
      await _tearDown(tester);
    });

    testWidgets('a finger resting on the thumb takes it, and the thumb moves '
        'with the finger whichever way it then goes', (tester) async {
      await _pump(tester, games: 1);
      final top = tester.getRect(_pages).top;
      final strip = tester.getRect(find.byType(FeedScrubStrip).first);
      final counter = tester.getRect(
        find.byKey(const ValueKey('feed_scrub_play_toggle')).first,
      );
      final runLeft = strip.left + 16 + FeedScrubStrip.thumbInset;
      final runRight =
          counter.right -
          _counterWidth(tester) -
          FeedScrubStrip.counterGap -
          FeedScrubStrip.thumbInset;
      // On the thumb (at the start), a little right of its centre.
      final at = Offset(runLeft + 6, strip.top + 18);
      final gesture = await tester.startGesture(at);
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(FeedMoveBubble), findsNothing);

      // Resting there: taken, where it stood. Nothing jumps.
      await tester.pump(const Duration(milliseconds: 140));
      expect(find.byType(FeedMoveBubble), findsOneWidget);
      expect(
        tester
            .widget<FeedScrubStrip>(find.byType(FeedScrubStrip).first)
            .progress,
        closeTo(0 / 7, 0.001),
      );

      // Taken: up and across, it scrubs by the finger's sideways travel and
      // never pages the feed. Three quarters along: ply 5 of 7, move 3.
      final across = (runRight - runLeft) * 0.75;
      for (var i = 1; i <= 6; i++) {
        await gesture.moveTo(at + Offset(across * i / 6, -30.0 * i));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byType(FeedMoveBubble), findsOneWidget);
      expect(
        tester
            .widget<FeedScrubStrip>(find.byType(FeedScrubStrip).first)
            .progress,
        closeTo(5 / 7, 0.001),
      );
      await gesture.up();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.getRect(_post('g0')).top, closeTo(top, 0.5));
      expect(_currentKey(tester), 'game:g0');
      expect(find.byType(FeedMoveBubble), findsNothing);
      await _tearDown(tester);
    });

    testWidgets('a slow or paused swipe up from the line, away from the '
        'thumb, pages the feed and leaves the game on its move', (
      tester,
    ) async {
      // (pt/s, rest before moving): the probes that used to be taken.
      for (final (speed, rest) in const [(60, 0), (100, 0), (400, 120)]) {
        final feed = await _pump(tester, games: 2);
        final top = tester.getRect(_pages).top;
        final strip = tester.getRect(find.byType(FeedScrubStrip).first);
        final start = Offset(strip.left + strip.width * 0.6, strip.top + 18);
        final heard = feed.sound.played.length;
        final gesture = await tester.startGesture(start);
        if (rest > 0) await tester.pump(Duration(milliseconds: rest));
        var scrubbed = false;
        var moved = 0.0;
        for (var t = 16; t <= 900; t += 16) {
          await gesture.moveTo(start + Offset(0, -speed * t / 1000));
          await tester.pump(const Duration(milliseconds: 16));
          scrubbed |= find.byType(FeedMoveBubble).evaluate().isNotEmpty;
          moved = tester.getRect(_post('g0')).top - top;
          if (moved < -40) break;
        }
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 600));
        expect(scrubbed, isFalse, reason: '$speed pt/s after ${rest}ms');
        expect(moved, lessThan(-20), reason: '$speed pt/s after ${rest}ms');
        // No jump to the move under the finger: only the clip's own moves,
        // one at a time from the start.
        expect(
          feed.sound.played.skip(heard).map((m) => m.$1),
          everyElement(isIn(['e4', 'e5', 'Bc4'])),
          reason: '$speed pt/s after ${rest}ms',
        );
        await _tearDown(tester);
      }
    });

    testWidgets('a tap on Stop leaves the game where it is', (tester) async {
      final feed = await _pump(tester, games: 1);
      final counter = tester.getRect(
        find.byKey(const ValueKey('feed_scrub_play_toggle')),
      );
      final strip = tester.getRect(find.byType(FeedScrubStrip));
      await tester.tapAt(Offset(counter.center.dx, strip.center.dy));
      await tester.pump();
      expect(
        tester
            .widget<FeedScrubStrip>(find.byType(FeedScrubStrip).first)
            .progress,
        closeTo(0 / 7, 0.001),
      );
      expect(find.text('4/4'), findsNothing);
      expect(feed.sound.played, isEmpty);
      await _tearDown(tester);
    });

    for (final (platform, slop) in const [('iOS', null), ('Android', 24.0)]) {
      testWidgets('$platform: a swipe from the line pages when it is steeper '
          'than 45 degrees, scrubs when it is flatter', (tester) async {
        for (final (degrees, pages) in const [(35, true), (55, false)]) {
          await _pump(tester, games: 2);
          if (slop != null) {
            tester.view.gestureSettings = GestureSettings(
              physicalTouchSlop: slop,
            );
            addTearDown(tester.view.resetGestureSettings);
            await tester.pump();
          }
          final top = tester.getRect(_pages).top;
          final strip = tester.getRect(find.byType(FeedScrubStrip).first);
          final angle = degrees * math.pi / 180;
          // Off vertical by [degrees], upwards, in 4pt steps.
          final step = Offset(math.sin(angle), -math.cos(angle)) * 4;
          final gesture = await tester.startGesture(strip.center);
          var scrubbed = false;
          for (var i = 1; i <= 30; i++) {
            await gesture.moveTo(strip.center + step * i.toDouble());
            await tester.pump(const Duration(milliseconds: 8));
            scrubbed |= find.byType(FeedMoveBubble).evaluate().isNotEmpty;
          }
          final moved = tester.getRect(_post('g0')).top - top;
          await gesture.up();
          await tester.pump(const Duration(milliseconds: 600));
          expect(scrubbed, !pages, reason: '$degrees degrees');
          if (pages) {
            expect(moved, lessThan(-20), reason: '$degrees degrees');
          } else {
            expect(moved, closeTo(0, 0.5), reason: '$degrees degrees');
          }
          await _tearDown(tester);
        }
      });
    }

    testWidgets('chart drag scrubs in both directions and resumes on release', (
      tester,
    ) async {
      final feed = await _pump(tester, games: 1, evals: true);
      final chart = tester.getRect(
        find.byKey(const ValueKey('feed_report_chart')),
      );
      final gesture = await tester.startGesture(
        Offset(chart.left + 55, chart.center.dy),
      );
      await gesture.moveTo(
        Offset(chart.left + chart.width * 0.7, chart.center.dy),
      );
      await tester.pump();
      expect(
        tester.widget<FeedScrubStrip>(find.byType(FeedScrubStrip)).scrubbing,
        isTrue,
      );
      expect(
        tester
            .widget<FeedEvaluationGraph>(find.byType(FeedEvaluationGraph))
            .ply,
        5,
      );
      final heard = feed.sound.played.length;
      await tester.pump(const Duration(seconds: 1));
      expect(feed.sound.played.length, heard);
      await gesture.moveTo(
        Offset(chart.left + chart.width * 0.3, chart.center.dy),
      );
      await tester.pump();
      expect(
        tester
            .widget<FeedEvaluationGraph>(find.byType(FeedEvaluationGraph))
            .ply,
        2,
      );
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        tester.widget<FeedScrubStrip>(find.byType(FeedScrubStrip)).scrubbing,
        isFalse,
      );
      expect(feed.sound.played.length, greaterThan(heard));
      await _tearDown(tester);
    });

    testWidgets(
      'holding the chart selector preserves its grip and cancellation releases playback',
      (tester) async {
        await _pump(tester, games: 1, evals: true);
        final chart = tester.getRect(
          find.byKey(const ValueKey('feed_report_chart')),
        );
        final gesture = await tester.startGesture(
          Offset(chart.left + FeedScrubStrip.thumbInset + 6, chart.center.dy),
        );
        await tester.pump(
          FeedScrubStrip.holdToGrab + const Duration(milliseconds: 10),
        );
        expect(
          tester.widget<FeedScrubStrip>(find.byType(FeedScrubStrip)).scrubbing,
          isTrue,
        );
        await gesture.moveBy(
          Offset((chart.width - 2 * FeedScrubStrip.thumbInset) * 3 / 7, 12),
        );
        await tester.pump();
        expect(
          tester
              .widget<FeedEvaluationGraph>(find.byType(FeedEvaluationGraph))
              .ply,
          3,
        );
        await gesture.cancel();
        await tester.pump();
        expect(
          tester.widget<FeedScrubStrip>(find.byType(FeedScrubStrip)).scrubbing,
          isFalse,
        );
        await _tearDown(tester);
      },
    );

    testWidgets('vertical swipe starting on the chart pages the feed', (
      tester,
    ) async {
      await _pump(tester, games: 2, evals: true);
      final chart = tester.getRect(
        find.byKey(const ValueKey('feed_report_chart')).first,
      );
      await tester.flingFrom(chart.center, const Offset(0, -300), 1500);
      await _settle(tester);
      expect(_currentKey(tester), 'game:g1');
      await _tearDown(tester);
    });

    testWidgets('phase labels fit the chart at large text size', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(
        tester,
        games: 1,
        evals: true,
        makeFeed: (items, more) => _FakeFeed([
          _scholarsMate(
            'g0',
            evals: true,
            pgn:
                '1. e3 g6 2. d4 Bg7 3. Nf3 Nf6 4. Bd3 O-O 5. O-O b6 6. c4 Bb7 7. Nbd2 d5 8. b3 Nbd7 9. Bb2 Re8 10. Qc2 dxc4 11. bxc4 c5 12. d5 e5 13. e4 h5 14. a4 Nf8 15. h3 Qd6 16. Nxe5 Rxe5 17. Nf3 N6d7 18. Nxe5 Bxe5 19. Bxe5 Nxe5 20. Be2 Bc8 21. f4 Ned7 22. e5 Qe7 23. Bf3 Rb8 24. Rae1 f5 25. d6 Qh4 26. e6 Nxe6 27. Rxe6 Nf6 28. Ree1 Qxf4 29. Bd5+ Nxd5 30. Rxf4 Nxf4 31. Qd2 g5 32. d7 Bb7 33. d8=Q+ Rxd8 34. Qxd8+ Kh7 35. Qc7+ Kh6 36. Qxb7 g4 37. Qc6+ Ng6 38. Re6 gxh3 39. Rxg6+ Kh7 40. Rh6+ Kg7 41. Qf6+ Kg8 42. Rh8#',
          ),
        ], moreValue: more),
      );
      final chart = tester.getRect(
        find.byKey(const ValueKey('feed_report_chart')),
      );
      for (final name in ['Opening', 'Middlegame', 'Endgame']) {
        final label = find.byKey(ValueKey('feed_phase_$name'));
        expect(label, findsOneWidget);
        final bounds = tester.getRect(label);
        expect(bounds.left, greaterThanOrEqualTo(chart.left));
        expect(bounds.right, lessThanOrEqualTo(chart.right));
        expect(bounds.top, greaterThanOrEqualTo(chart.top));
        expect(bounds.bottom, lessThanOrEqualTo(chart.bottom));
      }
      expect(tester.takeException(), isNull);
      await _tearDown(tester);
    });

    testWidgets(
      'the evaluation graph stays visible before, during and after scrubbing',
      (tester) async {
        await _pump(tester, games: 1, evals: true);
        final strip = tester.getRect(find.byType(FeedScrubStrip));
        final trackLeft = strip.left + 16;
        final chartFinder = find.byKey(const ValueKey('feed_report_chart'));
        final resting = tester.getRect(chartFinder);
        final graph = tester.getRect(find.byType(FeedEvaluationGraph));
        final actions = tester.getRect(
          find.byKey(const ValueKey('feed_like_button')),
        );
        final run = FeedScrubRun.resolve(
          tester.element(find.byType(FeedScrubStrip)),
          width: strip.width,
          inset: tester
              .widget<FeedScrubStrip>(find.byType(FeedScrubStrip))
              .inset,
          counterWidest: '4/4',
        );
        expect(resting.left, closeTo(strip.left + run.trackLeft, 0.5));
        expect(
          resting.right,
          closeTo(tester.getRect(find.byType(FeedLiveBoard)).right, 0.01),
        );
        expect(graph.top, greaterThanOrEqualTo(actions.bottom));
        expect(graph.bottom, closeTo(strip.top, 0.5));
        final gesture = await tester.startGesture(
          Offset(trackLeft + 30, strip.top + 18),
        );
        await gesture.moveTo(Offset(strip.left + run.xAt(0.5), strip.top + 18));
        await tester.pump(const Duration(milliseconds: 16));
        final scrubbing = tester.widget<FeedScrubStrip>(
          find.byType(FeedScrubStrip),
        );
        expect(scrubbing.scrubbing, isTrue);
        expect(
          tester
              .widget<FeedEvaluationGraph>(find.byType(FeedEvaluationGraph))
              .ply,
          (scrubbing.progress * 7).round(),
        );
        expect(tester.getRect(chartFinder), resting);
        expect(find.byType(FeedMoveBubble), findsNothing);
        expect(
          find.byKey(const ValueKey('feed_like_button')).hitTestable(),
          findsOneWidget,
        );
        // The move and its eval once, above the chart; where it sits in the
        // game only in the counter.
        expect(find.textContaining('move '), findsNothing);
        await gesture.up();
        await tester.pump();
        expect(tester.getRect(chartFinder), resting);
        expect(
          tester.widget<FeedScrubStrip>(find.byType(FeedScrubStrip)).scrubbing,
          isFalse,
        );
        // The graph uses its full width; the timeline leaves room for its
        // counter. Tapping the graph's end still chooses the final move.
        await tester.tapAt(
          Offset(resting.right - FeedScrubStrip.thumbInset, resting.center.dy),
        );
        await tester.pump();
        expect(
          tester.widget<FeedScrubStrip>(find.byType(FeedScrubStrip)).progress,
          1,
        );
        await _tearDown(tester);
      },
    );

    for (final setting in ['missing', 'engine off', 'no spoilers']) {
      testWidgets('persistent graph respects $setting evaluations', (
        tester,
      ) async {
        await _pump(
          tester,
          games: 1,
          evals: setting != 'missing',
          analysis: setting != 'engine off',
          noSpoilers: setting == 'no spoilers',
        );
        expect(find.bySemanticsLabel('Game evaluation graph'), findsNothing);
        expect(
          find.text(
            setting == 'missing'
                ? 'No recorded evaluation'
                : 'Evaluation hidden',
          ),
          findsOneWidget,
        );
        final strip = tester.getRect(find.byType(FeedScrubStrip));
        final gesture = await tester.startGesture(strip.center);
        await gesture.moveBy(const Offset(60, 0));
        await tester.pump();
        expect(find.bySemanticsLabel('Game evaluation graph'), findsNothing);
        expect(find.byType(FeedMoveBubble), findsOneWidget);
        await gesture.up();
        await tester.pump();
        await _tearDown(tester);
      });
    }

    testWidgets('at a large text size the chart\'s move line is whole', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(tester, games: 1, evals: true);
      final strip = tester.getRect(find.byType(FeedScrubStrip));
      final y = strip.top + 18;
      // A sideways drag from the start of the track to its middle.
      final gesture = await tester.startGesture(Offset(strip.left + 40, y));
      for (var x = 60.0; x <= strip.width * 0.5; x += 20) {
        await gesture.moveTo(Offset(strip.left + x, y));
        await tester.pump(const Duration(milliseconds: 16));
      }
      final label = find
          .descendant(
            of: find.byType(FeedMoveInfoRow),
            matching: find.byType(RichText),
          )
          .first;
      final paragraph = tester.renderObject<RenderParagraph>(label);
      // The 18/24 line at 1.3x (about 31pt) gets all the height it needs:
      // a box short of it clips the descenders ("Ng5" reads "Na5").
      final needs = paragraph.getMinIntrinsicHeight(paragraph.size.width);
      expect(needs, greaterThan(30));
      expect(paragraph.size.height, greaterThanOrEqualTo(needs - 0.01));
      expect(paragraph.didExceedMaxLines, isFalse);
      await gesture.up();
      await tester.pump();
      await _tearDown(tester);
    });

    testWidgets('the counter is measured as it is drawn, letter spacing and '
        'all', (tester) async {
      late double measured;
      const key = ValueKey('counter');
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTextStyle(
            style: const TextStyle(letterSpacing: 2),
            child: Builder(
              builder: (context) {
                measured = FeedScrubStrip.counterWidthOf(context, '14/14');
                return Center(
                  child: Text(
                    '14/14',
                    key: key,
                    style: FeedScrubStrip.counterStyle(context),
                  ),
                );
              },
            ),
          ),
        ),
      );
      final drawn = tester.getSize(find.byKey(key)).width;
      expect(measured, greaterThanOrEqualTo(drawn));
      expect(measured - drawn, lessThan(1));
    });

    testWidgets('the move line keeps up with a scrub, move for move', (
      tester,
    ) async {
      await _pump(tester, games: 1);
      final strip = tester.getRect(find.byType(FeedScrubStrip));
      final counter = tester.getRect(
        find.byKey(const ValueKey('feed_scrub_play_toggle')),
      );
      final left = strip.left + 16;
      final right =
          counter.right - _counterWidth(tester) - FeedScrubStrip.counterGap;
      final row = find.byType(FeedMoveInfoRow);
      Finder move(String san) => find.descendant(
        of: row,
        matching: find.textContaining(san, findRichText: true),
      );
      expect(move('Start'), findsOneWidget);

      // A quick scrub to the end, a frame per move or two.
      final gesture = await tester.startGesture(Offset(left, strip.center.dy));
      for (var x = left + 24; x <= right + 24; x += 24) {
        await gesture.moveTo(Offset(x, strip.center.dy));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        tester
            .widget<FeedScrubStrip>(find.byType(FeedScrubStrip).first)
            .progress,
        closeTo(7 / 7, 0.001),
      );
      // The current move updates on the same frame as the scrub counter.
      await tester.pump(const Duration(milliseconds: 16));
      expect(move('Qxf7#'), findsOneWidget);
      expect(
        tester
            .widget<FeedEvaluationGraph>(find.byType(FeedEvaluationGraph))
            .ply,
        7,
      );

      // Back to the start just as fast: "Start" is back in sight.
      for (var x = right; x >= left - 24; x -= 24) {
        await gesture.moveTo(Offset(x, strip.center.dy));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester
            .widget<FeedScrubStrip>(find.byType(FeedScrubStrip).first)
            .progress,
        closeTo(0 / 7, 0.001),
      );
      expect(move('Start'), findsOneWidget);
      expect(
        tester
            .widget<FeedEvaluationGraph>(find.byType(FeedEvaluationGraph))
            .ply,
        0,
      );
      await gesture.up();
      await tester.pump();
      await _tearDown(tester);
    });
  });
}

// --------------------------------------------------------------- harness

final Finder _pages = find.byKey(const ValueKey('feed_pages'));
final Finder _tail = find.byKey(const ValueKey('feed:tail'));

Finder _post(String id) => find.byKey(ValueKey('game:$id'));

String? _currentKey(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(FeedScreen)),
).read(feedCurrentEntryKeyProvider);

/// The counter's reserved width: the widest it can read, "4/4".
double _counterWidth(WidgetTester tester) {
  return 44 + 16 - FeedScrubStrip.counterGap;
}

Future<void> _fling(WidgetTester tester) async {
  await tester.fling(_pages, const Offset(0, -400), 1500);
  await _settle(tester);
}

/// Long enough for a full-screen page to come to rest.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class _Feed {
  _Feed(this.notifier, this.sound);

  final _FakeFeed notifier;
  final _RecordingMoveSound sound;

  int get loads => notifier.loads;
  int get refreshes => notifier.refreshes;
}

Future<_Feed> _pump(
  WidgetTester tester, {
  required int games,
  FeedMore more = FeedMore.open,
  Future<void>? adds,
  Size size = const Size(393, 852),
  bool evals = false,
  bool analysis = true,
  bool noSpoilers = false,
  _FakeFeed Function(List<FeedItem> items, FeedMore more)? makeFeed,
}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final sfx = _SilentSfx();
  final sound = _RecordingMoveSound(sfx);
  final items = [
    for (var i = 0; i < games; i++) _scholarsMate('g$i', evals: evals),
  ];
  final feed =
      makeFeed?.call(items, more) ??
      _FakeFeed(items, moreValue: more, adds: adds);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        feedProvider.overrideWith(() => feed),
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
          () => _TestEngineSettings(analysis),
        ),
        eventNoSpoilersProvider.overrideWith(
          (ref, tourId) => _MemoryNoSpoilers(ref, tourId, noSpoilers),
        ),
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
  return _Feed(feed, sound);
}

Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

const _pgn = '1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0';

FeedItem _scholarsMate(String id, {bool evals = false, String pgn = _pgn}) {
  final parsed = PgnGame.parsePgn(pgn);
  Position position = PgnGame.startingPosition(parsed.headers);
  final plies = <FeedPly>[FeedPly(fen: position.fen, cp: evals ? 20 : null)];
  for (final node in parsed.moves.mainline()) {
    final move = position.parseSan(node.san)!;
    position = position.play(move);
    plies.add(
      FeedPly(
        fen: position.fen,
        san: node.san,
        uci: move.uci,
        cp: evals ? 20 + 40 * plies.length : null,
      ),
    );
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
      pgn: pgn,
      fen: plies.last.fen,
      eco: 'C20',
      openingName: "King's Pawn Game",
    ),
    plies: plies,
    reason: '',
    eventLabel: 'Test Open 2026',
    result: '1-0',
    hasEvals: evals,
  );
}

/// A feed of [_items]. [adds] (when given) is one more game that lands once
/// it completes, asked for by the first loadMore; [more] is what the tail is
/// told lies past the last game; a refresh deals two fresh games.
class _FakeFeed extends FeedNotifier {
  _FakeFeed(this._items, {this.moreValue = FeedMore.open, this.adds});

  final List<FeedItem> _items;
  FeedMore moreValue;
  final Future<void>? adds;
  Future<void>? _adding;
  int loads = 0;
  int refreshes = 0;

  @override
  FeedMore get more => moreValue;

  @override
  Future<List<FeedItem>> build() async => _items;

  @override
  Future<void> loadMore() {
    loads++;
    final adds = this.adds;
    if (adds == null) return Future<void>.value();
    return _adding ??= adds.then((_) {
      state = AsyncData([
        ...state.valueOrNull ?? const <FeedItem>[],
        _scholarsMate('more0'),
      ]);
    });
  }

  @override
  Future<void> refresh() async {
    refreshes++;
    moreValue = FeedMore.open;
    state = AsyncData([_scholarsMate('fresh0'), _scholarsMate('fresh1')]);
  }

  @override
  void onVisible(int index) {}
}

/// Loads the way [FeedNotifier.loadMore] does: [FeedMore.open] from the
/// moment one starts. While [hold] is on a load stays pending until [fail];
/// otherwise it fails at once, as a load with nothing to find does.
class _RetryingFeed extends _FakeFeed {
  _RetryingFeed(super.items, FeedMore more) : super(moreValue: more);

  bool hold = false;
  Completer<void>? _pending;

  @override
  Future<void> loadMore() {
    loads++;
    moreValue = FeedMore.open;
    final pending = _pending ??= Completer<void>();
    if (!hold) fail();
    return pending.future;
  }

  /// The load in flight comes back empty.
  void fail() {
    moreValue = FeedMore.stalled;
    final pending = _pending;
    _pending = null;
    pending?.complete();
  }
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

class _RecordingMoveSound extends FeedMoveSound {
  _RecordingMoveSound(super.sfx);

  final List<(String, MoveClass?)> played = [];

  @override
  void play({required String san, MoveClass? moveClass, bool fast = false}) {
    played.add((san, moveClass));
  }
}

class _TestEngineSettings extends EngineSettingsNotifierNew {
  _TestEngineSettings(this.analysis);
  final bool analysis;
  @override
  Future<EngineSettings> build() async =>
      EngineSettings(showEngineAnalysis: analysis);
}

class _MemoryNoSpoilers extends EventNoSpoilersController {
  _MemoryNoSpoilers(Ref ref, String tourId, this.enabled)
    : super(ref: ref, tourId: tourId);
  final bool enabled;

  @override
  Future<void> load() async {
    state = EventNoSpoilersState(enabled: enabled, isLoading: false);
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
