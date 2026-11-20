import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/screens/for_you/for_you_screen.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/group_event/widget/for_you_games_widget.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:chessever2/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _MemoryRecentSearches implements RecentSearchStorage {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}
}

/// Stand-in pages: the shell is under test, not the network-backed pages.
Widget _fakePage(BuildContext context, ForYouTab tab, ScrollController c) {
  return ListView(controller: c, children: [Text('page:${tab.name}')]);
}

Widget _app({
  ForYouPageBuilder? pageBuilder = _fakePage,
  ForYouTab? initialTab,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      recentSearchStorageProvider.overrideWithValue(_MemoryRecentSearches()),
      selectedBottomNavBarItemProvider.overrideWith(
        (ref) => BottomNavBarItem.forYou,
      ),
      if (initialTab != null)
        selectedForYouTabProvider.overrideWith(
          (ref) => ForYouTabController(initialTab),
        ),
      ...overrides,
    ],
    child: MaterialApp(
      theme: AppTheme.darkTheme,
      home: Builder(
        builder: (context) {
          ResponsiveHelper.init(context);
          return Scaffold(body: ForYouScreen(pageBuilder: pageBuilder));
        },
      ),
    ),
  );
}

Future<void> _pump(WidgetTester tester, Widget app) async {
  await tester.binding.setSurfaceSize(const Size(393, 852));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(app);
  await tester.pump();
}

int _selectedSegment(WidgetTester tester) =>
    tester.widget<ForYouPageTabs>(find.byType(ForYouPageTabs)).selectedIndex;

ForYouTab _selectedTab(WidgetTester tester) => ProviderScope.containerOf(
  tester.element(find.byType(ForYouScreen)),
).read(selectedForYouTabProvider);

