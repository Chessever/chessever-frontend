import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/liquid_glass/home_search_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// The bottom nav is the canonical package [GlassTabBar.searchable] — a single
/// floating pill whose tabs morph into a search bar. These tests drive the real
/// shipped widget through its public provider contract.
Widget _harness(WidgetRef Function()? _) => ProviderScope(
  child: LiquidGlassWidgets.wrap(
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return const Scaffold(
            extendBody: true,
            backgroundColor: Colors.black,
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
);

void main() {
  testWidgets('renders one canonical GlassTabBar with all three destinations', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(null));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // One cohesive glass pill — not three independent islands. (The package
    // crossfades a selected + unselected label layer per tab, so each label
    // text appears twice.)
    expect(find.byType(GlassTabBar), findsOneWidget);
    expect(find.text('Events'), findsWidgets);
    expect(find.text('Calendar'), findsWidgets);
    expect(find.text('Library'), findsWidgets);
  });

  testWidgets('search starts collapsed and driving the provider expands it', (
    tester,
  ) async {
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        child: LiquidGlassWidgets.wrap(
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                container = ProviderScope.containerOf(context);
                return const Scaffold(
                  extendBody: true,
                  backgroundColor: Colors.black,
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
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(homeBottomSearchExpandedProvider), isFalse);

    // The searchable bar reflects the shared expanded state (Events search).
    container.read(homeBottomSearchExpandedProvider.notifier).state = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Still a single GlassTabBar — it morphs internally, it does not swap out.
    expect(find.byType(GlassTabBar), findsOneWidget);
    expect(container.read(homeBottomSearchExpandedProvider), isTrue);
  });

  testWidgets('tapping a destination label switches the selected tab', (
    tester,
  ) async {
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        child: LiquidGlassWidgets.wrap(
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                container = ProviderScope.containerOf(context);
                return const Scaffold(
                  extendBody: true,
                  backgroundColor: Colors.black,
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
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      container.read(selectedBottomNavBarItemProvider),
      BottomNavBarItem.tournaments,
    );

    await tester.tap(find.text('Calendar').first, warnIfMissed: false);
    await tester.pump();

    expect(
      container.read(selectedBottomNavBarItemProvider),
      BottomNavBarItem.calendar,
    );
  });
}
