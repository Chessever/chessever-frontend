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
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/widgets/glass_surface.dart';
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

    test('the dock names Home, Events, Botvinnik, Feed, Profile: Events '
        'beside Home, Feed beside Profile, no Collections', () {
      expect(bottomNavBarOrder.map((item) => item.name), [
        'forYou',
        'tournaments',
        'botvinnik',
        'feed',
        'profile',
      ]);
      expect(bottomNavBarOrder.map((item) => namesBottomNavBarIcons[item]), [
        'Home',
        'Events',
        'Botvinnik',
        'Feed',
        'Profile',
      ]);
      expect(
        BottomNavBarItem.values.map((item) => item.name),
        isNot(contains('collections')),
      );
      // Analytics, the start screen and the discovery dots name Events as
      // its tab did before 38.18.
      expect(BottomNavBarItem.tournaments.name, 'tournaments');
      expect(
        bottomNavBarDotIds[BottomNavBarItem.tournaments],
        'home.nav.events',
      );
      expect(
        bottomNavBarItemKey(BottomNavBarItem.tournaments),
        e2eKey(E2eIds.navEvents),
      );
      expect(
        bottomNavBarDotIds.values,
        isNot(contains('home.nav.collections')),
      );
    });

    test('Botvinnik switched off leaves four tabs: Home, Events, Feed, '
        'Profile', () {
      final container = ProviderContainer(
        overrides: [botvinnikTabAvailableProvider.overrideWithValue(false)],
      );
      addTearDown(container.dispose);
      expect(container.read(visibleBottomNavItemsProvider), [
        BottomNavBarItem.forYou,
        BottomNavBarItem.tournaments,
        BottomNavBarItem.feed,
        BottomNavBarItem.profile,
      ]);
    });

    test('Botvinnik on: the dock holds all five, in the dock\'s order', () {
      final container = ProviderContainer(
        overrides: [botvinnikTabAvailableProvider.overrideWithValue(true)],
      );
      addTearDown(container.dispose);
      expect(container.read(visibleBottomNavItemsProvider), [
        BottomNavBarItem.forYou,
        BottomNavBarItem.tournaments,
        BottomNavBarItem.botvinnik,
        BottomNavBarItem.feed,
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
            if (item == BottomNavBarItem.tournaments) {
              // The trophy, in the dock's line weight.
              expect(icon.path, SvgAsset.eventsNavIcon);
            }
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
        tester.getSemantics(find.byKey(e2eKey(E2eIds.navEvents))),
        isSemantics(label: 'Events', isButton: true, isSelected: false),
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
        final slot = find.byKey(e2eKey(E2eIds.navEvents));

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
        E2eIds.navEvents,
        E2eIds.navBotvinnik,
        E2eIds.navFeed,
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

    /// How much of the capsule's glass is there: the fade its own material
    /// takes ([GlassFade]), never an opacity over the frost.
    double glass(WidgetTester tester) => tester
        .widget<GlassFade>(
          find.ancestor(of: capsule, matching: find.byType(GlassFade)),
        )
        .opacity
        .value;

    /// The opacity the marks are drawn at.
    double marks(WidgetTester tester) => tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.byKey(bottomNavBarItemKey(BottomNavBarItem.forYou)),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;

    /// Whether a tap at [point] would reach the dock.
    bool hitsDock(WidgetTester tester, Offset point) {
      final result = tester.hitTestOnBinding(point);
      final box = tester.renderObject(dock);
      return result.path.any((entry) => entry.target == box);
    }

    testWidgets('iPhone: a full capsule over the page, 22 above the edge; '
        'reading on it slides wholly past the screen\'s edge and fades out, '
        'the slot never changing', (tester) async {
      final semantics = tester.ensureSemantics();
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
      expect(glass(tester), 1);
      expect(marks(tester), 1);

      // Halfway, it is halfway down and half there: one value drives both.
      chrome.value = 0.5;
      await tester.pump();
      const slide = 22 + 56 + HomeNavMetrics.shadowReach;
      final mid = tester.getRect(capsule);
      expect(mid.size, full.size);
      expect(mid.top, closeTo(full.top + slide / 2, 0.01));
      expect(glass(tester), closeTo(0.5, 1e-9));
      expect(marks(tester), closeTo(0.5, 1e-9));

      chrome.value = 0;
      await tester.pump();
      final gone = tester.getRect(capsule);
      // Wholly past the screen's edge, its shadow with it, and faded out.
      expect(gone.top, greaterThanOrEqualTo(852 + 0.01));
      expect(gone.top, closeTo(full.top + slide, 0.01));
      expect(glass(tester), 0);
      expect(marks(tester), 0);
      // The slot never changes height, so the page is never laid out again.
      expect(tester.getSize(dock).height, 78);
      expect(find.text('pad 78.0'), findsOneWidget);
      // Out of the semantics tree: no section is announced.
      for (final item in bottomNavBarOrder) {
        expect(
          find.semantics.byLabel(namesBottomNavBarIcons[item]!),
          findsNothing,
          reason: item.name,
        );
      }

      chrome.value = 1;
      await tester.pump();
      expect(tester.getRect(capsule), full);
      expect(find.semantics.byLabel('Home'), findsOne);
      semantics.dispose();
    });

    testWidgets('gone, the dock paints nothing and takes no tap: the page '
        'under it does', (tester) async {
      final chrome = ValueNotifier<double>(1);
      addTearDown(chrome.dispose);
      await pumpDock(tester, chrome: chrome);
      final events = tester.getRect(
        find.byKey(bottomNavBarItemKey(BottomNavBarItem.tournaments)),
      );
      final point = events.center;
      expect(hitsDock(tester, point), isTrue);

      chrome.value = 0;
      await tester.pump();
      expect(hitsDock(tester, point), isFalse);
      // Its strip to the screen's edge is the page's again too.
      expect(hitsDock(tester, Offset(point.dx, 852 - 4)), isFalse);
      expect(
        tester
            .hitTestOnBinding(point)
            .path
            .any(
              (entry) =>
                  entry.target ==
                  tester.renderObject(find.byKey(const ValueKey('page'))),
            ),
        isTrue,
      );
      // Nothing of it is painted.
      final slide = find.ancestor(
        of: capsule,
        matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_DockSlide',
        ),
      );
      expect(slide, paintsNothing);

      // Mostly gone (on its way out, or only just arriving): no taps yet.
      chrome.value = HomeNavDock.tapFloor - 0.01;
      await tester.pump();
      final low = tester.getRect(
        find.byKey(bottomNavBarItemKey(BottomNavBarItem.tournaments)),
      );
      expect(hitsDock(tester, Offset(low.center.dx, low.top + 4)), isFalse);
      chrome.value = HomeNavDock.tapFloor + 0.01;
      await tester.pump();
      final high = tester.getRect(
        find.byKey(bottomNavBarItemKey(BottomNavBarItem.tournaments)),
      );
      // Where it is drawn (its top, still on the screen), it takes the
      // tap.
      expect(hitsDock(tester, Offset(high.center.dx, high.top + 4)), isTrue);
    });

    testWidgets('the scrim leaves with the dock', (tester) async {
      final chrome = ValueNotifier<double>(1);
      addTearDown(chrome.dispose);
      await pumpDock(tester, chrome: chrome);
      final scrim = find.descendant(
        of: dock,
        matching: find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter != null,
        ),
      );
      expect(scrim, paints..rect());
      chrome.value = 0;
      await tester.pump();
      expect(scrim, paintsNothing);
    });

    testWidgets('the marks stay centred in the capsule, at one size', (
      tester,
    ) async {
      final chrome = ValueNotifier<double>(1);
      addTearDown(chrome.dispose);
      await pumpDock(tester, chrome: chrome);
      final box = tester.getRect(capsule);
      final home = find.descendant(
        of: find.byKey(bottomNavBarItemKey(BottomNavBarItem.forYou)),
        matching: find.byType(Icon),
      );
      final mark = tester.getRect(home);
      expect(mark.center.dy, closeTo(box.center.dy, 0.5));
      // Sliding away, the mark rides with the capsule, never shrinking.
      chrome.value = 0.6;
      await tester.pump();
      final moved = tester.getRect(home);
      expect(moved.size, mark.size);
      expect(moved.center.dy, closeTo(tester.getRect(capsule).center.dy, 0.5));
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

    testWidgets('a tap on a mark selects its section', (tester) async {
      final chrome = ValueNotifier<double>(1);
      addTearDown(chrome.dispose);
      await pumpDock(tester, chrome: chrome);
      final container = ProviderScope.containerOf(tester.element(dock));
      // Under the capsule, in the strip to the screen's edge: still a tap.
      final events = tester.getRect(
        find.byKey(bottomNavBarItemKey(BottomNavBarItem.tournaments)),
      );
      await tester.tapAt(Offset(events.center.dx, events.bottom - 4));
      await tester.pumpAndSettle();
      expect(
        container.read(selectedBottomNavBarItemProvider),
        BottomNavBarItem.tournaments,
      );
    });

    test('metrics: one slot; the dock leaves whole', () {
      const m = HomeNavMetrics(gap: 22, count: 4, screenWidth: 393, inset: 34);
      expect(m.extent, 78);
      // Gone, only the home indicator's strip covers the page's foot.
      expect(m.awayExtent, 34);
      // Feed's capsule never leaves: drawn in, it covers 44 over its gap.
      expect(m.compactExtent, 22 + 44);
      expect(m.heightAt(0), 44);
      expect(m.heightAt(1), 56);
      // Four 44pt targets, 6 apart, inside 10 at either end.
      expect(m.compactWidth, 4 * 44 + 3 * 6 + 2 * 10);
      expect(m.widthAt(1), m.normalWidth);
      expect(m.markScaleAt(0), 22 / 28);
      // The buttons come down from over the capsule to over the strip.
      expect(m.ride, 78 - 34);
      // Past the screen's edge, its contact shadow included.
      expect(m.slide, 22 + 56 + HomeNavMetrics.shadowReach);
      expect(m.normalWidth, 361);
      // An SE (no strip): the buttons come down the whole slot.
      expect(
        const HomeNavMetrics(gap: 12, count: 5, screenWidth: 375).ride,
        12 + 56,
      );
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
