import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/hub_context_art.dart';
import 'package:chessever2/widgets/media_card.dart';
import 'package:chessever2/widgets/player_initials_avatar.dart';
import 'package:country_flags/country_flags.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// The parts every media card is made of: the vector flag behind it, in its
// own colours; the title badge on it; the one smooth shade out of the
// words' corner, as light as each line's bar allows (3:1 large bold, 4.5:1
// smaller), painted as a single gradient with no layer; and the portrait's
// fade, solid over the face.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader('Inter');
    for (final weight in ['Regular', 'Bold']) {
      loader.addFont(
        File(
          'assets/fonts/Inter-$weight.otf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
  });

  group('the flag behind a media card', () {
    test('every way a federation is written finds its vector flag', () {
      // ISO alpha-2, FIDE codes (some unlike ISO alpha-3), country names.
      expect(MediaFlagBackdrop.flagCodeOf('NO'), 'NO');
      expect(MediaFlagBackdrop.flagCodeOf('NOR'), 'NO');
      expect(MediaFlagBackdrop.flagCodeOf('GER'), 'DE');
      expect(MediaFlagBackdrop.flagCodeOf('NED'), 'NL');
      expect(MediaFlagBackdrop.flagCodeOf('SUI'), 'CH');
      expect(MediaFlagBackdrop.flagCodeOf('TUR'), 'TR');
      expect(MediaFlagBackdrop.flagCodeOf('JPN'), 'JP');
      expect(MediaFlagBackdrop.flagCodeOf('Norway'), 'NO');
      // The UK's nations have vector flags of their own.
      expect(MediaFlagBackdrop.flagCodeOf('ENG'), 'GB-ENG');
      expect(MediaFlagBackdrop.flagCodeOf('Scotland'), 'GB-SCT');
      expect(MediaFlagBackdrop.flagCodeOf('WLS'), 'GB-WLS');
      // No country, no flag: the card keeps its plain ink.
      for (final none in [null, '', '  ', 'FID', 'FIDE', 'XX', 'Unknown']) {
        expect(MediaFlagBackdrop.flagCodeOf(none), isNull, reason: '$none');
        expect(MediaFlagBackdrop.ofFederation(none), isNull, reason: '$none');
      }
    });

    testWidgets('it is drawn from the vector flags, never a raster one', (
      tester,
    ) async {
      for (final fed in ['NOR', 'JP', 'TUR', 'ENG', 'GER']) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: SizedBox(
              width: 360,
              height: 120,
              child: MediaFlagBackdrop.ofFederation(fed),
            ),
          ),
        );
        expect(find.byType(CountryFlag), findsOneWidget, reason: fed);
        expect(find.byType(Image), findsNothing, reason: fed);
      }
    });

    testWidgets('it keeps the flag\'s own colours: Japan\'s red is its red, '
        'its white is white', (tester) async {
      const key = ValueKey('flag');
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 300,
                height: 200,
                child: MediaFlagBackdrop.ofFederation('JPN'),
              ),
            ),
          ),
        ),
      );
      // The vector flag reads its asset off the frame.
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      final pixels = await _pixels(tester, find.byKey(key));
      // The disc, at the centre: Japan's crimson (BC002D), deepened only
      // by the faint even shade.
      final disc = pixels.at(150, 100);
      final keep = 1 - MediaFlagBackdrop.deepen;
      expect(disc.r, closeTo(0xBC * keep, 4));
      expect(disc.g, lessThan(6));
      expect(disc.b, closeTo(0x2D * keep, 4));
      // The field, at a corner: white, never a grey.
      final field = pixels.at(12, 12);
      for (final channel in [field.r, field.g, field.b]) {
        expect(channel, greaterThanOrEqualTo(240));
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('the title badge', () {
    const titles = [
      'GM', 'IM', 'FM', 'CM', 'NM', 'WGM', 'WIM', 'WFM', 'WCM', 'WNM', '??', //
    ];

    for (final light in [false, true]) {
      final theme = light ? 'light' : 'dark';
      testWidgets('$theme: every label reads at AA on its own fill', (
        tester,
      ) async {
        for (final title in titles) {
          await tester.pumpWidget(
            MaterialApp(
              theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
              home: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  return Center(
                    child: MediaTheme(child: MediaTitleBadge(title: title)),
                  );
                },
              ),
            ),
          );
          final fill =
              (tester
                          .widget<Container>(
                            find.descendant(
                              of: find.byType(MediaTitleBadge),
                              matching: find.byType(Container),
                            ),
                          )
                          .decoration!
                      as BoxDecoration)
                  .color!;
          final ink = tester.widget<Text>(find.text(title)).style!.color!;
          expect(
            wcagContrast(ink, fill),
            greaterThanOrEqualTo(4.5),
            reason: '$title: $ink on $fill',
          );
        }
      });
    }

    test('GM keeps its green and takes the dark label', () {
      const green = Color(0xFF22C55E);
      expect(titleBadgeLegibleFill(green), green);
      expect(titleBadgeLegibleInk(green), isNot(const Color(0xFFFFFFFF)));
      expect(
        wcagContrast(titleBadgeLegibleInk(green), green),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('the shade behind the words', () {
    test('a bold name or title is large type (3:1); the smaller lines are '
        'body type (4.5:1)', () {
      double bar(double size, FontWeight weight) =>
          MediaTextScrim.contrastFor(fontSize: size, weight: weight);
      expect(bar(16, FontWeight.w700), MediaTextScrim.largeContrast);
      expect(bar(18, FontWeight.w700), MediaTextScrim.largeContrast);
      expect(bar(24, FontWeight.w400), MediaTextScrim.largeContrast);
      expect(bar(16, FontWeight.w400), MediaTextScrim.bodyContrast);
      expect(bar(15, FontWeight.w700), MediaTextScrim.bodyContrast);
      expect(bar(12, FontWeight.w400), MediaTextScrim.bodyContrast);
    });

    test('just enough black for each bar over the brightest ground, none '
        'over dark ground', () {
      for (final ink in [kMediaOnInk, kMediaOnInkQuiet]) {
        for (final bar in [
          MediaTextScrim.largeContrast,
          MediaTextScrim.bodyContrast,
        ]) {
          for (final ground in [1.0, 0.86, 0.6, 0.4]) {
            final shade = MediaTextScrim.shadeFor(
              ink,
              ground: ground,
              contrast: bar,
            );
            Color under(double s) {
              final v = MediaTextScrim.srgbOf(ground) * (1 - s);
              return Color.from(alpha: 1, red: v, green: v, blue: v);
            }

            // Enough...
            expect(
              wcagContrast(Color.alphaBlend(ink, under(shade)), under(shade)),
              greaterThanOrEqualTo(bar),
              reason: '$ink over $ground at $bar',
            );
            // ...and no more than a hair over it.
            if (shade > 0) {
              final less = under(shade - 0.02);
              expect(
                wcagContrast(Color.alphaBlend(ink, less), less),
                lessThan(bar + 0.25),
                reason: '$ink over $ground at $bar',
              );
            }
          }
          // Ground already dark enough (the Likes heart, a black field).
          expect(MediaTextScrim.shadeFor(ink, ground: 0.11, contrast: bar), 0);
        }
      }
      // A name over white needs well under half black; a caption a little
      // over half.
      expect(
        MediaTextScrim.shadeFor(
          kMediaOnInk,
          contrast: MediaTextScrim.largeContrast,
        ),
        inInclusiveRange(0.38, 0.46),
      );
      expect(
        MediaTextScrim.shadeFor(kMediaOnInkQuiet),
        inInclusiveRange(0.52, 0.62),
      );
    });

    testWidgets('it answers to each line\'s own bar, leaves a skipped badge '
        'out, and lays nothing over dark ground', (tester) async {
      Future<RenderMediaTextScrim> pump(double ground) async {
        await tester.pumpWidget(
          _card(
            ground: ground,
            badge: true,
            child: const Text('Magnus Carlsen', style: _name),
          ),
        );
        return tester.renderObject<RenderMediaTextScrim>(
          find.byKey(const ValueKey('scrim')),
        );
      }

      final scrim = await pump(1);
      final lines = scrim.lines();
      // The badge, on its own fill, is not one of the words: the name and
      // the caption are.
      expect(lines, hasLength(2));
      final name = lines.first;
      final caption = lines.last;
      expect(name.contrast, MediaTextScrim.largeContrast);
      expect(caption.contrast, MediaTextScrim.bodyContrast);
      expect(caption.need, greaterThan(name.need));
      final shape = scrim.shape()!;
      expect(shape.floor, caption.need);
      // Every line keeps its bar at its far corner, where it gets least.
      for (final line in lines) {
        expect(
          shape.alphaAt(line.rect.topRight),
          greaterThanOrEqualTo(line.need - 1e-6),
        );
      }

      final dark = await pump(0.1);
      expect(dark.shape(), isNull);
      expect(
        find.byKey(const ValueKey('scrim')),
        isNot(paints..rect()),
        reason: 'nothing is laid over art dark enough already',
      );
    });

    testWidgets('it is one smooth gradient out of the words\' corner, '
        'painted with no layer, no box and no path', (tester) async {
      await tester.pumpWidget(
        _card(child: const Text('Kenta Kobayashi', style: _name)),
      );
      final finder = find.byKey(const ValueKey('scrim'));
      final scrim = tester.renderObject<RenderMediaTextScrim>(finder);
      final shape = scrim.shape()!;
      final face = Offset.zero & scrim.size;
      // Anchored at the corner the words sit in.
      expect(shape.anchor, face.bottomLeft);
      // One rect, filled by a shader: no flat veil, no blur, no path, no
      // offscreen layer.
      expect(
        finder,
        paints..something((method, args) {
          if (method != #drawRect) return false;
          final paint = args[1] as Paint;
          return paint.shader != null && paint.maskFilter == null;
        }),
      );
      expect(
        finder,
        isNot(paints..something((method, args) => method == #saveLayer)),
      );
      expect(finder, isNot(paints..path()));
      expect(scrim.needsCompositing, isFalse);
      // It rises out of the words' corner: dark there and along the card's
      // edge under the whole of the words, lighter up the card, clear by the
      // far corner.
      final corner = shape.floor * MediaScrimShape.cornerShare - 1e-9;
      var end = 0.0;
      for (final line in scrim.lines()) {
        end = math.max(end, line.rect.right);
      }
      expect(shape.alphaAt(face.bottomLeft), greaterThanOrEqualTo(corner));
      expect(
        shape.alphaAt(Offset(end, face.bottom)),
        greaterThanOrEqualTo(corner),
      );
      expect(shape.alphaAt(face.topLeft), lessThan(shape.floor * 0.5));
      expect(shape.alphaAt(face.topRight), lessThan(0.02));
      // And it never steps: along the diagonal, point by point, it never
      // changes faster than the shade's own limit, either way (it may
      // darken a touch from the corner up under the words, which hold the
      // most). The shape is chosen against that limit on a grid two points
      // apart, so a peak between its points may run a few percent over it.
      final limit = MediaScrimShape.maxSlope * 1.05;
      final diagonal = (face.topRight - face.bottomLeft).distance;
      final steps = diagonal.ceil();
      var last = shape.alphaAt(face.bottomLeft);
      for (var i = 1; i <= steps; i++) {
        final p = Offset.lerp(face.bottomLeft, face.topRight, i / steps)!;
        final a = shape.alphaAt(p);
        expect((last - a).abs() / (diagonal / steps), lessThanOrEqualTo(limit));
        last = a;
      }
      // Nowhere on the card does it fall faster, read point by point.
      expect(shape.steepestOn(face, step: 1), lessThanOrEqualTo(limit));
    });

    test(
      'its slope is read exactly: the shade\'s own fall, point by point',
      () {
        for (final aspect in [0.75, 1.0, 2.0, 3.0, 6.0]) {
          const fade = 48.0;
          final shift = (40 / aspect - fade).clamp(-0.95 * fade, 0.95 * fade);
          const centre = Offset(60, 100);
          final shape = MediaScrimShape(
            anchor: const Offset(0, 106),
            centre: centre,
            outerCentre: centre + Offset(shift * aspect, 0),
            aspect: aspect,
            hold: 40,
            reach: 40 + fade,
            floor: 0.58,
          );
          for (var y = 2.0; y < 106; y += 7) {
            for (var x = 3.0; x < 340; x += 11) {
              final p = Offset(x, y);
              final t = shape.fadeAt(p);
              if (t <= 0.02 || t >= 0.98) continue;
              const h = 1e-3;
              final dx =
                  (shape.alphaAt(p + const Offset(h, 0)) -
                      shape.alphaAt(p - const Offset(h, 0))) /
                  (2 * h);
              final dy =
                  (shape.alphaAt(p + const Offset(0, h)) -
                      shape.alphaAt(p - const Offset(0, h))) /
                  (2 * h);
              expect(
                shape.slopeAt(p),
                closeTo(math.sqrt(dx * dx + dy * dy), 1e-5),
              );
            }
          }
        }
      },
    );

    testWidgets('it stays by the words: the card\'s top and its far side, '
        'where the portrait stands, are left as drawn', (tester) async {
      for (final name in ['D Gukesh', 'Kenta Kobayashi']) {
        await tester.pumpWidget(_card(child: Text(name, style: _name)));
        final scrim = tester.renderObject<RenderMediaTextScrim>(
          find.byKey(const ValueKey('scrim')),
        );
        final shape = scrim.shape()!;
        final w = scrim.size.width;
        final h = scrim.size.height;
        var end = 0.0;
        var top = h;
        for (final line in scrim.lines()) {
          end = math.max(end, line.rect.right);
          top = math.min(top, line.rect.top);
        }
        var aboveWords = 0.0;
        var farSide = 0.0;
        for (var y = 0.5; y < h; y += 1) {
          for (var x = 0.5; x < w; x += 1) {
            final a = shape.alphaAt(Offset(x, y));
            // The band over the words, clear of their fade.
            if (y < top - 30) aboveWords = math.max(aboveWords, a);
            // Past the words' far end, clear of their fade.
            if (x > end + 40) farSide = math.max(farSide, a);
          }
        }
        // Only the fade's faint tail reaches up there, and nothing past
        // the words' far end: the portrait and the flag's far field show
        // as drawn.
        expect(aboveWords, lessThan(0.15), reason: name);
        expect(farSide, lessThan(0.05), reason: name);
      }
    });

    testWidgets('over a white picture the words keep their bars, and the '
        'picture beyond them stays bright', (tester) async {
      const key = ValueKey('card');
      await tester.pumpWidget(
        _card(
          boundary: key,
          child: const Text('Kenta Kobayashi', style: _name),
        ),
      );
      final scrim = tester.renderObject<RenderMediaTextScrim>(
        find.byKey(const ValueKey('scrim')),
      );
      final pixels = await _pixels(tester, find.byKey(key));
      for (final line in scrim.lines()) {
        // The line's far corner, a point inside its box.
        final corner = line.rect.topRight + const Offset(-1, 1);
        final under = pixels.at(corner.dx.floor(), corner.dy.floor());
        expect(
          wcagContrast(kMediaOnInk, under.color),
          greaterThanOrEqualTo(line.contrast),
        );
      }
      // The top right of the card, far from the words: the white picture.
      final far = pixels.at(scrim.size.width.floor() - 3, 3);
      expect(far.color.computeLuminance(), greaterThan(0.9));
    });
  });

  group('the portrait', () {
    testWidgets('it fades on the card\'s canvas, with no layer of its own', (
      tester,
    ) async {
      await tester.pumpWidget(
        const Center(
          child: SizedBox(
            width: 80,
            height: 100,
            child: MediaPortraitFade(
              child: ColoredBox(color: Color(0xFF808080)),
            ),
          ),
        ),
      );
      expect(
        tester.renderObject(find.byType(MediaPortraitFade)).needsCompositing,
        isFalse,
      );
    });

    test('a long fade at its outer edge, solid over the face', () {
      expect(kMediaPortraitFade, inInclusiveRange(0.35, 0.4));
      // No slope where it starts or ends: no line where the photo begins.
      expect(mediaPortraitFadeAt(0), 0);
      expect(mediaPortraitFadeAt(1), 1);
      expect(mediaPortraitFadeAt(0.05), lessThan(0.01));
      expect(mediaPortraitFadeAt(0.95), greaterThan(0.999));
      // Rising throughout.
      for (var i = 1; i <= 100; i++) {
        expect(
          mediaPortraitFadeAt(i / 100),
          greaterThanOrEqualTo(mediaPortraitFadeAt((i - 1) / 100)),
        );
      }
      // A face starts a fifth to three tenths of the cropped width in: by
      // a fifth the photo is mostly there, by three tenths it is solid.
      expect(mediaPortraitFadeAt(0.2 / kMediaPortraitFade), greaterThan(0.7));
      expect(mediaPortraitFadeAt(0.3 / kMediaPortraitFade), greaterThan(0.99));
      // The mask: clear at the edge, opaque from the fade's end on.
      final mask = mediaPortraitFade();
      final stops = mask.stops!;
      expect(mask.colors.first.a, 0.0);
      for (var i = 0; i < stops.length; i++) {
        if (stops[i] >= kMediaPortraitFade - 1e-9) {
          expect(mask.colors[i].a, 1.0);
        }
      }
    });

    testWidgets('it stands whole at the card\'s right edge, a touch past it', (
      tester,
    ) async {
      late double bleed;
      late double overhang;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              bleed = MediaCardPortrait.bleed(compact: true);
              overhang = MediaCardPortrait.overhang(compact: true);
              return Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  key: const ValueKey('card'),
                  width: 174,
                  height: 108,
                  child: const Stack(
                    clipBehavior: Clip.none,
                    children: [
                      MediaCardPortrait(
                        url: 'https://photos.preview.test/x.webp',
                        compact: true,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
      final card = tester.getRect(find.byKey(const ValueKey('card')));
      final portrait = tester.getRect(find.byType(MediaPortraitFade));
      expect(portrait.right, closeTo(card.right + bleed, 0.01));
      expect(portrait.top, closeTo(card.top - overhang, 0.01));
      expect(portrait.bottom, closeTo(card.bottom + overhang, 0.01));
      expect(
        portrait.width / portrait.height,
        closeTo(MediaCardPortrait.aspect, 0.001),
      );
    });
  });

  group('hub art', () {
    test('each scene declares the brightest its drawing gets, and the '
        'drawing never gets brighter', () async {
      for (final scene in HubScene.values) {
        final file = File(HubSceneBackdrop.asset(scene));
        final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
        final image = (await codec.getNextFrame()).image;
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        var brightest = 0.0;
        for (var i = 0; i < data.lengthInBytes; i += 4) {
          final color = Color.fromARGB(
            255,
            data.getUint8(i),
            data.getUint8(i + 1),
            data.getUint8(i + 2),
          );
          brightest = math.max(brightest, color.computeLuminance());
        }
        image.dispose();
        expect(
          HubSceneBackdrop.brightest(scene),
          greaterThanOrEqualTo(brightest),
          reason: '$scene measures $brightest',
        );
        // Declared close to what it is, so the shade is no heavier than it
        // needs to be.
        expect(
          HubSceneBackdrop.brightest(scene),
          lessThan(brightest + 0.03),
          reason: '$scene measures $brightest',
        );
      }
    });

    test('the Likes heart is dark enough to need no shade at all', () {
      final ground = HubSceneBackdrop.brightest(HubScene.mostLiked);
      for (final ink in [kMediaOnInk, kMediaOnInkQuiet]) {
        expect(MediaTextScrim.shadeFor(ink, ground: ground), 0);
      }
    });
  });
}

/// A media card's name.
const TextStyle _name = TextStyle(
  fontFamily: 'Inter',
  fontSize: 16,
  fontWeight: FontWeight.w700,
  color: kMediaOnInk,
);

/// A 174x108 media card over a white picture (the brightest there is), its
/// words bottom-left under a [MediaTextScrim] keyed 'scrim': an optional
/// badge (skipped), [child] (the name), and a caption.
Widget _card({
  required Widget child,
  double ground = 1,
  bool badge = false,
  Key? boundary,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: const MediaQueryData(),
    child: Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: boundary,
        child: SizedBox(
          width: 174,
          height: 108,
          child: Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: Color(0xFFFFFFFF)),
              ),
              Positioned.fill(
                child: MediaTextScrim(
                  key: const ValueKey('scrim'),
                  ground: ground,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (badge)
                          const MediaScrimSkip(
                            child: Text(
                              'GM',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 10,
                                color: Color(0xFF0B0B0B),
                              ),
                            ),
                          ),
                        child,
                        const Text(
                          '2310 • Japan',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 10,
                            color: kMediaOnInkQuiet,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
);

/// A logical pixel's colour, read at 1x.
class _Pixel {
  const _Pixel(this.r, this.g, this.b);
  final int r;
  final int g;
  final int b;
  Color get color => Color.fromARGB(255, r, g, b);
}

class _Image {
  const _Image(this.width, this.data);
  final int width;
  final ByteData data;
  _Pixel at(int x, int y) {
    final i = (y * width + x) * 4;
    return _Pixel(data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
  }
}

/// [finder]'s repaint boundary, read back at 1x.
Future<_Image> _pixels(WidgetTester tester, Finder finder) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
  late _Image out;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    out = _Image(image.width, data!);
    image.dispose();
  });
  return out;
}
