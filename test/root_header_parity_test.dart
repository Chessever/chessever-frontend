// The five bottom-bar roots are one composition: switching tabs must never
// make the page jump or the bar change colour. Every root wears the same bar
// (HomeTopBarFrame): the same top inset, the same band height, the same
// gutter, its title, tabs or field on the same centre line, the same ground
// under it, its page starting at the same y and, on every root that is a
// page to read down, its first content on the same line under that
// (HomeTopBarMetrics.contentGap). This pumps Home, Feed, Botvinnik and
// Profile as the home shell holds them (in a ScrollChromeRegion over a
// bottom bar) and measures each, on three phones, light and dark: the
// geometry from the layout, the colours from the pixels actually drawn.
// Search, which lives in another file, is held to the same numbers in
// root_header_search_parity_test.dart.
//
// Feed's first content is its own: a post is one framed page composed by
// FeedLayout, not a list, so only its page start is held to the line.
import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:chessever2/chat/botvinnik_icon.dart';
import 'package:chessever2/chat/botvinnik_inbox_section.dart';
import 'package:chessever2/chat/chat_api.dart';
import 'package:chessever2/chat/chat_screen.dart';
import 'package:chessever2/providers/app_version_provider.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/feed/audio/feed_sfx.dart';
import 'package:chessever2/screens/feed/feed_screen.dart';
import 'package:chessever2/screens/feed/models/feed_entry.dart';
import 'package:chessever2/screens/feed/models/feed_models.dart';
import 'package:chessever2/screens/feed/news/feed_news.dart';
import 'package:chessever2/screens/feed/providers/feed_entries_provider.dart';
import 'package:chessever2/screens/feed/providers/feed_provider.dart';
import 'package:chessever2/screens/feed/puzzles/feed_puzzle.dart';
import 'package:chessever2/screens/feed/widgets/feed_sfx_provider.dart';
import 'package:chessever2/screens/feed/widgets/feed_states.dart';
import 'package:chessever2/screens/for_you/for_you_screen.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/screens/my_profile/my_profile_screen.dart';
import 'package:chessever2/screens/my_profile/profile_hub_screen.dart';
import 'package:chessever2/services/attention_policy.dart';
import 'package:chessever2/services/discovery_dots/discovery_dots_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'inbox_fakes.dart';

/// A phone the roots are measured on: its window and its safe-area insets.
typedef _Phone = ({String name, Size size, double statusBar, double home});

const _Phone _iPhone = (
  name: 'iPhone 15',
  size: Size(393, 852),
  statusBar: 47,
  home: 34,
);

const List<_Phone> _phones = [
  (name: 'iPhone SE', size: Size(375, 667), statusBar: 20, home: 0),
  _iPhone,
  (name: 'iPhone Pro Max', size: Size(430, 932), statusBar: 59, home: 34),
];

/// The app as captured for its pixels.
const ValueKey<String> _shot = ValueKey('shot');

/// What one root's bar and page measure.
class _Measure {
  _Measure({
    required this.name,
    required this.frame,
    required this.centre,
    required this.pageTop,
    required this.ground,
    this.firstContent,
  });

  final String name;

  /// The bar's frame: from the top of the screen to where the page starts.
  final Rect frame;

  /// The centre line of the root's title, selected tab or field.
  final double centre;

  /// Where the root's page starts.
  final double pageTop;

  /// The colours drawn under the bar, sampled on its start gutter where no
  /// control stands: in the status bar's strip, at the top of the band and
  /// at its foot.
  final List<Color> ground;

  /// Where the root's first content starts, for a root that owns it.
  final double? firstContent;

  @override
  String toString() =>
      '$name: frame ${frame.top}..${frame.bottom}, centre $centre, '
      'page $pageTop, first content $firstContent, ground $ground';
}

/// A root as the home shell holds it: a region over its page, a bottom bar
/// that steps away with the same chrome. Feed's bar slides over its page.
class _Shell extends StatefulWidget {
  const _Shell({required this.child, this.feed = false, this.still = false});

  final Widget child;
  final bool feed;

  /// Botvinnik: a conversation whose bars stay.
  final bool still;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with SingleTickerProviderStateMixin {
  late final ScrollChromeController chrome = ScrollChromeController(
    vsync: this,
  );

  @override
  void dispose() {
    chrome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBody: widget.feed,
      bottomNavigationBar: CollapsingChrome(
        controller: chrome,
        edge: VerticalDirection.down,
        overlay: widget.feed,
        child: SizedBox(
          height: 56 + MediaQuery.viewPaddingOf(context).bottom,
          width: double.infinity,
        ),
      ),
      body: ScrollChromeRegion(
        controller: chrome,
        enabled: !widget.still,
        paged: widget.feed,
        child: widget.child,
      ),
    );
  }
}

