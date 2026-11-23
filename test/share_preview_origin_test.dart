import 'dart:convert';

import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/utils/share_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

/// On iPad the share sheet is a popover pointing at its anchor. The preview
/// sheet's shares (standings, scorecards, profiles, bracket, team) anchored
/// it at Rect(0, 0, 1, 1), the screen's top-left corner, far from the
/// button that was tapped.
void main() {
  setUp(debugResetSharePreviewOrigin);

  for (final action in ['Share Image', 'Share Link']) {
    testWidgets('$action anchors the popover at the tapped button', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1024, 1366);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Rect? origin;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: Builder(
                  builder: (context) => Center(
                    child: TextButton(
                      onPressed: () => showShareImagePreview(
                        context,
                        imageBytes: _onePixelPng,
                        onShareImage: () async => origin = sharePreviewOrigin(),
                        onShareLink: () async => origin = sharePreviewOrigin(),
                      ),
                      child: const Text('Share'),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      final button = tester.getRect(find.text(action));
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();

      expect(origin, isNotNull);
      expect(origin, isNot(const Rect.fromLTWH(0, 0, 1, 1)));
      expect(origin!.contains(button.center), isTrue);
    });
  }

  testWidgets('with no button tapped the anchor is the bottom centre', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1024, 1366);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox());
    expect(sharePreviewOrigin(), const Rect.fromLTWH(512, 1365, 1, 1));
    expect(shareScreenBottomOrigin(), const Rect.fromLTWH(512, 1365, 1, 1));
  });
}
