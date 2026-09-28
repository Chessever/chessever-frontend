import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/hub_context_art.dart';
import 'package:chessever2/widgets/hub_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('retired My Likes decoration remains empty and static', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(width: 180, height: 108, child: HubLikesBackdrop()),
      ),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.byType(SvgPicture), findsNothing);
    expect(find.byType(Icon), findsNothing);
    expect(
      find.descendant(
        of: find.byType(HubLikesBackdrop),
        matching: find.byType(AnimatedBuilder),
      ),
      findsNothing,
    );
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pump(const Duration(seconds: 60));
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final light in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'art fills the whole tile in ${light ? 'light' : 'dark'} at $scale text',
        (tester) async {
          final assets = <String>{};
          for (final scene in HubScene.values) {
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
                      child: Center(
                        child: SizedBox(
                          width: 170,
                          child: HubTile(
                            title: 'Reports',
                            caption: 'Games with analysis',
                            artwork: HubSceneBackdrop(scene: scene),
                            onTap: () {},
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
            final art = find.descendant(
              of: find.byType(HubSceneBackdrop),
              matching: find.byType(Image),
            );
            expect(art, findsOneWidget);
            expect(
              find.descendant(
                of: find.byType(HubSceneBackdrop),
                matching: find.byType(AnimatedBuilder),
              ),
              findsNothing,
            );
            final widget = tester.widget<Image>(art);
            expect(widget.fit, BoxFit.cover);
            final resized = widget.image as ResizeImage;
            assets.add((resized.imageProvider as AssetImage).assetName);
            // Artwork reaches every inner edge of the existing 1px tile border.
            expect(
              tester.getRect(art),
              tester.getRect(find.byType(HubTile)).deflate(1),
            );
            final tile = tester.getRect(find.byType(HubTile));
            final title = tester.getRect(find.text('Reports'));
            expect(title.left, greaterThan(tile.left));
            expect(title.bottom, lessThan(tile.bottom));
            expect(tester.takeException(), isNull);
          }
          expect(assets, hasLength(HubScene.values.length));
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
