// Renders the Today collection stories to PNGs for review: the Today row
// (unseen circles first, watched ones grey, the Missed chances mark), and
// the viewer on a commented position, a classified blunder, a position
// asking for the move, the move found, a missed chance asking for the win,
// the actions under a story, the end card once everything is watched, and
// a phone on its side; then Settings › Customization with the Collection
// stories choice. Light and dark, at a 393x852 phone view, 3x.
//
//   flutter test --no-pub test/collection_stories_preview_test.dart \
//     --dart-define=STORIES_DIR=/tmp/stories_v3/out
//
// Covers are read from STORIES_COVERS (default /tmp/stories/covers_full,
// u1.png ... u9.png: real collection covers); a missing file falls back to
// the app's own artwork. Without STORIES_DIR the scenes still run, as a
// smoke test, and write nothing.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessever2/chat/botvinnik_provider.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/auto_pin_preferences_provider.dart';
import 'package:chessever2/providers/board_engine_lines_visibility_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/engine_settings_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/providers/notification_permission_provider.dart';
import 'package:chessever2/providers/notification_preferences_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/local_storage/auto_pin_preferences/auto_pin_preferences_repository.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/group_event/widget/premium_collection_cards.dart';
import 'package:chessever2/screens/settings/settings_page.dart';
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:chessever2/screens/stories/story_pages.dart';
import 'package:chessever2/screens/stories/story_row.dart';
import 'package:chessever2/screens/stories/story_row_prefs.dart';
import 'package:chessever2/screens/stories/story_seen_store.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/adaptive_window.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessground/chessground.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _outDir = String.fromEnvironment('STORIES_DIR');
const _coverDir = String.fromEnvironment(
  'STORIES_COVERS',
  defaultValue: '/tmp/stories/covers_full',
);

const _capture = ValueKey('stories_capture');

// --------------------------------------------------------------- catalog

Collection _collection(
  String slug,
  CollectionKind kind,
  String title, {
  required int games,
  String? author,
  String? location,
  int? year,
  int hoursAgo = 0,
}) => Collection(
  id: slug,
  slug: slug,
  kind: kind,
  title: title,
  author: author,
  location: location,
  publishedYear: year,
  gameCount: games,
  contentVersion: 'v-$slug',
  updatedAt: _now.subtract(Duration(hours: 2 + hoursAgo)),
  access: CollectionAccess.free,
);

final _now = DateTime(2026, 11, 21, 10);

final _catalog = [
  _collection(
    'us-championship-2026',
    CollectionKind.event,
    'U.S. Championship 2026',
    hoursAgo: 3,
    games: 66,
    location: 'Saint Louis',
    year: 2026,
  ),
  _collection(
    'exchange-sacrifice-2',
    CollectionKind.book,
    'Exchange Sacrifice in Openings, Vol. 2',
    hoursAgo: 6,
    games: 48,
    author: 'Sarhan Guliev',
  ),
  _collection(
    '60-instructive-wins',
    CollectionKind.book,
    '60 Instructive Wins',
    hoursAgo: 9,
    games: 60,
    author: 'Ulvi Bajarani, Ilgar Bajarani',
  ),
  _collection(
    'neiksans-annotated',
    CollectionKind.analysis,
    'GM Neiksans Annotated Games',
    hoursAgo: 12,
    games: 24,
    author: 'GM Arturs Neiksans',
  ),
  _collection(
    'fide-candidates-2026',
    CollectionKind.event,
    'FIDE Candidates 2026',
    hoursAgo: 15,
    games: 56,
    location: 'Cyprus',
    year: 2026,
  ),
  _collection(
    'exchange-sacrifice-1',
    CollectionKind.book,
    'Exchange Sacrifice in Openings, Vol. 1',
    hoursAgo: 18,
    games: 51,
    author: 'Sarhan Guliev',
  ),
  _collection(
    'jayaram-annotated',
    CollectionKind.analysis,
    'GM Jayaram Annotated Games',
    hoursAgo: 21,
    games: 18,
    author: 'GM Jayaram',
  ),
  _collection(
    '2021-in-52-games',
    CollectionKind.book,
    '2021 in 52 Games',
    hoursAgo: 24,
    games: 52,
    author: 'GM Vasif Durarbayli',
  ),
  _collection(
    '2022-in-53-games',
    CollectionKind.book,
    '2022 in 53 Games',
    hoursAgo: 27,
    games: 53,
    author: 'GM Ulvi Bajarani',
  ),
];