Future<void> _pumpRoot(
  WidgetTester tester, {
  required Widget root,
  required List<Override> overrides,
  required bool light,
  _Phone phone = _iPhone,
  bool feed = false,
  bool still = false,
}) async {
  tester.view
    ..physicalSize = phone.size * 3
    ..devicePixelRatio = 3
    ..padding = FakeViewPadding(
      top: phone.statusBar * 3,
      bottom: phone.home * 3,
    )
    ..viewPadding = FakeViewPadding(
      top: phone.statusBar * 3,
      bottom: phone.home * 3,
    );
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
        themeAnimationDuration: Duration.zero,
        // The empty chat's mark and a lit dot loop; held still, the page
        // can settle. The bars stay shown, which is what is measured.
        builder: (context, child) => RepaintBoundary(
          key: _shot,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return _Shell(feed: feed, still: still, child: root);
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _tearDown(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

/// The app's pixels at one logical pixel each, and their row length.
Future<({ByteData bytes, int width})> _capture(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_shot),
  );
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      return await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    } finally {
      image.dispose();
    }
  });
  return (bytes: bytes!, width: boundary.size.width.round());
}

Color _pixel(({ByteData bytes, int width}) shot, double x, double y) {
  final i = (y.floor() * shot.width + x.floor()) * 4;
  return Color.fromARGB(
    shot.bytes.getUint8(i + 3),
    shot.bytes.getUint8(i),
    shot.bytes.getUint8(i + 1),
    shot.bytes.getUint8(i + 2),
  );
}

Future<_Measure> _measure(
  WidgetTester tester,
  String name, {
  required Finder label,
  required Finder page,
  Finder? firstContent,
}) async {
  final frame = tester.getRect(find.byType(HomeTopBarFrame).first);
  final status = MediaQuery.viewPaddingOf(
    tester.element(find.byType(HomeTopBarFrame).first),
  ).top;
  final shot = await _capture(tester);
  // On the start gutter, clear of every control: the first two points.
  const x = 2.0;
  return _Measure(
    name: name,
    frame: frame,
    centre: tester.getCenter(label.first).dy,
    pageTop: tester.getTopLeft(page.first).dy,
    ground: [
      if (status >= 2) _pixel(shot, x, 1),
      _pixel(shot, x, status + 1),
      _pixel(shot, x, frame.bottom - 1),
    ],
    firstContent: firstContent == null
        ? null
        : tester.getTopLeft(firstContent.first).dy,
  );
}

// ------------------------------------------------------------------ roots

/// Stands in for My Space, Today and Discovery, which need the network: a
/// list opening on the lead-in those pages open their own scroll on
/// (`16.sp`, [HomeTopBarMetrics.contentGap]), so this measures what Home's
/// shell adds above it, which must be nothing.
Widget _fakePage(BuildContext context, ForYouTab tab, ScrollController c) {
  return ListView(
    controller: c,
    padding: EdgeInsets.only(top: HomeTopBarMetrics.contentGap),
    children: [
      SizedBox(
        key: ValueKey('home-first:${tab.name}'),
        height: 120,
        child: Text('page:${tab.name}'),
      ),
    ],
  );
}

/// Profile's first row: the reader.
final Finder _profileFirst = find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_ReaderHeader',
);

class _MemoryRecentSearches implements RecentSearchStorage {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}
}

List<Override> _homeOverrides() => [
  recentSearchStorageProvider.overrideWithValue(_MemoryRecentSearches()),
  selectedBottomNavBarItemProvider.overrideWith(
    (ref) => BottomNavBarItem.forYou,
  ),
];

class _LoadingFeed extends FeedNotifier {
  /// Never resolves, and leaves no timer behind.
  @override
  Future<List<FeedItem>> build() => Completer<List<FeedItem>>().future;

  @override
  Future<void> loadMore() async {}

  @override
  void onVisible(int index) {}
}

class _NoEntries extends FeedEntriesNotifier {
  @override
  List<FeedEntry> build() => const [];

  @override
  void markSeen(int index) {}
}

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
}

class _SilentSfx implements FeedSfx {
  @override
  bool muted = true;

  @override
  bool boardSoundEnabled = false;

