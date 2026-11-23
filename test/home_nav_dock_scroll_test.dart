// The home dock as the shell holds it, driven by a real scroll: reading a
// root down sends the dock away whole (it slides past the screen's edge and
// fades out, its glass through its own material), the floating buttons
// riding down to where a page with no dock stands them; heading back up
// brings both back. Gone, the dock takes no tap and the page under it does;
// the page's own layout never changes as it comes and goes.
//
// Also: a page that would push a second Events (Discovery's tile, Search's
// Coming up section) switches to the dock's Events section instead.
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/home/widget/home_nav_dock.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/glass_surface.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription() : super(SubscriptionState(isSubscribed: false));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _unread = StateProvider<int>((ref) => 0);

List<Override> _overrides() => [
  botvinnikTabAvailableProvider.overrideWithValue(true),
  currentUserProvider.overrideWithValue(null),
  profileAvatarUrlProvider.overrideWithValue(null),
  inboxHasUnreadProvider.overrideWith((ref) => ref.watch(_unread) > 0),
  inboxUnreadCountProvider.overrideWith((ref) => ref.watch(_unread)),
  subscriptionProvider.overrideWith((ref) => _Subscription()),
];

/// A root in the home shell: the bar every root wears over a long list,
/// the dock under it, a search button riding the dock.
class _Shell extends StatefulWidget {
  const _Shell({required this.onController});