/// The cover files of [_coverDir], by slug.
const _coverFiles = {
  'us-championship-2026': 'u1.png',
  'exchange-sacrifice-2': 'u2.png',
  'exchange-sacrifice-1': 'u3.png',
  'neiksans-annotated': 'u4.png',
  'jayaram-annotated': 'u5.png',
  'fide-candidates-2026': 'u6.png',
  '2021-in-52-games': 'u7.png',
  '2022-in-53-games': 'u8.png',
  '60-instructive-wins': 'u9.png',
};

const _fallbackArt = [
  'assets/pngs/hub_feed_editorial.webp',
  'assets/pngs/hub_library_editorial.webp',
  'assets/pngs/hub_miniatures_editorial.webp',
  'assets/pngs/hub_reports_editorial.webp',
];

final Map<String, ImageProvider> _covers = {
  for (final (i, c) in _catalog.indexed)
    c.slug: () {
      final file = File('$_coverDir/${_coverFiles[c.slug]}');
      return file.existsSync()
          ? MemoryImage(file.readAsBytesSync()) as ImageProvider
          : AssetImage(_fallbackArt[i % _fallbackArt.length]);
    }(),
};

// ----------------------------------------------------------------- games

CollectionPlayerSide _side(
  String name,
  String fed, {
  String title = '',
  int? elo,
}) => CollectionPlayerSide(
  name: name,
  key: 'name:${name.toLowerCase()}',
  fed: fed,
  title: title.isEmpty ? null : title,
  elo: elo,
);

CollectionGame _card(
  String id, {
  required CollectionPlayerSide white,
  required CollectionPlayerSide black,
  required String result,
  required String event,
  String? eco,
  String? opening,
}) => CollectionGame.fromPreviewCard(
  CollectionGameCard(
    id: id,
    white: white,
    black: black,
    result: result,
    event: event,
    eco: eco,
    opening: opening,
  ),
)!;

/// The Opera game as a book annotates it: arrows, marked squares, glyphs,
/// and words on the moments that matter.
const _operaPgn = '''[Event "Paris Opera 1858"]
[White "Morphy, Paul"]
[Black "Duke Karl, Count Isouard"]
[Result "1-0"]

1. e4 e5 2. Nf3 d6 3. d4 Bg4 4. dxe5 Bxf3 5. Qxf3 dxe5 6. Bc4 Nf6 7. Qb3 { [%clk 0:58:10] [%cal Gb3f7,Gb3b7] The queen eyes f7 and b7 at once, and Black has no single move that covers both. } 7... Qe7 8. Nc3 c6 9. Bg5 b5?! 10. Nxb5! { [%csl Gb5] White gives the knight to open lines toward the king, two pieces ahead in development. } 10... cxb5 11. Bxb5+ Nbd7 12. O-O-O Rd8 13. Rxd7! { [%cal Gd1d8] The exchange goes back, and with it the last of the defenders. With his bishop and his rook on d1 both pointing at the black king, every white piece joins the attack, while the queen on e7 and the knight on f6 stand too far away to help in time. } 13... Rxd7 14. Rd1 Qe6 15. Bxd7+ Nxd7 16. Qb8+!! { [%cal Gb8d8,Gd1d8] [%csl Rd8] The queen is given so the rook can mate on d8. } 16... Nxb8 17. Rd8# 1-0''';

