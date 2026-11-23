// Renders of the dock leaving as a root is read down (shown, part-way out,
// gone) in both themes, driven by a real scroll, and the Events root's top
// against Home's: the two bars and their first content side by side on one
// guide line. PNGs are written only with --dart-define=NAV_DIR=/abs/dir;
// without it every scene still pumps and must throw nothing.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/for_you/for_you_screen.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/providers/home_live_first_provider.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/home/widget/home_nav_dock.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:chessever2/widgets/segmented_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _outDir = String.fromEnvironment('NAV_DIR');
const _capture = ValueKey('dock_capture');

class _Subscription extends SubscriptionNotifier {
  _Subscription() : super() {
    state = SubscriptionState(isSubscribed: false, isLoading: false);
  }

  @override
  set state(SubscriptionState value) =>
      super.state = value.copyWith(isSubscribed: false, isLoading: false);
}

class _NoFavoriteEvents extends FavoriteEventsNotifier {
  @override
  Future<List<FavoriteEvent>> build() async => const <FavoriteEvent>[];
}

class _MemoryRecentSearches implements RecentSearchStorage {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}
}

/// Today's cards, in the size and tone of the event cards, under the bar
/// every root wears: something for the dock's glass to show through.
class _Cards extends StatelessWidget {
  const _Cards();

  static const _titles = [
    'Tata Steel Masters',
    'Grand Chess Tour: Zagreb',
    'Norway Chess',
    'Sinquefield Cup',
    'Qatar Masters',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        16,
        HomeTopBarMetrics.contentGap,
        16,
        MediaQuery.paddingOf(context).bottom + 24,
      ),
      itemCount: 24,
      itemBuilder: (context, i) => Padding(
        key: ValueKey('card-$i'),
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          height: 132,
          decoration: BoxDecoration(
            color: colors.popup,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(16),
          alignment: Alignment.topLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _titles[i % _titles.length],
                style: AppTypography.textSmMedium.copyWith(
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Round ${i % 9 + 1}  ·  4 boards live',
                style: AppTypography.textXsRegular.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Home's root as the shell holds it: the bar (its page tabs), Today's
/// cards, Today's buttons riding the dock, the dock.
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
        child: const ForYouTodayFabs(),
      ),
      floatingActionButtonLocation: RidingFabLocation(metrics.ride),
      bottomNavigationBar: HomeNavDock(chrome: chrome),
      body: HomeNavScope(
        metrics: metrics,
        child: ScrollChromeRegion(
          controller: chrome,
          child: const ForYouScreen(pageBuilder: _todayPage),
        ),
      ),
    );
  }
}

Widget _todayPage(BuildContext context, ForYouTab tab, ScrollController c) =>
    PrimaryScrollController(controller: c, child: const _Cards());

/// Stands in for an Events list, which reads the network.
Widget _eventsPage(
  BuildContext context,
  GroupEventCategory category,
  ScrollController c,
) => ListView(
  controller: c,
  padding: EdgeInsets.zero,
  children: [SizedBox(height: 120, child: Text('events:${category.name}'))],
);

List<Override> _overrides(BottomNavBarItem section) => [
  botvinnikTabAvailableProvider.overrideWithValue(true),
  currentUserProvider.overrideWithValue(
    AppUser(id: 'u1', displayName: 'Test', createdAt: DateTime(2026)),
  ),
  profileAvatarUrlProvider.overrideWithValue(null),
  inboxHasUnreadProvider.overrideWithValue(false),
  subscriptionProvider.overrideWith((ref) => _Subscription()),
  selectedBottomNavBarItemProvider.overrideWith((ref) => section),
  todayLiveEventCountProvider.overrideWith((ref) => 3),
  eventsLiveEventCountProvider.overrideWith((ref) => 3),
  favoriteEventsProvider.overrideWith(_NoFavoriteEvents.new),
  recentSearchStorageProvider.overrideWithValue(_MemoryRecentSearches()),
];

