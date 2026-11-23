import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/screens/collections/collection_plate_row.dart';
import 'package:chessever2/screens/feed/widgets/feed_tile_board.dart';
import 'package:chessever2/screens/for_you/discovery/discovery_view.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/providers/reports_provider.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/widget/premium_collection_cards.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/widgets/space_tile_content.dart';
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:chessever2/widgets/event_card/event_next_round_provider.dart';
import 'package:chessever2/widgets/hub_context_art.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// The media cards in place on their pages, so a dark media card can be
// judged on the light page around it: Today (the Favorites and Countrymen
// tiles above the event cards), Discovery (the page itself) and My Space
// (Prep and Library over the Likes card and a saved event, then the
// Countrymen tiles a Players section shows). A phone, 393x852 at 3x.
//
// Run with
//   flutter test --no-pub --dart-define=LIGHT_V2_DIR=/tmp/media_tiles2/after \
//     test/media_cards_in_context_preview_test.dart
// to write `context_<page>_<light|dark>.png` there (Discovery also writes
// its Events row alone, `context_discovery_events_<light|dark>.png`). Photos
// come from
// LIGHT_V2_PHOTOS (square PNGs named after the players); a missing photo is
// drawn as a stand-in, so nothing asks the network.

const _outDir = String.fromEnvironment('LIGHT_V2_DIR');
const _photoDir = String.fromEnvironment(
  'LIGHT_V2_PHOTOS',
  defaultValue: '/tmp/light_v2/photos/sq',
);

const _root = ValueKey('in_context_root');
const _view = Size(393, 852);
const _ratio = 3.0;

const _favorites = [
  ('Carlsen, Magnus', '1503014', 'Magnus_Carlsen'),
  ('Nakamura, Hikaru', '2016192', 'Hikaru_Nakamura'),
  ('Caruana, Fabiano', '2020009', 'Fabiano_Caruana'),
  ('Ding, Liren', '8603677', 'Ding_Liren'),
  ('Gukesh, D', '46616543', 'Gukesh_Dommaraju'),
  ('Firouzja, Alireza', '12573981', 'Alireza_Firouzja'),
  ('Nepomniachtchi, Ian', '4168119', 'Ian_Nepomniachtchi'),
];

