import 'dart:async';

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
import 'package:chessever2/screens/feed/puzzles/puzzle_repository.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_service_client.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_store.dart';
import 'package:chessever2/screens/feed/widgets/feed_action_row.dart';
import 'package:chessever2/screens/feed/widgets/feed_live_board.dart';
import 'package:chessever2/screens/feed/widgets/feed_clip.dart';
import 'package:chessever2/screens/feed/widgets/feed_layout.dart';
import 'package:chessever2/screens/feed/widgets/feed_move_strip.dart';
import 'package:chessever2/screens/feed/widgets/feed_move_sound.dart';
import 'package:chessever2/screens/feed/widgets/feed_scrub.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Every Feed post type starts and ends cleanly on a small, a common and a
/// tall phone, in both themes, at the default and a large text size: nothing
/// thrown, nothing cropped at the page edges, no text touching the sides,
/// the one-line header, the board right under it, and the action row clear
/// of the scrub line.
///
/// On-device checks this cannot make (for the report): the status bar icons
/// flip with the theme; the bottom nav sits below the scrub line with no
/// neighbouring post peeking in; the news cover dissolves into the page with
/// no seam under the top bar.
void main() {
  for (final scale in [1.8, 2.0]) {
    testWidgets('exploration keeps the board still and its move line and '
        'controls whole at ${scale}x text', (tester) async {
      await _pump(
        tester,
        // FeedScreen clamps phone chrome to its supported reading size.
        // A wider direct clip isolates the reusable strip's raw scale contract.
        (const Size(600, 1100), 24, 64),
        false,
        scale,
        _Kind.game,
        unclampedClip: true,
      );
      final board = tester.getRect(find.byType(FeedLiveBoard));
      final graphBefore = tester.getRect(
        find.byKey(const ValueKey('feed_evaluation_graph')),
      );
      final actionsBefore = tester.getRect(find.byType(FeedActionRow));
      Offset square(String name) {
        final square = Square.fromName(name);
        final side = board.width / 8;
        return Offset(
          board.left + (square.file + 0.5) * side,
          board.top + (7 - square.rank + 0.5) * side,
        );
      }

      // e3 differs from the recorded e4, so this is a real variation.
      await tester.tapAt(square('e2'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(square('e3'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Your line'), findsOneWidget);
      // Playing a line shifts nothing: same board, same rows.
      expect(tester.getRect(find.byType(FeedLiveBoard)), board);
      expect(tester.getRect(find.byType(FeedActionRow)), actionsBefore);
      final strip = tester.getRect(find.byType(FeedMoveStrip));
      expect(
        strip.height,
        closeTo(FeedLayout.moveStripHeightFor(TextScaler.linear(scale)), 0.01),
      );
      expect(strip.height, greaterThan(44));
      // The line's strip stands in the graph's slot.
      expect(find.byKey(const ValueKey('feed_evaluation_graph')), findsNothing);
      expect(strip.top, greaterThanOrEqualTo(graphBefore.top));
      expect(strip.bottom, lessThanOrEqualTo(graphBefore.bottom));
      final page = tester.getRect(find.byType(FeedClip));
      expect(strip.bottom, lessThanOrEqualTo(page.bottom));
      for (final text in tester.widgetList<Text>(
        find.descendant(
          of: find.byType(FeedMoveStrip),
          matching: find.byType(Text),
        ),
      )) {
        final rect = tester.getRect(find.byWidget(text));
        expect(rect.top, greaterThanOrEqualTo(strip.top), reason: text.data);
        expect(rect.bottom, lessThanOrEqualTo(strip.bottom), reason: text.data);
      }
      await tester.tap(find.bySemanticsLabel('Previous move'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.bySemanticsLabel('Next move'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('feed_back_to_game')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(FeedMoveStrip), findsNothing);
      expect(
        find.byKey(const ValueKey('feed_evaluation_graph')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await _tearDown(tester);
    });
  }

  const sizes = <String, (Size, double, double)>{
    // size, top inset, bottom nav height
    '360x640': (Size(360, 640), 24, 64),
    '393x852': (Size(393, 852), 59, 83),
    '430x932': (Size(430, 932), 59, 83),
  };

  for (final size in sizes.entries) {
    for (final light in [true, false]) {
      for (final scale in [1.0, 1.3]) {
        final label = '${size.key} ${light ? 'light' : 'dark'} ${scale}x';

        testWidgets('game post, $label', (tester) async {
          await _pump(tester, size.value, light, scale, _Kind.game);
          expect(tester.takeException(), isNull);
          final page = _pageRect(tester);
          final graph = tester.getRect(
            find.byKey(const ValueKey('feed_report_chart')),
          );
          expect(graph.top, greaterThanOrEqualTo(page.top));
          expect(graph.bottom, lessThanOrEqualTo(page.bottom));
          expect(graph.left, greaterThanOrEqualTo(page.left + 16));
          expect(graph.right, lessThanOrEqualTo(page.right - 16));
          final header = tester.getRect(
            find.byKey(const ValueKey('feed_post_header')),
          );
          final top = tester.getRect(
            find.byKey(const ValueKey('feed_row_black')),
          );
          final board = tester.getRect(find.byType(FeedLiveBoard));
          final bottom = tester.getRect(
            find.byKey(const ValueKey('feed_row_white')),
          );
          final actions = tester.getRect(
            find.byKey(const ValueKey('feed_like_button')),
          );
          final scrub = tester.getRect(find.byType(FeedScrubStrip));
          final actionRow = tester.getRect(find.byType(FeedActionRow));
          final counter = tester.getRect(
            find.byKey(const ValueKey('feed_scrub_play_toggle')),
          );

          expect(header.height, 44);
          expect(board.width, closeTo(board.height, 0.01));
          // Surfaces share the board column; toolbar contents have their
          // own centered rhythm rather than being pinned to its edges.
          expect(bottom.right, closeTo(board.right, 0.01));
          expect(actionRow.left, closeTo(bottom.left, 0.01));
          expect(actionRow.right, closeTo(board.right, 0.01));
          expect(graph.left, closeTo(bottom.left, 0.01));
          expect(graph.right, closeTo(board.right, 0.01));
          expect(counter.right, closeTo(board.right, 0.01));
          final buttons = find.descendant(
            of: find.byType(FeedActionRow),
            matching: find.byType(FeedActionLabel),
          );
          final cellWidth = actionRow.width / buttons.evaluate().length;
          for (var i = 0; i < buttons.evaluate().length; i++) {
            final label = buttons.at(i);
            final expectedCenter = actionRow.left + cellWidth * (i + 0.5);
            final word = tester.getRect(
              find.descendant(of: label, matching: find.byType(Text)),
            );
            expect(word.center.dx, closeTo(expectedCenter, 0.01));
          }
          // Header, row, board, row: in order, tight, no stretch between.
          expect(top.top, greaterThanOrEqualTo(header.bottom));
          expect(board.top, greaterThanOrEqualTo(top.bottom));
          expect(board.top - header.bottom, lessThanOrEqualTo(36));
          expect(bottom.top, greaterThanOrEqualTo(board.bottom));
          expect(actions.bottom, lessThanOrEqualTo(scrub.top));
          final graphSlot = tester.getRect(find.byType(FeedEvaluationGraph));
          expect(graphSlot.right, closeTo(board.right, 0.01));
          expect(graphSlot.top, greaterThanOrEqualTo(actions.bottom));
          expect(graphSlot.bottom, closeTo(scrub.top, 0.5));
          expect(scrub.bottom, lessThanOrEqualTo(page.bottom + 0.5));
          expect(header.top, greaterThanOrEqualTo(page.top));
          _expectTextInside(tester, page);
          await _tearDown(tester);
        });

        testWidgets('puzzle post, $label', (tester) async {
          await _pump(tester, size.value, light, scale, _Kind.puzzle);
          expect(tester.takeException(), isNull);
          final page = _pageRect(tester);
          final header = tester.getRect(
            find.byKey(const ValueKey('feed_puzzle_header')),
          );
          final board = tester.getRect(
            find.byKey(const ValueKey('feed_puzzle_board')),
          );
          expect(header.height, 44);
          expect(header.top, greaterThanOrEqualTo(page.top));
          expect(board.width, closeTo(board.height, 0.01));
          expect(board.top - header.bottom, lessThanOrEqualTo(36));
          expect(
            find.byKey(const ValueKey('feed_header_difficulty')),
            findsOneWidget,
          );
          _expectTextInside(tester, page);
          await _tearDown(tester);
        });

        testWidgets('news post, $label', (tester) async {
          await _pump(tester, size.value, light, scale, _Kind.news);
          expect(tester.takeException(), isNull);
          _expectTextInside(tester, _pageRect(tester));
          await _tearDown(tester);
        });

        testWidgets('empty feed, $label', (tester) async {
          await _pump(tester, size.value, light, scale, _Kind.empty);
          expect(tester.takeException(), isNull);
          expect(find.text('Nothing to play yet'), findsOneWidget);
          _expectTextInside(tester, _pageRect(tester));
          await _tearDown(tester);
        });

        testWidgets('loading, $label', (tester) async {
          await _pump(tester, size.value, light, scale, _Kind.loading);
          expect(tester.takeException(), isNull);
          expect(find.bySemanticsLabel('Loading Feed'), findsOneWidget);
          await _tearDown(tester);
        });
      }
    }
  }
}

enum _Kind { game, puzzle, news, empty, loading }

/// The page area under the Feed's top bar and above the bottom nav. The bar
/// itself is the home bar every tab shares, on Events' gutter; its placement
/// is checked by home_top_bar_parity_test.
Rect _pageRect(WidgetTester tester) {
  final pages = find.byKey(const ValueKey('feed_pages'));
  if (pages.evaluate().isNotEmpty) return tester.getRect(pages);
  final root = tester.getRect(find.byType(FeedScreen));
  final bar = find.byType(HomeTopBarFrame);
  if (bar.evaluate().isEmpty) return root;
  return Rect.fromLTRB(
    root.left,
    tester.getRect(bar).bottom,
    root.right,
    root.bottom,
  );
}

/// Every line of text on the current page sits inside it, at least 16pt
/// from either side; lines inside a horizontal scroller (the move strip)
/// are only checked against the page itself.
void _expectTextInside(WidgetTester tester, Rect page) {
  for (final element in find.byType(RichText).evaluate()) {
    final box = element.renderObject as RenderBox?;
    if (box == null || !box.hasSize || !box.attached) continue;
    // Through every transform (a label a FittedBox scales down reports its
    // unscaled size on its own).
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    // Neighbouring pages are built off screen; only the current one counts.
    if (rect.bottom <= page.top || rect.top >= page.bottom) continue;
    // Empty labels (an eval bar with no number yet) have no box to place.
    if (rect.width == 0 || rect.height == 0 || !rect.isFinite) continue;
    final inScroller =
        element.findAncestorWidgetOfExactType<SingleChildScrollView>() != null;
    if (inScroller) continue;
    final text = (element.widget as RichText).text.toPlainText();
    expect(rect.top, greaterThanOrEqualTo(page.top - 0.5), reason: text);
    expect(rect.bottom, lessThanOrEqualTo(page.bottom + 0.5), reason: text);
    expect(rect.left, greaterThanOrEqualTo(page.left + 15.5), reason: text);
    expect(rect.right, lessThanOrEqualTo(page.right - 15.5), reason: text);
  }
}

Future<void> _pump(
  WidgetTester tester,
  (Size, double, double) size,
  bool light,
  double scale,
  _Kind kind, {
  bool unclampedClip = false,
}) async {
  final (screen, inset, nav) = size;
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = screen * 3;
  tester.view.padding = FakeViewPadding(top: inset * 3);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final sfx = _SilentSfx();
  final entries = switch (kind) {
    _Kind.game => [FeedGameEntry(_game())],
    _Kind.puzzle => [
      const FeedPuzzleEntry(
        FeedPuzzle(
          id: 'p1',
          fen: '6k1/5ppp/8/8/8/8/5PPP/R5K1 b - - 0 1',
          initialMoveUci: 'g8h8',
          solution: ['a1a8'],
          rating: 1650,
          openingTags: ['Sicilian_Defense'],
          white: FeedPuzzlePlayer(name: 'Hikaru', title: 'GM', rating: 3050),
          black: FeedPuzzlePlayer(name: 'Opponent', rating: 2700),
        ),
      ),
    ],
    _Kind.news => [
      FeedNewsEntry(
        FeedNews(
          id: 1,
          title:
              'Gukesh holds the World Championship lead after a marathon '
              'endgame in round nine',
          summary:
              'A seven-hour defence keeps the champion a half point clear '
              'with three rounds to play in Singapore.',
          content: 'Body',
          publishedAt: DateTime(2026, 9, 20),
        ),
      ),
    ],
    _Kind.empty || _Kind.loading => const <FeedEntry>[],
  };

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        feedProvider.overrideWith(
          () => kind == _Kind.loading ? _LoadingFeed() : _FakeFeed(entries),
        ),
        feedEntriesProvider.overrideWith(() => _FixedEntries(entries)),
        feedPuzzlesProvider.overrideWith((ref) async => const <FeedPuzzle>[]),
        feedNewsProvider.overrideWith((ref) async => const <FeedNews>[]),
        feedPuzzleRepositoryProvider.overrideWithValue(
          FeedPuzzleRepository(
            client: PuzzleServiceClient(
              baseUrl: 'https://race.example.dev',
              httpClient: MockClient(
                (_) async => throw http.ClientException('offline'),
              ),
            ),
            store: MemoryFeedPuzzleStore(),
          ),
        ),
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
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              body: unclampedClip
                  ? SafeArea(
                      child: FeedClip(
                        item: _game(),
                        isCurrent: true,
                        isVisible: true,
                        onRequestNext: () {},
                        onScrollLock: (_) {},
                      ),
                    )
                  : const FeedScreen(),
              bottomNavigationBar: SizedBox(height: nav),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

FeedItem _game() {
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
      gameId: 'layout-game',
      whitePlayer: player('Vachier-Lagrave, Maxime', 2780),
      blackPlayer: player('Nepomniachtchi, Ian', 2770),
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.whiteWins,
      roundId: 'round-1',
      tourId: 'tour-1',
      pgn: pgn,
      fen: plies.last.fen,
      eco: 'C65',
      openingName: 'Ruy Lopez: Berlin Defense',
      timeControl: 'rapid',
    ),
    plies: plies,
    reason: '',
    eventLabel: 'Grand Chess Tour Superbet Classic Romania 2026',
    result: '1-0',
    signal: const FeedSignal(
      FeedSignalKind.favorite,
      name: 'Maxime Vachier-Lagrave',
    ),
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
}

class _LoadingFeed extends FeedNotifier {
  /// Never resolves, and leaves no timer behind.
  @override
  Future<List<FeedItem>> build() => Completer<List<FeedItem>>().future;

  @override
  Future<void> loadMore() async {}

  @override
  void onVisible(int index) {}
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
