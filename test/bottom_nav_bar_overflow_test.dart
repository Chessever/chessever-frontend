import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() {
  testWidgets(
    'floating glass bottom nav island never overflows the bottom on a short '
    'screen at large text scale with a gesture-nav inset',
    (tester) async {
      // The old solid bar put icon+label Columns in a fixed height slot that
      // overflowed under large text scale + large safe-area insets. The glass
      // island uses GlassTabBar.bottom (package floating pill) which sizes to
      // its barHeight and FittedBox labels — it must still not overflow.
      final mediaQuery = const MediaQueryData(
        size: Size(393, 600),
        devicePixelRatio: 3,
        viewPadding: EdgeInsets.only(bottom: 34),
        padding: EdgeInsets.only(bottom: 34),
      ).copyWith(textScaler: const TextScaler.linear(3));

      final errors = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = errors.add;

      await tester.pumpWidget(
        ProviderScope(
          child: LiquidGlassWidgets.wrap(
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: MediaQuery(
                data: mediaQuery,
                child: Builder(
                  builder: (context) {
                    ResponsiveHelper.init(context);
                    return const Scaffold(
                      extendBody: true,
                      backgroundColor: Colors.black,
                      // Floating island over body (content-first layout).
                      body: Stack(
                        children: [
                          Positioned.fill(child: SizedBox.shrink()),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: BottomNavBar(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );

      // Allow glass indicator / layout animations to settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      FlutterError.onError = previousOnError;

      final overflowErrors =
          errors
              .map((e) => e.exceptionAsString())
              .where((e) => e.contains('overflowed'))
              .toList();

      expect(overflowErrors, isEmpty, reason: overflowErrors.join('\n'));

      // Shipped phone chrome path must be the package searchable floating bar.
      expect(find.byType(GlassTabBar), findsOneWidget);
      expect(find.byType(BottomNavBar), findsOneWidget);
      // Labels exist (GlassTabBar dual-paints selected/unselected layers).
      expect(find.text('Events'), findsWidgets);
      expect(find.text('Calendar'), findsWidgets);
      expect(find.text('Library'), findsWidgets);
    },
  );

  testWidgets('bottom nav tab selection + re-tap request via GlassTabBar', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: LiquidGlassWidgets.wrap(
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return const Scaffold(
                  extendBody: true,
                  body: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: BottomNavBar(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BottomNavBar)),
    );

    expect(
      container.read(selectedBottomNavBarItemProvider),
      BottomNavBarItem.tournaments,
    );
    final before = container.read(bottomNavBarReTapRequestProvider);

    // Hit targets are sized to the compact pill (tabWidth × count), not the
    // full GlassTabBar rect (which includes the search circle gap).
    await tester.tap(find.byKey(e2eKey(E2eIds.navEvents)));
    await tester.pump();

    expect(
      container.read(selectedBottomNavBarItemProvider),
      BottomNavBarItem.tournaments,
    );
    final after = container.read(bottomNavBarReTapRequestProvider);
    expect(after.item, BottomNavBarItem.tournaments);
    expect(after.sequence, before.sequence + 1);

    await tester.tap(find.byKey(e2eKey(E2eIds.navCalendar)));
    await tester.pump();
    expect(
      container.read(selectedBottomNavBarItemProvider),
      BottomNavBarItem.calendar,
    );
  });

  testWidgets('e2e keys are unique on the floating glass nav island', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: LiquidGlassWidgets.wrap(
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return const Scaffold(
                  extendBody: true,
                  body: Stack(
                    children: [
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: BottomNavBar(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Unique keys (not dual-painted) for Events/Calendar/Library.
    expect(find.byKey(e2eKey(E2eIds.navEvents)), findsOneWidget);
    expect(find.byKey(e2eKey(E2eIds.navCalendar)), findsOneWidget);
    expect(find.byKey(e2eKey(E2eIds.navLibrary)), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(BottomNavBar)),
    );
    await tester.tap(find.byKey(e2eKey(E2eIds.navLibrary)));
    await tester.pump();
    expect(
      container.read(selectedBottomNavBarItemProvider),
      BottomNavBarItem.library,
    );
  });
}