  @override
  Future<void> warmUp() async {}

  @override
  void playGameEnd(FeedItem item) {}

  @override
  void playSwipe() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

List<Override> _feedOverrides() => [
  feedProvider.overrideWith(_LoadingFeed.new),
  feedEntriesProvider.overrideWith(_NoEntries.new),
  feedPuzzlesProvider.overrideWith((ref) async => const <FeedPuzzle>[]),
  feedNewsProvider.overrideWith((ref) async => const <FeedNews>[]),
  feedSfxProvider.overrideWithValue(_SilentSfx()),
  boardSettingsProviderNew.overrideWith(_BoardSettings.new),
];

class _Guest extends AuthController {
  @override
  Future<AppAuthState> build() async => AppAuthState.authenticated(
    AppUser(id: inboxOwnerA, createdAt: DateTime.utc(2026), isAnonymous: true),
  );
}

List<Override> _chatOverrides() => [
  authStateProvider.overrideWith(_Guest.new),
  attentionClockProvider.overrideWithValue(inboxFixtureNow),
  inboxSourceProvider.overrideWithValue(FakeInboxSource()..rows.clear()),
  inboxCacheProvider.overrideWithValue(FakeInboxCache()),
];

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription() : super(SubscriptionState(isSubscribed: false));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DotsSource implements DiscoveryDotsSource {
  @override
  Future<String> initialize() async => jsonEncode({'dots': const []});

  @override
  Future<String> fetch() async => jsonEncode({'dots': const []});

  @override
  Stream<String> get updates => const Stream.empty();
}

class _MemoryStore implements DiscoveryDotsSeenStore {
  Map<String, int> seen = {};

  @override
  Map<String, int> read() => seen;

