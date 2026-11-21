import 'dart:io';
import 'dart:math' as math;
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
import 'package:chessever2/widgets/hub_context_art.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:chessever2/widgets/media_card.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// The media cards as a phone shows them, in light and in dark: Today's
// Favorites and Countrymen tiles, the My Space Countrymen tile and the My
// Space Prep and Library tiles, the Discovery tiles, the Discovery tour's
// Countrymen picture, the player search cards (full width and half width)
// and the TWIC player cards, at a 393x852 view and 3x.
//
// Every surface is checked twice:
//  * its words (white type on a photo, a flag or drawn art) are measured
//    against the pixels actually under their glyphs: each card is drawn once
//    more with its type (and the type's shadows) made clear, so what is left
//    is the picture with the card's shade over it; every pixel a glyph
//    covers (half or more, found by comparing the two draws) must leave its
//    line at its bar: 3:1 for a large bold line (a name, a title:
//    `MediaTextScrim.contrastFor`), 4.5:1 for the smaller lines. The text
//    shadow is left out of the measurement, so the shade alone carries it.
//    The strictest box-wide figures (every pixel of each line's box) are
//    written alongside, for the record;
//  * the same card in light and in dark must be the same picture: a media
//    card is one design in both themes.
//
// Run with
//   flutter test --no-pub --dart-define=LIGHT_V2_DIR=/tmp/media_tiles/after \
//     test/light_media_cards_preview_test.dart
// to write `<surface>_<light|dark>.png` and `contrast.tsv` there. Photos come
// from LIGHT_V2_PHOTOS (default /tmp/light_v2/photos/sq: square PNGs named
// after the players below); a missing photo is drawn as a stand-in, so a
// card never asks the network for one. `MEDIA_TILES_PHASE=before` records
// the measurements without asserting them (for a render of an older tree).

const _outDir = String.fromEnvironment('LIGHT_V2_DIR');
const _photoDir = String.fromEnvironment(
  'LIGHT_V2_PHOTOS',
  defaultValue: '/tmp/light_v2/photos/sq',
);
const _phase = String.fromEnvironment(
  'MEDIA_TILES_PHASE',
  defaultValue: 'after',
);
bool get _asserting => _phase != 'before';

const _root = ValueKey('light_media_root');

/// The view a phone gives: 393x852 at 3x.
const _view = Size(393, 852);
const _ratio = 3.0;

/// A player the previews show, with the photo file standing in for theirs.
class _Player {
  const _Player(
    this.name,
    this.fideId,
    this.fed,
    this.rating,
    this.file, {
    this.bright = false,
  });

  /// "Lastname, Firstname", as the data carries it.
  final String name;
  final String fideId;
  final String fed;
  final int rating;

  /// Photo file name in [_photoDir], without `.png`; null: no photo.
  final String? file;