  final ValueChanged<ScrollChromeController> onController;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with SingleTickerProviderStateMixin {
  late final ScrollChromeController chrome = ScrollChromeController(
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    widget.onController(chrome);
  }

  @override
  void dispose() {
    chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metrics = HomeNavMetrics.of(context, count: 5);
    return Scaffold(
      extendBody: true,
      floatingActionButton: SlidingFabs(
        controller: chrome,
        ride: metrics.ride,
        child: InkFabStack(children: [SearchInkFab(onTap: () {})]),
      ),
      floatingActionButtonLocation: RidingFabLocation(metrics.ride),
      bottomNavigationBar: HomeNavDock(chrome: chrome),
      body: HomeNavScope(
        metrics: metrics,
        child: ScrollChromeRegion(
          controller: chrome,
          child: Column(
            children: [
              const HomeTopBarFrame(child: Center(child: Text('Today'))),
              Expanded(
                child: Builder(
                  builder: (context) => ListView.builder(
                    key: const ValueKey('list'),
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.paddingOf(context).bottom,
                    ),
                    itemCount: 80,
                    itemExtent: 64,
                    itemBuilder: (context, i) =>
                        Text('row $i', key: ValueKey('row-$i')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<ScrollChromeController> _pump(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(393, 852) * 3
    ..devicePixelRatio = 3
    ..padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3)
    ..viewPadding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  late ScrollChromeController chrome;
  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(),
      child: MaterialApp(
        theme: AppTheme.darkTheme.copyWith(platform: TargetPlatform.iOS),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return _Shell(onController: (c) => chrome = c);
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return chrome;
}

final Finder _capsule = find.byKey(const ValueKey('home-nav-capsule'));
final Finder _dock = find.byKey(const ValueKey('home-nav-dock'));
final Finder _fab = find.byType(SearchInkFab);

double _glass(WidgetTester tester) => tester
    .widget<GlassFade>(
      find.ancestor(of: _capsule, matching: find.byType(GlassFade)),
    )
    .opacity
    .value;

bool _hitsDock(WidgetTester tester, Offset point) {
  final box = tester.renderObject(_dock);
  return tester
      .hitTestOnBinding(point)
      .path
      .any((entry) => entry.target == box);
}

void main() {
  testWidgets('Botvinnik shows the unread count until Inbox confirms a read', (
    tester,
  ) async {
    await _pump(tester);
    final slot = find.byKey(bottomNavBarItemKey(BottomNavBarItem.botvinnik));
    final badge = find.descendant(
      of: slot,
      matching: find.byKey(const ValueKey('botvinnik-dock-unread-badge')),
    );
    final container = ProviderScope.containerOf(tester.element(slot));
    expect(badge, findsNothing);
    container.read(_unread.notifier).state = 2;
    await tester.pump();
    expect(badge, findsOneWidget);
    expect(
      find.descendant(of: badge, matching: find.text('2')),
      findsOneWidget,
    );
    // The dock is Home, Events, Botvinnik, Feed, Profile: the count sits
    // on Botvinnik's slot, clear of Events on its left and Feed on its right.
    expect(
      find.byKey(const ValueKey('botvinnik-dock-unread-badge')),
      findsOneWidget,
    );
    Rect slotOf(BottomNavBarItem item) =>
        tester.getRect(find.byKey(bottomNavBarItemKey(item)));
    final events = slotOf(BottomNavBarItem.tournaments);
    final botvinnik = slotOf(BottomNavBarItem.botvinnik);
    final feed = slotOf(BottomNavBarItem.feed);
    expect(events.right, lessThanOrEqualTo(botvinnik.left + 0.5));
    expect(botvinnik.right, lessThanOrEqualTo(feed.left + 0.5));
    final badgeRect = tester.getRect(badge);
    expect(badgeRect.left, greaterThanOrEqualTo(botvinnik.left));
    expect(badgeRect.right, lessThanOrEqualTo(botvinnik.right));
    final badgePosition = tester.getCenter(badge);
    await tester.tapAt(badgePosition);
    await tester.pump();
    expect(
      container.read(selectedBottomNavBarItemProvider),
      BottomNavBarItem.botvinnik,
    );
    expect(badge, findsOneWidget);
    container.read(_unread.notifier).state = 0;
    await tester.pump();
    expect(badge, findsNothing);
  });

  testWidgets('reading down sends the dock away whole and the buttons down '
      'to the strip; heading back up brings both back', (tester) async {
    final semantics = tester.ensureSemantics();
    final chrome = await _pump(tester);
    final shown = tester.getRect(_capsule);
    final fab = tester.getRect(_fab);
    final mark = tester
        .getRect(find.byKey(bottomNavBarItemKey(BottomNavBarItem.feed)))
        .center;
    final list = tester.getRect(find.byKey(const ValueKey('list')));
    // The button stands 16 over the capsule.
    expect(fab.bottom, closeTo(shown.top - 16, 0.5));
    expect(_hitsDock(tester, mark), isTrue);

    // Reading down: a slow drag up the screen.
    final gesture = await tester.startGesture(const Offset(200, 500));
    for (var i = 0; i < 30; i++) {
      await gesture.moveBy(
        const Offset(0, -6),
        timeStamp: Duration(milliseconds: 16 * (i + 1)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up(timeStamp: const Duration(milliseconds: 16 * 31));
    await tester.pumpAndSettle();
    expect(chrome.value, 0);

    // Gone whole: past the screen's edge, its glass faded out.
    expect(tester.getRect(_capsule).top, greaterThan(852));
    expect(_glass(tester), 0);
    expect(_hitsDock(tester, mark), isFalse);
    expect(find.semantics.byLabel('Feed'), findsNothing);
    // The button came down to where a page with no dock stands it: 16 over
    // the home indicator's strip, the same size, still there to tap.
    final away = tester.getRect(_fab);
    expect(away.size, fab.size);
    expect(away.bottom, closeTo(852 - 34 - 16, 0.5));
    // The dock never laid the page out again: the list ends where it did.
    expect(
      tester.getRect(find.byKey(const ValueKey('list'))).bottom,
      list.bottom,
    );

    // Heading back up.
    final back = await tester.startGesture(const Offset(200, 300));
    for (var i = 0; i < 6; i++) {
      await back.moveBy(
        const Offset(0, 8),
        timeStamp: Duration(milliseconds: 16 * (i + 1)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await back.up(timeStamp: const Duration(milliseconds: 16 * 7));
    await tester.pumpAndSettle();
    expect(chrome.value, 1);
    expect(tester.getRect(_capsule), shown);
    expect(_glass(tester), 1);
    expect(tester.getRect(_fab), fab);
    expect(_hitsDock(tester, mark), isTrue);
    expect(find.semantics.byLabel('Feed'), findsOne);
    semantics.dispose();
  });

  testWidgets('the dock fades exactly as far as it has slid, the whole way', (
    tester,
  ) async {
    final chrome = await _pump(tester);
    final shown = tester.getRect(_capsule);
    final m = HomeNavMetrics.of(tester.element(_dock), count: 5);
    chrome.hide();
    var frames = 0;
    while (chrome.value > 0 && frames++ < 60) {
      await tester.pump(const Duration(milliseconds: 8));
      final f = chrome.value;
      expect(_glass(tester), closeTo(f, 1e-9));
      expect(
        tester.getRect(_capsule).top,
        closeTo(shown.top + (1 - f) * m.slide, 0.01),
      );
    }
    expect(chrome.value, 0);
  });

  group('a second Events', () {
    Future<ProviderContainer> pumpShell(
      WidgetTester tester, {
      required bool register,
    }) async {
      late ProviderContainer container;
      ModalRoute<Object?>? shell;
      addTearDown(() => unregisterHomeShellRoute(shell));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [botvinnikTabAvailableProvider.overrideWithValue(true)],
          child: MaterialApp(
            home: Consumer(
              builder: (context, ref, _) {
                container = ProviderScope.containerOf(context);
                // The shell keeps the section alive while it is mounted.
                ref.watch(selectedBottomNavBarItemProvider);
                if (register) {
                  shell = ModalRoute.of(context);
                  registerHomeShellRoute(shell);
                }
                return Scaffold(
                  body: Center(
                    child: TextButton(
                      key: const ValueKey('push'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (context) => Scaffold(
                            body: Center(
                              child: TextButton(
                                key: const ValueKey('open'),
                                onPressed: () {
                                  if (!openHomeSection(
                                    context,
                                    BottomNavBarItem.tournaments,
                                  )) {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => const Scaffold(
                                          body: Text('pushed copy'),
                                        ),
                                      ),
                                    );
                                  }
                                },
                                child: const Text('Events'),
                              ),
                            ),
                          ),
                        ),
                      ),
                      child: const Text('open search'),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      return container;
    }

    testWidgets('from a page over the shell, the page closes onto the '
        'dock\'s Events section', (tester) async {
      final container = await pumpShell(tester, register: true);
      expect(
        container.read(selectedBottomNavBarItemProvider),
        BottomNavBarItem.forYou,
      );
      await tester.tap(find.byKey(const ValueKey('push')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      // Back on the shell, on Events; nothing was pushed.
      expect(find.byKey(const ValueKey('open')), findsNothing);
      expect(find.byKey(const ValueKey('push')), findsOneWidget);
      expect(find.text('pushed copy'), findsNothing);
      expect(
        container.read(selectedBottomNavBarItemProvider),
        BottomNavBarItem.tournaments,
      );
    });

    testWidgets('with no shell under it, the page pushes its own copy', (
      tester,
    ) async {
      final container = await pumpShell(tester, register: false);
      await tester.tap(find.byKey(const ValueKey('push')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      expect(find.text('pushed copy'), findsOneWidget);
      expect(
        container.read(selectedBottomNavBarItemProvider),
        BottomNavBarItem.forYou,
      );
    });
  });
}
