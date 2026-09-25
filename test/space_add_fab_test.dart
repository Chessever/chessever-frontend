import 'package:chessever2/screens/my_space/widgets/space_add_fab.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

Future<void> _pumpFab(WidgetTester tester, {ThemeData? theme}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              backgroundColor: context.colors.background,
              floatingActionButton: const SpaceAddFab(),
              body: const SizedBox.expand(),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  for (final light in [false, true]) {
    testWidgets('the "+" opens a popover pointing at it with every type, '
        '(${light ? 'light' : 'dark'})', (tester) async {
      await _pumpFab(
        tester,
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
      );

      expect(find.bySemanticsLabel(SpaceAddFab.label), findsOneWidget);
      final fab = tester.getRect(find.byType(SpaceAddFab));
      expect(fab.width, greaterThanOrEqualTo(48));

      await tester.tap(find.byType(SpaceAddFab));
      await _settle(tester);

      for (final choice in kSpaceAddChoices) {
        expect(find.text(choice.label), findsOneWidget, reason: choice.label);
        // Every row is a full touch target.
        expect(
          tester.getSize(find.bySemanticsLabel(choice.label)).height,
          greaterThanOrEqualTo(44),
        );
      }
      // The popover sits above the button, right-aligned with it.
      final card = tester.getRect(find.text('Smart event'));
      expect(card.bottom, lessThan(fab.top));
      expect(card.right, lessThanOrEqualTo(fab.right));
      expect(tester.takeException(), isNull);

      // A tap outside closes it and picks nothing.
      await tester.tapAt(const Offset(40, 120));
      await _settle(tester);
      expect(find.text('Smart event'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('with reduced motion the popover opens and closes at once', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pumpFab(tester);

    await tester.tap(find.byType(SpaceAddFab));
    await tester.pump();
    await tester.pump();
    expect(find.text('Event'), findsOneWidget);

    await tester.tapAt(const Offset(40, 120));
    await tester.pump();
    await tester.pump();
    expect(find.text('Event'), findsNothing);
  });
}
