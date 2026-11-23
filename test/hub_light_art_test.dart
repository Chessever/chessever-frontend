import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/hub_context_art.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Set to a directory to write each tile, in both themes, as a PNG.
const _previewDir = String.fromEnvironment('HUB_PREVIEW_DIR');

Future<ui.Image> _decode(String asset) async {
  final bytes = await rootBundle.load(asset);
  final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

Widget _tile({
  required bool light,
  required Widget artwork,
  String title = 'Reports',
  String caption = 'Games with analysis',
}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  home: Builder(
    builder: (context) {
      ResponsiveHelper.init(context);
      return Material(
        child: Center(
          child: RepaintBoundary(
            key: const ValueKey('capture'),
            child: SizedBox(
              width: 174,
              child: HubTile(
                title: title,
                caption: caption,
                artwork: artwork,
                onTap: () {},
              ),
            ),
          ),
        ),
      );
    },
  ),
);

/// What each scene's tile says where it is used, so the words are measured
/// against the drawing they sit on.
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
  HubScene.events: ('Events', 'Current, upcoming and past'),
};

/// The readability ramp the tile lays over its artwork.
LinearGradient _ramp(WidgetTester tester) {
  final boxes = tester
      .widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(HubTileFace),
          matching: find.byType(DecoratedBox),
        ),
      )
      .map((box) => box.decoration)
      .whereType<BoxDecoration>()
      .where((decoration) => decoration.gradient != null)
      .toList();
  expect(boxes, hasLength(1));
  return boxes.single.gradient! as LinearGradient;
}

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

  test(
    'every scene ships its own light drawing at its dark one\'s size',
    () async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final scene in HubScene.values) {
        final dark = HubSceneBackdrop.darkAsset(scene);
        final light = HubSceneBackdrop.lightAsset(scene);
        expect(light, isNot(dark));
        expect(light, dark.replaceFirst('.webp', '_light.webp'));
        expect(manifest.listAssets(), containsAll([dark, light]));
        final darkImage = await _decode(dark);
        final lightImage = await _decode(light);
        expect(
          [lightImage.width, lightImage.height],
          [darkImage.width, darkImage.height],
          reason: '$light is drawn at $dark\'s size',
        );
        darkImage.dispose();
        lightImage.dispose();
      }
    },
  );

  test(
    'Events ships its pair at 768 x 512, each on its own tile\'s ground',
    () async {
      // The full-row Events tile shows its picture beside the tile's own base,
      // so each drawing's field must be that base or a seam shows where the
      // picture begins.
      Future<(ui.Image, ByteData)> pixels(String asset) async {
        final image = await _decode(asset);
        final bytes = await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        return (image, bytes!);
      }

      Color at(ui.Image image, ByteData bytes, int x, int y) {
        final i = (y * image.width + x) * 4;
        return Color.fromARGB(
          bytes.getUint8(i + 3),
          bytes.getUint8(i),
          bytes.getUint8(i + 1),
          bytes.getUint8(i + 2),
        );
      }

      // Compared as the 8-bit levels the screen shows.
      void expectNear(Color actual, Color expected, int tolerance, String why) {
        for (final (a, e) in [
          (actual.r, expected.r),
          (actual.g, expected.g),
          (actual.b, expected.b),
        ]) {
          expect(
            ((a * 255).round() - (e * 255).round()).abs(),
            lessThanOrEqualTo(tolerance),
            reason: why,
          );
        }
        expect(
          actual.a,
          1.0,
          reason: '$why: drawn opaque, like its neighbours',
        );
      }

      final dark = HubSceneBackdrop.darkAsset(HubScene.events);
      final light = HubSceneBackdrop.lightAsset(HubScene.events);
      expect(dark, 'assets/pngs/hub_events_simple.webp');
      expect(light, 'assets/pngs/hub_events_simple_light.webp');
      final paper = Color.lerp(
        AppColors.light.background,
        AppColors.light.surface,
        0.45,
      )!;
      // The light drawing is lossless and its field is the paper base to the
      // level: across the band where the picture fades into the tile, even
      // one level shows as a faint vertical stripe on the flat paper.
      for (final (asset, ground, tolerance) in [
        (dark, kHubTileInk, 2),
        (light, paper, 0),
      ]) {
        final (image, bytes) = await pixels(asset);
        expect([image.width, image.height], [768, 512], reason: asset);
        // The label's corner and the picture's left edge (the fade band, its
        // first fifth) are the tile's own ground; the subject sits up and to
        // the right.
        for (final (x, y) in [
          (4, 4),
          (4, 256),
          (4, 507),
          (84, 128),
          (168, 128),
          (168, 384),
          (200, 480),
        ]) {
          expectNear(
            at(image, bytes, x, y),
            ground,
            tolerance,
            '$asset ($x, $y)',
          );
        }
        image.dispose();
      }
    },
  );

  for (final light in [false, true]) {
    final theme = light ? 'light' : 'dark';
    testWidgets('$theme tiles show the $theme drawing', (tester) async {
      // A 393pt phone, where a Discovery tile is 174 wide and 108 tall.
      tester.view.physicalSize = const Size(393 * 3, 852 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      for (final scene in HubScene.values) {
        final (title, caption) = _words[scene]!;
        await tester.pumpWidget(
          _tile(
            light: light,
            artwork: HubSceneBackdrop(scene: scene),
            title: title,
            caption: caption,
          ),
        );
        final art = find.descendant(
          of: find.byType(HubSceneBackdrop),
          matching: find.byType(Image),
        );
        final image = tester.widget<Image>(art);
        expect(
          ((image.image as ResizeImage).imageProvider as AssetImage).assetName,
          light
              ? HubSceneBackdrop.lightAsset(scene)
              : HubSceneBackdrop.darkAsset(scene),
          reason: '$scene in $theme',
        );
        final faded = tester
            .widgetList<Opacity>(
              find.descendant(
                of: find.byType(HubSceneBackdrop),
                matching: find.byType(Opacity),
              ),
            )
            .where((opacity) => opacity.opacity < 1);
        // Light shows its drawing at full strength: never a dimmed copy.
        expect(faded, isEmpty, reason: '$scene in $theme');

        final ramp = _ramp(tester);
        if (light) {
          // No veil across the drawing: at most a faint breath of the
          // tile's own tone in the label's corner.
          expect(ramp.begin, Alignment.bottomLeft);
          for (final color in ramp.colors) {
            expect(color.a, lessThanOrEqualTo(0.5));
          }
        } else {
          // Dark keeps the media tile's ramp exactly.
          expect(ramp.begin, Alignment.topCenter);
          expect(ramp.end, Alignment.bottomCenter);
          expect(ramp.colors, [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.6),
            Colors.black.withValues(alpha: 0.95),
          ]);
          expect(ramp.stops, const [0.0, 0.5, 1.0]);
        }

        if (_previewDir.isNotEmpty) {
          await tester.runAsync(
            () => precacheImage(image.image, tester.element(art)),
          );
          await tester.pump();
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')),
          );
          await tester.runAsync(() async {
            final capture = await boundary.toImage(pixelRatio: 3);
            final bytes = await capture.toByteData(
              format: ui.ImageByteFormat.png,
            );
            capture.dispose();
            await Directory(_previewDir).create(recursive: true);
            await File(
              '$_previewDir/${scene.name}_$theme.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          });
        }
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('artwork with no light drawing keeps the paper veil', (
    tester,
  ) async {
    // A photo mosaic or a flag (Today's Favorites and Countrymen) is not
    // drawn for paper, so the light tile still grades it down at the label.
    await tester.pumpWidget(
      _tile(light: true, artwork: const ColoredBox(color: Color(0xFF2C3F43))),
    );
    final ramp = _ramp(tester);
    expect(ramp.begin, Alignment.topCenter);
    expect(ramp.colors.last.a, closeTo(0.92, 0.001));
  });
}
