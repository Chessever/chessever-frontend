import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/widgets/liquid_glass/glass_full_screen_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() {
  testWidgets('content fills behind safe-area-aware floating overlays', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    const media = MediaQueryData(
      size: Size(320, 640),
      viewPadding: EdgeInsets.only(top: 24, bottom: 34),
      padding: EdgeInsets.only(top: 24, bottom: 34),
    );

    await tester.pumpWidget(
      LiquidGlassWidgets.wrap(
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const MediaQuery(
            data: media,
            child: GlassFullScreenPage(
              contentPadding: EdgeInsets.only(top: 56, bottom: 72),
              topOverlayPadding: EdgeInsets.only(top: 4),
              bottomOverlayPadding: EdgeInsets.only(bottom: 12),
              content: ColoredBox(
                key: ValueKey('content'),
                color: Colors.white,
              ),
              topOverlay: SizedBox(key: ValueKey('top-overlay'), height: 48),
              bottomOverlay: SizedBox(
                key: ValueKey('bottom-overlay'),
                height: 48,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.byKey(const ValueKey('top-overlay'))).dy, 28);
    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('bottom-overlay'))).dy,
      640 - 34 - 12,
    );
    expect(tester.getSize(find.byKey(const ValueKey('content'))).height, 454);
    expect(find.byType(Stack), findsWidgets);
  });

  testWidgets('bottom overlay moves above the keyboard without a fixed band', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);

    const media = MediaQueryData(
      size: Size(320, 640),
      viewPadding: EdgeInsets.only(top: 24, bottom: 34),
      viewInsets: EdgeInsets.only(bottom: 220),
    );

    await tester.pumpWidget(
      LiquidGlassWidgets.wrap(
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          home: const MediaQuery(
            data: media,
            child: GlassFullScreenPage(
              bottomOverlayPadding: EdgeInsets.only(bottom: 12),
              content: SizedBox.expand(),
              bottomOverlay: SizedBox(
                key: ValueKey('keyboard-overlay'),
                height: 48,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('keyboard-overlay'))).dy,
      640 - 220 - 12,
    );
  });
}
