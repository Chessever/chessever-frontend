// Duo audit: Feed (game, news and puzzle posts, the news reader with its
// related-article group, Discovery news) and the For You shell, in every
// iPhone Duo window state at 1.0x and 1.3x text, plus folded <-> unfolded
// transitions for the screens that hold state.
import 'dart:math' as math;

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/repository/lichess/cloud_eval/cloud_eval.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/classification_fx/move_class.dart';
import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/screens/feed/feed_screen.dart';
import 'package:chessever2/screens/feed/models/feed_entry.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/news/news_group_repository.dart';
import 'package:chessever2/screens/feed/news/news_models.dart';
import 'package:chessever2/screens/feed/news/news_reader_screen.dart';
import 'package:chessever2/screens/feed/news/news_repository.dart';
import 'package:chessever2/screens/feed/providers/feed_entries_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_eval_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/screens/feed/puzzles/feed_puzzle.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_repository.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_service_client.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_store.dart';
import 'package:chessever2/screens/feed/race/puzzle_rating_range.dart';
import 'package:chessever2/screens/feed/race/race_flames.dart';
import 'package:chessever2/screens/feed/race/race_controller.dart';
import 'package:chessever2/screens/feed/race/race_lobby_screen.dart';
import 'package:chessever2/screens/feed/widgets/feed_move_sound.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/news_screen.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/most_liked_controls.dart';
import 'package:chessever2/screens/for_you/for_you_screen.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/adaptive_window.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fixtures/duo_window_matrix.dart';
import 'puzzle_race_fakes.dart';

const _scales = [1.0, 1.3];

/// The transitions that cross the fold: folded <-> unfolded, either way.
Iterable<DuoWindowTransition> get _foldTransitions =>
    duoWindowTransitions.where((t) => t.from.unfolded != t.to.unfolded);

/// The app's root scopes under [child], at a fixed text [scale].
Widget _root(BuildContext context, Widget? child, double scale) =>
    MediaQuery.withClampedTextScaling(
      minScaleFactor: scale,
      maxScaleFactor: scale,
      child: AdaptiveWindowScope(child: child!),
    );

void _setWindow(WidgetTester tester, DuoWindowCase window) {
  tester.view.devicePixelRatio = 3;
  applyDuoWindow(tester, window);
  addTearDown(tester.view.reset);
}

