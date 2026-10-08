import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/hub_context_art.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _previewDir = String.fromEnvironment('HUB_PREVIEW_DIR');

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

  for (final light in [false, true]) {
    for (final width in [160.0, 173.0, 358.0, 720.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('complete study art and captions at $width, $scale text, '
            '${light ? 'light' : 'dark'}', (tester) async {
          tester.view.physicalSize = Size(width > 393 ? width : 393, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          var taps = 0;
          for (final scene in [HubScene.myPrep, HubScene.library]) {
            final prep = scene == HubScene.myPrep;
            final title = prep ? 'My Prep' : 'Library';
            final caption = prep
                ? 'Your games and opponents'
                : 'Your databases';
            // Bounds measured from the actual generated bitmaps, including
            // all pieces, branch endpoints and the Library database rims.
            final subject = prep
                ? const Rect.fromLTRB(.645, .078, .936, .492)
                : const Rect.fromLTRB(.669, .111, .85, .58);
            await tester.pumpWidget(
              MaterialApp(
                theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
                home: Builder(
                  builder: (context) {
                    ResponsiveHelper.init(context);
                    return MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(scale)),
                      child: Material(
                        child: Center(
                          child: OverflowBox(
                            maxWidth: width,
                            minWidth: width,
                            child: RepaintBoundary(
                              key: const ValueKey('capture'),
                              child: HubTile(
                                title: title,
                                caption: caption,
                                artwork: HubSceneBackdrop(scene: scene),
                                ramp: false,
                                artworkHeadroom: 40.sp,
                                minCaptionLines: 2,
                                onTap: () => taps++,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
            final image = tester.widget<Image>(find.byType(Image));
            await tester.runAsync(
              () => precacheImage(
                image.image,
                tester.element(find.byType(Image)),
              ),
            );
            await tester.pump();
            final render = tester.renderObject<RenderImage>(
              find.byType(RawImage),
            );
            expect(render.image, isNotNull);
            expect(render.image!.width / render.image!.height, 3);
            final tile = tester.getRect(find.byType(HubTile));
            final picture = tester.getRect(find.byType(Image));
            final paintedSubject = Rect.fromLTRB(
              picture.left + subject.left * picture.width,
              picture.top + subject.top * picture.height,
              picture.left + subject.right * picture.width,
              picture.top + subject.bottom * picture.height,
            );
            expect(tile.deflate(1).contains(paintedSubject.topLeft), isTrue);
            expect(
              tile.deflate(1).contains(paintedSubject.bottomRight),
              isTrue,
            );
            expect(
              paintedSubject.bottom,
              lessThan(tester.getRect(find.text(title)).top - 4),
            );

            final paragraph = tester.renderObject<RenderParagraph>(
              find.text(caption),
            );
            expect(paragraph.didExceedMaxLines, isFalse);
            final lastWord = caption.lastIndexOf(' ') + 1;
            final boxes = paragraph.getBoxesForSelection(
              TextSelection(baseOffset: lastWord, extentOffset: caption.length),
            );
            expect(boxes, isNotEmpty);
            for (final box in boxes) {
              expect(
                tile
                    .deflate(1)
                    .contains(
                      paragraph.localToGlobal(box.toRect().bottomRight),
                    ),
                isTrue,
              );
            }
            final textRect = tester.getRect(find.text(caption));
            expect(tile.deflate(1).contains(textRect.topLeft), isTrue);
            expect(tile.deflate(1).contains(textRect.bottomRight), isTrue);
            expect(tester.takeException(), isNull);

            if (_previewDir.isNotEmpty &&
                scale == 1 &&
                (width == 173 || width == 358)) {
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
                  '$_previewDir/${scene.name}_${width.toInt()}_${light ? 'light' : 'dark'}.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
              });
            }
            // Both cards remain working native navigation controls.
            await tester.tap(find.byType(HubTile));
            await tester.pump(const Duration(milliseconds: 300));
          }
          expect(taps, 2);
        });
      }
    }
  }
}