  /// A studio photo on a white backdrop (most FIDE photos): the brightest
  /// picture type can land on. Always the drawn stand-in.
  final bool bright;

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
const _erdogmus = _Player(
  'Erdogmus, Yagiz Kaan',
  '44599790',
  'TUR',
  2651,
  'Yagiz_Kaan_Erdogmus',
  bright: true,
);
const _japan = _Player(
  'Kobayashi, Kenta',
  '7700112',
  'JPN',
  2310,
  'Kenta_Kobayashi',
  bright: true,
);
const _noPhoto = _Player('Sindarov, Javokhir', '14205483', 'UZB', 2726, null);
// TWIC writes some federations as names, and England as its own.
const _england = _Player('Adams, Michael', '400041', 'ENG', 2650, null);
const _norwayByName = _Player(
  'Tari, Aryan',
  '1510045',
  'Norway',
  2651,
  null,
  bright: true,
);

const _favorites = [
  _carlsen,
  _nakamura,
  _erdogmus,
  _caruana,
  _ding,
  _gukesh,
  _firouzja,
];
const _all = [
  _carlsen,
  _nakamura,
  _caruana,
  _ding,
  _gukesh,
  _firouzja,
  _nepo,
  _abdusattorov,
  _erdogmus,
  _japan,
  _norwayByName,
];

/// Decoded photos by the URLs the widgets ask for.
final Map<String, ui.Image> _photos = {};

/// Every measurement, written to `contrast.tsv` at the end.
final List<String> _report = [];

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
      final ui.Image image;
      if (!player.bright && file.existsSync()) {
        final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
        image = (await codec.getNextFrame()).image;
      } else {
        // No fixture on this machine (a fresh checkout, CI), or the bright
        // studio case: a drawn stand-in, so a card never asks the network.
        image = _standInPhoto(player.fideId.hashCode, bright: player.bright);
      }
      _photos[player.fideUrl] = image;
      _photos[player.searchUrl] = image.clone();
      FidePhotoService.debugSetPhotoUrl(player.fideId, player.fideUrl);
    }
  });

  tearDownAll(() async {
    if (_outDir.isEmpty) return;
    final file = File('$_outDir/contrast.tsv');
    await file.parent.create(recursive: true);
    await file.writeAsString(
      [
        'phase\tsurface\ttheme\ttext\tbar\tglyph_min\tbox_min\tbox_p1'
            '\tworst_glyph_bg',
        ..._report,
      ].join('\n'),
    );
  });

  // ------------------------------------------------------------ Today
  for (final code in const ['TR', 'NO', 'JP']) {
    _surface(
      'today_${code.toLowerCase()}',
      overrides: [
        countryDropdownProvider.overrideWith((ref) => _Country(code)),
        favoritePlayersProviderNew.overrideWith(() => _Favorites(_favorites)),
      ],
      build: (_) => const PremiumCollectionCards(),
      target: find.byType(PremiumCollectionCards),
      cards: find.byType(HubTileFace),
    );
  }
  _surface(
    'today_empty',
    overrides: [
      countryDropdownProvider.overrideWith((ref) => _Country('TR')),
      favoritePlayersProviderNew.overrideWith(() => _Favorites(const [])),
    ],
    build: (_) => const PremiumCollectionCards(),
    target: find.byType(PremiumCollectionCards),
    cards: find.byType(HubTileFace),
  );
  // The largest standard iOS text size (xxxLarge).
  _surface(
    'today_tr_xl',
    textScale: 1.35,
    overrides: [
      countryDropdownProvider.overrideWith((ref) => _Country('TR')),
      favoritePlayersProviderNew.overrideWith(() => _Favorites(_favorites)),
    ],
    build: (_) => const PremiumCollectionCards(),
    target: find.byType(PremiumCollectionCards),
    cards: find.byType(HubTileFace),
  );

  // --------------------------------------------------------- My Space
  for (final (code, title) in const [
    ('TR', 'Türkiye'),
    ('NO', 'Norway'),
    ('JP', 'Japan'),
  ]) {
    _surface(
      'myspace_countrymen_${code.toLowerCase()}',
      build: (_) => Align(
        alignment: Alignment.topLeft,
        child: SpaceTileContent(
          shortcut: SpaceShortcut.draft(
            kind: SpaceShortcutKind.countrymen,
            targetId: code,
            title: title,
            subtitle: 'Countrymen',
          ),
        ),
      ),
      target: find.byType(SpaceTileContent),
      cards: find.byType(SpaceTileContent),
    );
  }
  // Pins that name their federation by a FIDE code (older pins) or a UK
  // nation: the vector flag all the same, never a stretched raster one.
  for (final (code, title) in const [('NOR', 'Norway'), ('ENG', 'England')]) {
    _surface(
      'myspace_countrymen_${code.toLowerCase()}',
      build: (_) => Align(
        alignment: Alignment.topLeft,
        child: SpaceTileContent(
          shortcut: SpaceShortcut.draft(
            kind: SpaceShortcutKind.countrymen,
            targetId: code,
            title: title,
            subtitle: 'Countrymen',
          ),
        ),
      ),
      target: find.byType(SpaceTileContent),
      cards: find.byType(SpaceTileContent),
    );
  }
  // Prep and Library as the page sets them, wide (a full row) and small
  // (a pair).
  _surface(
    'myspace_hubs_wide',
    build: (_) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [_prepTile(), const SizedBox(height: 12), _libraryTile()],
    ),
    target: find.byKey(const ValueKey('media_tiles_hubs')),
    cards: find.byType(HubTileFace),
  );
  _surface(
    'myspace_hubs_small',
    build: (_) => HubTileRow(left: _prepTile(), right: _libraryTile()),
    target: find.byKey(const ValueKey('media_tiles_hubs')),
    cards: find.byType(HubTileFace),
  );

  // -------------------------------------------------------- Discovery
  _surface(
    'discovery_hubs',
    build: (_) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        HubTileRow(
          left: _hub(
            'Feed',
            'Nepomniachtchi vs Firouzja',
            const HubSceneBackdrop(scene: HubScene.feed),
          ),
          right: _hub(
            'Likes',
            'Community favorites',
            const HubSceneBackdrop(scene: HubScene.mostLiked),
          ),
        ),
        HubTileRow(
          left: _hub(
            'News',
            'Latest headlines',
            const HubSceneBackdrop(scene: HubScene.news),
          ),
          right: _hub(
            'Reports',
            'Games with analysis',
            const HubSceneBackdrop(scene: HubScene.reports),
          ),
        ),
        HubTileRow(
          left: _hub(
            'Miniatures',
            '25 moves or fewer',
            const HubSceneBackdrop(scene: HubScene.miniatures),
          ),
          right: _hub(
            'Collections',
            'Curated games and books',
            const HubSceneBackdrop(scene: HubScene.collections),
          ),
        ),
      ],
    ),
    target: find.byKey(const ValueKey('media_tiles_hubs')),
    cards: find.byType(HubTileFace),
  );
  for (final code in const ['TR', 'NO', 'JP']) {
    _surface(
      'discovery_tour_${code.toLowerCase()}',
      overrides: [
        countryDropdownProvider.overrideWith((ref) => _Country(code)),
        discoveryHotRowsProvider.overrideWith((ref, tc) => const []),
        mostLikedProvider.overrideWith(
          (ref, query) async => const MostLikedResult.ranked([]),
        ),
        discoveryAnalyzedGamesProvider.overrideWith((ref) async => []),
        discoveryReviewCurveProvider.overrideWith((ref) async => null),
        miniaturesTotalCountProvider.overrideWith((ref) async => 0),
        discoveryTodayMiniaturesProvider.overrideWith((ref) async => const []),
      ],
      build: (_) =>
          PremiumTourSection(onShowMostLiked: () {}, onShowAnalyzed: () {}),
      target: find.byKey(const ValueKey('tour_countrymen')),
      cards: find
          .descendant(
            of: find.byKey(const ValueKey('tour_countrymen')),
            matching: find.byType(ClipRRect),
          )
          .first,
      reveal: find.byKey(const ValueKey('tour_countrymen')),
    );
  }

  // ----------------------------------------------------- Search cards
  // `landing`: a pair as the Search tab's Top players row sets it, one
  // carousel card's width (the next one peeking past the edge).
  // `names`: the full names a card must show, running over its photo's
  // faded edge (a half-width card steps a name down only when the full one
  // cannot fit the card's width).
  for (final (name, players, landing, scale, names) in const [
    ('player_big', [_carlsen], false, 1.0, ['Magnus Carlsen']),
    ('player_big_bright', [_erdogmus], false, 1.0, ['Yagiz Kaan Erdogmus']),
    (
      'player_pair',
      [_abdusattorov, _firouzja],
      false,
      1.0,
      ['Alireza Firouzja'],
    ),
    (
      'player_pair_bright',
      [_japan, _erdogmus],
      false,
      1.0,
      ['Kenta Kobayashi'],
    ),
    (
      'player_quad',
      [_carlsen, _nakamura, _japan, _gukesh],
      false,
      1.0,
      ['Magnus Carlsen', 'Hikaru Nakamura', 'Kenta Kobayashi', 'D Gukesh'],
    ),
    (
      'player_nophoto',
      [_gukesh, _noPhoto],
      false,
      1.0,
      ['D Gukesh', 'Javokhir Sindarov'],
    ),
    ('player_big_nophoto', [_noPhoto], false, 1.0, ['Javokhir Sindarov']),
    (
      'player_pair_landing',
      [_abdusattorov, _firouzja],
      true,
      1.0,
      ['Alireza Firouzja'],
    ),
    ('player_pair_top_landing', [_carlsen, _nakamura], true, 1.0, <String>[]),
    ('player_pair_xl', [_carlsen, _firouzja], false, 1.35, <String>[]),
  ]) {
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
    _surface(
      name,
      textScale: scale,
      padded: !landing,
      build: (_) => landing
          ? Padding(
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
            )
          : cards,
      target: find.byType(PlayerSearchCards),
      cards: _byTypeName('_PlayerSearchCard'),
      names: names,
    );
  }

  for (final (name, players, names) in const [
    ('twic_pair', [_nepo, _noPhoto], ['Javokhir Sindarov']),
    ('twic_big_bright', [_erdogmus], ['Yagiz Kaan Erdogmus']),
    (
      'twic_flags',
      [_japan, _england, _norwayByName],
      ['Kenta Kobayashi', 'Michael Adams', 'Aryan Tari'],
    ),
  ]) {
    _surface(
      name,
      padded: false,
      overrides: [
        topTwicSearchedPlayersProvider.overrideWith(
          (ref, query) => [
            for (final p in players)
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
      build: (_) => const TwicPlayerSearchCards(searchQuery: 'preview'),
      target: find.byType(TwicPlayerSearchCards),
      cards: _byTypeName('_TwicPlayerCard'),
      // The list stands as tall as the page; write the cards alone.
      saveAll: true,
      names: names,
    );
  }

  // The worst case for white type: artwork that is white everywhere. The
  // label must hold 4.5:1 over it with nothing but its own backing.
  _surface(
    'hub_white_worst',
    build: (_) => HubTileRow(
      left: _hub(
        'Countrymen',
        'Tap to view',
        const ColoredBox(color: Color(0xFFFFFFFF)),
      ),
      right: _hub(
        'Collections',
        'Curated games and books',
        const ColoredBox(color: Color(0xFFFFFFFF)),
      ),
    ),
    target: find.byKey(const ValueKey('media_tiles_hubs')),
    cards: find.byType(HubTileFace),
  );
}

Widget _hub(String title, String caption, Widget artwork) =>
    HubTile(title: title, caption: caption, artwork: artwork, onTap: () {});

Widget _prepTile() => HubTile(
  title: 'Prep',
  caption: 'Your games and opponents',
  ramp: false,
  artwork: const HubSceneBackdrop(scene: HubScene.myPrep),
  onTap: () {},
);

Widget _libraryTile() => HubTile(
  title: 'Library',
  caption: 'Your databases',
  ramp: false,
  artwork: const HubLibraryBackdrop(),
  onTap: () {},
);

Finder _byTypeName(String name) =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == name);

/// One surface: drawn in dark and in light, each written out, its type
/// measured against its own pixels, and the two themes' cards compared.
void _surface(
  String name, {
  required WidgetBuilder build,
  required Finder target,
  required Finder cards,
  List<Override> overrides = const [],
  bool padded = true,
  double textScale = 1,
  Finder? reveal,
  bool saveAll = false,
  List<String> names = const [],
}) {
  testWidgets('media cards: $name', (tester) async {
    final shots = <bool, List<_Pixels>>{};
    for (final light in [false, true]) {
      final theme = light ? 'light' : 'dark';
      await _pump(
        tester,
        light: light,
        overrides: overrides,
        padded: padded,
        textScale: textScale,
        child: KeyedSubtree(
          key: const ValueKey('media_tiles_hubs'),
          child: Builder(builder: build),
        ),
      );
      expect(target, findsWidgets);
      if (reveal != null) {
        await tester.ensureVisible(reveal);
        await _settle(tester);
      }
      expect(tester.takeException(), isNull);
      // Every card fills the width it is given, photo or none.
      for (final element in cards.evaluate()) {
        expect(
          _rectOf(element).width,
          greaterThan(100),
          reason: '$name ($theme): a card collapsed',
        );
      }
      // The full names, over the photo's faded edge.
      for (final full in names) {
        expect(
          find.descendant(of: target.first, matching: find.text(full)),
          findsOneWidget,
          reason: '$name ($theme): "$full" is shortened',
        );
      }
      await _save(tester, saveAll ? cards : target.first, name, light);

      final full = await _capture(tester);
      final rects = [
        for (final element in cards.evaluate()) _rectOf(element).deflate(15),
      ].where((r) => r.width > 4 && r.height > 4).toList();
      shots[light] = [for (final r in rects) full.crop(r)];

      // The type, measured against the pixels under its glyphs.
      final measured = await _measureType(tester, cards, full);
      for (final m in measured) {
        _report.add(
          [
            _phase,
            name,
            theme,
            m.text,
            m.bar.toStringAsFixed(1),
            m.glyphMin.toStringAsFixed(2),
            m.boxMin.toStringAsFixed(2),
            m.boxP1.toStringAsFixed(2),
            '#${m.worstBackground.toRadixString(16).padLeft(6, '0')}',
          ].join('\t'),
        );
        if (_asserting) {
          expect(
            m.glyphMin,
            greaterThanOrEqualTo(m.bar),
            reason:
                '$name ($theme): "${m.text}" falls to '
                '${m.glyphMin.toStringAsFixed(2)}:1 under its glyphs '
                '(its bar: ${m.bar}:1)',
          );
        }
      }
      // Tear the tree down, so the next theme starts every motion from the
      // same moment.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    }

    // One design in both themes: the light card is the dark card.
    final dark = shots[false]!;
    final light = shots[true]!;
    if (_asserting) expect(light.length, dark.length);
    for (var i = 0; i < math.min(dark.length, light.length); i++) {
      final difference = dark[i].meanDifference(light[i]);
      _report.add(
        [
          _phase,
          name,
          'light-vs-dark',
          'card $i',
          difference.toStringAsFixed(2),
          '',
          '',
          '',
          '',
        ].join('\t'),
      );
      if (_asserting) {
        expect(
          difference,
          lessThan(1.0),
          reason:
              '$name card $i differs between light and dark by '
              '$difference levels on average',
        );
      }
    }
  });
}

Rect _rectOf(Element element) {
  final box = element.renderObject! as RenderBox;
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
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
  // One fixed moment of every running motion (the mosaic's drift), the same
  // in every run so two runs compare byte for byte.
  await tester.pump(const Duration(milliseconds: 1500));
  await _settle(tester);
  // Entrances that wait a zero-length timer first start only once the clock
  // has moved; let them finish.
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

/// A square stand-in for a player's photo: head and shoulders on a backdrop.
/// [bright] puts them on a studio's white backdrop.
ui.Image _standInPhoto(int seed, {bool bright = false}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const side = 256.0;
  final hue = (seed * 47 % 360).toDouble();
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, side, side),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        const Offset(0, side),
        bright
            ? const [Color(0xFFFFFFFF), Color(0xFFF1F1EF)]
            : [
                HSLColor.fromAHSL(1, hue, 0.22, 0.42).toColor(),
                HSLColor.fromAHSL(1, hue, 0.25, 0.28).toColor(),
              ],
      ),
  );
  // Shoulders: a jacket.
  canvas.drawOval(
    const Rect.fromLTWH(side * 0.12, side * 0.7, side * 0.76, side * 0.6),
    Paint()
      ..color = HSLColor.fromAHSL(1, (hue + 200) % 360, 0.2, 0.2).toColor(),
  );
  // Neck and face.
  final skin = HSLColor.fromAHSL(1, 28, 0.42, bright ? 0.66 : 0.6).toColor();
  canvas.drawRect(
    const Rect.fromLTWH(side * 0.43, side * 0.55, side * 0.14, side * 0.2),
    Paint()..color = skin,
  );
  canvas.drawOval(
    const Rect.fromLTWH(side * 0.34, side * 0.2, side * 0.32, side * 0.4),
    Paint()..color = skin,
  );
  // Hair.
  canvas.drawArc(
    const Rect.fromLTWH(side * 0.33, side * 0.17, side * 0.34, side * 0.26),
    math.pi,
    math.pi,
    true,
    Paint()..color = const Color(0xFF2A211C),
  );
  return recorder.endRecording().toImageSync(side.toInt(), side.toInt());
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

/// The whole view's pixels, at [_ratio].
class _Pixels {
  _Pixels(this.width, this.height, this.rgba);

  final int width;
  final int height;
  final Uint8List rgba;

  int _index(int x, int y) => (y * width + x) * 4;

  /// The logical [rect]'s pixels.
  _Pixels crop(Rect rect) {
    final left = (rect.left * _ratio).round().clamp(0, width);
    final top = (rect.top * _ratio).round().clamp(0, height);
    final right = (rect.right * _ratio).round().clamp(left, width);
    final bottom = (rect.bottom * _ratio).round().clamp(top, height);
    final w = right - left;
    final h = bottom - top;
    final out = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      final from = _index(left, top + y);
      out.setRange(y * w * 4, (y + 1) * w * 4, rgba, from);
    }
    return _Pixels(w, h, out);
  }

  /// The mean difference per colour channel, in levels (0-255), from
  /// [other]; the two are compared over their common size.
  double meanDifference(_Pixels other) {
    final w = math.min(width, other.width);
    final h = math.min(height, other.height);
    if (w == 0 || h == 0) return 0;
    var sum = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final a = (y * width + x) * 4;
        final b = (y * other.width + x) * 4;
        for (var c = 0; c < 3; c++) {
          sum += (rgba[a + c] - other.rgba[b + c]).abs();
        }
      }
    }
    return sum / (w * h * 3);
  }
}