Future<void> _settleFrames(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Unmount inside the fake clock so no clip/page timer outlives the test.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

/// Brings [finder] into view inside its nearest scrollable only (a short
/// Feed page scrolls within itself; the PageView around it must not move),
/// then expects it hittable.
Future<void> _reach(WidgetTester tester, Finder finder, String reason) async {
  expect(finder, findsWidgets, reason: reason);
  final target = finder.first;
  final scrollable = find.ancestor(
    of: target,
    matching: find.byType(Scrollable),
  );
  if (scrollable.evaluate().isNotEmpty) {
    final position = tester.state<ScrollableState>(scrollable.first).position;
    await position.ensureVisible(tester.renderObject(target), alignment: 0.5);
    await tester.pump();
  }
  _expectHittable(target, reason);
}

void _expectHittable(Finder finder, String reason) {
  expect(finder.hitTestable(), findsWidgets, reason: reason);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  // ------------------------------------------------------------ Feed posts
  group('Feed screen', () {
    for (final window in duoWindowCases) {
      for (final scale in _scales) {
        testWidgets(
          'game post fits ${window.name} at ${scale}x with actions hittable',
          (tester) async {
            _setWindow(tester, window);
            final feed = await _pumpFeed(tester, scale: scale);
            expect(tester.takeException(), isNull);
            for (final key in ['feed_title', 'feed_sound_toggle']) {
              _expectHittable(find.byKey(ValueKey(key)), key);
            }
            for (final key in ['feed_analyze_button', 'feed_share_button']) {
              await _reach(tester, find.byKey(ValueKey(key)), key);
            }
            _expectHittable(find.byKey(const ValueKey('feed_back')), 'back');
            // The board and its scrub row sit inside the window.
            final board = tester.getRect(find.byType(Chessboard).first);
            expect(board.width, greaterThan(120));
            expect(board.bottom, lessThanOrEqualTo(window.size.height));
            expect(board.right, lessThanOrEqualTo(window.size.width));
            // The speaker answers a tap.
            final before = feed.sfx.muted;
            await tester.tap(find.byKey(const ValueKey('feed_sound_toggle')));
            await tester.pump();
            expect(feed.sfx.muted, !before);
            expect(tester.takeException(), isNull);
            await _unmount(tester);
          },
        );

        testWidgets('grouped news post fits ${window.name} at ${scale}x and '
            'Read opens the reader', (tester) async {
          _setWindow(tester, window);
          await _pumpFeed(tester, scale: scale);
          await _jumpToEntry(tester, (e) => e is FeedNewsEntry);
          expect(tester.takeException(), isNull);
          expect(find.text('17 articles · Latest'), findsOneWidget);
          final read = find.bySemanticsLabel('Read');
          _expectHittable(find.text('Read'), 'Read');
          expect(read, findsWidgets);
          _expectHittable(
            find.bySemanticsLabel('Share article'),
            'Share article',
          );
          await tester.tap(find.text('Read').hitTestable().first);
          await _settleFrames(tester, 10);
          expect(tester.takeException(), isNull);
          expect(find.byType(NewsReaderScreen), findsOneWidget);
          _expectHittable(find.byTooltip('Back'), 'reader Back');
          await _unmount(tester);
        });

        testWidgets('partner news post fits ${window.name} at ${scale}x', (
          tester,
        ) async {
          _setWindow(tester, window);
          await _pumpFeed(tester, scale: scale);
          await _jumpToEntry(
            tester,
            (e) => e is FeedNewsEntry && e.news.publisher.isPartner,
          );
          expect(tester.takeException(), isNull);
          _expectHittable(find.text('Read'), 'Read');
          _expectHittable(
            find.bySemanticsLabel('Share article'),
            'Share article',
          );
          await _unmount(tester);
        });

        testWidgets('empty Feed fits ${window.name} at ${scale}x with Refresh '
            'hittable', (tester) async {
          _setWindow(tester, window);
          await _pumpFeed(tester, scale: scale, games: const []);
          await _settleFrames(tester);
          expect(tester.takeException(), isNull);
          _expectHittable(find.text('Refresh'), 'Refresh');
          await _unmount(tester);
        });
      }
    }

    for (final t in _foldTransitions) {
      testWidgets('keeps its post across ${t.from.name} -> ${t.to.name}', (
        tester,
      ) async {
        _setWindow(tester, t.from);
        await _pumpFeed(tester, scale: 1.3);
        final pages = find.byKey(const ValueKey('feed_pages'));
        tester.widget<PageView>(pages).controller!.jumpToPage(2);
        await _settleFrames(tester, 4);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(FeedScreen)),
          listen: false,
        );
        final key = container.read(feedCurrentEntryKeyProvider);
        expect(key, contains('g3'));
        final screen = find.byType(FeedScreen).evaluate().single;

        applyDuoWindow(tester, t.to, mirrorInsets: true);
        await _settleFrames(tester, 6);
        expect(tester.takeException(), isNull);
        expect(screen.mounted, isTrue);
        expect(tester.widget<PageView>(pages).controller!.page, 2);
        expect(container.read(feedCurrentEntryKeyProvider), key);
        await _reach(
          tester,
          find.byKey(const ValueKey('feed_analyze_button')),
          'Analyze after resize',
        );
        await _unmount(tester);
      });
    }
  });

  // ------------------------------------------------------------ Puzzle post
  group('Feed puzzle post', () {
    for (final window in duoWindowCases) {
      for (final scale in _scales) {
        testWidgets('fits ${window.name} at ${scale}x, actions and difficulty '
            'sheet work', (tester) async {
          _setWindow(tester, window);
          final h = await _pumpPuzzle(tester, scale: scale);
          await tester.pump(const Duration(milliseconds: 700));
          expect(tester.takeException(), isNull);
          for (final key in [
            'feed_puzzle_hint',
            'feed_puzzle_solution',
            'feed_puzzle_next',
            'feed_header_difficulty',
          ]) {
            await _reach(tester, find.byKey(ValueKey(key)), key);
          }
          await _reach(
            tester,
            find.byKey(const ValueKey('feed_puzzle_hint')),
            'hint',
          );
          await tester.tap(find.byKey(const ValueKey('feed_puzzle_hint')));
          await tester.pump();
          expect(_hintCircles(tester), contains(Square.a1));
          await _reach(
            tester,
            find.byKey(const ValueKey('feed_puzzle_next')),
            'next',
          );
          await tester.tap(find.byKey(const ValueKey('feed_puzzle_next')));
          await tester.pump();
          expect(h.nextRequests, 1);

          await _reach(
            tester,
            find.byKey(const ValueKey('feed_header_difficulty')),
            'difficulty',
          );
          await tester.tap(
            find.byKey(const ValueKey('feed_header_difficulty')),
          );
          await _settleFrames(tester);
          expect(tester.takeException(), isNull);
          expect(find.text('Puzzle difficulty'), findsOneWidget);
          await tester.ensureVisible(find.text('Strong'));
          await tester.pump();
          _expectHittable(find.text('Strong'), 'Strong preset');
          await tester.tap(find.text('Strong'));
          await _settleFrames(tester);
          expect(tester.takeException(), isNull);
          final container = ProviderScope.containerOf(
            tester.element(find.byType(FeedPuzzlePage)),
          );
          expect(
            container.read(puzzleRatingRangeProvider),
            PuzzleRatingPreset.strong.range,
          );
          await _unmount(tester);
        });
      }
    }

    for (final t in _foldTransitions) {
      testWidgets('keeps its hint and position across '
          '${t.from.name} -> ${t.to.name}', (tester) async {
        _setWindow(tester, t.from);
        await _pumpPuzzle(tester, scale: 1.3);
        await tester.pump(const Duration(milliseconds: 700));
        await _reach(
          tester,
          find.byKey(const ValueKey('feed_puzzle_hint')),
          'hint',
        );
        await tester.tap(find.byKey(const ValueKey('feed_puzzle_hint')));
        await tester.pump();
        final fen = _board(tester).fen;
        final page = find.byType(FeedPuzzlePage).evaluate().single;

        applyDuoWindow(tester, t.to, mirrorInsets: true);
        await _settleFrames(tester, 4);
        expect(tester.takeException(), isNull);
        expect(page.mounted, isTrue);
        expect(_board(tester).fen, fen);
        expect(_hintCircles(tester), contains(Square.a1));
        await _reach(
          tester,
          find.byKey(const ValueKey('feed_puzzle_next')),
          'Next after resize',
        );
        await _unmount(tester);
      });
    }
  });

  // ------------------------------------------------------------ Puzzle race
  group('Puzzle race', () {
    for (final window in duoWindowCases) {
      for (final scale in _scales) {
        testWidgets(
          'lobby, board and results fit ${window.name} at ${scale}x',
          (tester) async {
            _setWindow(tester, window);
            final h = RaceHarness();
            final container = await _pumpRace(tester, h, scale: scale);
            expect(tester.takeException(), isNull);
            for (final key in ['race_mode_infinite', 'race_multiplayer']) {
              await _reach(tester, find.byKey(ValueKey(key)), key);
            }
            await _reach(
              tester,
              find.byKey(const ValueKey('race_start_solo')),
              'Start race',
            );
            await _startRace(tester, h);
            expect(tester.takeException(), isNull);
            final board = find.descendant(
              of: find.byKey(const ValueKey('race_board_0')),
              matching: find.byType(Chessboard),
            );
            expect(board, findsOneWidget);
            final rect = tester.getRect(board);
            expect(rect.width, greaterThan(120));
            expect(rect.bottom, lessThanOrEqualTo(window.size.height));
            expect(rect.right, lessThanOrEqualTo(window.size.width));
            _expectHittable(find.byKey(const ValueKey('race_clock')), 'clock');

            await _loseRace(tester, h, container);
            await tester.pump(const Duration(milliseconds: 400));
            await tester.pump();
            expect(tester.takeException(), isNull);
            expect(find.text('Out of lives'), findsOneWidget);
            for (final label in ['Back to Feed', 'Play again']) {
              await _reach(tester, find.text(label), label);
            }
            await _unmountRace(tester);
          },
        );
      }
    }

    for (final t in _foldTransitions) {
      testWidgets('keeps the running puzzle across '
          '${t.from.name} -> ${t.to.name}', (tester) async {
        _setWindow(tester, t.from);
        final h = RaceHarness();
        final container = await _pumpRace(tester, h, scale: 1.3);
        await _startRace(tester, h);
        await tester.pump(const Duration(milliseconds: 400));
        final before = container.read(raceControllerProvider);
        final sockets = h.server.sockets.length;

        applyDuoWindow(tester, t.to, mirrorInsets: true);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        final after = container.read(raceControllerProvider);
        expect(after.mode, before.mode);
        expect(h.server.sockets.length, sockets, reason: 'no reconnect');
        final board = find.descendant(
          of: find.byKey(const ValueKey('race_board_0')),
          matching: find.byType(Chessboard),
        );
        expect(board, findsOneWidget);
        final rect = tester.getRect(board);
        expect(rect.bottom, lessThanOrEqualTo(t.to.size.height));
        expect(rect.right, lessThanOrEqualTo(t.to.size.width));
        expect(find.textContaining('Your move'), findsOneWidget);
        await _unmountRace(tester);
      });
    }
  });

  // ------------------------------------------------- News reader with group
  group('News reader with related articles', () {
    for (final window in duoWindowCases) {
      for (final scale in _scales) {
        testWidgets('fits ${window.name} at ${scale}x; Back, siblings and '
            'Show more hittable', (tester) async {
          _setWindow(tester, window);
          final groups = _Groups();
          await _pumpReader(tester, groups, scale: scale);
          expect(tester.takeException(), isNull);
          _expectHittable(find.byTooltip('Back'), 'Back');
          await tester.scrollUntilVisible(
            find.textContaining('Sibling 2'),
            400,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Show more'));
          await tester.pumpAndSettle();
          _expectHittable(find.text('Show more'), 'Show more');
          await tester.tap(find.text('Show more'));
          await tester.pumpAndSettle();
          expect(groups.offsets, [0, 1]);
          await tester.ensureVisible(find.textContaining('Sibling 2'));
          await tester.pumpAndSettle();
          _expectHittable(find.textContaining('Sibling 2'), 'Sibling 2');
          await tester.tap(find.textContaining('Sibling 2'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(
            tester
                .widget<NewsReaderScreen>(find.byType(NewsReaderScreen))
                .news
                .id,
            2,
          );
          _expectHittable(find.byTooltip('Back'), 'Back on sibling');
          await tester.tap(find.byTooltip('Back').hitTestable().first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final t in _foldTransitions) {
      testWidgets('keeps scroll and loaded siblings across '
          '${t.from.name} -> ${t.to.name}', (tester) async {
        _setWindow(tester, t.from);
        final groups = _Groups();
        await _pumpReader(tester, groups, scale: 1.3);
        final scrollable = find.byType(Scrollable).first;
        final position = tester.state<ScrollableState>(scrollable).position;
        position.jumpTo(position.maxScrollExtent * 0.5);
        await tester.pumpAndSettle();
        final share = position.pixels / position.maxScrollExtent;
        expect(share, greaterThan(0));
        final reader = find.byType(NewsReaderScreen).evaluate().single;

        applyDuoWindow(tester, t.to, mirrorInsets: true);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(reader.mounted, isTrue);
        final after = tester.state<ScrollableState>(scrollable).position;
        expect(after.pixels, greaterThan(0));
        expect(after.pixels / after.maxScrollExtent, closeTo(share, 0.35));
        // A resize must not reload the related group.
        expect(groups.calls, 1);
        _expectHittable(find.byTooltip('Back'), 'Back after resize');
      });
    }
  });

  // ------------------------------------------------------- Discovery news
  group('Discovery news grid', () {
    for (final window in duoWindowCases) {
      for (final scale in _scales) {
        testWidgets('fits ${window.name} at ${scale}x and a grouped card '
            'opens the reader', (tester) async {
          _setWindow(tester, window);
          final own = _CatalogRows([
            for (var i = 1; i <= 8; i++)
              _catalogRow(i)..['group_article_count'] = i == 1 ? 17 : 1,
          ]);
          await _pumpNewsScreen(tester, own, scale: scale);
          expect(tester.takeException(), isNull);
          expect(find.text('17 articles · Latest'), findsOneWidget);
          final card = find.byKey(const ValueKey('news_card_1'));
          await tester.ensureVisible(card);
          await tester.pumpAndSettle();
          _expectHittable(card, 'news_card_1');
          await tester.tap(card.hitTestable().first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.byType(NewsReaderScreen), findsOneWidget);
          _expectHittable(find.byTooltip('Back'), 'reader Back');
        });
      }
    }

    for (final t in _foldTransitions) {
      testWidgets('keeps its scroll and pages across '
          '${t.from.name} -> ${t.to.name}', (tester) async {
        _setWindow(tester, t.from);
        final own = _CatalogRows([
          for (var i = 1; i <= 10; i++) _catalogRow(i),
        ]);
        await _pumpNewsScreen(tester, own, scale: 1.3);
        final scrollable = find.byType(Scrollable).first;
        final position = tester.state<ScrollableState>(scrollable).position;
        position.jumpTo(math.min(300, position.maxScrollExtent));
        await tester.pumpAndSettle();
        final requests = own.offsets.length;
        final screen = find.byType(NewsScreen).evaluate().single;

        applyDuoWindow(tester, t.to, mirrorInsets: true);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(screen.mounted, isTrue);
        expect(own.offsets.length, requests);
        final card = find.byKey(const ValueKey('news_card_3'));
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        _expectHittable(card, 'news_card_3 after resize');
      });
    }
  });

  // ------------------------------------------------- Most liked date control
  group('Most liked date control', () {
    for (final window in duoWindowCases) {
      for (final scale in _scales) {
        for (final period in MostLikedPeriod.values) {
          testWidgets('${period.name} fits ${window.name} at ${scale}x; '
              'arrows step and the reset tooltip opens', (tester) async {
            _setWindow(tester, window);
            final now = DateTime.utc(2026, 11, 12, 15);
            var previous = 0;
            var next = 0;
            await tester.pumpWidget(
              MaterialApp(
                theme: AppTheme.darkTheme,
                builder: (context, child) => _root(context, child, scale),
                home: Scaffold(
                  body: SafeArea(
                    child: MostLikedDateControl(
                      query: MostLikedQuery(
                        period,
                        now.subtract(const Duration(days: 400)),
                      ),
                      now: now,
                      onPrevious: () => previous++,
                      onNext: () => next++,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final back = find.bySemanticsLabel(RegExp('^Previous '));
            final forward = find.bySemanticsLabel(RegExp('^Next '));
            _expectHittable(back, 'previous');
            _expectHittable(forward, 'next');
            await tester.tap(back.hitTestable().first);
            await tester.tap(forward.hitTestable().first);
            await tester.pump();
            expect((previous, next), (1, 1));
            await tester.tap(find.byType(Tooltip).hitTestable().first);
            await tester.pump(const Duration(milliseconds: 300));
            expect(find.text('Resets at 00:00 UTC'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.pump(const Duration(seconds: 3));
          });
        }
      }
    }
  });

  // ------------------------------------------------------------- For You
  group('For You shell', () {
    for (final window in duoWindowCases) {
      for (final scale in _scales) {
        testWidgets('fits ${window.name} at ${scale}x; pages fill their slot '
            'and segments switch', (tester) async {
          _setWindow(tester, window);
          await _pumpForYou(tester, scale: scale);
          expect(tester.takeException(), isNull);
          _expectPageFillsSlot(tester, ForYouTab.today);
          for (final label in ['My Space', 'Today', 'Discovery']) {
            _expectHittable(find.text(label), label);
          }
          await tester.tap(find.text('Discovery').hitTestable().first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(_selectedTab(tester), ForYouTab.discovery);
          _expectPageFillsSlot(tester, ForYouTab.discovery);
          await tester.tap(find.text('My Space').hitTestable().first);
          await tester.pumpAndSettle();
          expect(_selectedTab(tester), ForYouTab.mySpace);
          _expectPageFillsSlot(tester, ForYouTab.mySpace);
          expect(tester.takeException(), isNull);
        });
      }
    }

    for (final t in _foldTransitions) {
      testWidgets('keeps its tab and refills the slot across '
          '${t.from.name} -> ${t.to.name}', (tester) async {
        _setWindow(tester, t.from);
        await _pumpForYou(tester, scale: 1.3);
        await tester.tap(find.text('Discovery').hitTestable().first);
        await tester.pumpAndSettle();
        final scroll = tester
            .widget<ListView>(find.byKey(const ValueKey('probe:discovery')))
            .controller!;
        scroll.jumpTo(200);
        await tester.pump();

        applyDuoWindow(tester, t.to, mirrorInsets: true);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(_selectedTab(tester), ForYouTab.discovery);
        _expectPageFillsSlot(tester, ForYouTab.discovery);
        expect(scroll.offset, 200);
        _expectHittable(find.text('Today'), 'Today after resize');
      });
    }
  });
}

// =================================================================== Feed

const _pgn = '1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0';

class _Feed {
  _Feed(this.sfx);
  final _SilentSfx sfx;
}

Future<_Feed> _pumpFeed(
  WidgetTester tester, {
  required double scale,
  List<FeedItem>? games,
}) async {
  final sfx = _SilentSfx();
  final items =
      games ?? [for (var i = 1; i <= 14; i++) _scholarsMate(id: 'g$i')];
  final news = [
    FeedNews(
      id: 1,
      title:
          'Javokhir Sindarov Wins Clutch Chess: Champions Showdown 2026 in '
          'Saint Louis After Three Days of Play',
      summary: 'The players and results from the final day in Saint Louis.',
      content: 'Body',
      publishedAt: DateTime.utc(2026, 11, 11),
      groupArticleCount: 17,
    ),
    FeedNews(
      id: 2,
      title: 'RookReview: the opening that decided the Candidates',
      summary: 'A partner story.',
      content: 'Partner body. ' * 40,
      publishedAt: DateTime.utc(2026, 11, 10),
      publisher: NewsPublisher.rookReview,
    ),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        premiumAccessProvider.overrideWithValue(true),
        feedProvider.overrideWith(() => _FakeFeed(items)),
        feedPuzzlesProvider.overrideWith((ref) async => const <FeedPuzzle>[]),
        feedNewsProvider.overrideWith((ref) async => news),
        feedSfxProvider.overrideWithValue(sfx),
        feedMoveSoundProvider.overrideWithValue(FeedMoveSound(sfx)),
        boardSettingsProviderNew.overrideWith(_TestBoardSettings.new),
        likedGamesProvider.overrideWith(_NoLikes.new),
        spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
        currentUserProvider.overrideWithValue(null),
        subscriptionProvider.overrideWith((ref) => _FreeSubscription()),
        engineSettingsProviderNew.overrideWith(_TestEngineSettings.new),
        eventNoSpoilersProvider.overrideWith(
          (ref, tourId) => _MemoryNoSpoilers(ref, tourId),
        ),
        feedCachedEvalProvider.overrideWith((ref, fen) async => null),
        feedEngineProvider.overrideWithValue(_QuietEngine()),
        newsGroupRepositoryProvider.overrideWithValue(_Groups()),
        newsArticleLoaderProvider.overrideWithValue(
          (link) async => _article(link.id!),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) => _root(context, child, scale),
        home: const Scaffold(body: FeedScreen()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return _Feed(sfx);
}

Future<void> _jumpToEntry(
  WidgetTester tester,
  bool Function(FeedEntry entry) test,
) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(FeedScreen)),
    listen: false,
  );
  final pages = container.read(feedPagesProvider);
  final index = pages.indexWhere(test);
  expect(index, isNonNegative, reason: 'entry not composed into the feed');
  tester
      .widget<PageView>(find.byKey(const ValueKey('feed_pages')))
      .controller!
      .jumpToPage(index);
  await _settleFrames(tester, 12);
}

FeedItem _scholarsMate({required String id}) {
  final parsed = PgnGame.parsePgn(_pgn);
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
      name: 'Nepomniachtchi, Ian',
      federation: '',
      title: 'GM',
      rating: 2770,
      countryCode: '',
      team: null,
    ),
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
    openingName: "King's Pawn Game: Wayward Queen Attack, Kiddie Countergambit",
  );
  return FeedItem(
    game: game,
    plies: plies,
    reason: 'Brilliant finish',
    eventLabel: 'FIDE World Rapid & Blitz Championships 2026',
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

class _SilentSfx implements FeedSfx {
  @override
  bool muted = false;

  @override
  bool boardSoundEnabled = true;

  @override
  Future<void> warmUp() async {}

  @override
  void playGameEnd(FeedItem item) {}

  @override
  void playSwipe() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
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

class _QuietEngine extends FeedEngine {
  @override
  Future<CloudEval?> evaluate(
    String fen, {
    required void Function(List<Pv> pvs, int depth) onUpdate,
  }) async => CloudEval(
    fen: fen,
    knodes: 1,
    depth: 20,
    pvs: [Pv(moves: 'e2e4', cp: 30)],
  );

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

// ================================================================= Puzzle

const _backRank = FeedPuzzle(
  id: 'backrank',
  fen: '6k1/6pp/8/8/8/8/8/RR4K1 b - - 0 1',
  initialMoveUci: 'g8h8',
  solution: ['a1a8'],
  rating: 900,
  themes: ['mateIn1', 'mate', 'backRankMate', 'oneMove', 'endgame'],
  openingTags: ['Sicilian_Defense', 'Sicilian_Defense_Najdorf_Variation'],
);

class _PuzzleHarness {
  int nextRequests = 0;
}

Future<_PuzzleHarness> _pumpPuzzle(
  WidgetTester tester, {
  required double scale,
}) async {
  final repo = FeedPuzzleRepository(
    client: PuzzleServiceClient(
      baseUrl: '',
      httpClient: MockClient((_) async => http.Response('', 404)),
    ),
    store: MemoryFeedPuzzleStore(),
  );
  final harness = _PuzzleHarness();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        feedPuzzleRepositoryProvider.overrideWithValue(repo),
        feedPuzzleSoundsProvider.overrideWithValue(_QuietPuzzleSounds()),
        boardSettingsProviderNew.overrideWith(_TestBoardSettings.new),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) => _root(context, child, scale),
        home: Scaffold(
          body: SafeArea(
            child: FeedPuzzlePage(
              puzzle: _backRank,
              isCurrent: true,
              isVisible: true,
              onRequestNext: () => harness.nextRequests++,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return harness;
}

ChessboardController _board(WidgetTester tester) =>
    tester.widget<Chessboard>(find.byType(Chessboard)).controller;

Iterable<Square> _hintCircles(WidgetTester tester) => tester
    .widget<Chessboard>(find.byType(Chessboard))
    .shapes
    .whereType<Circle>()
    .map((c) => c.orig);

class _QuietPuzzleSounds extends FeedPuzzleSounds {
  @override
  void move({required String san, MoveClass? moveClass}) {}
}

// ================================================================== Race

Future<ProviderContainer> _pumpRace(
  WidgetTester tester,
  RaceHarness h, {
  required double scale,
}) async {
  final container = ProviderContainer(
    overrides: [
      raceDepsProvider.overrideWithValue(h.deps()),
      boardSettingsProviderNew.overrideWith(_TestBoardSettings.new),
      raceServerStatsSourceProvider.overrideWithValue(
        FakeRaceServerStatsSource(),
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) => _root(context, child, scale),
        home: const RaceLobbyScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return container;
}

Future<void> _raceFrames(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<void> _startRace(WidgetTester tester, RaceHarness h) async {
  await tester.tap(find.byKey(const ValueKey('race_start_solo')));
  await _raceFrames(tester);
  h.server.last.push(snapshot());
  await _raceFrames(tester);
  h.server.last.push(snapshot(state: 'running', startedAt: h.clock - 2000));
  h.server.last.push(puzzle());
  await _raceFrames(tester);
}

Future<void> _loseRace(
  WidgetTester tester,
  RaceHarness h,
  ProviderContainer container,
) async {
  final socket = h.server.last;
  await tester.pump(const Duration(milliseconds: 400));
  final race = container.read(raceControllerProvider.notifier);
  for (var i = 0; i < 3; i++) {
    race.submitMove('b1b7');
    socket.push(verdict(index: i, correct: false, score: 0, mistakes: i + 1));
    if (i < 2) {
      socket.push(puzzle(index: i + 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }
  }
  socket.push(
    finished(
      results: [result(mistakes: 3, elapsedMs: 9000, finishReason: 'lives')],
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _unmountRace(WidgetTester tester) async {
  final containers = [
    for (final s in tester.widgetList<UncontrolledProviderScope>(
      find.byType(UncontrolledProviderScope),
    ))
      s.container,
  ];
  await tester.pumpWidget(const SizedBox.shrink());
  for (final c in containers) {
    c.dispose();
  }
  await tester.pump(const Duration(seconds: 1));
}

// ============================================================ News reader

FeedNews _article(int id) => FeedNews(
  id: id,
  title: 'Article $id',
  summary: '',
  content: 'Full body $id',
  publishedAt: DateTime.utc(2026, 11, 11),
);

class _Groups extends NewsGroupRepository {
  int calls = 0;
  final offsets = <int>[];

  @override
  Future<NewsGroupPage> load(int articleId, {int offset = 0}) async {
    calls++;
    offsets.add(offset);
    return NewsGroupPage([
      NewsGroupArticle(
        id: offset + 2,
        title:
            'Sibling ${offset + 2}: Gukesh holds Firouzja to a draw in a '
            'long rook endgame at the Grand Swiss',
        publishedAt: DateTime.utc(2026, 11, 11),
      ),
    ], hasMore: offset == 0);
  }
}

Future<void> _pumpReader(
  WidgetTester tester,
  _Groups groups, {
  required double scale,
}) async {
  final original = FeedNews(
    id: 1,
    title:
        'Javokhir Sindarov Wins Clutch Chess: Champions Showdown 2026 in '
        'Saint Louis After Three Days of Play',
    summary: '',
    content: List.filled(30, 'Long original paragraph.').join('\n\n'),
    publishedAt: DateTime.utc(2026, 11, 11),
    groupArticleCount: 3,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        newsGroupRepositoryProvider.overrideWithValue(groups),
        newsArticleLoaderProvider.overrideWithValue(
          (link) async => _article(link.id!),
        ),
        premiumAccessProvider.overrideWithValue(true),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) => _root(context, child, scale),
        home: NewsReaderScreen(news: original),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// ========================================================= Discovery news

Map<String, dynamic> _catalogRow(int id) => {
  'id': id,
  'title': id == 1
      ? 'Javokhir Sindarov Wins Clutch Chess: Champions Showdown 2026 in '
            'Saint Louis After Three Days of Play'
      : 'ChessEver story $id',
  'summary': 'The players and results from round $id.',
  'content': 'Round $id included a **decisive** game.',
  'image_url': null,
  'status': 'published',
  'published_at': DateTime.utc(
    2026,
    10,
    1,
  ).add(Duration(hours: 100 - id)).toIso8601String(),
  'created_at': DateTime.utc(2026, 10, 1).toIso8601String(),
};

class _CatalogRows {
  _CatalogRows(this.rows);
  final List<Map<String, dynamic>> rows;
  final offsets = <int>[];

  Future<List<Map<String, dynamic>>> fetch(int offset, int limit) async {
    offsets.add(offset);
    return rows.sublist(
      math.min(offset, rows.length),
      math.min(offset + limit, rows.length),
    );
  }
}

Future<void> _pumpNewsScreen(
  WidgetTester tester,
  _CatalogRows own, {
  required double scale,
}) async {
  final partners = _CatalogRows([]);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        newsCatalogFactoryProvider.overrideWithValue(
          () => NewsCatalogRepository(
            fetchOwn: own.fetch,
            fetchPartners: partners.fetch,
            pageSize: 12,
          ),
        ),
        feedNewsProvider.overrideWith((ref) async => []),
        premiumAccessProvider.overrideWithValue(true),
        newsGroupRepositoryProvider.overrideWithValue(_Groups()),
        newsArticleLoaderProvider.overrideWithValue(
          (link) async => _article(link.id!),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) => _root(context, child, scale),
        home: const NewsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// ================================================================ For You

class _MemoryRecentSearches implements RecentSearchStorage {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}
}

/// Each page is a probe that fills whatever slot it is given.
Widget _probePage(BuildContext context, ForYouTab tab, ScrollController c) =>
    ListView(
      key: ValueKey('probe:${tab.name}'),
      controller: c,
      children: [
        for (var i = 0; i < 40; i++)
          SizedBox(height: 48, child: Text('${tab.name} row $i')),
      ],
    );

Future<void> _pumpForYou(WidgetTester tester, {required double scale}) async {
  final prefs = (await SharedPreferencesService.instance.initialize())!;
  await prefs.remove(forYouLastTabPrefsKey);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recentSearchStorageProvider.overrideWithValue(_MemoryRecentSearches()),
        selectedBottomNavBarItemProvider.overrideWith(
          (ref) => BottomNavBarItem.forYou,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) => _root(context, child, scale),
        home: const Scaffold(
          body: SafeArea(child: ForYouScreen(pageBuilder: _probePage)),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

ForYouTab _selectedTab(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(ForYouScreen)),
).read(selectedForYouTabProvider);

/// The page is exactly the PageView's slot: no stale height, no band.
void _expectPageFillsSlot(WidgetTester tester, ForYouTab tab) {
  final slot = tester.getRect(find.byType(PageView));
  final page = tester.getRect(find.byKey(ValueKey('probe:${tab.name}')));
  expect(page.height, moreOrLessEquals(slot.height), reason: tab.name);
  expect(page.width, moreOrLessEquals(slot.width), reason: tab.name);
  expect(page.top, moreOrLessEquals(slot.top), reason: tab.name);
  // The segment control sits above the slot and inside the window.
  final segments = tester.getRect(find.byType(SegmentedSwitcher));
  expect(segments.bottom, lessThanOrEqualTo(slot.top + 0.5));
  expect(segments.top, greaterThanOrEqualTo(0));
}