final Map<String, ui.Image> _photos = {};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    Future<ByteData> bytes(String path) =>
        File(path).readAsBytes().then(ByteData.sublistView);
    for (final family in ['InterDisplay', 'Inter']) {
      final loader = FontLoader(family);
      for (final weight in ['Regular', 'Medium', 'Bold']) {
        loader.addFont(bytes('assets/fonts/Inter-$weight.otf'));
      }
      await loader.load();
    }
    final flutterRoot = Platform.environment['FLUTTER_ROOT'];
    if (flutterRoot != null) {
      final icons = File(
        '$flutterRoot/bin/cache/artifacts/material_fonts/'
        'MaterialIcons-Regular.otf',
      );
      if (icons.existsSync()) {
        await (FontLoader('MaterialIcons')..addFont(bytes(icons.path))).load();
      }
    }
    for (final (_, fideId, file) in _favorites) {
      final path = File('$_photoDir/$file.png');
      final ui.Image image;
      if (path.existsSync()) {
        final codec = await ui.instantiateImageCodec(path.readAsBytesSync());
        image = (await codec.getNextFrame()).image;
      } else {
        image = _standIn(fideId.hashCode);
      }
      final url = 'https://photos.preview.test/$fideId.webp';
      _photos[url] = image;
      FidePhotoService.debugSetPhotoUrl(fideId, url);
    }
  });

  final common = <Override>[
    favoritePlayersProviderNew.overrideWith(_Favorites.new),
    favoriteEventsProvider.overrideWith(_NoFavoriteEvents.new),
    eventNextRoundProvider.overrideWith((ref, id) async => null),
    eventImageProvider.overrideWith(
      (ref, id) async => EventImageData(
        fallbackCountryCode: id == 'norway-chess' ? 'NO' : 'US',
      ),
    ),
  ];

  for (final light in [true, false]) {
    final theme = light ? 'light' : 'dark';

    testWidgets('in context: Today ($theme)', (tester) async {
      await _pump(
        tester,
        light: light,
        overrides: [
          ...common,
          countryDropdownProvider.overrideWith((ref) => _Country('JP')),
        ],
        child: Builder(
          builder: (context) => ListView(
            padding: EdgeInsets.only(top: 16.sp),
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.sp),
                child: const PremiumCollectionCards(),
              ),
              for (final event in _events)
                Padding(
                  padding: EdgeInsets.fromLTRB(16.sp, 0, 16.sp, 16.sp),
                  child: EventCard(
                    tourEventCardModel: event,
                    forceCompactLayout: true,
                    showHeartIndicator: true,
                    favoritePlayersSource: EventFavoritePlayersSource.cacheOnly,
                    heroTagSuffix: '_context',
                    onTap: () {},
                  ),
                ),
            ],
          ),
        ),
      );
      await _save(tester, 'context_today_$theme');
    });

    testWidgets('in context: Discovery ($theme)', (tester) async {
      await _pump(
        tester,
        light: light,
        overrides: [
          ...common,
          feedTilePreviewProvider.overrideWith((ref) async => null),
          reportsFirstPageProvider.overrideWith(
            (ref) async => const AnalyzedGamesPage(items: []),
          ),
        ],
        child: const DiscoveryView(),
      );
      // The Events row closes the page whole, inside the phone's first
      // screen: no edge of it is cut by the view.
      final events = find.byKey(const ValueKey('discovery_events_tile'));
      expect(events, findsOneWidget);
      expect(
        Offset.zero & _view,
        predicate<Rect>(
          (view) =>
              view.contains(tester.getRect(events).topLeft) &&
              view.contains(tester.getRect(events).bottomRight),
        ),
      );
      await _save(tester, 'context_discovery_$theme');
      await _save(
        tester,
        'context_discovery_events_$theme',
        region: tester.getRect(events),
      );
    });

    testWidgets('in context: My Space ($theme)', (tester) async {
      await _pump(
        tester,
        light: light,
        overrides: common,
        child: Builder(
          builder: (context) => ListView(
            padding: EdgeInsets.fromLTRB(hubGutter, 16.sp, hubGutter, 0),
            children: [
              HubTileRow(
                left: HubTile(
                  title: 'Prep',
                  caption: 'Your games and opponents',
                  ramp: false,
                  artwork: const HubSceneBackdrop(scene: HubScene.myPrep),
                  onTap: () {},
                ),
                right: HubTile(
                  title: 'Library',
                  caption: 'Your databases',
                  ramp: false,
                  artwork: const HubLibraryBackdrop(),
                  onTap: () {},
                ),
              ),
              CollectionPlateRow(
                plate: Center(child: LikesHeartMark(size: 64.0.h)),
                title: 'Likes',
                meta: 'Your saved games',
                tally: '128 games',
                semanticsLabel: 'Likes, your saved games, 128 games',
                onTap: () {},
              ),
              SizedBox(height: 16.sp),
              EventCard(
                tourEventCardModel: _events.first,
                forceCompactLayout: true,
                heroTagSuffix: '_context_space',
                onTap: () {},
              ),
              SizedBox(height: 12.sp),
              const HubSectionHeader(title: 'Countrymen'),
              SizedBox(height: 8.sp),
              // A rail, as the Players section scrolls its tiles.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (code, title) in const [
                      ('JP', 'Japan'),
                      ('TR', 'Türkiye'),
                      ('NO', 'Norway'),
                    ]) ...[
                      SpaceTileContent(
                        shortcut: SpaceShortcut.draft(
                          kind: SpaceShortcutKind.countrymen,
                          targetId: code,
                          title: title,
                          subtitle: 'Countrymen',
                        ),
                      ),
                      if (code != 'NO') SizedBox(width: 10.sp),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      await _save(tester, 'context_myspace_$theme');
    });
  }

  // The dark originals: the Discovery tiles as dark mode drew them before
  // the media cards became one design (the shipped HubTileFace's dark
  // branch: the art under a full-width ramp from clear at the top to 0.6
  // black at mid-height and 0.95 at the foot). The yardstick for "the art
  // is at least as vivid as it was".
  testWidgets('dark originals: Discovery tiles', (tester) async {
    Widget tile(String title, String caption, HubScene scene) =>
        _OriginalDarkTile(
          title: title,
          caption: caption,
          artwork: HubSceneBackdrop(scene: scene),
        );
    await _pump(
      tester,
      light: false,
      child: Builder(
        builder: (context) => ListView(
          padding: EdgeInsets.fromLTRB(16.sp, 16.sp, 16.sp, 0),
          children: [
            HubTileRow(
              left: tile('Feed', 'Nepomniachtchi vs Firouzja', HubScene.feed),
              right: tile('Likes', 'Community favorites', HubScene.mostLiked),
            ),
            HubTileRow(
              left: tile('News', 'Latest headlines', HubScene.news),
              right: tile('Reports', 'Games with analysis', HubScene.reports),
            ),
            HubTileRow(
              left: tile(
                'Miniatures',
                '25 moves or fewer',
                HubScene.miniatures,
              ),
              right: tile(
                'Collections',
                'Curated games and books',
                HubScene.collections,
              ),
            ),
          ],
        ),
      ),
    );
    await _save(tester, 'discovery_hubs_original_dark');
  });
}

/// The shipped dark hub tile (HEAD's HubTileFace, dark branch), redrawn
/// here only as a yardstick for the art's vividness.
class _OriginalDarkTile extends StatelessWidget {
  const _OriginalDarkTile({
    required this.title,
    required this.caption,
    required this.artwork,
  });

  final String title;
  final String caption;
  final Widget artwork;

  @override
  Widget build(BuildContext context) {
    List<Shadow> shadow(double alpha, double blur, [Offset? offset]) => [
      Shadow(
        color: Colors.black.withValues(alpha: alpha),
        blurRadius: blur,
        offset: offset ?? Offset.zero,
      ),
    ];
    final quiet = kHubTileOnMedia.withValues(alpha: 0.85);
    return Container(
      height: 108.sp,
      decoration: BoxDecoration(
        color: kHubTileInk,
        borderRadius: BorderRadius.circular(14.br),
        border: Border.all(color: context.colors.divider, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14.br),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(child: artwork),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.6),
                      Colors.black.withValues(alpha: 0.95),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(14.sp),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    style: HubTileFace.titleType().copyWith(
                      color: kHubTileOnMedia,
                      shadows: shadow(0.45, 4, const Offset(0, 1)),
                    ),
                  ),
                  SizedBox(height: 2.sp),
                  Text(
                    caption,
                    maxLines: 1,
                    style: HubTileFace.captionType().copyWith(
                      color: quiet,
                      shadows: shadow(0.4, 3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final _events = [
  GroupEventCardModel(
    id: 'norway-chess',
    title: 'Norway Chess 2026',
    dates: 'May 25 - Jun 5, 2026',
    maxAvgElo: 2781,
    timeUntilStart: '',
    tourEventCategory: TourEventCategory.live,
    timeControl: 'Classical',
    startDate: DateTime.utc(2026, 5, 25),
    endDate: DateTime.utc(2026, 6, 5),
    location: 'Oslo, Norway',
  ),
  GroupEventCardModel(
    id: 'sinquefield',
    title: 'Sinquefield Cup 2026',
    dates: 'Aug 20 - Aug 30, 2026',
    maxAvgElo: 2752,
    timeUntilStart: '',
    tourEventCategory: TourEventCategory.completed,
    timeControl: 'Classical',
    startDate: DateTime.utc(2026, 8, 20),
    endDate: DateTime.utc(2026, 8, 30),
    location: 'Saint Louis, USA',
  ),
];

Future<void> _pump(
  WidgetTester tester, {
  required bool light,
  required Widget child,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = _view * _ratio;
  tester.view.devicePixelRatio = _ratio;
  addTearDown(tester.view.reset);
  _seedPhotos();
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return RepaintBoundary(
              key: _root,
              child: Scaffold(
                backgroundColor: context.colors.background,
                body: SafeArea(child: child),
              ),
            );
          },
        ),
      ),
    ),
  );
  for (var round = 0; round < 3; round++) {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 700));
  }
  expect(tester.takeException(), isNull);
}