Future<_Pixels> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_root),
  );
  late _Pixels pixels;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    pixels = _Pixels(image.width, image.height, data!.buffer.asUint8List());
    image.dispose();
  });
  return pixels;
}

/// One line of type, measured against the pixels under it.
class _Measure {
  const _Measure(
    this.text,
    this.bar,
    this.glyphMin,
    this.boxMin,
    this.boxP1,
    this.worstBackground,
  );

  final String text;

  /// The contrast it must keep: 3:1 large bold, 4.5:1 otherwise.
  final double bar;

  /// The least contrast over the picture under any pixel its glyphs cover.
  final double glyphMin;

  /// The least contrast over any pixel of its line box (the strictest
  /// figure: the box takes in the line's leading and the gaps between
  /// letters, where no ink lands).
  final double boxMin;

  /// The box's 1st percentile.
  final double boxP1;

  /// The pixel under a glyph that gave [glyphMin], as 0xRRGGBB.
  final int worstBackground;
}

final List<double> _linear = [
  for (var v = 0; v < 256; v++)
    v / 255 <= 0.04045
        ? v / 255 / 12.92
        : math.pow((v / 255 + 0.055) / 1.055, 2.4).toDouble(),
];

double _luminance(num r, num g, num b) {
  double channel(num v) {
    final c = v.clamp(0, 255);
    final low = c.floor();
    final high = math.min(255, low + 1);
    final t = c - low;
    return _linear[low] * (1 - t) + _linear[high] * t;
  }

  return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
}

