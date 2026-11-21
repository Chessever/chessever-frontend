// The Feed tab as the home shell holds it, for tests that look at a post on
// a real phone: the real dock (HomeNavDock) over a page that runs under its
// slot, the region paging the bars, every provider faked so nothing reaches
// the network, and the app's own faces loaded so text measures as on a
// phone. Used by the preview renders and the dock and rail geometry tests.

import 'dart:async';
import 'dart:io';

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
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/providers/feed_entries_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_eval_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/screens/feed/puzzles/feed_puzzle.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_repository.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_service_client.dart';
import 'package:chessever2/screens/feed/puzzles/puzzle_store.dart';
import 'package:chessever2/screens/feed/widgets/feed_move_sound.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/home/widget/home_nav_dock.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:dartchess/dartchess.dart' hide File;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// What the page shows.
enum FeedShellScene { game, puzzle, news, skeleton }

/// A phone: its screen, its status bar and its bottom system inset, and
/// whether it is an iPhone (the dock sits into the home indicator's strip
/// there, above Android's bar).
typedef FeedPhone = ({
  String name,
  Size size,
  double top,
  double bottom,
  bool ios,
});

const FeedPhone feedIphone15 = (
  name: '393x852',
  size: Size(393, 852),
  top: 59,
  bottom: 34,
  ios: true,
);
const FeedPhone feedIphoneSe = (
  name: 'se_375x667',
  size: Size(375, 667),
  top: 20,
  bottom: 0,
  ios: true,
);
const FeedPhone feedAndroidGesture = (
  name: 'android_360x640_gesture',
  size: Size(360, 640),
  top: 24,
  bottom: 24,
  ios: false,
);
const FeedPhone feedAndroidButtons = (
  name: 'android_360x640_3button',
  size: Size(360, 640),
  top: 24,
  bottom: 48,
  ios: false,
);

/// Every phone the geometry tests walk.
const List<FeedPhone> feedPhones = [
  feedIphone15,
  feedIphoneSe,
  feedAndroidGesture,
  feedAndroidButtons,
];

/// Loads the app's faces (Inter as InterDisplay and Inter, Instrument Serif)
/// and the Material icons, so text is laid out at a phone's widths.
Future<void> loadFeedFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      // Sync read: an async one never completes under the fake clock.
      loader.addFont(
        Future.value(ByteData.sublistView(File(file).readAsBytesSync())),
      );
    }
    await loader.load();
  }

  final inter = [
    for (final weight in ['Regular', 'Medium', 'Bold'])
      'assets/fonts/Inter-$weight.otf',
  ];
  await family('InterDisplay', inter);
  await family('Inter', inter);
  await family('InstrumentSerif', ['assets/fonts/InstrumentSerif-Regular.ttf']);
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
  final icons = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (icons.existsSync()) await family('MaterialIcons', [icons.path]);
}