Future<void> _pump(
  WidgetTester tester, {
  required bool light,
  required BottomNavBarItem section,
  required Widget home,
}) async {
  tester.view
    ..physicalSize = const Size(393, 852) * 3
    ..devicePixelRatio = 3
    ..padding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3)
    ..viewPadding = const FakeViewPadding(top: 59 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _capture,
      child: ProviderScope(
        overrides: _overrides(section),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: (light ? AppTheme.lightTheme : AppTheme.darkTheme).copyWith(
            platform: TargetPlatform.iOS,
          ),
          home: Builder(
            builder: (context) {
              ResponsiveHelper.init(context);
              return home;
            },
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<ui.Image> _image(WidgetTester tester) async {
  final image = await tester.runAsync(() {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_capture),
    );
    return boundary.toImage(pixelRatio: 3);
  });
  return image!;
}

Future<void> _write(WidgetTester tester, ui.Image image, String name) async {
  await tester.runAsync(() async {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(_outDir).create(recursive: true);
    await File('$_outDir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
  });
}

Future<void> _shot(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  if (_outDir.isEmpty) return;
  final image = await _image(tester);
  await _write(tester, image, name);
  image.dispose();
}

void _scene(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    debugDisableShadows = false;
    try {
      await body(tester);
    } finally {
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    Future<void> family(String name, List<String> files) async {
      final loader = FontLoader(name);
      for (final file in files) {
        loader.addFont(
          Future.value(ByteData.sublistView(File(file).readAsBytesSync())),
        );
      }
      await loader.load();
    }

    final inter = [
      for (final weight in ['Regular', 'Medium', 'Bold'])
        'assets/fonts/Inter-$weight.otf',
    ];
    await family('InterDisplay', inter);
    await family('Inter', inter);
    await family('Roboto', inter);
    final flutterRoot =
        Platform.environment['FLUTTER_ROOT'] ??
        File(Platform.resolvedExecutable).parent.parent.parent.parent.path;
    final icons = File(
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) await family('MaterialIcons', [icons.path]);
  });

  for (final light in [false, true]) {
    final theme = light ? 'light' : 'dark';

    _scene('the dock leaving as Today is read down, $theme', (tester) async {
      late ScrollChromeController chrome;
      await _pump(
        tester,
        light: light,
        section: BottomNavBarItem.forYou,
        home: _Shell(onController: (c) => chrome = c),
      );
      expect(chrome.value, 1);
      await _shot(tester, 'dock_shown_$theme');

      // Reading down, slowly enough to catch the dock part-way out.
      final gesture = await tester.startGesture(const Offset(200, 600));
      var t = Duration.zero;
      var caught = false;
      for (var i = 0; i < 60; i++) {
        t += const Duration(milliseconds: 16);
        await gesture.moveBy(const Offset(0, -3), timeStamp: t);
        await tester.pump(const Duration(milliseconds: 16));
        if (!caught && chrome.value > 0.35 && chrome.value < 0.65) {
          caught = true;
          await _shot(tester, 'dock_mid_hide_$theme');
        }
      }
      await gesture.up(timeStamp: t + const Duration(milliseconds: 16));
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(caught, isTrue);
      expect(chrome.value, 0);
      await _shot(tester, 'dock_hidden_$theme');
    });

    _scene('the Events root\'s top against Home\'s, $theme', (tester) async {
      // Where every root's first content starts: under the bar, by the
      // roots' one lead-in.
      double firstLine(WidgetTester tester) =>
          HomeTopBarMetrics.headerExtent(
            tester.element(find.byType(Scaffold).first),
          ) +
          HomeTopBarMetrics.contentGap;

      await _pump(
        tester,
        light: light,
        section: BottomNavBarItem.forYou,
        home: _Shell(onController: (_) {}),
      );
      final homeLine = firstLine(tester);
      final homeFirst = tester
          .getTopLeft(find.byKey(const ValueKey('card-0')))
          .dy;
      final home = _outDir.isEmpty ? null : await _image(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));

      late ScrollChromeController chrome;
      await _pump(
        tester,
        light: light,
        section: BottomNavBarItem.tournaments,
        home: Builder(
          builder: (context) {
            final metrics = HomeNavMetrics.of(context, count: 5);
            return _ChromeHost(
              onController: (c) => chrome = c,
              builder: (chrome) => Scaffold(
                extendBody: true,
                bottomNavigationBar: HomeNavDock(chrome: chrome),
                body: HomeNavScope(
                  metrics: metrics,
                  child: ScrollChromeRegion(
                    controller: chrome,
                    child: const GroupEventScreen(
                      root: true,
                      pageBuilder: _eventsPage,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
      expect(chrome.value, 1);
      final eventsLine = firstLine(tester);
      // Its first content: the segments, on the line Home's first card is.
      final eventsFirst = tester.getTopLeft(find.byType(SegmentedSwitcher)).dy;
      expect(eventsLine, closeTo(homeLine, 0.5));
      expect(eventsFirst, closeTo(homeFirst, 0.5));
      expect(eventsFirst, closeTo(eventsLine, 0.5));
      expect(tester.takeException(), isNull);
      if (home == null) return;
      final events = await _image(tester);

      // Side by side, the top 360pt of each, one guide line across both at
      // the roots' first-content line.
      final composite = await tester.runAsync(() async {
        const scale = 3.0;
        const top = 360.0 * scale;
        const gap = 24.0 * scale;
        final width = home.width.toDouble();
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final ground = light
            ? const Color(0xFF8A8A8A)
            : const Color(0xFF3A3A3A);
        canvas.drawRect(
          Rect.fromLTWH(0, 0, width * 2 + gap, top),
          Paint()..color = ground,
        );
        final src = Rect.fromLTWH(0, 0, width, top);
        canvas.drawImageRect(home, src, src, Paint());
        canvas.drawImageRect(
          events,
          src,
          src.shift(Offset(width + gap, 0)),
          Paint(),
        );
        final y = homeLine * scale;
        canvas.drawLine(
          Offset(0, y),
          Offset(width * 2 + gap, y),
          Paint()
            ..color = const Color(0xFFE5484D)
            ..strokeWidth = 2,
        );
        final picture = recorder.endRecording();
        return picture.toImage((width * 2 + gap).round(), top.round());
      });
      await _write(tester, composite!, 'roots_top_alignment_$theme');
      await _write(tester, events, 'events_root_$theme');
      await _write(tester, home, 'home_root_$theme');
      composite.dispose();
      events.dispose();
      home.dispose();
    });
  }
}

/// Holds a [ScrollChromeController] for [builder].
class _ChromeHost extends StatefulWidget {
  const _ChromeHost({required this.onController, required this.builder});

  final ValueChanged<ScrollChromeController> onController;
  final Widget Function(ScrollChromeController chrome) builder;

  @override
  State<_ChromeHost> createState() => _ChromeHostState();
}

class _ChromeHostState extends State<_ChromeHost>
    with SingleTickerProviderStateMixin {
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
  Widget build(BuildContext context) => widget.builder(chrome);
}
