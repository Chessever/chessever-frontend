// Renders, for review: the Today story circles with real collection covers
// (circles_<tag>_*, circles_sheet_<tag>_*), and one Premium book's story as
// a free and as a Premium reader watch it, through the app's own providers
// (free_*, premium_*), light and dark at a 393x852 phone view, 3x.
//
//   flutter test --no-pub test/collection_stories_free_parity_preview_test.dart \
//     --dart-define=PARITY_DIR=/tmp/stories_free_parity \
//     --dart-define=PARITY_TAG=after
//
// Covers are read from STORIES_COVERS (default /tmp/stories/covers_full,
// u1.png ... u9.png); a missing file falls back to the app's own artwork.
// Without PARITY_DIR the scenes still run, as a smoke test, and write
// nothing.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/stories/story_models.dart';
import 'package:chessever2/screens/stories/story_pages.dart'
    show StoryFrameView;
import 'package:chessever2/screens/stories/story_row.dart';
import 'package:chessever2/screens/stories/story_row_prefs.dart';
import 'package:chessever2/screens/stories/story_seen_store.dart';
import 'package:chessever2/screens/tour_detail/games_tour/models/games_tour_model.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'support/memory_story_row_store.dart';
import 'support/story_parity_harness.dart' as parity;

const _outDir = String.fromEnvironment('PARITY_DIR');
const _tag = String.fromEnvironment('PARITY_TAG', defaultValue: 'after');
const _coverDir = String.fromEnvironment(
  'STORIES_COVERS',
  defaultValue: '/tmp/stories/covers_full',
);

const _capture = ValueKey('parity_capture');

final _now = DateTime(2026, 11, 23, 10);

Collection _book(String slug, String title, int i) => Collection(
  id: slug,
  slug: slug,
  kind: CollectionKind.book,
  title: title,
  author: 'Author',
  gameCount: 7,
  contentVersion: 'v-$slug',
  updatedAt: _now.subtract(Duration(hours: 1 + i)),
  access: CollectionAccess.premium,
);

final _circles = [
  _book('botvinnik', 'Complete Botvinnik Repertoire For Black', 0),
  _book('exchange-2', 'Exchange Sacrifice in Openings, Vol. 2', 1),
  _book('neiksans', 'GM Neiksans Annotated Games', 2),
  _book('most-liked', 'Most Liked Games of the Week', 3),
  _book('us-champs', 'U.S. Championships 2026', 4),
  _book('2022-in-53', '2022 in 53 Games', 5),
  _book('exchange-1', 'Exchange Sacrifice in Openings, Vol. 1', 6),
  _book('jayaram', 'GM Jayaram Annotated Games', 7),
  _book('60-wins', '60 Instructive Wins', 8),
];

const _fallbackArt = [
  'assets/pngs/hub_feed_editorial.webp',
  'assets/pngs/hub_library_editorial.webp',
  'assets/pngs/hub_miniatures_editorial.webp',
  'assets/pngs/hub_reports_editorial.webp',
];

final Map<String, ImageProvider> _covers = {
  for (final (i, c) in _circles.indexed)
    c.slug: () {
      final file = File('$_coverDir/u${i + 1}.png');
      return file.existsSync()
          ? MemoryImage(file.readAsBytesSync()) as ImageProvider
          : AssetImage(_fallbackArt[i % _fallbackArt.length]);
    }(),
};

const _stillFen =
    'r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4';

GamesTourModel _preview(String id) => CollectionGame.fromPreviewCard(
  CollectionGameCard(
    id: id,
    white: const CollectionPlayerSide(name: 'White', key: 'name:white'),
    black: const CollectionPlayerSide(name: 'Black', key: 'name:black'),
    result: '1-0',
    finalFen: _stillFen,
  ),
)!.game;