/// A report from a broadcast: an evaluation on every move, the verdicts,
/// and the engine line beside the missed win.
const _reportPgn = '''[Event "Round 5: Firouzja - Caruana"]
[BroadcastName "Sinquefield Cup 2026"]
[White "Firouzja, Alireza"]
[Black "Caruana, Fabiano"]
[Result "1/2-1/2"]

1. e4 \$247 { [%eval 0.2] } 1... e5 \$247 { [%eval 0.2] } 2. Bc4 { [%eval 0.1] } 2... Nc6 { [%eval 0.1] } 3. Qh5 { [%eval 0.0] } 3... Nf6 \$4 \$246 { [%eval #1] } ( 3... g6 4. Qf3 Nf6 ) 4. Qf3 \$4 \$243 { [%eval 0.1] } ( 4. Qxf7# ) 4... Be7 { [%eval 0.1] } 5. Ne2 { [%eval 0.0] } 5... d6 { [%eval 0.1] } 1/2-1/2''';

final _morphy = _side('Morphy, Paul', 'USA');
final _duke = _side('Duke Karl, Count Isouard', 'FRA');
final _firouzja = _side('Firouzja, Alireza', 'FRA', title: 'GM', elo: 2766);
final _caruana = _side('Caruana, Fabiano', 'USA', title: 'GM', elo: 2795);

StoryGame _opera(String id) => buildStoryGame(
  _card(
    id,
    white: _morphy,
    black: _duke,
    result: '1-0',
    event: 'Paris Opera 1858',
    eco: 'C41',
    opening: 'Philidor Defence',
  ),
  pgn: _operaPgn,
);

/// The report game as a collection story: the blunder, then the missed win.
StoryGame _report(String id) => buildStoryGame(
  _card(
    id,
    white: _firouzja,
    black: _caruana,
    result: '1/2-1/2',
    event: 'Sinquefield Cup 2026',
    eco: 'C23',
    opening: "Bishop's Opening",
  ),
  pgn: _reportPgn,
);

StoryBatch _batchOf(String slug) {
  final collection = _catalog.firstWhere((c) => c.slug == slug);
  final stories = switch (slug) {
    'us-championship-2026' => [_report('r0'), _opera('o1')],
    _ => [_opera('o0'), _report('r1')],
  };
  return StoryBatch(
    games: stories,
    ordered: [for (final s in stories) s.game],
    gameCount: collection.gameCount,
    signature: storySignature(collection),
  );
}

StoryBatch _missedBatch() {
  final game = _card(
    'm0',
    white: _firouzja,
    black: _caruana,
    result: '1/2-1/2',
    event: 'Sinquefield Cup 2026',
  ).game;
  final segments = pickMissedChanceSegments(parseStoryPgn(_reportPgn)!);
  return StoryBatch(
    games: [
      StoryGame(
        game: game,
        segments: segments,
        caption: 'Sinquefield Cup 2026 · Round 5',
      ),
    ],
    ordered: [game],
    signature: 'v:missed:2026-11-21',
  );
}

// ---------------------------------------------------------------- harness

class _RowStore implements StoryRowPrefsStore {
  String? local;

  @override
  String? readLocal() => local;

  @override
  Future<void> writeLocal(String value) async => local = value;

  @override
  Future<Map<String, dynamic>?> readAccount() async => null;

  @override
  String? accountId() => null;

  @override
  Future<void> writeAccount(Map<String, Object?> value) async {}

  @override
  Stream<void> accountChanges() => const Stream.empty();
}

class _MemoryStorage implements StorySeenStorage {
  _MemoryStorage(this.value);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async => this.value = value;
}

class _Board extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _NoFavorites extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => const [];
}

