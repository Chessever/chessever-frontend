import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:chessever2/providers/country_dropdown_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/gamebase/memorial_player.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/for_you/discovery/widgets/premium_tour_section.dart';
import 'package:chessever2/screens/gamebase/models/gamebase_player.dart';
import 'package:chessever2/screens/group_event/widget/player_search_cards.dart';
import 'package:chessever2/screens/group_event/widget/premium_collection_cards.dart';
import 'package:chessever2/screens/library/providers/miniatures_provider.dart';
import 'package:chessever2/screens/library/widgets/twic_player_search_cards.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/widgets/space_tile_content.dart';
import 'package:chessever2/screens/search/search_carousel.dart'
    show searchCarouselItemWidth;
import 'package:chessever2/screens/search/search_page_sections.dart'
    show searchPageGutter;
import 'package:chessever2/services/fide_photo_service.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// The light-mode media cards as a phone shows them: Today's Favorites and
// Countrymen tiles, the My Space Countrymen tile, the Discovery tour's
// Countrymen tile and the player search cards, each in light and dark, at a
// 393x852 view and 3x.
//
// Run with
//   flutter test --no-pub --dart-define=LIGHT_V2_DIR=/tmp/light_v2/out \
//     test/light_media_cards_preview_test.dart
// to write `<surface>_<light|dark>.png` there. Photos come from
// LIGHT_V2_PHOTOS (default /tmp/light_v2/photos/sq: square PNGs named after
// the players below); a missing photo shows as the card's no-photo state.
// Without LIGHT_V2_DIR the test only checks that every surface builds.

const _outDir = String.fromEnvironment('LIGHT_V2_DIR');
const _photoDir = String.fromEnvironment(
  'LIGHT_V2_PHOTOS',
  defaultValue: '/tmp/light_v2/photos/sq',
);

const _root = ValueKey('light_media_root');

/// The view a phone gives: 393x852 at 3x.
const _view = Size(393, 852);
const _ratio = 3.0;

/// A player the previews show, with the photo file standing in for theirs.
class _Player {
  const _Player(this.name, this.fideId, this.fed, this.rating, this.file);

  /// "Lastname, Firstname", as the data carries it.
  final String name;
  final String fideId;
  final String fed;
  final int rating;

  /// Photo file name in [_photoDir], without `.png`; null: no photo.
  final String? file;

  /// The URL the FIDE photo lookup answers for them.
  String get fideUrl => 'https://photos.preview.test/$fideId.webp';

  /// The URL a search card shows for them (the memorial seam: a search
  /// player with a source identity and no FIDE id).
  String get searchUrl =>
      memorialPlayerPhotoUrl(playerName: name, sourceIdentity: 'preview')!;
}

const _carlsen = _Player(
  'Carlsen, Magnus',
  '1503014',
  'NOR',
  2823,
  'Magnus_Carlsen',
);
const _nakamura = _Player(
  'Nakamura, Hikaru',
  '2016192',
  'USA',
  2802,
  'Hikaru_Nakamura',
);
const _caruana = _Player(
  'Caruana, Fabiano',
  '2020009',
  'USA',
  2795,
  'Fabiano_Caruana',
);
const _ding = _Player('Ding, Liren', '8603677', 'CHN', 2734, 'Ding_Liren');
const _gukesh = _Player(
  'Gukesh, D',
  '46616543',
  'IND',
  2767,
  'Gukesh_Dommaraju',
);
const _firouzja = _Player(
  'Firouzja, Alireza',
  '12573981',
  'FRA',
  2759,
  'Alireza_Firouzja',
);
const _nepo = _Player(
  'Nepomniachtchi, Ian',
  '4168119',
  'RUS',
  2754,
  'Ian_Nepomniachtchi',
);
const _abdusattorov = _Player(
  'Abdusattorov, Nodirbek',
  '14204118',
  'UZB',
  2766,
  'Nodirbek_Abdusattorov',
);
const _noPhoto = _Player('Sindarov, Javokhir', '14205483', 'UZB', 2726, null);

const _favorites = [_carlsen, _nakamura, _caruana, _ding, _gukesh, _firouzja];
const _all = [
  _carlsen,
  _nakamura,
  _caruana,
  _ding,
  _gukesh,
  _firouzja,
  _nepo,
  _abdusattorov,
];

