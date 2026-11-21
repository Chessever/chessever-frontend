import 'dart:io';

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/hub_context_art.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:chessever2/widgets/media_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The hub tiles (Today's pair, My Space's Prep and Library, Discovery) are a
// media card: ONE design in both themes, the dark one. A light page shows
// the very tile dark mode shows, its drawing at full strength, the label
// carried by one smooth shade out of its corner, only as deep as the
// drawing's brightest pixel needs. The pixel-level checks (type against the
// pixels under its glyphs, light against dark) live in
// light_media_cards_preview_test.dart.

/// What each scene's tile says where it is used.
const _words = <HubScene, (String, String)>{
  HubScene.feed: ('Feed', 'Nepomniachtchi vs Firouzja'),
  HubScene.news: ('News', 'Latest headlines'),
  HubScene.miniatures: ('Miniatures', '25 moves or fewer'),
  HubScene.reports: ('Reports', 'Games with analysis'),
  HubScene.library: ('Library', 'Your databases'),
  HubScene.smartEvents: ('Smart events', 'Tap to view'),
  HubScene.mostLiked: ('Likes', 'Community favorites'),
  HubScene.myPrep: ('Prep', 'Your games and opponents'),
  HubScene.collections: ('Collections', 'Curated games and books'),
};

Widget _tile({
  required bool light,
  required Widget artwork,
  String title = 'Reports',
  String caption = 'Games with analysis',
  bool ramp = true,
}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  home: Builder(
    builder: (context) {
      ResponsiveHelper.init(context);
      return Material(
        child: Center(
          child: SizedBox(
            width: 174,
            child: HubTile(
              title: title,
              caption: caption,
              artwork: artwork,
              ramp: ramp,
              onTap: () {},
            ),
          ),
        ),
      );
    },
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test('every scene has its one drawing in the bundle, and the retired '
      'light drawings are gone', () async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = manifest.listAssets();
    for (final scene in HubScene.values) {
      expect(assets, contains(HubSceneBackdrop.asset(scene)));
    }
    expect(
      Directory('assets/pngs')
          .listSync()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n.startsWith('hub_') && n.endsWith('_light.webp')),
      isEmpty,
    );
  });

  for (final light in [false, true]) {
    final theme = light ? 'light' : 'dark';
    testWidgets('$theme: every scene is the dark media tile', (tester) async {
      tester.view.physicalSize = const Size(393 * 3, 852 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      for (final scene in HubScene.values) {
        final (title, caption) = _words[scene]!;
        final framed = scene == HubScene.myPrep || scene == HubScene.library;
        await tester.pumpWidget(
          _tile(
            light: light,
            artwork: HubSceneBackdrop(scene: scene),
            title: title,
            caption: caption,
            // As My Space sets its study scenes: they fade clear of the
            // label on their own.
            ramp: !framed,
          ),
        );
        final art = find.descendant(
          of: find.byType(HubSceneBackdrop),
          matching: find.byType(Image),
        );
        final image = tester.widget<Image>(art);
        expect(
          ((image.image as ResizeImage).imageProvider as AssetImage).assetName,
          HubSceneBackdrop.asset(scene),
          reason: '$scene in $theme',
        );
        // The art resolves the dark theme, whatever the page's.
        expect(
          Theme.of(tester.element(art)).brightness,
          Brightness.dark,
          reason: '$scene in $theme',
        );
        // At full strength: never a dimmed copy.
        expect(
          tester
              .widgetList<Opacity>(
                find.descendant(
                  of: find.byType(HubSceneBackdrop),
                  matching: find.byType(Opacity),
                ),
              )
              .where((o) => o.opacity < 1),
          isEmpty,
        );
        // No gradient laid across the artwork: the only shade is the one
        // behind the label.
        expect(
          tester
              .widgetList<DecoratedBox>(
                find.descendant(
                  of: find.byType(HubTileFace),
                  matching: find.byType(DecoratedBox),
                ),
              )
              .map((b) => b.decoration)
              .whereType<BoxDecoration>()
              .where((d) => d.gradient != null),
          isEmpty,
        );
        expect(
          find.descendant(
            of: find.byType(HubTileFace),
            matching: find.byType(MediaTextScrim),
          ),
          framed ? findsNothing : findsOneWidget,
        );
        // The dark tile's own ink and white type.
        final plate = tester
            .widgetList<Container>(
              find.descendant(
                of: find.byType(HubTileFace),
                matching: find.byType(Container),
              ),
            )
            .map((c) => c.decoration)
            .whereType<BoxDecoration>()
            .firstWhere((d) => d.color != null);
        expect(plate.color, kHubTileInk);
        expect((plate.border! as Border).top.color, AppColors.dark.divider);
        expect(tester.widget<Text>(find.text(title)).style!.color, kMediaOnInk);
        expect(
          tester.widget<Text>(find.text(caption)).style!.color,
          kMediaOnInkQuiet,
        );
        expect(tester.takeException(), isNull);
      }
    });
  }

  group('the shade behind the words', () {
    // How the shade itself is made (one gradient out of the words' corner,
    // no layer, each line at its bar) is pinned in media_card_parts_test.dart;
    // here, what each hub tile tells it about its ground.
    for (final scene in HubScene.values) {
      if (scene == HubScene.myPrep || scene == HubScene.library) continue;
      testWidgets('$scene: the shade knows the brightest its drawing gets', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(393 * 3, 852 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final (title, caption) = _words[scene]!;
        await tester.pumpWidget(
          _tile(
            light: false,
            artwork: HubSceneBackdrop(scene: scene),
            title: title,
            caption: caption,
          ),
        );
        final scrim = tester.widget<MediaTextScrim>(
          find.byType(MediaTextScrim),
        );
        expect(scrim.ground, HubSceneBackdrop.brightest(scene));
        final render = tester.renderObject<RenderMediaTextScrim>(
          find.byType(MediaTextScrim),
        );
        // The title (large, bold), the caption and its arrow.
        final lines = render.lines();
        expect(lines.length, greaterThanOrEqualTo(3));
        expect(lines.first.contrast, MediaTextScrim.largeContrast);
        expect(
          lines.map((l) => l.contrast),
          contains(MediaTextScrim.bodyContrast),
        );
        final shape = render.shape();
        if (scene == HubScene.mostLiked) {
          // Dark red on black: white type already reads, so the heart is
          // left exactly as drawn.
          expect(shape, isNull);
        } else {
          // Anchored at the label's corner (bottom-left), no deeper than a
          // white picture would need.
          expect(shape, isNotNull);
          expect(shape!.anchor, Offset(0, render.size.height));
          expect(shape.floor, greaterThan(0));
          expect(
            shape.floor,
            lessThanOrEqualTo(
              MediaTextScrim.shadeFor(
                kMediaOnInkQuiet,
                contrast: MediaTextScrim.bodyContrast + MediaTextScrim.margin,
              ),
            ),
          );
          // The picture's top edge, away from the label, is left lighter
          // than the label's corner.
          expect(
            shape.alphaAt(Offset(render.size.width, 0)),
            lessThan(shape.floor * 0.5),
          );
        }
      });
    }

    testWidgets('a photo or a flag can put white anywhere: full ground', (
      tester,
    ) async {
      await tester.pumpWidget(
        _tile(
          light: true,
          artwork: const ColoredBox(color: Color(0xFFFFFFFF)),
          title: 'Countrymen',
          caption: 'Tap to view',
        ),
      );
      expect(
        tester.widget<MediaTextScrim>(find.byType(MediaTextScrim)).ground,
        1,
      );
    });

    testWidgets('the label carries a tight shadow; a mark tile\'s does not', (
      tester,
    ) async {
      await tester.pumpWidget(
        _tile(
          light: true,
          artwork: const ColoredBox(color: Color(0xFFFFFFFF)),
          title: 'Countrymen',
          caption: 'Tap to view',
        ),
      );
      expect(
        tester.widget<Text>(find.text('Countrymen')).style!.shadows,
        kMediaTitleShadows,
      );
      expect(
        tester.widget<Text>(find.text('Tap to view')).style!.shadows,
        kMediaCaptionShadows,
      );
      for (final shadow in [...kMediaTitleShadows, ...kMediaCaptionShadows]) {
        // Tight and from above: a small blur, one point down, never a halo.
        expect(shadow.blurRadius, inInclusiveRange(4, 8));
        expect(shadow.offset, const Offset(0, 1));
        expect(shadow.color.a, inInclusiveRange(0.35, 0.45));
      }
    });
  });
}