class _Country extends StateNotifier<AsyncValue<Country>>
    implements SelectedCountryNotifier {
  _Country() : super(AsyncValue.data(Country.parse('NO')));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The seen record the scenes start from: three collections new, the rest
/// watched (they follow the new ones, in quiet rings), and the first
/// The device's seen record: the collections the reader caught up with
/// (every one with [allWatched]).
String _seen({bool allWatched = false}) {
  final watched = {
    'neiksans-annotated',
    'fide-candidates-2026',
    'exchange-sacrifice-1',
    'jayaram-annotated',
    '2021-in-52-games',
  };
  return jsonEncode({
    'v': 3,
    'c': {
      for (final c in _catalog)
        if (allWatched || watched.contains(c.slug))
          c.slug: StorySeen(
            ids: [for (final g in _batchOf(c.slug).games) g.id],
            signature: storySignature(c),
            caught: true,
          ).toJson(),
      if (allWatched)
        kMissedChancesSlug: StorySeen(
          ids: [for (final g in _missedBatch().games) g.id],
          signature: 'v:missed:2026-11-21',
          caught: true,
        ).toJson(),
    },
  });
}

Future<ProviderContainer> _pumpToday(
  WidgetTester tester, {
  required bool light,
  bool landscape = false,
  bool allWatched = false,
}) async {
  tester.view.devicePixelRatio = 3;
  if (landscape) {
    // An iPhone on its side: the notch at the left, the home bar below.
    tester.view.physicalSize = const Size(852 * 3, 393 * 3);
    tester.view.padding = const FakeViewPadding(
      left: 59 * 3,
      right: 59 * 3,
      bottom: 21 * 3,
    );
    tester.view.viewPadding = const FakeViewPadding(
      left: 59 * 3,
      right: 59 * 3,
      bottom: 21 * 3,
    );
  } else {
    tester.view.physicalSize = const Size(393 * 3, 852 * 3);
    tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
    tester.view.viewPadding = const FakeViewPadding(
      top: 59 * 3,
      bottom: 34 * 3,
    );
  }
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      storyCollectionsProvider.overrideWith((ref) async => _catalog),
      storyBatchProvider.overrideWith(
        (ref, slug) async =>
            slug == kMissedChancesSlug ? _missedBatch() : _batchOf(slug),
      ),
      storySeenStorageProvider.overrideWithValue(
        _MemoryStorage(_seen(allWatched: allWatched)),
      ),
      storyClockProvider.overrideWithValue(() => _now),
      storyRowPrefsStoreProvider.overrideWithValue(_RowStore()),
      storyCoverOverrideProvider.overrideWithValue((c) => _covers[c.slug]),
      boardSettingsProviderNew.overrideWith(_Board.new),
      favoritePlayersProviderNew.overrideWith(_NoFavorites.new),
      countryDropdownProvider.overrideWith((ref) => _Country()),
      currentUserProvider.overrideWithValue(null),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _capture,
      child: UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: ListView(
                  padding: EdgeInsets.only(
                    top: MediaQuery.paddingOf(context).top + 16,
                  ),
                  children: const [
                    TodayStoryRow(gutter: 16),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: PremiumCollectionCards(),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await _precache(tester);
  return container;
}

/// Decodes every picture on screen (covers, tile art, pieces) for real, so
/// the frame drawn is the finished one.
Future<void> _precache(WidgetTester tester) async {
  await tester.runAsync(() async {
    await ChessgroundImages.instance.loadAll(
      const BoardSettingsNew().pieceAssets,
      devicePixelRatio: 3,
    );
    final context = tester.element(find.byType(Scaffold).first);
    for (final image in _covers.values) {
      await precacheImage(image, context);
    }
    for (final widget in tester.widgetList<Image>(find.byType(Image))) {
      await precacheImage(widget.image, context);
    }
  });
  await tester.pump();
}

Future<void> _shot(WidgetTester tester, String name, bool light) async {
  expect(tester.takeException(), isNull);
  if (_outDir.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_capture),
    );
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(_outDir).create(recursive: true);
    await File(
      '$_outDir/${name}_${light ? 'light' : 'dark'}.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<void> _run(WidgetTester tester, Duration duration) async {
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(duration);
}

Finder _circle(String slug) => find.byKey(ValueKey('story_circle_$slug'));

/// Taps the story beside its position (between the header and the board),
/// at a share of the width: the next position, or the previous one.
Future<void> _tapAside(WidgetTester tester, double share) async {
  final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
  final header = tester.getRect(find.byKey(const ValueKey('story_close')));
  final frame = tester.getRect(find.byType(StoryFrameView));
  await tester.tapAt(Offset(width * share, (header.bottom + frame.top) / 2));
  await tester.pump();
}

/// Opens [slug]'s stories and lets the surface settle.
Future<void> _open(WidgetTester tester, String slug) async {
  await tester.tap(_circle(slug));
  await tester.pump();
  await _run(tester, const Duration(milliseconds: 800));
  await tester.pump(const Duration(milliseconds: 16));
  await _precache(tester);
}

/// Plays [duration] frame by frame, as a phone would, so the board's
/// pieces slide.
Future<void> _play(WidgetTester tester, Duration duration) async {
  const frame = Duration(milliseconds: 40);
  var left = duration;
  while (left > Duration.zero) {
    final step = left < frame ? left : frame;
    await tester.pump(step);
    left -= step;
  }
}

// ------------------------------------------------------------- settings

class _Engine extends EngineSettingsNotifierNew {
  @override
  Future<EngineSettings> build() async => const EngineSettings();
}

class _BoardLinesVisibility extends BoardEngineLinesVisibleNotifier {
  @override
  Future<bool> build() async => true;
}

class _Notifications extends NotificationPreferencesNotifier {
  @override
  Future<NotificationPreferences> build() async =>
      NotificationPreferences.defaults;
}

class _Permission extends StateNotifier<AsyncValue<bool>>
    implements NotificationPermissionNotifier {
  _Permission() : super(const AsyncData(false));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription() : super(SubscriptionState(isSubscribed: true));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _AutoPin extends AutoPinPreferencesNotifier {
  @override
  Future<AutoPinPreferences> build() async => AutoPinPreferences.defaults;
}

class _Botvinnik extends BotvinnikEnabledNotifier {
  @override
  Future<bool> build() async => true;
}

/// Settings opened on Customization, as the reader finds it.
Future<void> _pumpSettings(WidgetTester tester, {required bool light}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  tester.view.viewPadding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      boardSettingsProviderNew.overrideWith(_Board.new),
      engineSettingsProviderNew.overrideWith(_Engine.new),
      boardEngineLinesVisibleProvider.overrideWith(_BoardLinesVisibility.new),
      notificationPreferencesProvider.overrideWith(_Notifications.new),
      notificationPermissionProvider.overrideWith((_) => _Permission()),
      subscriptionProvider.overrideWith((_) => _Subscription()),
      autoPinPreferencesProvider.overrideWith(_AutoPin.new),
      botvinnikEnabledProvider.overrideWith(_Botvinnik.new),
      storyRowPrefsStoreProvider.overrideWithValue(_RowStore()),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _capture,
      child: UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
          builder: (_, child) => AdaptiveWindowScope(child: child!),
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return const SettingsPage(
                initiallyExpanded: SettingsSection.customization,
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    Future<void> family(String name, List<String> files) async {
      final loader = FontLoader(name);
      for (final file in files) {
        loader.addFont(File(file).readAsBytes().then(ByteData.sublistView));
      }
      await loader.load();
    }

    final inter = [
      for (final weight in ['Regular', 'Medium', 'Bold'])
        'assets/fonts/Inter-$weight.otf',
    ];
    await family('InterDisplay', inter);
    await family('Inter', inter);
    final flutterRoot =
        Platform.environment['FLUTTER_ROOT'] ??
        File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
    final icons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) await family('MaterialIcons', [icons.path]);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SharedPreferencesService.instance.ensureInitialized();
  });

  for (final light in [false, true]) {
    final theme = light ? 'light' : 'dark';

    testWidgets('Today row: unseen first, watched grey, Missed chances, '
        '$theme', (tester) async {
      await _pumpToday(tester, light: light);
      expect(_circle(kMissedChancesSlug), findsOneWidget);
      await _shot(tester, '01_today_row', light);
    });

    testWidgets('a commented position, $theme', (tester) async {
      await _pumpToday(tester, light: light);
      await _open(tester, 'exchange-sacrifice-2');
      await _play(tester, const Duration(milliseconds: 900));
      expect(find.byKey(const ValueKey('story_comment')), findsOneWidget);
      await _shot(tester, '02_commented_position', light);
      // The same frame is the actions' scene.
      expect(find.byKey(const ValueKey('story_open_game')), findsOneWidget);
      await _shot(tester, '07_bottom_actions', light);
    });

    testWidgets('a classified blunder, $theme', (tester) async {
      await _pumpToday(tester, light: light);
      await _open(tester, 'us-championship-2026');
      await _play(tester, const Duration(milliseconds: 900));
      expect(find.text('Blunder'), findsOneWidget);
      await _shot(tester, '03_blunder_position', light);
    });

    testWidgets('a position asking for the move, then found, $theme', (
      tester,
    ) async {
      await _pumpToday(tester, light: light);
      await _open(tester, 'exchange-sacrifice-2');
      // To the third position: 13. Rxd7! asks.
      await _tapAside(tester, 0.8);
      await _play(tester, const Duration(milliseconds: 300));
      await _tapAside(tester, 0.8);
      await _play(tester, const Duration(milliseconds: 600));
      await _precache(tester);
      expect(find.byKey(const ValueKey('story_prompt')), findsOneWidget);
      await _shot(tester, '04_puzzle_prompt', light);
      final board = tester.getRect(
        find.byKey(const ValueKey('story_puzzle_board')),
      );
      Offset at(int file, int rank) => Offset(
        board.left + (file + 0.5) * board.width / 8,
        board.top + (7 - rank + 0.5) * board.width / 8,
      );
      // The rook takes on d7.
      await tester.tapAt(at(3, 0));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(at(3, 6));
      await _play(tester, const Duration(milliseconds: 700));
      expect(find.textContaining('Found it'), findsOneWidget);
      await _shot(tester, '05_puzzle_solved', light);
    });

    testWidgets('a missed chance asking for the win, $theme', (tester) async {
      await _pumpToday(tester, light: light);
      await _open(tester, kMissedChancesSlug);
      await _play(tester, const Duration(milliseconds: 600));
      await _precache(tester);
      expect(find.text('White missed a win here'), findsOneWidget);
      await _shot(tester, '06_missed_chance_prompt', light);
    });

    testWidgets('all caught up, $theme', (tester) async {
      await _pumpToday(tester, light: light);
      // Everything else watched: the last story ends on the card.
      await tester.pumpWidget(const SizedBox());
      await _pumpToday(tester, light: light, allWatched: true);
      await _shot(tester, '09_today_row_all_watched', light);
      // The row's last circle: the 2022 book is the ninth by its update,
      // past the row's eight.
      final row = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(TodayStoryRow),
          matching: find.byType(Scrollable),
        ),
      );
      row.position.jumpTo(row.position.maxScrollExtent);
      await tester.pump();
      expect(_circle('2022-in-53-games'), findsNothing);
      await _open(tester, '2021-in-52-games');
      // Through the last circle's pages.
      for (var i = 0; i < 12; i++) {
        if (find
            .byKey(const ValueKey('story_caught_up'))
            .evaluate()
            .isNotEmpty) {
          break;
        }
        await _tapAside(tester, 0.8);
        await _play(tester, const Duration(milliseconds: 400));
        if (find
            .byKey(const ValueKey('story_show_answer'))
            .evaluate()
            .isNotEmpty) {
          await tester.tap(find.byKey(const ValueKey('story_show_answer')));
          await _play(tester, const Duration(milliseconds: 400));
        }
      }
      expect(find.byKey(const ValueKey('story_caught_up')), findsOneWidget);
      await _shot(tester, '08_all_caught_up', light);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a phone on its side, $theme', (tester) async {
      await _pumpToday(tester, light: light, landscape: true);
      await _open(tester, 'exchange-sacrifice-2');
      await _play(tester, const Duration(milliseconds: 900));
      await _shot(tester, '10_landscape', light);
    });

    testWidgets('Settings, Customization, $theme', (tester) async {
      await _pumpSettings(tester, light: light);
      expect(find.text('Collection stories'), findsOneWidget);
      await _shot(tester, '11_settings_customization', light);
      await tester.tap(find.text('Collection stories'));
      await tester.pumpAndSettle();
      await _shot(tester, '12_settings_story_choice', light);
    });
  }
}