/// Decoded photos by the URLs the widgets ask for.
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
    for (final player in _all) {
      final file = File('$_photoDir/${player.file}.png');
      if (!file.existsSync()) continue;
      final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
      final image = (await codec.getNextFrame()).image;
      _photos[player.fideUrl] = image;
      _photos[player.searchUrl] = image.clone();
      FidePhotoService.debugSetPhotoUrl(player.fideId, player.fideUrl);
    }
  });

  for (final light in [true, false]) {
    final theme = light ? 'light' : 'dark';

    for (final (code, name) in const [('TR', 'tr'), ('NO', 'no')]) {
      testWidgets('Today tiles, $code, $theme', (tester) async {
        await _pump(
          tester,
          light: light,
          overrides: [
            countryDropdownProvider.overrideWith((ref) => _Country(code)),
            favoritePlayersProviderNew.overrideWith(
              () => _Favorites(_favorites),
            ),
          ],
          child: const PremiumCollectionCards(),
        );
        expect(find.byType(PremiumCollectionCards), findsOneWidget);
        await _save(
          tester,
          find.byType(PremiumCollectionCards),
          'today_$name',
          light,
        );
      });

      testWidgets('My Space Countrymen, $code, $theme', (tester) async {
        await _pump(
          tester,
          light: light,
          child: Align(
            alignment: Alignment.topLeft,
            child: SpaceTileContent(
              shortcut: SpaceShortcut.draft(
                kind: SpaceShortcutKind.countrymen,
                targetId: code,
                title: code == 'TR' ? 'Türkiye' : 'Norway',
                subtitle: 'Countrymen',
              ),
            ),
          ),
        );
        expect(find.byType(SpaceTileContent), findsOneWidget);
        await _save(
          tester,
          find.byType(SpaceTileContent),
          'myspace_$name',
          light,
        );
      });

      testWidgets('Discovery tour Countrymen, $code, $theme', (tester) async {
        await _pump(
          tester,
          light: light,
          overrides: [
            countryDropdownProvider.overrideWith((ref) => _Country(code)),
            discoveryHotRowsProvider.overrideWith((ref, tc) => const []),
            mostLikedProvider.overrideWith(
              (ref, query) async => const MostLikedResult.ranked([]),
            ),
            discoveryAnalyzedGamesProvider.overrideWith((ref) async => []),
            discoveryReviewCurveProvider.overrideWith((ref) async => null),
            miniaturesTotalCountProvider.overrideWith((ref) async => 0),
            discoveryTodayMiniaturesProvider.overrideWith(
              (ref) async => const [],
            ),
          ],
          child: PremiumTourSection(
            onShowMostLiked: () {},
            onShowAnalyzed: () {},
          ),
        );
        final tile = find.byKey(const ValueKey('tour_countrymen'));
        expect(tile, findsOneWidget);
        await tester.ensureVisible(tile);
        await _settle(tester);
        await _save(tester, tile, 'discovery_$name', light);
      });
    }

    // The largest standard iOS text size (xxxLarge): the art keeps above
    // the larger label, and the avatar above the name.
    testWidgets('Today tiles, largest text, $theme', (tester) async {
      await _pump(
        tester,
        light: light,
        textScale: 1.35,
        overrides: [
          countryDropdownProvider.overrideWith((ref) => _Country('TR')),
          favoritePlayersProviderNew.overrideWith(() => _Favorites(_favorites)),
        ],
        child: const PremiumCollectionCards(),
      );
      await _save(
        tester,
        find.byType(PremiumCollectionCards),
        'today_tr_xl',
        light,
      );
    });

    testWidgets('player search cards, largest text, $theme', (tester) async {
      await _pump(
        tester,
        light: light,
        textScale: 1.35,
        child: PlayerSearchCards(
          players: [
            for (final p in const [_carlsen, _firouzja])
              SearchPlayer(
                id: p.name,
                name: p.name,
                fed: p.fed,
                rating: p.rating,
                title: 'GM',
                tournamentId: 't',
                tournamentName: 'T',
                memorialSourceIdentity: 'preview',
              ),
          ],
          animateIn: false,
          bottomPadding: 0,
        ),
      );
      await _save(
        tester,
        find.byType(PlayerSearchCards),
        'player_pair_xl',
        light,
      );
    });

    testWidgets('Today tiles, no favorites, $theme', (tester) async {
      await _pump(
        tester,
        light: light,
        overrides: [
          countryDropdownProvider.overrideWith((ref) => _Country('TR')),
          favoritePlayersProviderNew.overrideWith(() => _Favorites(const [])),
        ],
        child: const PremiumCollectionCards(),
      );
      await _save(
        tester,
        find.byType(PremiumCollectionCards),
        'today_empty',
        light,
      );
    });

    // `landing`: a pair as the Search tab's Top players row sets it, one
    // carousel card's width (the next one peeking past the edge).
    for (final (name, players, landing) in const [
      ('player_big', [_carlsen], false),
      ('player_pair', [_abdusattorov, _firouzja], false),
      ('player_nophoto', [_gukesh, _noPhoto], false),
      ('player_big_nophoto', [_noPhoto], false),
      ('player_pair_landing', [_abdusattorov, _firouzja], true),
      ('player_pair_top_landing', [_carlsen, _nakamura], true),
    ]) {
      testWidgets('player search cards $name, $theme', (tester) async {
        final cards = PlayerSearchCards(
          players: [
            for (final p in players)
              SearchPlayer(
                id: p.name,
                name: p.name,
                fed: p.fed,
                rating: p.rating,
                title: 'GM',
                tournamentId: 't',
                tournamentName: 'T',
                memorialSourceIdentity: p.file == null ? null : 'preview',
              ),
          ],
          animateIn: false,
          bottomPadding: 0,
        );
        await _pump(
          tester,
          light: light,
          padded: !landing,
          child: landing
              ? Builder(
                  builder: (context) => Padding(
                    padding: EdgeInsets.symmetric(horizontal: searchPageGutter),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: searchCarouselItemWidth(
                          _view.width - 2 * searchPageGutter,
                          tabletMinWidth: 320,
                        ),
                        child: cards,
                      ),
                    ),
                  ),
                )
              : cards,
        );
        expect(find.byType(PlayerSearchCards), findsOneWidget);
        await _save(tester, find.byType(PlayerSearchCards), name, light);
      });
    }

    testWidgets('TWIC player cards, $theme', (tester) async {
      await _pump(
        tester,
        light: light,
        overrides: [
          topTwicSearchedPlayersProvider.overrideWith(
            (ref, query) => [
              for (final p in [_nepo, _noPhoto])
                GamebasePlayer(
                  id: p.fideId,
                  fideId: p.fideId,
                  name: p.name,
                  gender: PlayerGender.male,
                  fed: p.fed,
                  title: 'GM',
                ),
            ],
          ),
        ],
        child: const TwicPlayerSearchCards(searchQuery: 'preview'),
        padded: false,
      );
      expect(find.byType(TwicPlayerSearchCards), findsOneWidget);
      await _save(
        tester,
        find.byType(TwicPlayerSearchCards),
        'twic_pair',
        light,
      );
    });
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required bool light,
  required Widget child,
  List<Override> overrides = const [],
  bool padded = true,
  double textScale = 1,
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
                body: SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      padded ? 16 : 0,
                      24,
                      padded ? 16 : 0,
                      0,
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: textScale == 1
                          ? child
                          : MediaQuery(
                              data: MediaQuery.of(context).copyWith(
                                textScaler: TextScaler.linear(textScale),
                              ),
                              child: child,
                            ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await _settle(tester);
  // One fixed moment of every running motion (the mosaic's drift, a flag's
  // wave), the same in every run so two runs compare byte for byte.
  await tester.pump(const Duration(milliseconds: 1500));
  await _settle(tester);
  // Entrances that wait a zero-length timer first (the TWIC cards' fade)
  // start only once the clock has moved; let them finish.
  await tester.pump(const Duration(milliseconds: 600));
  await _settle(tester);
}

