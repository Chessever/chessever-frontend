import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/for_you/for_you_screen.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/home/home_screen.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar_widget.dart';
import 'package:chessever2/screens/home/widget/home_nav_dock.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// WCAG 2.x contrast of [ink] (composited over [paper]) against [paper].
double _contrast(Color ink, Color paper) {
  final fg = Color.alphaBlend(ink, paper).computeLuminance();
  final bg = paper.computeLuminance();
  final hi = fg > bg ? fg : bg;
  final lo = fg > bg ? bg : fg;
  return (hi + 0.05) / (lo + 0.05);
}

final _themes = <(String, ThemeData, AppColors)>[
  ('light', AppTheme.lightTheme, AppColors.light),
  ('dark', AppTheme.darkTheme, AppColors.dark),
];

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription() : super(SubscriptionState(isSubscribed: false));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryRecentSearches implements RecentSearchStorage {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}
}

void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    prefs = (await SharedPreferencesService.instance.initialize())!;
  });

  group('launch route', () {
    test('Home opens on For You', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final sub = container.listen(selectedBottomNavBarItemProvider, (_, _) {});
      addTearDown(sub.close);

      expect(sub.read(), BottomNavBarItem.forYou);
    });

    test('the icon bar names Home, Feed, Botvinnik, Search, Profile', () {
      expect(bottomNavBarOrder.map((item) => item.name), [
        'forYou',
        'feed',
        'botvinnik',
        'search',
        'profile',
      ]);
      expect(bottomNavBarOrder.map((item) => namesBottomNavBarIcons[item]), [
        'Home',
        'Feed',
        'Botvinnik',
        'Search',
        'Profile',
      ]);
    });

    test('Botvinnik switched off leaves four tabs', () {
      final container = ProviderContainer(
        overrides: [botvinnikTabAvailableProvider.overrideWithValue(false)],
      );
      addTearDown(container.dispose);
      expect(container.read(visibleBottomNavItemsProvider), [
        BottomNavBarItem.forYou,
        BottomNavBarItem.feed,
        BottomNavBarItem.search,
        BottomNavBarItem.profile,
      ]);
    });

    test('a stored My Space or Discovery never survives into a launch', () {
      for (final stored in [ForYouTab.discovery, ForYouTab.mySpace]) {
        prefs.setString(forYouLastTabPrefsKey, stored.name);

        forgetForYouPageForLaunch();

        expect(prefs.getString(forYouLastTabPrefsKey), isNull);
        expect(ForYouTabController().state, ForYouTab.today);
      }
    });
  });

  group('bottom bar', () {
    Future<void> pumpBar(
      WidgetTester tester, {
      required ThemeData theme,
      Size size = const Size(393, 852),
      double textScale = 1,
    }) async {
      // The view itself, not only the surface: the bar sizes its slots
      // from MediaQuery, which follows the view.
      tester.view
        ..physicalSize = size * 3
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // The switch lives in SQLite, which retries on a timer here.
            botvinnikTabAvailableProvider.overrideWithValue(true),
            // Profile wears the reader's avatar.
            currentUserProvider.overrideWithValue(null),
            profileAvatarUrlProvider.overrideWithValue(null),
            inboxHasUnreadProvider.overrideWithValue(false),
            subscriptionProvider.overrideWith((ref) => _Subscription()),
          ],
          child: MaterialApp(
            theme: theme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(textScale)),
                  child: const Scaffold(
                    bottomNavigationBar: BottomNavBar(),
                    body: SizedBox.shrink(),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final (name, theme, colors) in _themes) {
      testWidgets('$name: every icon clears AA and its name remains semantic', (
        tester,
      ) async {
        await pumpBar(tester, theme: theme);

        for (final item in bottomNavBarOrder) {
          final slot = find.byWidgetPredicate(
            (w) =>
                w is BottomNavBarWidget &&
                w.title == namesBottomNavBarIcons[item],
          );
          final selected = item == BottomNavBarItem.forYou;
          final ink = selected ? colors.textPrimary : colors.textSecondary;

          // Marks only: no names drawn. Profile's mark is the avatar, which
          // may draw the reader's initial; that is the picture, not a label.
          if (item != BottomNavBarItem.profile) {
            expect(
              find.descendant(of: slot, matching: find.byType(Text)),
              findsNothing,
            );
          }
          expect(
            _contrast(ink, colors.background),
            greaterThanOrEqualTo(4.5),
            reason: '${item.name} mark',
          );

          if (item == BottomNavBarItem.forYou) {
            final icon = tester.widget<Icon>(
              find.descendant(of: slot, matching: find.byType(Icon)),
            );
            expect(icon.color, ink);
          } else if (item == BottomNavBarItem.profile) {
            // Signed out, so no face: the bare person mark in the slot's
            // ink, never one on a disc.
            final icon = tester.widget<Icon>(
              find.descendant(of: slot, matching: find.byType(Icon)),
            );
            expect(icon.icon, Icons.person_rounded);
            expect(icon.color, ink);
            expect(
              find.descendant(of: slot, matching: find.byType(ClipOval)),
              findsNothing,
            );
          } else {
            final icon = tester.widget<SvgWidget>(
              find.descendant(of: slot, matching: find.byType(SvgWidget)),
            );
            expect(icon.colorFilter, ColorFilter.mode(ink, BlendMode.srcIn));
            expect(icon.width, icon.height, reason: 'square icon box');
          }
        }
      });
    }

    testWidgets('the selected slot is announced as a selected button', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpBar(tester, theme: AppTheme.lightTheme);

      expect(
        tester.getSemantics(find.byKey(e2eKey(E2eIds.navForYou))),
        isSemantics(label: 'Home', isButton: true, isSelected: true),
      );
      expect(
        tester.getSemantics(find.byKey(e2eKey(E2eIds.navSearch))),
        isSemantics(label: 'Search', isButton: true, isSelected: false),
      );
      expect(
        tester.getSemantics(find.byKey(e2eKey(E2eIds.navProfile))),
        isSemantics(label: 'Profile', isButton: true, isSelected: false),
      );
      handle.dispose();
    });

    testWidgets(
      'a press takes the slot down under the finger and springs it back',
      (tester) async {
        await pumpBar(tester, theme: AppTheme.darkTheme);
        final slot = find.byKey(e2eKey(E2eIds.navSearch));

        double scale() {
          final transform = tester.widget<Transform>(
            find.descendant(of: slot, matching: find.byType(Transform)).first,
          );
          // The x axis: z stays 1 under Transform.scale, so the max-axis
          // scale would always read 1.
          return transform.transform.storage[0];
        }

        expect(scale(), closeTo(1, 0.001));
        final gesture = await tester.startGesture(tester.getCenter(slot));
        // The press shows on touch-down, before any recognizer decides.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(scale(), closeTo(BottomNavBarWidget.pressedScale, 0.01));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(scale(), closeTo(1, 0.002));

        // Anywhere in the slot is a press, not only the mark's pixels: its
        // top corner and the strip at its foot both take it down.
        final box = tester.getRect(slot);
        for (final point in [
          box.topLeft + const Offset(4, 4),
          box.bottomCenter - const Offset(0, 4),
        ]) {
          final held = await tester.startGesture(point);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 250));
          expect(
            scale(),
            closeTo(BottomNavBarWidget.pressedScale, 0.01),
            reason: '$point',
          );
          await held.up();
          await tester.pumpAndSettle();
        }
      },
    );

    testWidgets('360dp at 1.3x text: no overflow, 44dp slots', (tester) async {
      await pumpBar(
        tester,
        theme: AppTheme.lightTheme,
        size: const Size(360, 640),
        textScale: 1.3,
      );

      expect(tester.takeException(), isNull);
      for (final id in [
        E2eIds.navForYou,
        E2eIds.navFeed,
        E2eIds.navBotvinnik,
        E2eIds.navSearch,
        E2eIds.navProfile,
      ]) {
        final size = tester.getSize(find.byKey(e2eKey(id)));
        expect(size.height, greaterThanOrEqualTo(44));
        // Five equal slots inside the full capsule's round ends.
        expect(
          size.width,
          closeTo(
            (360 - 2 * HomeNavMetrics.sideMargin - 2 * HomeNavMetrics.padding) /
                5,
            0.01,
          ),
        );
        expect(size.width, greaterThanOrEqualTo(44));
      }
    });
  });

  group('dock', () {
    Future<void> pumpDock(
      WidgetTester tester, {
      required ValueNotifier<double> chrome,
      TargetPlatform platform = TargetPlatform.iOS,
      double inset = 34,
      bool scrim = true,
    }) async {
      tester.view
        ..physicalSize = const Size(393, 852) * 3
        ..devicePixelRatio = 3
        ..padding = FakeViewPadding(bottom: inset * 3)
        ..viewPadding = FakeViewPadding(bottom: inset * 3);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            botvinnikTabAvailableProvider.overrideWithValue(true),
            currentUserProvider.overrideWithValue(null),
            profileAvatarUrlProvider.overrideWithValue(null),
            inboxHasUnreadProvider.overrideWithValue(false),
            subscriptionProvider.overrideWith((ref) => _Subscription()),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme.copyWith(platform: platform),
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  extendBody: true,
                  bottomNavigationBar: HomeNavDock(
                    chrome: chrome,
                    scrim: scrim,
                  ),
                  body: Builder(
                    builder: (context) => SizedBox.expand(
                      key: const ValueKey('page'),
                      child: Text(
                        'pad ${MediaQuery.paddingOf(context).bottom}',
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
    }

    final capsule = find.byKey(const ValueKey('home-nav-capsule'));
    final dock = find.byKey(const ValueKey('home-nav-dock'));

    testWidgets('iPhone: a full capsule over the page, 22 above the edge; '
        'drawn in to 44 tall as wide as its marks, never gone', (tester) async {
      final chrome = ValueNotifier<double>(1);
      addTearDown(chrome.dispose);
      await pumpDock(tester, chrome: chrome);

      // The page runs under the dock and pads its end by the dock's slot.
      expect(tester.getSize(find.byKey(const ValueKey('page'))).height, 852);
      expect(find.text('pad 78.0'), findsOneWidget);
      expect(tester.getSize(dock).height, 78);
      final full = tester.getRect(capsule);
      expect(full.size, const Size(361, 56));
      expect(full.bottom, closeTo(852 - 22, 0.01));
      expect(full.center.dx, closeTo(393 / 2, 0.01));

      chrome.value = 0;
      await tester.pump();
      final compact = tester.getRect(capsule);
      // 5 targets of 44, 6 apart, inside 10 at either end.
      expect(compact.size, const Size(5 * 44 + 4 * 6 + 20, 44));
      expect(compact.bottom, closeTo(852 - 22, 0.01));
      expect(compact.center.dx, closeTo(393 / 2, 0.01));
      // The slot never changes height, so the page is never laid out again.
      expect(tester.getSize(dock).height, 78);
      expect(find.text('pad 78.0'), findsOneWidget);
      for (final item in bottomNavBarOrder) {
        final slot = tester.getRect(find.byKey(bottomNavBarItemKey(item)));
        expect(slot.width, greaterThanOrEqualTo(44), reason: item.name);
        // Each target runs from the capsule's top to the screen's edge.
        expect(slot.top, closeTo(compact.top, 0.01));
        expect(slot.bottom, closeTo(852, 0.01));
        expect(slot.left, greaterThanOrEqualTo(compact.left));
        expect(slot.right, lessThanOrEqualTo(compact.right));
      }

      // Halfway, it is halfway: one value drives the shape.
      chrome.value = 0.5;
      await tester.pump();
      expect(tester.getSize(capsule).height, closeTo(50, 0.01));
    });

    testWidgets('the marks draw in with the capsule and stay centred in it', (
      tester,
    ) async {
      final chrome = ValueNotifier<double>(0);
      addTearDown(chrome.dispose);
      await pumpDock(tester, chrome: chrome);
      final box = tester.getRect(capsule);
      final home = find.descendant(
        of: find.byKey(bottomNavBarItemKey(BottomNavBarItem.forYou)),
        matching: find.byType(Icon),
      );
      final mark = tester.getRect(home);
      expect(mark.center.dy, closeTo(box.center.dy, 0.5));
      // 22 of 28: the compact mark.
      final full = BottomNavBarWidget.iconSide + 4;
      expect(mark.height, closeTo(full * 22 / 28, 0.5));
    });

    testWidgets('Android: the capsule stays wholly above the system bar', (
      tester,
    ) async {
      final chrome = ValueNotifier<double>(1);
      addTearDown(chrome.dispose);
      // Three-button navigation.
      await pumpDock(
        tester,
        chrome: chrome,
        platform: TargetPlatform.android,
        inset: 48,
      );
      expect(tester.getRect(capsule).bottom, closeTo(852 - 48, 0.01));
      expect(tester.getSize(dock).height, 48 + 56);
    });

    testWidgets('a tap on a mark selects its section, at either size', (
      tester,
    ) async {
      final chrome = ValueNotifier<double>(0);
      addTearDown(chrome.dispose);
      await pumpDock(tester, chrome: chrome);
      final container = ProviderScope.containerOf(tester.element(dock));
      // Under the capsule, in the strip to the screen's edge: still a tap.
      final search = tester.getRect(
        find.byKey(bottomNavBarItemKey(BottomNavBarItem.search)),
      );
      await tester.tapAt(Offset(search.center.dx, search.bottom - 4));
      await tester.pumpAndSettle();
      expect(
        container.read(selectedBottomNavBarItemProvider),
        BottomNavBarItem.search,
      );
    });

    test('metrics: one slot, two shapes', () {
      const m = HomeNavMetrics(gap: 22, count: 4, screenWidth: 393);
      expect(m.extent, 78);
      expect(m.compactExtent, 66);
      expect(m.ride, 12);
      expect(m.normalWidth, 361);
      expect(m.compactWidth, 4 * 44 + 3 * 6 + 20);
      expect(m.widthAt(1), m.normalWidth);
      expect(m.widthAt(0), m.compactWidth);
      expect(m.markScaleAt(0), closeTo(22 / 28, 1e-9));
      // A landscape phone: never wider than 440.
      expect(
        const HomeNavMetrics(gap: 12, count: 5, screenWidth: 852).normalWidth,
        HomeNavMetrics.maxWidth,
      );
    });
  });

  group('For You segments', () {
    for (final (name, theme, colors) in _themes) {
      testWidgets('$name: resting and selected segments clear AA', (
        tester,
      ) async {
        tester.view
          ..physicalSize = const Size(393, 852) * 3
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              recentSearchStorageProvider.overrideWithValue(
                _MemoryRecentSearches(),
              ),
              selectedBottomNavBarItemProvider.overrideWith(
                (ref) => BottomNavBarItem.forYou,
              ),
            ],
            child: MaterialApp(
              theme: theme,
              home: Builder(
                builder: (context) {
                  ResponsiveHelper.init(context);
                  return Scaffold(
                    body: ForYouScreen(
                      pageBuilder: (context, tab, controller) => ListView(
                        controller: controller,
                        children: [Text('page:${tab.name}')],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();

        for (final tab in ForYouTab.values) {
          final text = tester.widget<Text>(find.text(tab.label));
          final ink = text.style!.color!;
          // Every title stays bright; the underline alone marks the page
          // (PM, 2026-11-20).
          expect(ink, colors.textPrimary);
          expect(
            _contrast(ink, colors.background),
            greaterThanOrEqualTo(4.5),
            reason: '${tab.label} on the page',
          );
        }
      });
    }
  });
}
