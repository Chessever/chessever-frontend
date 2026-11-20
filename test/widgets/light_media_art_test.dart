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
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/flag_pole_scene.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:chessever2/widgets/light_media_art.dart';
import 'package:country_flags/country_flags.dart';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// Light theme shows card pictures (a player's photo, the favourites strip, a
// federation's flag) crisp, at their true colour and full strength, in a
// region of their own: no veil over them, no dimming, no corner fade. The
// only fades are short ones at a picture's own edge. Dark must not change.
void main() {
  // The app's own type, so the label measures as it does on a phone (the
  // test font's square glyphs would run the title across the whole tile).
  setUpAll(() async {
    final loader = FontLoader('InterDisplay');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      loader.addFont(
        File(
          'assets/fonts/Inter-$weight.otf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
  });

  group('edge fades', () {
    double alphaAt(LinearGradient g, double t) {
      final stops = g.stops!;
      if (t <= stops.first) return g.colors.first.a;
      for (var i = 1; i < stops.length; i++) {
        if (t <= stops[i]) {
          final span = stops[i] - stops[i - 1];
          final f = span == 0 ? 1.0 : (t - stops[i - 1]) / span;
          return ui.lerpDouble(g.colors[i - 1].a, g.colors[i].a, f)!;
        }
      }
      return g.colors.last.a;
    }

    void expectSmooth(LinearGradient g) {
      expect(g.colors.length, greaterThanOrEqualTo(16));
      for (var i = 1; i < g.colors.length; i++) {
        expect((g.colors[i].a - g.colors[i - 1].a).abs(), lessThan(0.15));
      }
    }

    test('a portrait fades only along its left edge, at most 35% in', () {
      final g = portraitEdgeFade();
      expect(kPortraitFadeShare, lessThanOrEqualTo(0.35));
      expect(alphaAt(g, 0), 0);
      for (var t = kPortraitFadeShare; t <= 1; t += 0.01) {
        expect(alphaAt(g, t), 1, reason: 'opaque at $t');
      }
      var last = 0.0;
      for (var t = 0.0; t <= kPortraitFadeShare; t += 0.005) {
        final a = alphaAt(g, t);
        expect(a, greaterThanOrEqualTo(last - 1e-9));
        last = a;
      }
      expectSmooth(g);
    });

    test('a strip fades only at its two ends, at most 15% each', () {
      final g = stripEdgeFade();
      expect(kStripFadeShare, lessThanOrEqualTo(0.15));
      expect(alphaAt(g, 0), 0);
      expect(alphaAt(g, 1), 0);
      for (var t = kStripFadeShare; t <= 1 - kStripFadeShare; t += 0.01) {
        expect(alphaAt(g, t), closeTo(1, 1e-9), reason: 'opaque at $t');
      }
      expectSmooth(g);
    });

    test('the words stop short of the photo\'s opaque part', () {
      for (final height in [108.0, 120.0, 160.0]) {
        expect(
          LightCardPortrait.wordsClearance(height),
          greaterThan(LightCardPortrait.opaqueWidth(height)),
        );
        expect(
          LightCardPortrait.wordsClearance(height),
          lessThan(LightCardPortrait.width(height)),
        );
      }
    });
  });

  group('flag cloth codes', () {
    test('federations resolve to the country_flags artwork', () {
      expect(flagClothCode('TR'), 'tr');
      expect(flagClothCode('NOR'), 'no');
      expect(flagClothCode('Norway'), 'no');
      expect(flagClothCode('ENG'), 'gb-eng');
      expect(flagClothCode('SCO'), 'gb-sct');
      expect(flagClothCode('FID'), isNull);
      expect(flagClothCode('unknown'), isNull);
      expect(flagClothCode(''), isNull);
      expect(FlagCode.fromCountryCode('TR'), 'tr');
    });

    test('the light scenes are in the app bundle', () async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final asset in [
        kFlagPoleSceneAsset,
        'assets/pngs/hub_favorites_light.webp',
      ]) {
        expect(manifest.listAssets(), contains(asset));
      }
    });
  });

  group('player search cards', () {
    testWidgets('light: the photo whole at full strength on the right, no '
        'flag, no veil, words clear of it', (tester) async {
      await _pumpSearchCards(tester, light: true, count: 1);
      expect(_veils(tester), findsNothing);
      expect(_dimmed(tester, find.byType(PlayerSearchCards)), findsNothing);
      expect(_bigFlags(tester), isEmpty);
      final card = tester.getRect(find.byType(PlayerSearchCards));
      final photo = tester.getRect(_portrait());
      expect(photo.right, closeTo(card.right - 1, 0.5));
      expect(photo.height, closeTo(card.height - 2, 0.5));
      // The photo (solid red here) at its true colour wherever it is opaque.
      final red = await _pixel(
        tester,
        Offset(card.width - 12, card.height / 2),
      );
      expect(red.r, greaterThan(0.95));
      expect(red.g, lessThan(0.05));
      // Its left edge fades into the card, short.
      final edge = await _pixel(tester, Offset(photo.left - card.left + 1, 40));
      expect(edge.r, lessThan(1));
      final name = tester.getRect(find.text('Magnus Carlsen'));
      expect(
        name.right,
        lessThanOrEqualTo(card.right - LightCardPortrait.wordsClearance(120)),
      );
    });

    testWidgets('light: a half-width card shows the photo as an avatar above '
        'the name, which keeps the whole card', (tester) async {
      await _pumpSearchCards(
        tester,
        light: true,
        players: const [
          ('Abdusattorov, Nodirbek', 'UZB'),
          ('Firouzja, Alireza', 'FRA'),
        ],
      );
      expect(find.byType(LightEdgeFade), findsNothing);
      expect(_bigFlags(tester), isEmpty);
      // The name rule: the full name when it fits, else the first name's
      // initial and the rest; a fade only as a last resort.
      const shown = {
        'Nodirbek Abdusattorov': 'N. Abdusattorov',
        'Alireza Firouzja': 'Alireza Firouzja',
      };
      for (final MapEntry(key: name, value: form) in shown.entries) {
        final text = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is LightCardName && w.name == name,
          ),
          matching: find.text(form),
        );
        expect(text, findsOneWidget, reason: name);
        final card = tester.getRect(
          find.ancestor(of: text, matching: find.byType(GestureDetector)).first,
        );
        final avatar = tester.getRect(
          find.descendant(
            of: find.ancestor(of: text, matching: find.byType(Column)).first,
            matching: find.byType(LightAvatarPhoto),
          ),
        );
        // A circle in the card's top-right corner, as far from the top as
        // from the side (the room above the name, up to the Favorites
        // photos' size), its foot level with the badge's, clear above the
        // name.
        expect(avatar.width, closeTo(avatar.height, 0.01));
        expect(avatar.width, inInclusiveRange(32, 36));
        expect(avatar.right, closeTo(card.right - 1 - 12, 0.5));
        expect(avatar.top, closeTo(card.top + 1 + 12, 0.5));
        final badge = find.descendant(
          of: find.ancestor(of: text, matching: find.byType(Column)).first,
          matching: find.text('GM'),
        );
        expect(avatar.bottom, closeTo(tester.getRect(badge).bottom + 2, 0.5));
        expect(avatar.bottom, lessThanOrEqualTo(tester.getRect(text).top));
        // Whole, never faded, never shrunk.
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: text, matching: find.byType(RichText)),
        );
        expect(
          paragraph.getMaxIntrinsicWidth(double.infinity),
          lessThanOrEqualTo(paragraph.size.width + 0.5),
          reason: name,
        );
        // A screen reader hears the full name.
        expect(tester.widget<Text>(text).semanticsLabel, name);
      }
      // The avatar at full strength (solid red here).
      final avatar = tester.getRect(find.byType(LightAvatarPhoto).first);
      final origin = tester.getTopLeft(find.byKey(_capture));
      final red = await _pixel(tester, avatar.center - origin);
      expect(red.r, greaterThan(0.95));
      expect(red.g, lessThan(0.05));
    });

    testWidgets('light: no photo, a plain card', (tester) async {
      await _pumpSearchCards(tester, light: true, count: 1, photo: false);
      expect(find.byType(LightEdgeFade), findsNothing);
      expect(find.byType(RawImage), findsNothing);
      expect(find.byIcon(Icons.person_rounded), findsNothing);
      expect(_bigFlags(tester), isEmpty);
    });

    for (final count in [1, 2]) {
      testWidgets('light: a photo that fails to load leaves the words their '
          'whole card (${count == 1 ? 'full' : 'half'} width)', (tester) async {
        await _pumpSearchCards(
          tester,
          light: true,
          count: count,
          failing: true,
        );
        final name = find.text('Magnus Carlsen');
        final inset = count == 1 ? 14.0 : 12.0;
        void expectWholeCard() {
          expect(find.byType(LightEdgeFade), findsNothing);
          expect(find.byType(RawImage), findsNothing);
          expect(find.byType(ClipOval), findsNothing);
          final card = tester.getRect(
            find
                .ancestor(of: name, matching: find.byType(GestureDetector))
                .first,
          );
          final column = tester.getRect(
            find.ancestor(of: name, matching: find.byType(Column)).first,
          );
          expect(column.right, closeTo(card.right - 1 - inset, 0.5));
        }

        // While the photo loads the words already have the whole card, so
        // they never move when it fails...
        expectWholeCard();
        final before = tester.getRect(name);
        _failPhotos();
        await tester.pump();
        // ...and they keep it.
        expectWholeCard();
        expect(tester.getRect(name), before);
      });
    }

    testWidgets('dark keeps its flag, its veil and its dimming', (
      tester,
    ) async {
      await _pumpSearchCards(tester, light: false, count: 2);
      expect(_veils(tester), findsNWidgets(2));
      expect(_dimmed(tester, find.byType(PlayerSearchCards)), findsWidgets);
      expect(_bigFlags(tester), hasLength(2));
      expect(find.byType(LightPortraitCard), findsNothing);
      expect(find.byType(LightAvatarPhoto), findsNothing);
    });
  });

  group('TWIC player cards', () {
    for (final light in [true, false]) {
      testWidgets(light ? 'light: no veil, no flag' : 'dark keeps its veil', (
        tester,
      ) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              topTwicSearchedPlayersProvider.overrideWith(
                (ref, query) => const [
                  GamebasePlayer(
                    id: 'p1',
                    fideId: '',
                    name: 'Carlsen, Magnus',
                    gender: PlayerGender.male,
                    fed: 'NOR',
                  ),
                ],
              ),
            ],
            child: _app(
              light: light,
              child: const TwicPlayerSearchCards(searchQuery: 'carlsen'),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(_veils(tester), light ? findsNothing : findsOneWidget);
        expect(
          _dimmed(tester, find.byType(TwicPlayerSearchCards)),
          light ? findsNothing : findsWidgets,
        );
      });
    }
  });

  group('Today: Favorites and Countrymen', () {
    testWidgets('light: the flag flies in the picture band above the title, '
        'centred, matched to the photos, at its true colour', (tester) async {
      await _pumpToday(tester, light: true);
      final faces = tester.widgetList<HubTileFace>(find.byType(HubTileFace));
      expect(faces.every((face) => !face.ramp), isTrue);
      expect(
        _dimmed(tester, find.byType(PremiumCollectionCards)),
        findsNothing,
      );
      expect(find.byType(FlagPoleScene), findsOneWidget);
      expect(find.byType(WavingFlag), findsOneWidget);

      final scene = tester.widget<FlagPoleScene>(find.byType(FlagPoleScene));
      expect(scene.flagCode, 'no');
      final tileFinder = find.ancestor(
        of: find.byType(FlagPoleScene),
        matching: find.byType(HubTileFace),
      );
      final tile = tester.getRect(tileFinder);
      final capTop = HubTileFace.labelCapTop(
        tester.element(find.byType(FlagPoleScene)),
        title: 'Countrymen',
        height: tile.height - 2,
      );
      final layout = scene.layout(
        FlagClothArt.aspectOf(FlagClothArt.known('no')),
      );
      // The finial clear of the tile's top edge; the cloth, its swing and
      // the mound's fade all end above the title's capitals.
      expect(layout.finialTop, greaterThanOrEqualTo(7 - 0.01));
      final cloth = tester.getRect(find.byType(WavingFlag));
      expect(cloth.height, closeTo(layout.cloth.height, 0.01));
      expect(
        cloth.bottom + cloth.height * 0.075,
        lessThan(tile.top + 1 + capTop),
      );
      expect(scene.groundLine, lessThan(capTop));
      // The pole and its flag centred across the tile.
      final inner = tile.width - 2;
      expect(layout.finialLeft, closeTo(inner - layout.flyRight, 0.01));
      // The cloth as tall as the photos beside it, give or take the room
      // the pole needs; at the default size, 4:3 Norway near 46x34.
      expect(layout.cloth.height, greaterThan(30));
      expect(layout.cloth.width, greaterThan(40));

      // Norway's red at full strength in the fly half of the cloth.
      final red = await _pixel(
        tester,
        cloth.topLeft -
            tester.getTopLeft(find.byKey(_capture)) +
            Offset(cloth.width * 0.78, cloth.height * 0.18),
      );
      expect(red.r, greaterThan(0.7));
      expect(red.g, lessThan(0.35));
    });

    testWidgets('light: the photos glide in the band above the title, '
        'centred in it, moving on a layer of their own', (tester) async {
      await _pumpToday(tester, light: true);
      expect(find.byType(LightEdgeFade), findsOneWidget);
      final tileFinder = find.ancestor(
        of: find.byType(LightEdgeFade),
        matching: find.byType(HubTileFace),
      );
      final tile = tester.getRect(tileFinder);
      final capTop =
          tile.top +
          1 +
          HubTileFace.labelCapTop(
            tester.element(find.byType(LightEdgeFade)),
            title: 'Favorites',
            height: tile.height - 2,
          );
      final strip = tester.getRect(find.byType(LightEdgeFade));
      // As much room above the strip as below it, to the capitals.
      expect(strip.top - (tile.top + 1), closeTo(capTop - strip.bottom, 0.5));
      final photos = find.descendant(
        of: find.byType(PremiumCollectionCards),
        matching: find.byType(ClipOval),
      );
      expect(photos, findsWidgets);
      final title = tester.getRect(find.text('Favorites'));
      for (final photo in tester.widgetList(photos)) {
        final rect = tester.getRect(find.byWidget(photo));
        expect(rect.bottom, lessThanOrEqualTo(title.top + 1));
      }
      // The moving strip repaints inside its own layer, under the tile.
      expect(
        find.descendant(
          of: tileFinder,
          matching: find.ancestor(
            of: find.byType(LightEdgeFade),
            matching: find.byType(RepaintBoundary),
          ),
        ),
        findsWidgets,
      );
      // The stands' seats rise no higher than the photos' centre line.
      final stands = find.byWidgetPredicate((widget) {
        if (widget is! Image) return false;
        var image = widget.image;
        if (image is ResizeImage) image = image.imageProvider;
        return image is AssetImage &&
            image.assetName.contains('favorites_light');
      });
      final picture = tester.getRect(stands);
      expect(
        picture.top + picture.height * 332 / 1024,
        greaterThanOrEqualTo(strip.center.dy - 0.01),
      );
    });

    testWidgets('dark: the media tiles as before', (tester) async {
      await _pumpToday(tester, light: false);
      final faces = tester.widgetList<HubTileFace>(find.byType(HubTileFace));
      expect(faces.every((face) => face.ramp), isTrue);
      expect(find.byType(FlagPoleScene), findsNothing);
      expect(find.byType(LightEdgeFade), findsNothing);
      expect(
        _dimmed(tester, find.byType(PremiumCollectionCards)),
        findsOneWidget,
      );
    });
  });

  group('the waving flag', () {
    testWidgets('waves by repainting only, and stops when its ticker is off', (
      tester,
    ) async {
      Widget flag({required bool ticking}) => Directionality(
        textDirection: TextDirection.ltr,
        child: TickerMode(
          enabled: ticking,
          child: const Center(
            child: SizedBox(
              width: 60,
              height: 40,
              child: WavingFlag(art: null),
            ),
          ),
        ),
      );
      await tester.pumpWidget(flag(ticking: true));
      expect(tester.hasRunningAnimations, isTrue);
      Finder paint() => find.descendant(
        of: find.byType(WavingFlag),
        matching: find.byType(CustomPaint),
      );
      final before = tester.widget(paint());
      await tester.pump(const Duration(milliseconds: 700));
      // The same widget: the frame was a repaint, not a rebuild.
      expect(identical(tester.widget(paint()), before), isTrue);

      await tester.pumpWidget(flag(ticking: false));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('My Space Countrymen tile', () {
    for (final light in [true, false]) {
      testWidgets(
        light ? 'light: the flag on its pole' : 'dark: dimmed as before',
        (tester) async {
          await tester.pumpWidget(
            ProviderScope(
              child: _app(
                light: light,
                child: SpaceTileContent(
                  shortcut: SpaceShortcut.draft(
                    kind: SpaceShortcutKind.countrymen,
                    targetId: 'NOR',
                    title: 'Norway',
                    subtitle: 'Countrymen',
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(
            _dimmed(tester, find.byType(SpaceTileContent)),
            light ? findsNothing : findsOneWidget,
          );
          expect(
            find.byType(FlagPoleScene),
            light ? findsOneWidget : findsNothing,
          );
          if (light) {
            final scene = tester.widget<FlagPoleScene>(
              find.byType(FlagPoleScene),
            );
            expect(scene.flagCode, 'no');
            // The cloth stays above the name.
            final name = tester.getRect(find.text('Norway'));
            final cloth = tester.getRect(find.byType(WavingFlag));
            expect(cloth.bottom, lessThan(name.top));
            // The pole and its flag centred across the picture: finial to
            // the fly's resting edge, at the flag's own proportions.
            final layout = scene.layout(
              FlagClothArt.aspectOf(FlagClothArt.known('no')),
            );
            final box = tester.getRect(
              find
                  .ancestor(
                    of: find.byType(FlagPoleScene),
                    matching: find.byType(Positioned),
                  )
                  .first,
            );
            expect(
              layout.finialLeft,
              closeTo(box.width - layout.flyRight, 0.01),
            );
            expect(cloth.width, closeTo(layout.cloth.width, 0.01));
          }
        },
      );
    }
  });

  group('Discovery tour Countrymen tile', () {
    for (final light in [true, false]) {
      testWidgets(light ? 'light: the flag on its pole' : 'dark: as before', (
        tester,
      ) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              countryDropdownProvider.overrideWith((ref) => _Country()),
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
            child: _app(
              light: light,
              child: PremiumTourSection(
                onShowMostLiked: () {},
                onShowAnalyzed: () {},
              ),
            ),
          ),
        );
        await tester.pump();
        final tile = find.byKey(const ValueKey('tour_countrymen'));
        expect(tile, findsOneWidget);
        expect(
          find.descendant(of: tile, matching: find.byType(FlagPoleScene)),
          light ? findsOneWidget : findsNothing,
        );
        expect(_dimmed(tester, tile), light ? findsNothing : findsOneWidget);
        if (light) {
          await _settle(tester);
          final scene = tester.widget<FlagPoleScene>(
            find.descendant(of: tile, matching: find.byType(FlagPoleScene)),
          );
          final layout = scene.layout(
            FlagClothArt.aspectOf(FlagClothArt.known('no')),
          );
          final box = tester.getRect(
            find.descendant(of: tile, matching: find.byType(FlagPoleScene)),
          );
          expect(layout.finialLeft, closeTo(box.width - layout.flyRight, 0.01));
        }
      });
    }
  });
}

const _capture = ValueKey('light_media_capture');

Widget _app({required bool light, required Widget child}) {
  return MaterialApp(
    theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
    home: Builder(
      builder: (context) {
        ResponsiveHelper.init(context);
        return Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: RepaintBoundary(key: _capture, child: child),
            ),
          ),
        );
      },
    ),
  );
}

/// A phone's view, so the cards lay out at their real sizes.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(393 * 3, 852 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Lets asset loads and decodes land without moving the test clock.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

Future<void> _pumpSearchCards(
  WidgetTester tester, {
  required bool light,
  int count = 2,
  List<(String, String)>? players,
  bool photo = true,
  bool failing = false,
}) async {
  _phone(tester);
  final shown = [
    for (final (name, fed)
        in players ??
            const [
              ('Carlsen, Magnus', 'NOR'),
              ('Abdusattorov, Nodirbek', 'UZB'),
            ].take(count))
      SearchPlayer(
        id: name,
        name: name,
        fed: fed,
        rating: 2800,
        title: 'GM',
        tournamentId: 't',
        tournamentName: 'T',
        memorialSourceIdentity: photo ? 'test' : null,
      ),
  ];
  if (photo) {
    final urls = [
      for (final p in shown)
        memorialPlayerPhotoUrl(playerName: p.name, sourceIdentity: 'test')!,
    ];
    if (failing) {
      _seedFailingPhoto(urls);
    } else {
      await _seedSolidPhoto(tester, urls);
    }
  }
  await tester.pumpWidget(
    ProviderScope(
      child: _app(
        light: light,
        child: PlayerSearchCards(
          players: shown,
          animateIn: false,
          bottomPadding: 0,
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _pumpToday(WidgetTester tester, {required bool light}) async {
  _phone(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        countryDropdownProvider.overrideWith((ref) => _Country()),
        favoritePlayersProviderNew.overrideWith(_Favorites.new),
      ],
      child: _app(light: light, child: const PremiumCollectionCards()),
    ),
  );
  await _settle(tester);
  await tester.pump(const Duration(milliseconds: 300));
  await _settle(tester);
}

/// Answers each of [urls] from memory with a solid red picture, under every
/// key a card can ask for it by.
Future<void> _seedSolidPhoto(WidgetTester tester, List<String> urls) async {
  PaintingBinding.instance.imageCache.clear();
  final image = (await tester.runAsync(() {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, 40, 40),
      Paint()..color = const Color(0xFFFF0000),
    );
    return recorder.endRecording().toImage(40, 40);
  }))!;
  final cache = PaintingBinding.instance.imageCache;
  for (final url in urls) {
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
      ).obtainKey(ImageConfiguration.empty).then(put);
    }
  }
}

/// Answers each of [urls] with a photo still loading, under every key a card
/// can ask for it by; [_failPhotos] then fails them all.
void _seedFailingPhoto(List<String> urls) {
  final cache = PaintingBinding.instance.imageCache..clear();
  _failing.clear();
  for (final url in urls) {
    final completer = _FailingPhoto();
    _failing.add(completer);
    final provider = CachedNetworkImageProvider(url);
    void put(Object key) => cache.putIfAbsent(key, () => completer);
    put(provider);
    for (var side = 24; side <= 720; side++) {
      ResizeImage(
        provider,
        width: side,
      ).obtainKey(ImageConfiguration.empty).then(put);
    }
  }
}

final List<_FailingPhoto> _failing = [];

/// Fails every photo [_seedFailingPhoto] left loading.
void _failPhotos() {
  for (final photo in _failing) {
    photo.fail();
  }
}

class _FailingPhoto extends ImageStreamCompleter {
  void fail() => reportError(exception: StateError('no photo'));
}

/// The width a card's words may take: their column's.
double _room(WidgetTester tester, Finder text) => tester
    .getSize(find.ancestor(of: text, matching: find.byType(Column)).first)
    .width;

/// The light full-width card's portrait: the photo under its edge fade.
Finder _portrait() => find.descendant(
  of: find.byType(LightPortraitCard),
  matching: find.byType(LightEdgeFade),
);

/// A surface-coloured gradient laid over a card: the dark veil.
Finder _veils(WidgetTester tester) {
  final surface = tester
      .element(find.byKey(_capture))
      .colors
      .surface
      .withValues(alpha: 1);
  return find.byWidgetPredicate((widget) {
    if (widget is! DecoratedBox) return false;
    final decoration = widget.decoration;
    if (decoration is! BoxDecoration) return false;
    final gradient = decoration.gradient;
    if (gradient == null) return false;
    return gradient.colors.any(
      (c) => c.a > 0 && c.withValues(alpha: 1) == surface,
    );
  });
}

/// A picture dimmed by an opacity under [scope].
Finder _dimmed(WidgetTester tester, Finder scope) => find.descendant(
  of: scope,
  matching: find.byWidgetPredicate(
    (widget) => widget is Opacity && widget.opacity > 0 && widget.opacity < 1,
  ),
);

/// Flags drawn larger than the small one beside the rating: a flag
/// background.
List<CountryFlag> _bigFlags(WidgetTester tester) =>
    tester.widgetList<CountryFlag>(find.byType(CountryFlag)).where((flag) {
      final theme = flag.theme;
      return theme is ImageTheme && (theme.width ?? 0) > 40;
    }).toList();

Future<Color> _pixel(WidgetTester tester, Offset at) async {
  final boundary =
      tester.renderObject(find.byKey(_capture)) as RenderRepaintBoundary;
  late Color color;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final x = at.dx.round().clamp(0, image.width - 1);
    final y = at.dy.round().clamp(0, image.height - 1);
    final i = (y * image.width + x) * 4;
    final bytes = data!.buffer.asUint8List();
    color = Color.fromARGB(bytes[i + 3], bytes[i], bytes[i + 1], bytes[i + 2]);
    image.dispose();
  });
  return color;
}

class _Country extends StateNotifier<AsyncValue<Country>>
    implements SelectedCountryNotifier {
  _Country() : super(AsyncData(CountryService().findByCode('NO')!));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Favorites extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => [
    for (final (i, name) in const [
      'Carlsen, Magnus',
      'Nakamura, Hikaru',
      'Caruana, Fabiano',
    ].indexed)
      FavoritePlayer(
        id: 'f$i',
        userId: 'u',
        playerName: name,
        metadata: const {},
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
  ];
}