/// Lets real asynchronous work (flag assets, decoded pictures) land without
/// moving the test clock.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
}

/// Puts every photo in the image cache under each key a card can ask for it
/// by (the URL, resized to a square or to a width), so `CachedNetworkImage`
/// answers from memory with no network and no disk.
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
    for (var side = 24; side <= 720; side++) {
      ResizeImage(
        provider,
        width: side,
        height: side,
      ).obtainKey(ImageConfiguration.empty).then(put);
      ResizeImage(
        provider,
        width: side,
      ).obtainKey(ImageConfiguration.empty).then(put);
    }
  }
}

/// Writes [target], with a margin of the page around it, to
/// `<name>_<light|dark>.png` in [_outDir].
Future<void> _save(
  WidgetTester tester,
  Finder target,
  String name,
  bool light,
) async {
  if (_outDir.isEmpty) return;
  final box = tester.getRect(target).inflate(12);
  final rect = Rect.fromLTRB(
    box.left.floorToDouble().clamp(0, _view.width),
    box.top.floorToDouble().clamp(0, _view.height),
    box.right.ceilToDouble().clamp(0, _view.width),
    box.bottom.ceilToDouble().clamp(0, _view.height),
  );
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_root),
  );
  await tester.runAsync(() async {
    final full = await boundary.toImage(pixelRatio: _ratio);
    final source = Rect.fromLTRB(
      rect.left * _ratio,
      rect.top * _ratio,
      rect.right * _ratio,
      rect.bottom * _ratio,
    );
    final recorder = ui.PictureRecorder();
    Canvas(
      recorder,
    ).drawImageRect(full, source, Offset.zero & source.size, Paint());
    final crop = await recorder.endRecording().toImage(
      source.width.round(),
      source.height.round(),
    );
    final png = await crop.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$_outDir/${name}_${light ? 'light' : 'dark'}.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
    full.dispose();
    crop.dispose();
  });
}

class _Country extends StateNotifier<AsyncValue<Country>>
    implements SelectedCountryNotifier {
  _Country(String code) : super(AsyncData(CountryService().findByCode(code)!));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Favorites extends FavoritePlayersNotifierNew {
  _Favorites(this.players);

  final List<_Player> players;

  @override
  Future<List<FavoritePlayer>> build() async => [
    for (final p in players)
      FavoritePlayer(
        id: p.fideId,
        userId: 'u',
        fideId: p.fideId,
        playerName: p.name,
        metadata: const {},
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
  ];
}