StoryBatch _stillBatch(String slug) {
  final game = _preview('${slug}_g');
  return StoryBatch(
    games: [
      StoryGame(game: game, segments: [StorySegment.still(_stillFen, null)]),
    ],
    ordered: [game],
    total: 1,
    gameCount: 1,
    signature: 'v:$slug',
  );
}

class _MemoryStorage implements StorySeenStorage {
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

Future<void> _shot(WidgetTester tester, String name) async {
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
    await File('$_outDir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<void> _precache(WidgetTester tester) async {
  await tester.runAsync(() async {
    final context = tester.element(find.byType(Scaffold).first);
    for (final image in _covers.values) {
      await precacheImage(image, context);
    }
    for (final widget in tester.widgetList<Image>(find.byType(Image))) {
      await precacheImage(widget.image, context);
    }
  });
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _shotOf(WidgetTester tester, Key key, String name) async {
  expect(tester.takeException(), isNull);
  if (_outDir.isEmpty) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(_outDir).create(recursive: true);
    await File('$_outDir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

void main() {
  // The app's own type, so a reviewer reads the story, not test boxes.
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
  });

  for (final light in [false, true]) {
    for (final tier in parity.Tier.values) {
      testWidgets('the Botvinnik story, ${tier.name}, '
          '${light ? 'light' : 'dark'}', (tester) async {
        await parity.pumpStories(
          tester,
          tier: tier,
          collection: parity.book,
          light: light,
          extra: [
            storyCoverOverrideProvider.overrideWithValue(
              (c) => _covers['botvinnik'],
            ),
          ],
        );
        await _precache(tester);
        // On to the page with the book's "etc.", as in the report.
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 900));
          final comment = parity.pageOf(tester)['comment'] as String?;
          if (comment != null && comment.contains('etc.')) break;
          final header = tester.getRect(
            find.byKey(const ValueKey('story_close')),
          );
          final frame = tester.getRect(find.byType(StoryFrameView));
          await tester.tapAt(
            Offset(393 * 0.85, (header.bottom + frame.top) / 2),
          );
          await tester.pump();
        }
        // Hold the bars still where they stand, mid-page.
        await tester.pump(const Duration(milliseconds: 1200));
        await _precache(tester);
        await _shotOf(
          tester,
          parity.kParityCapture,
          '${tier.name}_${light ? 'light' : 'dark'}',
        );
      });
    }
  }

  for (final light in [false, true]) {
    testWidgets('the Today circles, ${light ? 'light' : 'dark'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393 * 3, 852 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          storyCollectionsProvider.overrideWith((ref) async => _circles),
          storyBatchProvider.overrideWith(
            (ref, slug) async => _stillBatch(slug),
          ),
          storySeenStorageProvider.overrideWithValue(_MemoryStorage()),
          storyRowPrefsStoreProvider.overrideWithValue(MemoryStoryRowStore()),
          storyClockProvider.overrideWithValue(() => _now),
          storyCoverOverrideProvider.overrideWithValue((c) => _covers[c.slug]),
          boardSettingsProviderNew.overrideWith(_Board.new),
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
                      padding: const EdgeInsets.only(top: 24),
                      children: const [TodayStoryRow(gutter: 16)],
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
      await tester.pump(const Duration(seconds: 3));
      await _precache(tester);
      await _shot(tester, 'circles_${_tag}_${light ? 'light' : 'dark'}');
    });

    testWidgets('every circle side by side, ${light ? 'light' : 'dark'}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(393 * 3, 852 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          storyCoverOverrideProvider.overrideWithValue((c) => _covers[c.slug]),
          boardSettingsProviderNew.overrideWith(_Board.new),
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
                    body: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          StoryCircleFace(
                            collection: missedChancesCollection(_now),
                            seen: false,
                          ),
                          for (final c in _circles)
                            StoryCircleFace(collection: c, seen: false),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await _precache(tester);
      await _shot(tester, 'circles_sheet_${_tag}_${light ? 'light' : 'dark'}');
    });
  }
}
