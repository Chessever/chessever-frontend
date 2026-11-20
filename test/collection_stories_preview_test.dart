// Renders the Today collection stories to PNGs for review: the Today top
// with its story row, and the viewer mid-story, at a story's end, mid open,
// mid cube turn, mid drag down, on its See all story and on a phone turned
// on its side, in light and dark, at a 393x852 phone view (852x393 on its
// side), 3x.
//
//   flutter test --no-pub test/collection_stories_preview_test.dart \
//     --dart-define=STORIES_DIR=/tmp/stories/out
//
// Covers are read from STORIES_COVERS (default /tmp/stories/covers_full,
// u1.png ... u9.png: real collection covers); a missing file falls back to
// the app's own artwork. Without STORIES_DIR the scenes still run, as a
// smoke test, and write nothing.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/group_event/widget/premium_collection_cards.dart';
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:chessever2/screens/stories/story_row.dart';
import 'package:chessever2/screens/stories/story_seen_store.dart';
import 'package:chessever2/theme/app_theme.dart';
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
}) => Collection(
  id: slug,
  slug: slug,
  kind: kind,
  title: title,
  author: author,
  location: location,
  publishedYear: year,
  gameCount: games,
  access: CollectionAccess.free,
);

final _catalog = [
  _collection(
    'us-championship-2026',
    CollectionKind.event,
    'U.S. Championship 2026',
    games: 66,
    location: 'Saint Louis',
    year: 2026,
  ),
  _collection(
    'exchange-sacrifice-2',
    CollectionKind.book,
    'Exchange Sacrifice in Openings, Vol. 2',
    games: 48,
    author: 'Sarhan Guliev',
  ),
  _collection(
    '60-instructive-wins',
    CollectionKind.book,
    '60 Instructive Wins',
    games: 60,
    author: 'Ulvi Bajarani, Ilgar Bajarani',
  ),
  _collection(
    'neiksans-annotated',
    CollectionKind.analysis,
    'GM Neiksans Annotated Games',
    games: 24,
    author: 'GM Arturs Neiksans',
  ),
  _collection(
    'fide-candidates-2026',
    CollectionKind.event,
    'FIDE Candidates 2026',
    games: 56,
    location: 'Cyprus',
    year: 2026,
  ),
  _collection(
    'exchange-sacrifice-1',
    CollectionKind.book,
    'Exchange Sacrifice in Openings, Vol. 1',
    games: 51,
    author: 'Sarhan Guliev',
  ),
  _collection(
    'jayaram-annotated',
    CollectionKind.analysis,
    'GM Jayaram Annotated Games',
    games: 18,
    author: 'GM Jayaram',
  ),
  _collection(
    '2021-in-52-games',
    CollectionKind.book,
    '2021 in 52 Games',
    games: 52,
    author: 'GM Vasif Durarbayli',
  ),
  _collection(
    '2022-in-53-games',
    CollectionKind.book,
    '2022 in 53 Games',
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

StoryGame _game(
  String id, {
  required CollectionPlayerSide white,
  required CollectionPlayerSide black,
  required String result,
  required String event,
  required String eco,
  required String opening,
  required String moves,
}) {
  final pgn =
      '[Event "$event"]\n[White "${white.name}"]\n[Black "${black.name}"]\n'
      '[Result "$result"]\n[ECO "$eco"]\n\n$moves $result';
  final game = CollectionGame.fromPreviewCard(
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
  return buildStoryGame(game, pgn: pgn);
}

final _opera = _game(
  'opera',
  white: _side('Morphy, Paul', 'USA'),
  black: _side('Duke Karl, Count Isouard', 'FRA'),
  result: '1-0',
  event: 'Paris Opera 1858',
  eco: 'C41',
  opening: 'Philidor Defence',
  moves:
      '1. e4 e5 2. Nf3 d6 3. d4 Bg4 4. dxe5 Bxf3 5. Qxf3 dxe5 6. Bc4 Nf6 '
      '7. Qb3 Qe7 8. Nc3 c6 9. Bg5 b5 10. Nxb5 cxb5 11. Bxb5+ Nbd7 '
      '12. O-O-O Rd8 13. Rxd7 Rxd7 14. Rd1 Qe6 15. Bxd7+ Nxd7 16. Qb8+ Nxb8 '
      '17. Rd8#',
);

final _century = _game(
  'century',
  white: _side('Byrne, Donald', 'USA', title: 'IM'),
  black: _side('Fischer, Robert James', 'USA'),
  result: '0-1',
  event: 'Rosenwald Memorial, New York 1956',
  eco: 'D92',
  opening: 'Grünfeld Defence',
  moves:
      '1. Nf3 Nf6 2. c4 g6 3. Nc3 Bg7 4. d4 O-O 5. Bf4 d5 6. Qb3 dxc4 '
      '7. Qxc4 c6 8. e4 Nbd7 9. Rd1 Nb6 10. Qc5 Bg4 11. Bg5 Na4 12. Qa3 Nxc3 '
      '13. bxc3 Nxe4 14. Bxe7 Qb6 15. Bc4 Nxc3 16. Bc5 Rfe8+ 17. Kf1 Be6 '
      '18. Bxb6 Bxc4+ 19. Kg1 Ne2+ 20. Kf1 Nxd4+ 21. Kg1 Ne2+ 22. Kf1 Nc3+ '
      '23. Kg1 axb6 24. Qb4 Ra4 25. Qxb6 Nxd1 26. h3 Rxa2 27. Kh2 Nxf2 '
      '28. Re1 Rxe1 29. Qd8+ Bf8 30. Nxe1 Bd5 31. Nf3 Ne4 32. Qb8 b5 33. h4 h5 '
      '34. Ne5 Kg7 35. Kg1 Bc5+ 36. Kf1 Ng3+ 37. Ke1 Bb4+ 38. Kd1 Bb3+ '
      '39. Kc1 Ne2+ 40. Kb1 Nc3+ 41. Kc1 Rc2#',
);

final _immortal = _game(
  'kasparov-topalov',
  white: _side('Kasparov, Garry', 'RUS', title: 'GM', elo: 2812),
  black: _side('Topalov, Veselin', 'BUL', title: 'GM', elo: 2700),
  result: '1-0',
  event: 'Hoogovens, Wijk aan Zee 1999',
  eco: 'B07',
  opening: 'Pirc Defence',
  moves:
      '1. e4 d6 2. d4 Nf6 3. Nc3 g6 4. Be3 Bg7 5. Qd2 c6 6. f3 b5 7. Nge2 Nbd7 '
      '8. Bh6 Bxh6 9. Qxh6 Bb7 10. a3 e5 11. O-O-O Qe7 12. Kb1 a6 13. Nc1 '
      'O-O-O 14. Nb3 exd4 15. Rxd4 c5 16. Rd1 Nb6 17. g3 Kb8 18. Na5 Ba8 '
      '19. Bh3 d5 20. Qf4+ Ka7 21. Rhe1 d4 22. Nd5 Nbxd5 23. exd5 Qd6 '
      '24. Rxd4 cxd4 25. Re7+ Kb6 26. Qxd4+ Kxa5 27. b4+ Ka4 28. Qc3 Qxd5 '
      '29. Ra7 Bb7 30. Rxb7 Qc4 31. Qxf6 Kxa3 32. Qxa6+ Kxb4 33. c3+ Kxc3 '
      '34. Qa1+ Kd2 35. Qb2+ Kd1 36. Bf1 Rd2 37. Rd7 Rxd7 38. Bxc4 bxc4 '
      '39. Qxh8 Rd3 40. Qa8 c3 41. Qa4+ Ke1 42. f4 f5 43. Kc1 Rd2 44. Qa7',
);

final _reti = _game(
  'reti-tartakower',
  white: _side('Reti, Richard', 'CZE'),
  black: _side('Tartakower, Savielly', 'POL'),
  result: '1-0',
  event: 'Vienna 1910',
  eco: 'B15',
  opening: 'Caro-Kann Defence',
  moves:
      '1. e4 c6 2. d4 d5 3. Nc3 dxe4 4. Nxe4 Nf6 5. Qd3 e5 6. dxe5 Qa5+ '
      '7. Bd2 Qxe5 8. O-O-O Nxe4 9. Qd8+ Kxd8 10. Bg5+ Kc7 11. Bd8#',
);

StoryBatch _batch(int total) {
  final games = [_opera, _century, _immortal, _reti];
  final stories = [for (var i = 0; i < kStoryCap; i++) games[i % games.length]];
  return StoryBatch(
    games: stories,
    ordered: [for (final s in stories) s.game],
    total: total,
  );
}

// ---------------------------------------------------------------- harness

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
/// watched (they follow the new ones, in quiet rings), and [resume] stories
/// in for the one the viewer opens.
String _seen(Map<String, int> resume) {
  final watched = {
    'neiksans-annotated',
    'fide-candidates-2026',
    'exchange-sacrifice-1',
    'jayaram-annotated',
    '2021-in-52-games',
    '2022-in-53-games',
  };
  final records = <String, Object>{
    for (final c in _catalog)
      if (watched.contains(c.slug))
        c.slug: StorySeen(
          signature: storySignature(c),
          next: 0,
          seen: true,
        ).toJson(),
    // Where the scene opens a collection: stories in, still new.
    for (final MapEntry(:key, :value) in resume.entries)
      key: StorySeen(
        signature: storySignature(_catalog.firstWhere((c) => c.slug == key)),
        next: value,
        seen: false,
      ).toJson(),
  };
  return jsonEncode(records);
}

Future<void> _pumpToday(
  WidgetTester tester, {
  required bool light,
  Map<String, int> resume = const {},
  bool landscape = false,
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
            _batch(_catalog.firstWhere((c) => c.slug == slug).gameCount),
      ),
      storySeenStorageProvider.overrideWithValue(_MemoryStorage(_seen(resume))),
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

/// Opens [slug]'s stories and lets the surface settle.
Future<void> _open(WidgetTester tester, String slug) async {
  await tester.tap(_circle(slug));
  await tester.pump();
  await _run(tester, const Duration(milliseconds: 800));
  await tester.pump(const Duration(milliseconds: 16));
  await _precache(tester);
}

/// Plays [duration] of a story frame by frame, as a phone would, so the
/// board's pieces slide one move at a time.
Future<void> _play(WidgetTester tester, Duration duration) async {
  const frame = Duration(milliseconds: 40);
  var left = duration;
  while (left > Duration.zero) {
    final step = left < frame ? left : frame;
    await tester.pump(step);
    left -= step;
  }
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
  });

  for (final light in [false, true]) {
    final theme = light ? 'light' : 'dark';

    testWidgets('Today top with the story row, $theme', (tester) async {
      await _pumpToday(tester, light: light);
      // The new ones first, in catalog order, then the watched ones.
      final first = tester.getTopLeft(_circle('us-championship-2026')).dx;
      final third = tester.getTopLeft(_circle('60-instructive-wins')).dx;
      final watched = tester.getTopLeft(_circle('neiksans-annotated')).dx;
      expect(first, closeTo(16, 0.01));
      expect(third, greaterThan(first));
      expect(watched, greaterThan(third));
      await _shot(tester, '01_today_row', light);
    });

    testWidgets('mid open transition, $theme', (tester) async {
      await _pumpToday(tester, light: light);
      // Once round, so the board's own pictures are decoded, then again.
      await _open(tester, '60-instructive-wins');
      await tester.tap(find.byKey(const ValueKey('story_close')));
      await tester.pump();
      await _run(tester, const Duration(seconds: 1));
      await tester.pump();
      await tester.tap(_circle('60-instructive-wins'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 85));
      await _shot(tester, '02_open_transition', light);
      await _run(tester, const Duration(seconds: 1));
    });

    testWidgets('viewer mid-story, $theme', (tester) async {
      await _pumpToday(
        tester,
        light: light,
        resume: {'60-instructive-wins': 1},
      );
      await _open(tester, '60-instructive-wins');
      // The Game of the Century, halfway through its finale.
      await _play(tester, kStoryGameDuration * 0.5);
      await _shot(tester, '03_viewer_mid_story', light);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('viewer at a story end, $theme', (tester) async {
      await _pumpToday(
        tester,
        light: light,
        resume: {'60-instructive-wins': 2},
      );
      await _open(tester, '60-instructive-wins');
      // Kasparov's immortal, its last move landed and the result shown.
      await _play(tester, kStoryGameDuration * 0.9);
      // The ending's marks (the fallen king) decode, then land.
      await _precache(tester);
      await _play(tester, kStoryGameDuration * 0.02);
      await _shot(tester, '04_viewer_story_end', light);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('mid cube turn, $theme', (tester) async {
      await _pumpToday(
        tester,
        light: light,
        resume: {'60-instructive-wins': 3},
      );
      await _open(tester, '60-instructive-wins');
      await _play(tester, kStoryGameDuration * 0.4);
      final swipe = await tester.startGesture(const Offset(330, 520));
      for (var i = 0; i < 9; i++) {
        await swipe.moveBy(const Offset(-20, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await _precache(tester);
      await _shot(tester, '05_cube_turn', light);
      await swipe.moveBy(const Offset(-200, 0));
      await swipe.up();
      await _run(tester, const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('mid drag down, $theme', (tester) async {
      await _pumpToday(
        tester,
        light: light,
        resume: {'60-instructive-wins': 2},
      );
      await _open(tester, '60-instructive-wins');
      await _play(tester, kStoryGameDuration * 0.6);
      final drag = await tester.startGesture(const Offset(196, 360));
      for (var i = 0; i < 12; i++) {
        await drag.moveBy(const Offset(0, 18));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await _shot(tester, '06_drag_down', light);
      await drag.moveBy(const Offset(0, -216));
      await tester.pump(const Duration(milliseconds: 16));
      await drag.up();
      await _run(tester, const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('a phone on its side, $theme', (tester) async {
      await _pumpToday(
        tester,
        light: light,
        landscape: true,
        resume: {'us-championship-2026': 1},
      );
      await _open(tester, 'us-championship-2026');
      await _play(tester, kStoryGameDuration * 0.6);
      await _shot(tester, '08_landscape', light);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('See all story, $theme', (tester) async {
      await _pumpToday(
        tester,
        light: light,
        resume: {'60-instructive-wins': kStoryCap},
      );
      await _open(tester, '60-instructive-wins');
      expect(find.text('See all 60 games'), findsOneWidget);
      await tester.pump(kStorySeeAllDuration * 0.35);
      await _shot(tester, '07_see_all', light);
      await tester.pump(const Duration(seconds: 6));
    });
  }
}
