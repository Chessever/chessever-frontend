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
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:chessever2/widgets/svg_widget.dart';
import 'package:flutter/gestures.dart';
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

          // The mark over its name, both in the slot's ink: the name says
          // what the slot is (the avatar reads as Profile), weight says
          // which one is open.
          final label = tester.widget<Text>(
            find.descendant(
              of: slot,
              matching: find.text(namesBottomNavBarIcons[item]!),
            ),
          );
          expect(label.style!.color, ink);
          expect(
            label.style!.fontWeight,
            selected ? FontWeight.w700 : FontWeight.w500,
          );
          expect(
            _contrast(ink, colors.background),
            greaterThanOrEqualTo(4.5),
            reason: '${item.name} label',
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
        expect(size.width, closeTo(72, 0.01));
      }
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
          expect(
            ink,
            tab == ForYouTab.today ? colors.textPrimary : colors.textSecondary,
          );
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
