// Renders of the dock with Collections where Search stood, Today's floating
// Search (Live first above it), the Collections root and its search, and
// Search as a pushed page, in both themes. PNGs are written only with
// --dart-define=NAV_DIR=/absolute/dir; without it every scene still pumps
// and must throw nothing.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/for_you/for_you_screen.dart';
import 'package:chessever2/screens/group_event/providers/home_live_first_provider.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/home/widget/home_nav_dock.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/search/search_landing.dart';
import 'package:chessever2/screens/search/search_tab_screen.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const _outDir = String.fromEnvironment('NAV_DIR');
const _capture = ValueKey('nav_capture');

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

class _NoFavoritePlayers extends FavoritePlayersNotifierNew {
  @override
  Future<List<FavoritePlayer>> build() async => const <FavoritePlayer>[];
}

class _NoShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];
}

class _MemoryRecentSearches implements RecentSearchStorage {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}
}

class _Broadcasts implements GroupBroadcastRepository {
  @override
  Future<List<GroupBroadcast>> getGroupBroadcastsByIdsOrNames(
    List<String> identifiers,
  ) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _books = [
  Collection(
    id: 'zurich-1953',
    slug: 'zurich-1953',
    kind: CollectionKind.event,
    title: 'Zurich 1953',
    location: 'Zurich',
    access: CollectionAccess.free,
  ),
  Collection(
    id: 'my-60',
    slug: 'my-60',
    kind: CollectionKind.book,
    title: 'My 60 Memorable Games',
    author: 'Bobby Fischer',
    access: CollectionAccess.free,
  ),
  Collection(
    id: 'endgames',
    slug: 'endgames',
    kind: CollectionKind.book,
    title: 'Carlsen Endgames',
    author: 'Magnus Carlsen',
    access: CollectionAccess.free,
  ),
  Collection(
    id: 'candidates-1959',
    slug: 'candidates-1959',
    kind: CollectionKind.event,
    title: 'Candidates 1959',
    location: 'Bled, Zagreb, Belgrade',
    access: CollectionAccess.free,
  ),
];

class _Books extends CollectionsRepository {
  _Books() : super(GamebaseRepository(Dio(), apiKey: 'test'));

  @override
  Future<List<String>> fetchAuthors() async => const ['Bobby Fischer'];

