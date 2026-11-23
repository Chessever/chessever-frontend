import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/home/start_screen.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Holding a bottom tab or a tab title saves the section and the page, and
/// the confirmation names both ("Home → Discovery").
void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    prefs = (await SharedPreferencesService.instance.initialize())!;
  });

  setUp(() async => prefs.clear());

  group('saved pages', () {
    test('each section opens on its default until one is saved', () {
      expect(readDefaultForYouTab(), ForYouTab.today);
      expect(readDefaultEventsCategory(), GroupEventCategory.current);
    });

    test('Events reads back what was saved', () async {
      await writeDefaultEventsCategory(GroupEventCategory.upcoming);

      expect(readDefaultEventsCategory(), GroupEventCategory.upcoming);

      final container = ProviderContainer(
        overrides: [
          subscriptionProvider.overrideWith((ref) => _PaidSubscription()),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(selectedGroupCategoryProvider),
        GroupEventCategory.upcoming,
      );
    });

    test(
      'an unreadable or transient value falls back to the default',
      () async {
        // Search is a transient Events segment, never a start page.
        await prefs.setString(defaultEventsCategoryPrefsKey, 'search');

        expect(readDefaultEventsCategory(), GroupEventCategory.current);
      },
    );

    test('the confirmation names the section, then the tab', () {
      expect(
        startScreenName(
          BottomNavBarItem.forYou,
          forYouStartPage(ForYouTab.discovery),
        ),
        'Home → Discovery',
      );
      expect(
        startScreenName(
          BottomNavBarItem.tournaments,
          eventsStartPage(GroupEventCategory.upcoming),
        ),
        'Events → Upcoming',
      );
      // Sections without pages are named alone.
      expect(startScreenName(BottomNavBarItem.feed, null), 'Feed');
      expect(startScreenName(BottomNavBarItem.profile, null), 'Profile');
    });

    test('a saved section that left the dock opens Home', () async {
      // Collections left the dock for Discovery (2026-11-23), Search for
      // Today's button: a reader who launched on one opens on Home, one tap
      // from it.
      for (final name in ['collections', 'search']) {
        await prefs.setString(defaultBottomTabPrefsKey, name);
        expect(readDefaultBottomTab(), BottomNavBarItem.forYou, reason: name);
      }
    });

    test('Events, on the dock again, reads back as itself', () async {
      // The name Events was saved under before 38.18.
      await prefs.setString(defaultBottomTabPrefsKey, 'tournaments');
      expect(readDefaultBottomTab(), BottomNavBarItem.tournaments);
    });
  });

  group('holding it', () {
    late ProviderContainer container;
    late BuildContext hostContext;

    Future<void> pumpHost(
      WidgetTester tester,
      void Function(BuildContext context, WidgetRef ref) onHold,
    ) async {
      container = ProviderContainer(
        overrides: [
          subscriptionProvider.overrideWith((ref) => _PaidSubscription()),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return Scaffold(
                  body: Consumer(
                    builder: (context, ref, _) {
                      hostContext = context;
                      return TextButton(
                        onPressed: () => onHold(context, ref),
                        child: const Text('hold'),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    testWidgets('Home saves the tab it is showing', (tester) async {
      await pumpHost(
        tester,
        (context, ref) => makeStartScreenDefault(
          context,
          ref,
          section: BottomNavBarItem.forYou,
        ),
      );
      container
          .read(selectedForYouTabProvider.notifier)
          .select(ForYouTab.discovery);

      await tester.tap(find.text('hold'));
      await settle(tester);

      expect(
        find.text('Make Home → Discovery your start screen?'),
        findsOneWidget,
      );
      expect(
        find.text(
          'The app will open on Home → Discovery next time you launch it.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Apply'));
      await settle(tester);

      expect(prefs.getString(defaultBottomTabPrefsKey), 'forYou');
      expect(prefs.getString(defaultForYouTabPrefsKey), 'discovery');
      expect(
        find.text('Home → Discovery is now your start screen'),
        findsOneWidget,
      );
      // Clear the snack timer before the test ends.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('cancelling saves nothing', (tester) async {
      await pumpHost(
        tester,
        (context, ref) => makeStartScreenDefault(
          context,
          ref,
          section: BottomNavBarItem.forYou,
        ),
      );

      await tester.tap(find.text('hold'));
      await settle(tester);
      await tester.tap(find.text('Cancel'));
      await settle(tester);

      expect(prefs.getString(defaultBottomTabPrefsKey), isNull);
      expect(prefs.getString(defaultForYouTabPrefsKey), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('Events saves the list it is showing', (tester) async {
      await pumpHost(
        tester,
        (context, ref) => makeStartScreenDefault(
          context,
          ref,
          section: BottomNavBarItem.tournaments,
        ),
      );
      container.read(selectedGroupCategoryProvider.notifier).state =
          GroupEventCategory.upcoming;

      await tester.tap(find.text('hold'));
      await settle(tester);
      expect(
        find.text('Make Events → Upcoming your start screen?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Apply'));
      await settle(tester);

      expect(prefs.getString(defaultBottomTabPrefsKey), 'tournaments');
      expect(prefs.getString(defaultEventsCategoryPrefsKey), 'upcoming');
      expect(readDefaultBottomTab(), BottomNavBarItem.tournaments);
      expect(readDefaultEventsCategory(), GroupEventCategory.upcoming);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('Events on a search saves the list the search hands back to', (
      tester,
    ) async {
      await pumpHost(
        tester,
        (context, ref) => makeStartScreenDefault(
          context,
          ref,
          section: BottomNavBarItem.tournaments,
        ),
      );
      container.read(selectedGroupCategoryProvider.notifier).state =
          GroupEventCategory.past;
      container.read(groupEventSearchTabControllerProvider).showSearch();

      await tester.tap(find.text('hold'));
      await settle(tester);
      expect(
        find.text('Make Events → Past your start screen?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });

    testWidgets('a section without pages saves the section alone', (
      tester,
    ) async {
      await pumpHost(
        tester,
        (context, ref) => makeStartScreenDefault(
          context,
          ref,
          section: BottomNavBarItem.feed,
        ),
      );

      await tester.tap(find.text('hold'));
      await settle(tester);
      expect(find.text('Make Feed your start screen?'), findsOneWidget);
      await tester.tap(find.text('Apply'));
      await settle(tester);

      expect(prefs.getString(defaultBottomTabPrefsKey), 'feed');
      expect(prefs.getString(defaultForYouTabPrefsKey), isNull);
      expect(hostContext.mounted, isTrue);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
  });

  group('tab titles', () {
    Future<List<int>> pumpSwitcher(
      WidgetTester tester, {
      required List<int> selected,
      required List<int> held,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return Scaffold(
                body: SegmentedSwitcher(
                  options: const ['One', 'Two', 'Three'],
                  currentSelection: 0,
                  onSelectionChanged: selected.add,
                  // The last segment is press-only, like a transient Search.
                  longPressFor: (index) =>
                      index < 2 ? () => held.add(index) : null,
                  longPressHint: (index) => 'Hold ${index + 1}',
                ),
              );
            },
          ),
        ),
      );
      return held;
    }

    testWidgets('holding a title reports it without selecting it', (
      tester,
    ) async {
      final selected = <int>[];
      final held = <int>[];
      await pumpSwitcher(tester, selected: selected, held: held);

      await tester.longPress(find.text('Two'));
      await tester.pump();

      expect(held, [1]);
      expect(selected, isEmpty);
    });

    testWidgets('a press-only title ignores a hold and still selects', (
      tester,
    ) async {
      final selected = <int>[];
      final held = <int>[];
      await pumpSwitcher(tester, selected: selected, held: held);

      await tester.longPress(find.text('Three'));
      await tester.pump();
      expect(held, isEmpty);

      await tester.tap(find.text('Three'));
      await tester.pump();
      expect(selected, [2]);
    });

    testWidgets('a tap still selects a title that can be held', (tester) async {
      final selected = <int>[];
      final held = <int>[];
      await pumpSwitcher(tester, selected: selected, held: held);

      await tester.tap(find.text('Two'));
      await tester.pump();

      expect(selected, [1]);
      expect(held, isEmpty);
    });
  });
}

class _PaidSubscription extends SubscriptionNotifier {
  _PaidSubscription() : super() {
    state = SubscriptionState(isSubscribed: true, isLoading: false);
  }

  // Keep a resolved subscriber while RevenueCat is unavailable under test.
  @override
  set state(SubscriptionState value) =>
      super.state = value.copyWith(isSubscribed: true, isLoading: false);
}