void main() {
  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    prefs = (await SharedPreferencesService.instance.initialize())!;
  });

  setUp(() async {
    await prefs.remove(forYouLastTabPrefsKey);
  });

  testWidgets('renders My Space | Today | Discovery and opens on Today', (
    tester,
  ) async {
    await _pump(tester, _app());

    final switcher = tester.widget<ForYouPageTabs>(find.byType(ForYouPageTabs));
    expect(switcher.labels, ['My Space', 'Today', 'Discovery']);
    expect(_selectedSegment(tester), ForYouTab.today.index);
    expect(find.text('page:today'), findsOneWidget);
    // Only the selected page is built.
    expect(find.text('page:mySpace'), findsNothing);
    expect(find.text('page:discovery'), findsNothing);
  });

  testWidgets('opens on the tab the controller starts with', (tester) async {
    await _pump(tester, _app(initialTab: ForYouTab.discovery));

    expect(_selectedSegment(tester), ForYouTab.discovery.index);
    expect(find.text('page:discovery'), findsOneWidget);
    expect(find.text('page:today'), findsNothing);
  });

  testWidgets('a page an older build stored on the device is ignored', (
    tester,
  ) async {
    for (final stored in [ForYouTab.discovery.name, 'calendar']) {
      await prefs.setString(forYouLastTabPrefsKey, stored);

      await _pump(tester, _app());

      expect(_selectedSegment(tester), ForYouTab.today.index);
      expect(find.text('page:today'), findsOneWidget);
      // Only Home's launch cleanup touches the legacy key.
      expect(prefs.getString(forYouLastTabPrefsKey), stored);

      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('picking a tab shows its page without writing to the device', (
    tester,
  ) async {
    await _pump(tester, _app());

    await tester.tap(find.text('My Space'));
    await tester.pumpAndSettle();

    expect(_selectedSegment(tester), ForYouTab.mySpace.index);
    expect(_selectedTab(tester), ForYouTab.mySpace);
    expect(find.text('page:mySpace'), findsOneWidget);
    expect(find.text('page:today'), findsNothing);
    expect(prefs.getString(forYouLastTabPrefsKey), isNull);
  });

  testWidgets('Home tapped again away from Today slides back to Today', (
    tester,
  ) async {
    await _pump(tester, _app(initialTab: ForYouTab.discovery));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ForYouScreen)),
    );

    container
        .read(bottomNavBarReTapRequestProvider.notifier)
        .request(BottomNavBarItem.forYou);
    await tester.pumpAndSettle();

    expect(_selectedTab(tester), ForYouTab.today);
    expect(_selectedSegment(tester), ForYouTab.today.index);
    expect(find.text('page:today'), findsOneWidget);
  });

  testWidgets('Home wears no avatar and no search field: Search and Profile '
      'have tabs of their own', (tester) async {
    await _pump(tester, _app());
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(UserAvatar), findsNothing);
    // The brand mark over the page tabs is the whole top bar.
    expect(find.byType(ForYouPageTabs), findsOneWidget);
  });

  testWidgets('a swipe follows the drag instead of snapping mid-gesture', (
    tester,
  ) async {
    await _pump(tester, _app());
    final controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    final width = controller.position.viewportDimension;
    expect(controller.position.pixels, closeTo(width, 0.5));

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    // Well past the halfway mark toward Discovery, finger still down.
    for (var i = 0; i < 14; i++) {
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_selectedSegment(tester), ForYouTab.discovery.index);
    final dragged = controller.position.pixels;
    expect(dragged, greaterThan(1.5 * width));
    expect(dragged, lessThan(2 * width - 50));
    // The selection change must not pull the page out from under the finger.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.position.pixels, closeTo(dragged, 0.5));

    // Back over the halfway mark: Today again, still tracking the drag.
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_selectedSegment(tester), ForYouTab.today.index);
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.position.pixels, closeTo(dragged - 160, 1));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.position.pixels, closeTo(width, 0.5));
    expect(find.text('page:today'), findsOneWidget);
  });

  testWidgets('both pages stay drawn while a swipe shows them', (tester) async {
    await _pump(tester, _app());

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    // Short of halfway: Discovery is carried in, Today still selected.
    for (var i = 0; i < 5; i++) {
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_selectedSegment(tester), ForYouTab.today.index);
    expect(find.text('page:today'), findsOneWidget);
    expect(find.text('page:discovery'), findsOneWidget);

    // Past halfway: Discovery takes the selection, Today is still half in
    // view and must not blank.
    for (var i = 0; i < 9; i++) {
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_selectedSegment(tester), ForYouTab.discovery.index);
    expect(find.text('page:today'), findsOneWidget);
    expect(find.text('page:discovery'), findsOneWidget);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('page:discovery'), findsOneWidget);
    expect(find.text('page:today'), findsNothing);
  });

  testWidgets('a tab picked while the pages settle lands once they stop', (
    tester,
  ) async {
    await _pump(tester, _app());
    final controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;

    // A short drag, released: the view springs back to Today.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 16));
    expect(controller.position.isScrollingNotifier.value, isTrue);

    await tester.tap(find.text('My Space'));
    await tester.pumpAndSettle();

    expect(_selectedSegment(tester), ForYouTab.mySpace.index);
    expect(controller.position.pixels, closeTo(0, 0.5));
    expect(find.text('page:mySpace'), findsOneWidget);
  });

  testWidgets('Today hosts the existing For You feed widget', (tester) async {
    await _pump(
      tester,
      _app(
        pageBuilder: null,
        // Keeps the feed inert (it renders nothing and subscribes to nothing
        // while its tab is inactive), so no network is touched here.
        overrides: [forYouTodayTabActiveProvider.overrideWith((ref) => false)],
      ),
    );

    expect(find.byType(ForYouGamesWidget), findsOneWidget);
  });

  test('buildForYouPage maps Today to the For You feed', () {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final page = buildForYouPage(
      _NeverBuiltContext(),
      ForYouTab.today,
      controller,
    );
    expect(page, isA<ForYouGamesWidget>());
    expect((page as ForYouGamesWidget).scrollController, same(controller));
  });

  group('forYouTodayTabActiveProvider', () {
    ProviderContainer container({
      required BottomNavBarItem nav,
      String query = '',
    }) {
      final c = ProviderContainer(
        overrides: [
          selectedBottomNavBarItemProvider.overrideWith((ref) => nav),
        ],
      );
      addTearDown(c.dispose);
      c.read(forYouSearchQueryProvider.notifier).state = query;
      return c;
    }

    test('is true only on For You > Today with no search running', () {
      final c = container(nav: BottomNavBarItem.forYou);
      final sub = c.listen(forYouTodayTabActiveProvider, (_, __) {});
      addTearDown(sub.close);
      c.read(selectedForYouTabProvider.notifier).select(ForYouTab.today);
      expect(c.read(forYouTodayTabActiveProvider), isTrue);

      c.read(selectedForYouTabProvider.notifier).select(ForYouTab.discovery);
      expect(c.read(forYouTodayTabActiveProvider), isFalse);

      c.read(selectedForYouTabProvider.notifier).select(ForYouTab.today);
      c.read(forYouSearchQueryProvider.notifier).state = 'carlsen';
      expect(c.read(forYouTodayTabActiveProvider), isFalse);
    });

    test('stays true while a swipe still shows Today', () {
      final c = container(nav: BottomNavBarItem.forYou);
      final sub = c.listen(forYouTodayTabActiveProvider, (_, __) {});
      addTearDown(sub.close);
      c.read(selectedForYouTabProvider.notifier).select(ForYouTab.discovery);
      expect(c.read(forYouTodayTabActiveProvider), isFalse);

      c.read(forYouTodayInViewProvider.notifier).state = true;
      expect(c.read(forYouTodayTabActiveProvider), isTrue);

      c.read(forYouTodayInViewProvider.notifier).state = false;
      expect(c.read(forYouTodayTabActiveProvider), isFalse);
    });

    test('is false while another main section is selected', () {
      final c = container(nav: BottomNavBarItem.feed);
      c.read(selectedForYouTabProvider.notifier).select(ForYouTab.today);
      expect(c.read(forYouTodayTabActiveProvider), isFalse);
    });
  });

  test('search segment title is title-cased and trimmed at a word', () {
    expect(forYouSearchTabTitle('HIKARU'), 'Hikaru');
    expect(forYouSearchTabTitle('magnus carlsen'), 'Magnus…');
    expect(forYouSearchTabTitle('najdorfvariation'), 'Najdorfvari…');
  });
}

/// `buildForYouPage` only constructs widgets; it never touches the context.
class _NeverBuiltContext extends Fake implements BuildContext {}