  @override
  Future<CollectionsPage> searchBooks(
    CollectionSearchQuery query,
    int offset,
  ) async {
    final words = query.text.trim().toLowerCase();
    final items = [
      for (final book in _books)
        if ('${book.title} ${book.author ?? ''}'.toLowerCase().contains(words))
          book,
    ];
    return CollectionsPage(
      items: items,
      total: items.length,
      limit: 40,
      offset: offset,
    );
  }
}

/// A stand-in for Today's cards under the buttons and the dock: rows the
/// size and tone of the event cards, so the glass has something to show.
class _TodayPage extends StatelessWidget {
  const _TodayPage();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.viewPaddingOf(context).top + 24,
        20,
        24,
      ),
      children: [
        Text(
          'Today',
          textAlign: TextAlign.center,
          style: AppTypography.textMdMedium.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 28),
        for (var i = 0; i < 7; i++) ...[
          Container(
            height: 112,
            decoration: BoxDecoration(
              color: colors.popup,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(16),
            alignment: Alignment.topLeft,
            child: Text(
              ['Tata Steel Masters', 'Grand Chess Tour', 'Norway Chess'][i % 3],
              style: AppTypography.textSmMedium.copyWith(
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// The home shell's frame around [body]: the dock (Collections in Search's
/// slot) under it and [fabs] riding it, as the shell stands them.
class _Shell extends StatefulWidget {
  const _Shell({required this.body, this.fabs});

  final Widget body;
  final Widget? fabs;

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
    final metrics = HomeNavMetrics.of(context, count: 5);
    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBody: true,
      floatingActionButton: widget.fabs == null
          ? null
          : SlidingFabs(
              controller: chrome,
              ride: metrics.ride,
              child: widget.fabs!,
            ),
      floatingActionButtonLocation: RidingFabLocation(metrics.ride),
      bottomNavigationBar: HomeNavDock(chrome: chrome),
      body: HomeNavScope(
        metrics: metrics,
        child: ScrollChromeRegion(controller: chrome, child: widget.body),
      ),
    );
  }
}

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
        overrides: [
          botvinnikTabAvailableProvider.overrideWithValue(true),
          currentUserProvider.overrideWithValue(
            AppUser(id: 'u1', displayName: 'Test', createdAt: DateTime(2026)),
          ),
          profileAvatarUrlProvider.overrideWithValue(null),
          inboxHasUnreadProvider.overrideWithValue(false),
          subscriptionProvider.overrideWith((ref) => _Subscription()),
          selectedBottomNavBarItemProvider.overrideWith((ref) => section),
          todayLiveEventCountProvider.overrideWith((ref) => 3),
          collectionsRepositoryProvider.overrideWithValue(_Books()),
          favoriteEventsProvider.overrideWith(_NoFavoriteEvents.new),
          favoritePlayersProviderNew.overrideWith(_NoFavoritePlayers.new),
          spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
          liveGroupBroadcastIdsProvider.overrideWith(
            (ref) => Stream.value(const <String>[]),
          ),
          groupBroadcastRepositoryProvider.overrideWith((ref) => _Broadcasts()),
          searchTopPlayersProvider.overrideWith((ref) async => []),
          searchLandingOpeningsProvider.overrideWith((ref) async => []),
          searchUpcomingProvider.overrideWith((ref) async => []),
          recentSearchStorageProvider.overrideWithValue(
            _MemoryRecentSearches(),
          ),
          supabaseCombinedSearchProvider.overrideWith(
            (ref, query) async => EnhancedSearchResult.empty(),
          ),
        ],
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
  await _frames(tester);
}

Future<void> _frames(WidgetTester tester, [int count = 40]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<void> _shot(WidgetTester tester, String name, bool light) async {
  expect(tester.takeException(), isNull);
  if (_outDir.isEmpty) return;
  await tester.runAsync(() async {
    final context = tester.element(find.byType(Scaffold).first);
    for (final widget in tester.widgetList<Image>(find.byType(Image))) {
      await precacheImage(widget.image, context);
    }
  });
  await tester.pump();
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(_capture),
    );
    final image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await Directory(_outDir).create(recursive: true);
    await File(
      '$_outDir/${name}_${light ? 'light' : 'dark'}.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
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

    _scene('Today: Live first above Search over the dock, $theme', (
      tester,
    ) async {
      await _pump(
        tester,
        light: light,
        section: BottomNavBarItem.forYou,
        home: const _Shell(body: _TodayPage(), fabs: ForYouTodayFabs()),
      );
      final dock = tester.getRect(find.byKey(const ValueKey('home-nav-dock')));
      final search = tester.getRect(
        find.byKey(const ValueKey(kForYouSearchButtonKey)),
      );
      // The main button in the corner, 16 over the full dock; Live first
      // one step above it.
      expect(search.bottom, closeTo(dock.top - 16, 2));
      expect(find.byKey(const ValueKey(kForYouLiveFirstButtonKey)), findsOne);
      await _shot(tester, 'today_search_fab', light);
    });

    _scene('the Collections tab, $theme', (tester) async {
      await _pump(
        tester,
        light: light,
        section: BottomNavBarItem.collections,
        home: const _Shell(body: CollectionsScreen(embedded: true)),
      );
      expect(find.text('Zurich 1953'), findsOne);
      // Where Home's main button stands over the dock: 16 above the full
      // capsule's top, on the 16 gutter.
      final dock = tester.getRect(find.byKey(const ValueKey('home-nav-dock')));
      final fab = tester.getRect(
        find.byKey(const ValueKey('event_view_search_fab')),
      );
      expect(fab.right, closeTo(393 - 16, 0.5));
      expect(fab.bottom, closeTo(dock.top - 16, 0.5));
      await _shot(tester, 'collections_tab', light);
    });

    _scene('the Collections tab searching, $theme', (tester) async {
      await _pump(
        tester,
        light: light,
        section: BottomNavBarItem.collections,
        home: const _Shell(body: CollectionsScreen(embedded: true)),
      );
      await tester.tap(find.byKey(const ValueKey('event_view_search_fab')));
      await _frames(tester);
      await tester.enterText(
        find.byKey(const ValueKey('collections_search')),
        'Fischer',
      );
      await _frames(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await _frames(tester);
      expect(find.text('My 60 Memorable Games'), findsOne);
      expect(find.text('Zurich 1953'), findsNothing);
      await _shot(tester, 'collections_tab_search', light);
    });

    _scene('Search, pushed over Home, $theme', (tester) async {
      await _pump(
        tester,
        light: light,
        section: BottomNavBarItem.forYou,
        home: const _Shell(body: _TodayPage(), fabs: ForYouTodayFabs()),
      );
      await tester.tap(find.byKey(const ValueKey(kForYouSearchButtonKey)));
      await _frames(tester);
      expect(find.byType(SearchTabScreen), findsOne);
      await _shot(tester, 'search_page', light);
    });
  }
}
