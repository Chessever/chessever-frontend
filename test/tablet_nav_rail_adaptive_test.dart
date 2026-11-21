import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
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
          // Every section on the rail, Botvinnik included: the tallest rail
          // is the one that must still scroll to its last slot. (The real
          // setting reads SQLite, which a widget test cannot open.)
          overrides: [botvinnikTabAvailableProvider.overrideWithValue(true)],
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

      // The rail carries the phone bar's sections and nothing else: no menu
      // button, Events lives on the Profile page, and Collections has the
      // slot Search left (Search opens from Today's button).
      final items = ProviderScope.containerOf(
        tester.element(find.byType(TabletNavRail)),
      ).read(visibleBottomNavItemsProvider);
      expect(items, bottomNavBarOrder);
      expect(items.last, BottomNavBarItem.profile);
      expect(find.byTooltip('Menu'), findsNothing);
      expect(find.text('Events'), findsNothing);
      expect(find.text('Search'), findsNothing);
      expect(find.text('Collections'), findsOneWidget);

      // 300dp tall at 2x text cannot fit every slot: each one, down to the
      // last (Profile), must scroll into view and take a hit.
      for (final item in items) {
        final label = find.text(namesBottomNavBarIcons[item]!);
        await tester.ensureVisible(label);
        await tester.pumpAndSettle();
        expect(label.hitTestable(), findsOneWidget, reason: item.name);
      }

      await tester.ensureVisible(find.text('Home'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