/// Pumps the Feed tab on [phone] holding [scene], in light or dark, at
/// [textScale], the game liked by [likes]; with [play] it lets the game play
/// into its middlegame first (twelve seconds of frames), so the chart has a
/// cursor.
Future<void> pumpFeedShell(
  WidgetTester tester, {
  required FeedShellScene scene,
  required FeedPhone phone,
  bool light = false,
  double textScale = 1,
  int likes = 128,
  bool play = true,
  Key? captureKey,
}) async {
  final device = phone;
  tester.view
    ..physicalSize = device.size * 3
    ..devicePixelRatio = 3
    ..padding = FakeViewPadding(top: device.top * 3, bottom: device.bottom * 3)
    ..viewPadding = FakeViewPadding(
      top: device.top * 3,
      bottom: device.bottom * 3,
    );
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  final entries = <FeedEntry>[
    switch (scene) {
      FeedShellScene.game ||
      FeedShellScene.skeleton => FeedGameEntry(feedOperaGame(likes: likes)),
      FeedShellScene.puzzle => const FeedPuzzleEntry(
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
      FeedShellScene.news => FeedNewsEntry(
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
    },
    FeedGameEntry(feedOperaGame(id: 'next')),
  ];
  final sfx = _SilentSfx();

  await tester.pumpWidget(
    RepaintBoundary(
      key: captureKey,
      child: ProviderScope(
        overrides: [
          feedProvider.overrideWith(
            () => scene == FeedShellScene.skeleton
                ? _LoadingFeed()
                : _FakeFeed(entries),
          ),
          feedEntriesProvider.overrideWith(
            () => _FixedEntries(
              scene == FeedShellScene.skeleton ? const <FeedEntry>[] : entries,
            ),
          ),
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
          profileAvatarUrlProvider.overrideWithValue(null),
          inboxHasUnreadProvider.overrideWithValue(false),
          botvinnikTabAvailableProvider.overrideWithValue(true),
          selectedBottomNavBarItemProvider.overrideWith(
            (ref) => BottomNavBarItem.feed,
          ),
          subscriptionProvider.overrideWith((ref) => _FreeSubscription()),
          engineSettingsProviderNew.overrideWith(_Settings.new),
          eventNoSpoilersProvider.overrideWith(_MemoryNoSpoilers.new),
          feedCachedEvalProvider.overrideWith((ref, fen) async => null),
          feedEngineProvider.overrideWithValue(_NoEngine()),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: (light ? AppTheme.lightTheme : AppTheme.darkTheme).copyWith(
            platform: device.ios ? TargetPlatform.iOS : TargetPlatform.android,
          ),
          navigatorObservers: [routeObserver],
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return const _Shell();
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  if (!play) return;
  // The game plays into its middlegame, so the chart has a cursor and the
  // board a position worth seeing.
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  await settleFeedImages(tester);
}

/// Decodes every image and loads every SVG on screen, then repaints.
Future<void> settleFeedImages(WidgetTester tester) async {
  for (var pass = 0; pass < 3; pass++) {
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        final image = element.widget as Image;
        try {
          await precacheImage(image.image, element);
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// The home shell's composition for Feed: the real dock over a page that
/// runs under its slot, the region paging the bars.
class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with SingleTickerProviderStateMixin {
  late final ScrollChromeController chrome = ScrollChromeController(
    vsync: this,
  );

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
      bottomNavigationBar: HomeNavDock(chrome: chrome, scrim: false),
      body: HomeNavScope(
        metrics: HomeNavMetrics.of(context, count: 5),
        child: ScrollChromeRegion(
          controller: chrome,
          paged: true,
          child: const FeedScreen(embedded: true),
        ),
      ),
    );
  }
}

/// Morphy's Opera Game, with a made-up evaluation curve that climbs to the
/// mate, liked by enough readers to show the count.
FeedItem feedOperaGame({String id = 'opera', int likes = 128}) {
  const pgn =
      '1. e4 e5 2. Nf3 d6 3. d4 Bg4 4. dxe5 Bxf3 5. Qxf3 dxe5 6. Bc4 Nf6 '
      '7. Qb3 Qe7 8. Nc3 c6 9. Bg5 b5 10. Nxb5 cxb5 11. Bxb5+ Nbd7 '
      '12. O-O-O Rd8 13. Rxd7 Rxd7 14. Rd1 Qe6 15. Bxd7+ Nxd7 16. Qb8+ Nxb8 '
      '17. Rd8# 1-0';
  const curve = [
    20, 35, 30, 60, 45, 110, 90, 140, 120, 115, 170, 150, 210, 160, //
    260, 230, 120, 180, 150, 240, 380, 300, 340, 420, 380, 520, 470, //
    560, 640, 600, 760, 900, 1000,
  ];
  final parsed = PgnGame.parsePgn(pgn);
  Position position = PgnGame.startingPosition(parsed.headers);
  final plies = <FeedPly>[FeedPly(fen: position.fen, cp: 20)];
  var i = 0;
  for (final node in parsed.moves.mainline()) {
    final move = position.parseSan(node.san)!;
    position = position.play(move);
    plies.add(
      FeedPly(
        fen: position.fen,
        san: node.san,
        uci: move.uci,
        cp: curve[i.clamp(0, curve.length - 1)],
      ),
    );
    i++;
  }
  PlayerCard player(String name, String federation, int rating) => PlayerCard(
    name: name,
    federation: federation,
    title: 'GM',
    rating: rating,
    countryCode: federation,
    team: null,
  );
  return FeedItem(
    game: GamesTourModel(
      gameId: id,
      whitePlayer: player('Carlsen, Magnus', 'NOR', 2830),
      blackPlayer: player('Nakamura, Hikaru', 'USA', 2802),
      whiteTimeDisplay: '--:--',
      blackTimeDisplay: '--:--',
      whiteClockCentiseconds: 0,
      blackClockCentiseconds: 0,
      gameStatus: GameStatus.whiteWins,
      roundId: 'round-1',
      tourId: 'tour-1',
      pgn: pgn,
      fen: plies.last.fen,
      eco: 'C41',
      openingName: 'Philidor Defense',
      timeControl: 'classical',
    ),
    plies: plies,
    reason: '',
    eventLabel: 'Tata Steel Masters 2026',
    result: '1-0',
    hasEvals: true,
    likes: likes,
    signal: const FeedSignal(FeedSignalKind.favorite, name: 'Magnus Carlsen'),
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

  @override
  Future<void> refresh() async {}
}

/// A first load that never lands: the page holds its skeleton.
class _LoadingFeed extends FeedNotifier {
  final Completer<List<FeedItem>> _never = Completer<List<FeedItem>>();

  @override
  Future<List<FeedItem>> build() => _never.future;

  @override
  Future<void> loadMore() async {}

  @override
  void onVisible(int index) {}

  @override
  Future<void> refresh() async {}
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

/// Silent: every sound call lands in [noSuchMethod].
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