/// Every line of type in [cards] (titles, names, captions, ratings; a
/// two-letter title badge sits on its own fill and is left out), measured
/// against the pixels under it: the cards are drawn once more with every
/// line's ink and shadows made clear, so the picture and the card's shade
/// are all that is left. The pixels each line's glyphs cover (half or more,
/// found by comparing that draw with [full], the card as shown) are the
/// ground its ink lands on.
Future<List<_Measure>> _measureType(
  WidgetTester tester,
  Finder cards,
  _Pixels full,
) async {
  final paragraphs = <RenderParagraph>[];
  for (final card in cards.evaluate()) {
    void visit(RenderObject node) {
      if (node is RenderParagraph) {
        final text = node.text.toPlainText().trim();
        if (text.length > 3) paragraphs.add(node);
      }
      node.visitChildren(visit);
    }

    final root = card.renderObject;
    if (root != null) visit(root);
  }
  if (paragraphs.isEmpty) return const [];

  final originals = {for (final p in paragraphs) p: p.text};
  for (final p in paragraphs) {
    p.text = _clear(p.text);
  }
  await tester.pump();
  final ground = await _capture(tester);
  originals.forEach((p, text) => p.text = text);
  await tester.pump();

  final results = <_Measure>[];
  for (final p in paragraphs) {
    final text = originals[p]!;
    final inks = <Color>{};
    var bar = MediaTextScrim.largeContrast;
    void collect(
      InlineSpan span,
      Color? inherited,
      double size,
      FontWeight weight,
    ) {
      final style = span.style;
      final color = style?.color ?? inherited;
      final fontSize = style?.fontSize ?? size;
      final fontWeight = style?.fontWeight ?? weight;
      if (span is TextSpan &&
          (span.text?.trim().isNotEmpty ?? false) &&
          color != null) {
        inks.add(color);
        bar = math.max(
          bar,
          MediaTextScrim.contrastFor(
            fontSize: p.textScaler.scale(fontSize),
            weight: fontWeight,
          ),
        );
      }
      span.visitDirectChildren((child) {
        collect(child, color, fontSize, fontWeight);
        return true;
      });
    }

    collect(text, null, 14, FontWeight.w400);
    if (inks.isEmpty) continue;
    final plain = text.toPlainText();
    final transform = p.getTransformTo(null);
    final bounds = Offset.zero & p.size;
    final boxes = p.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: plain.length),
    );
    final boxValues = <double>[];
    var glyphMin = double.infinity;
    var worst = 0;
    for (final box in boxes) {
      final local = box.toRect().intersect(bounds);
      if (local.isEmpty) continue;
      final rect = MatrixUtils.transformRect(transform, local);
      final left = (rect.left * _ratio).ceil().clamp(0, ground.width);
      final top = (rect.top * _ratio).ceil().clamp(0, ground.height);
      final right = (rect.right * _ratio).floor().clamp(left, ground.width);
      final bottom = (rect.bottom * _ratio).floor().clamp(top, ground.height);
      for (var y = top; y < bottom; y++) {
        for (var x = left; x < right; x++) {
          final i = ground._index(x, y);
          final r = ground.rgba[i];
          final g = ground.rgba[i + 1];
          final b = ground.rgba[i + 2];
          final under = _luminance(r, g, b);
          final shown =
              (full.rgba[i] + full.rgba[i + 1] + full.rgba[i + 2]) / 3;
          final bare = (r + g + b) / 3;
          for (final ink in inks) {
            final a = ink.a;
            final inkR = ink.r * 255 * a + r * (1 - a);
            final inkG = ink.g * 255 * a + g * (1 - a);
            final inkB = ink.b * 255 * a + b * (1 - a);
            final over = _luminance(inkR, inkG, inkB);
            final hi = math.max(over, under);
            final lo = math.min(over, under);
            final ratio = (hi + 0.05) / (lo + 0.05);
            boxValues.add(ratio);
            // How much of the pixel the glyph covers, from how far the
            // card as shown moved from the bare picture toward the ink.
            final reach = (inkR + inkG + inkB) / 3 - bare;
            final covered = reach.abs() < 8 ? 1.0 : (shown - bare) / reach;
            if (covered >= 0.5 && ratio < glyphMin) {
              glyphMin = ratio;
              worst = (r << 16) | (g << 8) | b;
            }
          }
        }
      }
    }
    if (boxValues.isEmpty) continue;
    boxValues.sort();
    results.add(
      _Measure(
        plain.replaceAll('\n', ' '),
        bar,
        glyphMin.isFinite ? glyphMin : boxValues.first,
        boxValues.first,
        boxValues[(boxValues.length * 0.01).floor()],
        worst,
      ),
    );
  }
  return results;
}