  @override
  Future<void> write(Map<String, int> value) async => seen = value;
}

List<Override> _profileOverrides() => [
  currentUserProvider.overrideWith(
    (ref) => AppUser(
      id: inboxOwnerA,
      createdAt: DateTime.utc(2026),
      isAnonymous: true,
    ),
  ),
  subscriptionProvider.overrideWith((ref) => _Subscription()),
  appVersionProvider.overrideWith((ref) async => '38.18.0'),
  attentionClockProvider.overrideWithValue(inboxFixtureNow),
  inboxSourceProvider.overrideWithValue(FakeInboxSource()),
  inboxCacheProvider.overrideWithValue(FakeInboxCache()),
  botvinnikTabAvailableProvider.overrideWithValue(true),
  myProfileIdentityProvider.overrideWith(
    (ref) => (displayName: 'Fixture Reader', email: null, isGuest: true),
  ),
  discoveryDotsSourceProvider.overrideWithValue(_DotsSource()),
  discoveryDotsSeenStoreProvider.overrideWithValue(_MemoryStore()),
  discoveryDotsDeliveryStoreProvider.overrideWithValue(_MemoryStore()),
];

Future<List<_Measure>> _measureRoots(
  WidgetTester tester, {
  required bool light,
  required _Phone phone,
}) async {
  final out = <_Measure>[];

  await _pumpRoot(
    tester,
    root: const ForYouScreen(pageBuilder: _fakePage),
    overrides: _homeOverrides(),
    light: light,
    phone: phone,
  );
  out.add(
    await _measure(
      tester,
      'Home',
      label: find.text('Today'),
      page: find.byType(PageView),
      firstContent: find.byKey(const ValueKey('home-first:today')),
    ),
  );
  await _tearDown(tester);

  await _pumpRoot(
    tester,
    root: const FeedScreen(embedded: true),
    overrides: _feedOverrides(),
    light: light,
    phone: phone,
    feed: true,
  );
  out.add(
    await _measure(
      tester,
      'Feed',
      label: find.text('Feed'),
      page: find.byType(FeedSkeleton),
    ),
  );
  await _tearDown(tester);

  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  Supabase.instance.client.auth.stopAutoRefresh();
  await _pumpRoot(
    tester,
    root: const ChatScreen(
      embedded: true,
      screenContext: ChatScreenContext(screen: 'home'),
    ),
    overrides: _chatOverrides(),
    light: light,
    phone: phone,
    still: true,
  );
  out.add(
    await _measure(
      tester,
      'Botvinnik',
      label: find.text('Botvinnik'),
      page: find.byType(BotvinnikInboxTimeline),
      // A new conversation: its mark is the first thing on the page.
      firstContent: find.byType(BotvinnikAnimatedIcon),
    ),
  );
  await _tearDown(tester);

  await _pumpRoot(
    tester,
    root: const ProfileHubScreen(),
    overrides: _profileOverrides(),
    light: light,
    phone: phone,
  );
  out.add(
    await _measure(
      tester,
      'Profile',
      label: find.text('Profile'),
      page: find.byType(Scrollable),
      firstContent: _profileFirst,
    ),
  );
  await _tearDown(tester);
  return out;
}

/// The numbers every root must hit on [phone], read off the frame's own
/// metrics in the shell the roots are pumped in.
typedef _Want = ({
  double header,
  double centre,
  double firstContent,
  Color ground,
});

Future<_Want> _wanted(
  WidgetTester tester, {
  required bool light,
  required _Phone phone,
}) async {
  const probe = ValueKey('probe');
  await _pumpRoot(
    tester,
    root: const SizedBox.expand(key: probe),
    overrides: const [],
    light: light,
    phone: phone,
  );
  final context = tester.element(find.byKey(probe));
  final header = HomeTopBarMetrics.headerExtent(context);
  final want = (
    header: header,
    centre:
        phone.statusBar +
        HomeTopBarMetrics.topGap +
        HomeTopBarMetrics.rowExtent(context) / 2,
    firstContent: header + HomeTopBarMetrics.contentGap,
    ground: context.colors.background,
  );
  await _tearDown(tester);
  return want;
}

/// Whether two drawn colours are the same, to a step of rounding.
bool _sameColour(Color a, Color b) {
  int channel(double v) => (v * 255).round();
  return (channel(a.r) - channel(b.r)).abs() <= 2 &&
      (channel(a.g) - channel(b.g)).abs() <= 2 &&
      (channel(a.b) - channel(b.b)).abs() <= 2 &&
      (channel(a.a) - channel(b.a)).abs() <= 2;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Supabase listens for deep links as it starts; with no plugin under the
    // test that listen fails, at whatever moment it lands, inside a test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.app_links/events'),
          (_) async => null,
        );
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await SharedPreferencesService.instance.initialize();
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      publishableKey: 'LOCAL-FIXTURE-ANON-KEY',
      authOptions: const FlutterAuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (_) async => throw StateError('Unexpected LOCAL FIXTURE request'),
      ),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());

  for (final phone in _phones) {
    for (final light in [false, true]) {
      testWidgets('every root wears one bar on the ${phone.name}: inset, '
          'height, centre line, ground, page start and first content '
          '(${light ? 'light' : 'dark'})', (tester) async {
        final roots = await _measureRoots(tester, light: light, phone: phone);
        expect(tester.takeException(), isNull);
        final want = await _wanted(tester, light: light, phone: phone);

        expect(roots.map((r) => r.name), [
          'Home',
          'Feed',
          'Botvinnik',
          'Profile',
        ]);
        // Every root that is a page to read down states where it starts.
        expect(
          [
            for (final root in roots)
              if (root.firstContent != null) root.name,
          ],
          ['Home', 'Botvinnik', 'Profile'],
        );

        for (final root in roots) {
          expect(root.frame.top, closeTo(0, 0.5), reason: '$root');
          expect(root.frame.height, closeTo(want.header, 0.5), reason: '$root');
          expect(root.centre, closeTo(want.centre, 0.5), reason: '$root');
          expect(root.pageTop, closeTo(want.header, 0.5), reason: '$root');
          final first = root.firstContent;
          if (first != null) {
            expect(first, closeTo(want.firstContent, 0.5), reason: '$root');
          }
          // The status bar's strip, the band's top and its foot: one ground,
          // the page's own, on every root.
          expect(root.ground, hasLength(3), reason: '$root');
          for (final colour in root.ground) {
            expect(
              _sameColour(colour, want.ground),
              isTrue,
              reason: '$root: want ${want.ground}',
            );
          }
        }
        // And so with each other.
        final first = roots.first;
        for (final root in roots.skip(1)) {
          final reason = '$root against $first';
          expect(root.frame.top, closeTo(first.frame.top, 0.5), reason: reason);
          expect(
            root.frame.height,
            closeTo(first.frame.height, 0.5),
            reason: reason,
          );
          expect(root.centre, closeTo(first.centre, 0.5), reason: reason);
          expect(root.pageTop, closeTo(first.pageTop, 0.5), reason: reason);
          if (root.firstContent case final double y) {
            expect(y, closeTo(first.firstContent!, 0.5), reason: reason);
          }
          for (var i = 0; i < root.ground.length; i++) {
            expect(
              _sameColour(root.ground[i], first.ground[i]),
              isTrue,
              reason: reason,
            );
          }
        }
      });
    }
  }

  testWidgets('the side controls sit on the bar\'s one gutter', (tester) async {
    const width = 393.0;
    await _pumpRoot(
      tester,
      root: const FeedScreen(embedded: true),
      overrides: _feedOverrides(),
      light: false,
      feed: true,
    );
    final gutter = HomeTopBarMetrics.horizontalPadding;
    expect(
      tester.getRect(find.byKey(const ValueKey('feed_sound_toggle'))).right,
      closeTo(width - gutter, 0.5),
    );
    // The title is centred on the screen, not between the controls.
    expect(tester.getCenter(find.text('Feed')).dx, closeTo(width / 2, 0.5));
    await _tearDown(tester);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    Supabase.instance.client.auth.stopAutoRefresh();
    await _pumpRoot(
      tester,
      root: const ChatScreen(
        embedded: true,
        screenContext: ChatScreenContext(screen: 'home'),
      ),
      overrides: _chatOverrides(),
      light: false,
      still: true,
    );
    expect(tester.getRect(find.byTooltip('Chats')).left, closeTo(gutter, 0.5));
    expect(
      tester.getRect(find.byTooltip('New chat')).right,
      closeTo(width - gutter, 0.5),
    );
    expect(
      tester.getCenter(find.text('Botvinnik')).dx,
      closeTo(width / 2, 0.5),
    );
    await _tearDown(tester);

    await _pumpRoot(
      tester,
      root: const ProfileHubScreen(),
      overrides: _profileOverrides(),
      light: false,
    );
    expect(tester.getCenter(find.text('Profile')).dx, closeTo(width / 2, 0.5));
    // The page's slabs run on the bar's gutter.
    expect(
      tester.getTopLeft(find.byType(Scrollable)).dx +
          HomeTopBarMetrics.horizontalPadding,
      closeTo(
        tester
            .getTopLeft(
              find
                  .ancestor(
                    of: find.text('Free plan'),
                    matching: find.byType(Container),
                  )
                  .last,
            )
            .dx,
        0.5,
      ),
    );
    await _tearDown(tester);

    await _pumpRoot(
      tester,
      root: const ForYouScreen(pageBuilder: _fakePage),
      overrides: _homeOverrides(),
      light: false,
    );
    expect(
      tester.getTopLeft(find.byType(ForYouPageTabs)).dx,
      closeTo(gutter, 0.5),
    );
    expect(
      tester.getTopRight(find.byType(ForYouPageTabs)).dx,
      closeTo(width - gutter, 0.5),
    );
    await _tearDown(tester);
  });

  testWidgets('the four titles wear one type: Home\'s selected tab', (
    tester,
  ) async {
    TextStyle styleOf(String text) =>
        tester.widget<Text>(find.text(text)).style!;
    final want = <String, TextStyle>{};
    await _pumpRoot(
      tester,
      root: const ForYouScreen(pageBuilder: _fakePage),
      overrides: _homeOverrides(),
      light: true,
    );
    want['Today'] = styleOf('Today');
    await _tearDown(tester);
    await _pumpRoot(
      tester,
      root: const FeedScreen(embedded: true),
      overrides: _feedOverrides(),
      light: true,
      feed: true,
    );
    want['Feed'] = styleOf('Feed');
    await _tearDown(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    Supabase.instance.client.auth.stopAutoRefresh();
    await _pumpRoot(
      tester,
      root: const ChatScreen(
        embedded: true,
        screenContext: ChatScreenContext(screen: 'home'),
      ),
      overrides: _chatOverrides(),
      light: true,
      still: true,
    );
    want['Botvinnik'] = styleOf('Botvinnik');
    await _tearDown(tester);
    await _pumpRoot(
      tester,
      root: const ProfileHubScreen(),
      overrides: _profileOverrides(),
      light: true,
    );
    want['Profile'] = styleOf('Profile');
    await _tearDown(tester);

    final today = want['Today']!;
    for (final MapEntry(:key, :value) in want.entries) {
      expect(value.fontSize, today.fontSize, reason: key);
      expect(value.fontWeight, today.fontWeight, reason: key);
      expect(value.fontFamily, today.fontFamily, reason: key);
      expect(value.height, today.height, reason: key);
      expect(value.letterSpacing, today.letterSpacing, reason: key);
    }
  });
}