/// Writes the page, or only [region] of it (logical pixels), as `name.png`.
Future<void> _save(WidgetTester tester, String name, {Rect? region}) async {
  if (_outDir.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_root),
  );
  await tester.runAsync(() async {
    var image = await boundary.toImage(pixelRatio: _ratio);
    if (region != null) {
      final src = Rect.fromLTRB(
        region.left * _ratio,
        region.top * _ratio,
        region.right * _ratio,
        region.bottom * _ratio,
      );
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        image,
        src,
        Offset.zero & src.size,
        Paint()..filterQuality = FilterQuality.none,
      );
      final picture = recorder.endRecording();
      final crop = await picture.toImage(src.width.round(), src.height.round());
      picture.dispose();
      image.dispose();
      image = crop;
    }
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_outDir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
  });
}

void _seedPhotos() {
  final cache = PaintingBinding.instance.imageCache;
  cache.maximumSize = 1 << 20;
  cache.maximumSizeBytes = 1 << 40;
  for (final MapEntry(key: url, value: image) in _photos.entries) {
    final provider = CachedNetworkImageProvider(url);
    void put(Object key) => cache.putIfAbsent(
      key,
      () => OneFrameImageStreamCompleter(
        SynchronousFuture(ImageInfo(image: image.clone())),
      ),
    );
    put(provider);
    for (var side = 24; side <= 400; side++) {
      ResizeImage(
        provider,
        width: side,
        height: side,
      ).obtainKey(ImageConfiguration.empty).then(put);
    }
  }
}

ui.Image _standIn(int seed) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const side = 256.0;
  final hue = (seed * 47 % 360).toDouble();
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, side, side),
    Paint()..color = HSLColor.fromAHSL(1, hue, 0.22, 0.38).toColor(),
  );
  canvas.drawOval(
    const Rect.fromLTWH(side * 0.34, side * 0.2, side * 0.32, side * 0.4),
    Paint()..color = HSLColor.fromAHSL(1, 28, 0.42, 0.6).toColor(),
  );
  canvas.drawArc(
    const Rect.fromLTWH(side * 0.12, side * 0.7, side * 0.76, side * 0.6),
    math.pi,
    math.pi,
    true,
    Paint()..color = const Color(0xFF263238),
  );
  return recorder.endRecording().toImageSync(side.toInt(), side.toInt());
}

class _Country extends StateNotifier<AsyncValue<Country>>
    implements SelectedCountryNotifier {
  _Country(String code) : super(AsyncData(CountryService().findByCode(code)!));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Favorites extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => [
    for (final (name, fideId, _) in _favorites)
      FavoritePlayer(
        id: fideId,
        userId: 'u',
        fideId: fideId,
        playerName: name,
        metadata: const {},
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
  ];
}

class _NoFavoriteEvents extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => [];
}