/// [span] with its glyphs and their shadows drawn as nothing: its ink kept
/// as a foreground paint (so the card's shade, which answers to the ink,
/// stays exactly as shown) that leaves the pixels under it untouched.
InlineSpan _clear(InlineSpan span, [Color? inherited]) {
  if (span is! TextSpan) return span;
  final style = span.style;
  final ink = style?.color ?? style?.foreground?.color ?? inherited;
  TextStyle? clearStyle;
  if (style != null) {
    clearStyle = style.copyWith(
      foreground: Paint()
        ..color = ink ?? const Color(0xFFFFFFFF)
        ..blendMode = BlendMode.dst,
      shadows: const [],
      decorationColor: const Color(0x00000000),
    );
  }
  return TextSpan(
    text: span.text,
    style: clearStyle,
    children: span.children?.map((c) => _clear(c, ink)).toList(),
    semanticsLabel: span.semanticsLabel,
    locale: span.locale,
    spellOut: span.spellOut,
  );
}

/// Writes [target] (every widget it finds, together), with a margin of the
/// page around it, to `<name>_<light|dark>.png` in [_outDir].
Future<void> _save(
  WidgetTester tester,
  Finder target,
  String name,
  bool light,
) async {
  if (_outDir.isEmpty) return;
  final box = target
      .evaluate()
      .map(_rectOf)
      .reduce((a, b) => a.expandToInclude(b))
      .inflate(12);
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
