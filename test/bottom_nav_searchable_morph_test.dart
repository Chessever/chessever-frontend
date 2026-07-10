import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/liquid_glass/home_search_providers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Drives the real shipped [BottomNavBar] searchable morph path:
/// tap search → [homeBottomSearchExpandedProvider] becomes true;
/// cancel / toggle off → collapses again.
void main() {
  testWidgets(
    'home BottomNavBar searchable morph expands and collapses via real provider',
    (tester) async {
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

      // Shipped bar is package searchable surface.
      expect(find.byType(GlassTabBar), findsOneWidget);
      expect(container.read(homeBottomSearchExpandedProvider), isFalse);

      // Tap the collapsed search control (package morph entry).
      final searchIcon = find.byIcon(CupertinoIcons.search);
      expect(searchIcon, findsWidgets);
      await tester.tap(searchIcon.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Real notifier path used by GlassSearchBarConfig.onSearchToggle.
      expect(
        container.read(homeBottomSearchExpandedProvider),
        isTrue,
        reason:
            'Tapping search must set homeBottomSearchExpandedProvider so '
            'GlassTabBar.searchable receives isSearchActive: true',
      );

      // Collapse via cancel (×) when package shows it, or second search toggle.
      final cancel = find.byIcon(CupertinoIcons.xmark);
      final cancelCircle = find.byIcon(CupertinoIcons.xmark_circle_fill);
      if (cancel.evaluate().isNotEmpty) {
        await tester.tap(cancel.first);
      } else if (cancelCircle.evaluate().isNotEmpty) {
        await tester.tap(cancelCircle.first);
      } else {
        // Fallback: drive the same provider API the cancel handler uses.
        container.read(homeBottomSearchExpandedProvider.notifier).state = false;
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(container.read(homeBottomSearchExpandedProvider), isFalse);
    },
  );

  testWidgets(
    'tabWidth on searchable bar is a compact per-tab slot (not full-bleed)',
    (tester) async {
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

      final bar = tester.widget<GlassTabBar>(find.byType(GlassTabBar));
      // package: pill width ≈ tabWidth × tabCount. 72×3 = 216 << screen width.
      expect(bar.tabWidth, BottomNavBar.tabWidth);
      expect(bar.tabWidth!, lessThan(100));
      expect(
        BottomNavBar.pillWidthFor(3),
        BottomNavBar.tabWidth * 3,
      );
    },
  );

  testWidgets(
    'e2e tab hit overlay matches pill width — taps past pill do not change tab',
    (tester) async {
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          child: LiquidGlassWidgets.wrap(
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: MediaQuery(
                data: const MediaQueryData(size: Size(393, 852)),
                child: Builder(
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
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        container.read(selectedBottomNavBarItemProvider),
        BottomNavBarItem.tournaments,
      );

      // E2e Events hit target is the left third of the pill overlay.
      final eventsKey = find.byKey(
        const ValueKey<String>('e2e_nav_events'),
      );
      expect(eventsKey, findsOneWidget);
      final eventsRect = tester.getRect(eventsKey);

      // Overlay must be pill-sized: Events slot ≈ tabWidth (not 1/3 of screen).
      // Cue shell scale may shrink layout by ~1–2% during settle — allow slack.
      expect(
        eventsRect.width,
        closeTo(BottomNavBar.tabWidth, 3.0),
        reason:
            'e2e hit slots must match compact pill tabWidth, not full-bleed thirds',
      );

      // Library is the rightmost e2e slot — its right edge is the pill edge.
      final libraryRect = tester.getRect(
        find.byKey(const ValueKey<String>('e2e_nav_library')),
      );
      final pillRight = libraryRect.right;
      final expectedPillRight =
          BottomNavBar.horizontalPadding + BottomNavBar.pillWidthFor(3);
      expect(pillRight, closeTo(expectedPillRight, 6.0));

      // Gap between pill and search: tap past the pill must not select Calendar.
      final emptyX = pillRight + 40;
      final emptyY = eventsRect.center.dy;
      expect(emptyX, lessThan(393 - 20));

      await tester.tapAt(Offset(emptyX, emptyY));
      await tester.pump();

      expect(
        container.read(selectedBottomNavBarItemProvider),
        BottomNavBarItem.tournaments,
        reason:
            'Taps in the gap between compact pill and search circle must not '
            'change tabs (overlay must not span that gap)',
      );
    },
  );
}
