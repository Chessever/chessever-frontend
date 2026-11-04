import 'package:chessever2/screens/home/widget/tablet_nav_rail.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/adaptive_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('rail stays reachable in short expanded window, dark=$dark', (
      tester,
    ) async {
      addTearDown(tester.view.reset);
      tester.view
        ..devicePixelRatio = 3
        ..physicalSize = const Size(810, 300) * 3;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            builder: (_, child) => AdaptiveWindowScope(
              child: MediaQuery.withClampedTextScaling(
                minScaleFactor: 2,
                maxScaleFactor: 2,
                child: child!,
              ),
            ),
            home: const Scaffold(
              body: Row(
                children: [
                  TabletNavRail(),
                  Expanded(child: SizedBox()),
                ],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Collections'));
      await tester.pumpAndSettle();
      expect(find.text('Collections').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
