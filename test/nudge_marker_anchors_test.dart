// Every Nudge placement the admin console offers has a surface in this app.
//
// The admin console (chessever-admin-portal `shared/nudges.ts`,
// NUDGE_SURFACES) lists the marker ids a Nudge can point at; the phone draws
// a dot only where a DiscoveryDotAnchor carries that id. Since 38.18 Home's
// page tabs and the Collections tab's page tabs (ForYouPageTabs) carried no
// anchor, so every Nudge on `home.tab.*` or `collections.tab.*`, and every
// trail through them, went dark on current builds.
//
// The catalog is read from the admin checkout beside this one when it is
// there (`NUDGE_CATALOG` names another file), and otherwise from the pinned
// copy in test/fixtures/nudge_surfaces_pinned.ts, so the check never depends
// on a sibling repo. Shell placements (dock, Home's pages and tabs,
// Discovery and My Space tiles, Profile rows, the Collections tab's pages)
// are looked up in the widget tree of the real screens: HomeNavDock,
// ForYouScreen with the real My Space and Discovery pages, the real
// CollectionsScreen as the dock's tab, the real ProfileHubScreen. Tabs
// inside pushed screens (an event, a player, a collection, ...) are drawn by
// SegmentedSwitcher / EventViewShell from their `dotScope`; those are
// checked against the source.
//
// Retired: `drawer.desktop` (the side menu's Desktop row left with the side
// menu at 38.18; nothing in the current shell is that surface).

import 'dart:convert';
import 'dart:io';

import 'package:chessever2/providers/app_version_provider.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/providers/for_you_games_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/repository/library/models/saved_analysis.dart';
import 'package:chessever2/repository/liked_games/liked_games_provider.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/collections/collections_data.dart';
import 'package:chessever2/screens/collections/collections_screen.dart';
import 'package:chessever2/screens/feed/widgets/feed_tile_board.dart';
import 'package:chessever2/screens/for_you/discovery/providers/reports_provider.dart';
import 'package:chessever2/screens/for_you/for_you_screen.dart';
import 'package:chessever2/screens/for_you/providers/for_you_tab_provider.dart';
import 'package:chessever2/screens/group_event/providers/home_live_first_provider.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/home/widget/home_nav_dock.dart';
import 'package:chessever2/screens/inbox/inbox_provider.dart';
import 'package:chessever2/screens/library/providers/gamebase_database_games_provider.dart';
import 'package:chessever2/screens/library/providers/library_auth_provider.dart';
import 'package:chessever2/screens/my_profile/my_profile_screen.dart';
import 'package:chessever2/screens/my_profile/profile_hub_screen.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_auto_provider.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/services/attention_policy.dart';
import 'package:chessever2/services/discovery_dots/discovery_dot.dart';
import 'package:chessever2/services/discovery_dots/discovery_dots_provider.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/adaptive_window.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/discovery_dot.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'inbox_fakes.dart';

// ------------------------------------------------------------ the catalog

/// One placement of the admin catalog.
class NudgeSurface {
  const NudgeSurface(this.id, this.group, this.builds);

  final String id;
  final String group;

  /// The catalog's version note (`OLD_SHELL`, `NEW_SHELL`, a quoted
  /// string), or null when every build draws it.
  final String? builds;

  @override
  String toString() => id;
}

/// Reads NUDGE_SURFACES out of the catalog's TypeScript: the literal rows
/// and the `...tabs(group, scope, [labels], trail?, builds?)` spreads, slugged
/// as the catalog and [discoveryDotId] slug them.
List<NudgeSurface> parseNudgeCatalog(String source) {
  final start = source.indexOf('export const NUDGE_SURFACES');
  if (start < 0) throw const FormatException('no NUDGE_SURFACES');
  final end = source.indexOf('];', start);
  final body = source.substring(start, end);
  final row = RegExp(
    r'\{\s*id:\s*"([^"]+)",\s*label:\s*"[^"]*",\s*group:\s*"([^"]+)"([^}]*)\}',
  );
  final tabs = RegExp(
    r'\.\.\.tabs\(\s*"([^"]+)",\s*"([^"]+)",\s*\[([^\]]*)\]([^)]*)\)',
  );
  final builds = RegExp(r'builds:\s*(OLD_SHELL|NEW_SHELL|`[^`]*`|"[^"]*")');
  final shell = RegExp(r'\b(OLD_SHELL|NEW_SHELL)\b');
  final quoted = RegExp(r'"([^"]+)"');
  final surfaces = <NudgeSurface>[];
  for (final line in const LineSplitter().convert(body)) {
    final literal = row.firstMatch(line);
    if (literal != null) {
      surfaces.add(
        NudgeSurface(
          literal.group(1)!,
          literal.group(2)!,
          builds.firstMatch(literal.group(3)!)?.group(1),
        ),
      );
      continue;
    }
    final spread = tabs.firstMatch(line);
    if (spread == null) continue;
    final note = shell.firstMatch(spread.group(4)!)?.group(1);
    for (final label in quoted.allMatches(spread.group(3)!)) {
      surfaces.add(
        NudgeSurface(
          discoveryDotId(spread.group(2)!, label.group(1)!),
          spread.group(1)!,
          note,
        ),
      );
    }
  }
  return surfaces;
}

const _pinnedCatalog = 'test/fixtures/nudge_surfaces_pinned.ts';

/// The admin checkout's catalog, when it is beside this one.
File? _siblingCatalog() {
  final named = Platform.environment['NUDGE_CATALOG'];
  for (final path in [?named, '../chessever-admin-portal/shared/nudges.ts']) {
    final file = File(path);
    if (file.existsSync()) return file;
  }
  return null;
}

/// Ids no current surface carries: published Nudges on them light only on
/// the builds that had them.
const _retired = {'drawer.desktop'};

/// The shell's placements: what the dock, Home's pages and Profile hold.
bool _isShell(String id) =>
    id == 'home.menu' ||
    [
      'home.nav.',
      'home.tab.',
      'discovery.tile.',
      'my_space.tile.',
      'drawer.',
      'profile.',
      'collections.tab.',
    ].any(id.startsWith);

// ------------------------------------------------------------ the doubles

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription() : super(SubscriptionState(isSubscribed: false));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

class _NoLikes extends LikedGamesNotifier {
  @override
  Future<List<SavedAnalysis>> build() async => const [];
}

class _Hidden extends SpaceHiddenAutoKeys {
  @override
  Set<String> build() => const <String>{};
}

class _Feed extends StateNotifier<ForYouState> implements ForYouNotifier {
  _Feed() : super(ForYouState(events: const [], hasMore: false));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Books extends CollectionsRepository {
  _Books() : super(GamebaseRepository(Dio(), apiKey: 'test'));

  @override
  Future<List<String>> fetchAuthors() async => const ['Bobby Fischer'];

  @override
  Future<({List<CollectionAuthor> items, int total})> searchAuthors(
    CollectionSearchQuery query,
    int offset,
  ) async => (items: const <CollectionAuthor>[], total: 0);

  @override
  Future<CollectionsPage> searchBooks(
    CollectionSearchQuery query,
    int offset,
  ) async => CollectionsPage(
    items: const [
      Collection(
        id: 'zurich-1953',
        slug: 'zurich-1953',
        kind: CollectionKind.event,
        title: 'Zurich 1953',
        location: 'Zurich',
        access: CollectionAccess.free,
      ),
    ],
    total: 1,
    limit: 40,
    offset: offset,
  );
}

class _DotsSource implements DiscoveryDotsSource {
  _DotsSource(this.cached);

  final String cached;

  @override
  Future<String> initialize() async => cached;

  @override
  Future<String> fetch() async => cached;

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

/// Today's page stood in (its feed reads the network); My Space and
/// Discovery are the real pages.
Widget _homePage(BuildContext context, ForYouTab tab, ScrollController c) =>
    tab == ForYouTab.today
    ? ListView(controller: c, children: const [Text('page:today')])
    : buildForYouPage(context, tab, c);

/// The home shell's frame around a section's root: the dock under it, as
/// HomeScreen stands it.
class _Shell extends StatefulWidget {
  const _Shell({required this.body});

  final Widget body;

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
      bottomNavigationBar: HomeNavDock(chrome: chrome),
      body: HomeNavScope(
        metrics: metrics,
        child: ScrollChromeRegion(controller: chrome, child: widget.body),
      ),
    );
  }
}

Future<_MemoryStore> _pump(
  WidgetTester tester, {
  required BottomNavBarItem section,
  required Widget body,
  List<Map<String, Object?>> dots = const [],
}) async {
  tester.view
    ..physicalSize = const Size(393, 852)
    ..devicePixelRatio = 1
    ..padding = const FakeViewPadding(top: 59, bottom: 34)
    ..viewPadding = const FakeViewPadding(top: 59, bottom: 34);
  addTearDown(tester.view.reset);
  final seen = _MemoryStore();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        botvinnikTabAvailableProvider.overrideWithValue(true),
        currentUserProvider.overrideWithValue(
          AppUser(
            id: inboxOwnerA,
            createdAt: DateTime.utc(2026),
            isAnonymous: true,
          ),
        ),
        profileAvatarUrlProvider.overrideWithValue(null),
        inboxHasUnreadProvider.overrideWithValue(false),
        inboxSourceProvider.overrideWithValue(FakeInboxSource()),
        inboxCacheProvider.overrideWithValue(FakeInboxCache()),
        subscriptionProvider.overrideWith((ref) => _Subscription()),
        appVersionProvider.overrideWith((ref) async => '39.2.6'),
        myProfileIdentityProvider.overrideWith(
          (ref) => (displayName: 'Fixture Reader', email: null, isGuest: true),
        ),
        selectedBottomNavBarItemProvider.overrideWith((ref) => section),
        todayLiveEventCountProvider.overrideWith((ref) => 0),
        collectionsRepositoryProvider.overrideWithValue(_Books()),
        favoriteEventsProvider.overrideWith(_NoFavoriteEvents.new),
        favoritePlayersProviderNew.overrideWith(_NoFavoritePlayers.new),
        spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
        spaceHiddenAutoKeysProvider.overrideWith(_Hidden.new),
        likedGamesProvider.overrideWith(_NoLikes.new),
        forYouEventsProvider.overrideWith((ref) => _Feed()),
        libraryFolderAuthenticatedUserIdProvider.overrideWith((ref) => null),
        twicDatabaseTotalGamesProvider.overrideWith((ref) async => 9812345),
        liveGroupBroadcastIdsProvider.overrideWith(
          (ref) => Stream.value(const <String>[]),
        ),
        feedTilePreviewProvider.overrideWith((ref) async => null),
        reportsFirstPageProvider.overrideWith(
          (ref) => Future.error(StateError('no network in this test')),
        ),
        // The dots: published in Remote Config, remembered on the device,
        // for an account past its quiet first week.
        discoveryDotsSourceProvider.overrideWithValue(
          _DotsSource(jsonEncode({'dots': dots})),
        ),
        discoveryDotsSeenStoreProvider.overrideWithValue(seen),
        discoveryDotsDeliveryStoreProvider.overrideWithValue(_MemoryStore()),
        accountCreatedAtProvider.overrideWithValue(DateTime.utc(2020)),
        attentionClockProvider.overrideWithValue(inboxFixtureNow),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        // A lit dot breathes forever; held still, the frames can settle.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: AdaptiveWindowScope(child: child!),
        ),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return _Shell(body: body);
          },
        ),
      ),
    ),
  );
  await _frames(tester);
  return seen;
}

Future<void> _frames(WidgetTester tester, [int count = 30]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

/// Every anchor id in the tree, offstage ones included.
Set<String> _anchors(WidgetTester tester) => {
  for (final anchor in tester.widgetList<DiscoveryDotAnchor>(
    find.byType(DiscoveryDotAnchor, skipOffstage: false),
  ))
    ?anchor.id,
};

/// The anchors the real shell carries: the dock, Home on each of its pages,
/// the dock's Collections tab, and Profile.
Future<Set<String>> _shellAnchors(WidgetTester tester) async {
  final ids = <String>{};
  await _pump(
    tester,
    section: BottomNavBarItem.forYou,
    body: const ForYouScreen(pageBuilder: _homePage),
  );
  ids.addAll(_anchors(tester));
  for (final page in ['My Space', 'Discovery']) {
    await tester.tap(find.text(page).first);
    await _frames(tester);
    ids.addAll(_anchors(tester));
  }
  await tester.pumpWidget(const SizedBox.shrink());

  await _pump(
    tester,
    section: BottomNavBarItem.collections,
    body: const CollectionsScreen(embedded: true),
  );
  ids.addAll(_anchors(tester));
  await tester.pumpWidget(const SizedBox.shrink());

  await _pump(
    tester,
    section: BottomNavBarItem.profile,
    body: const ProfileHubScreen(),
  );
  ids.addAll(_anchors(tester));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  return ids;
}

/// Every Dart file under lib, read once.
final Map<String, String> _libSources = {
  for (final file in Directory('lib').listSync(recursive: true))
    if (file is File && file.path.endsWith('.dart'))
      file.path: file.readAsStringSync(),
};

/// Whether a pushed screen draws [id]: as `<scope>.<label>` from a
/// `dotScope: '<scope>'` whose file holds the label, or as a literal id.
bool _screenDraws(String id) {
  final literal = "'$id'";
  if (_libSources.values.any((source) => source.contains(literal))) {
    return true;
  }
  final scope = id.substring(0, id.lastIndexOf('.'));
  final label = RegExp(r"'([A-Za-z][A-Za-z ]*)'");
  for (final source in _libSources.values) {
    if (!source.contains("dotScope: '$scope'")) continue;
    if (label
        .allMatches(source)
        .any((m) => discoveryDotId(scope, m.group(1)!) == id)) {
      return true;
    }
    // The labels live beside the screen (an enum's names map): any file
    // that holds them and is imported by it.
    final imports = RegExp(
      r"import 'package:chessever2/([^']+)'",
    ).allMatches(source).map((m) => 'lib/${m.group(1)}');
    for (final path in imports) {
      final other = _libSources[path];
      if (other != null &&
          label
              .allMatches(other)
              .any((m) => discoveryDotId(scope, m.group(1)!) == id)) {
        return true;
      }
    }
  }
  return false;
}

void _expectCatalogAnchored(
  List<NudgeSurface> catalog,
  Set<String> shell, {
  required String source,
}) {
  expect(catalog.length, greaterThan(20), reason: 'read $source');
  final missing = <String>[];
  for (final surface in catalog) {
    if (_retired.contains(surface.id)) continue;
    final drawn = _isShell(surface.id)
        ? shell.contains(surface.id)
        : _screenDraws(surface.id);
    if (!drawn) missing.add('${surface.id} (${surface.group})');
  }
  expect(
    missing,
    isEmpty,
    reason: 'placements in $source with no surface in the current app',
  );
  // A retired id is retired in the catalog too, once it says which builds
  // draw what.
  if (catalog.any((surface) => surface.builds != null)) {
    for (final surface in catalog.where((s) => _retired.contains(s.id))) {
      expect(surface.builds, 'OLD_SHELL', reason: surface.id);
    }
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
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

  test('the catalog parser reads literal rows and tab spreads', () {
    final catalog = parseNudgeCatalog(File(_pinnedCatalog).readAsStringSync());
    final ids = {for (final s in catalog) s.id: s};
    expect(ids['home.nav.feed']?.builds, 'NEW_SHELL');
    expect(ids['home.tab.my_space']?.group, 'Home');
    expect(ids['prep_profile.tab.build_tree']?.group, 'Inside a Prep profile');
    expect(ids['collections.tab.authors']?.builds, 'OLD_SHELL');
    expect(ids.length, catalog.length, reason: 'no id listed twice');
  });

  test('the source check of pushed screens\' tabs is not vacuous', () {
    expect(_screenDraws('event.tab.standings'), isTrue);
    expect(_screenDraws('prep_profile.tab.build_tree'), isTrue);
    expect(_screenDraws('board.bar.engine'), isTrue);
    expect(_screenDraws('event.tab.not_a_tab'), isFalse);
    expect(_screenDraws('no_such_screen.tab.games'), isFalse);
  });

  testWidgets('every placement of the pinned catalog is a surface of the '
      'current app', (tester) async {
    final shell = await _shellAnchors(tester);
    // The two page-tab rows the 38.18 shell left dark carry their ids again.
    expect(
      shell,
      containsAll([
        'home.tab.my_space',
        'home.tab.today',
        'home.tab.discovery',
        'collections.tab.about',
        'collections.tab.collections',
        'collections.tab.authors',
      ]),
    );
    _expectCatalogAnchored(
      parseNudgeCatalog(File(_pinnedCatalog).readAsStringSync()),
      shell,
      source: _pinnedCatalog,
    );
  });

  final sibling = _siblingCatalog();
  testWidgets(
    'every placement of the admin checkout\'s catalog is a surface of the '
    'current app',
    (tester) async {
      final shell = await _shellAnchors(tester);
      _expectCatalogAnchored(
        parseNudgeCatalog(sibling!.readAsStringSync()),
        shell,
        source: sibling.path,
      );
    },
    skip: sibling == null,
  );

  group('Home\'s page tabs and the Collections tab\'s pages are Nudge '
      'surfaces again', () {
    Finder dotIn(String label) => find.descendant(
      of: find.ancestor(
        of: find.text(label).first,
        matching: find.byType(DiscoveryDotAnchor),
      ),
      matching: find.byType(DiscoveryDotMark),
    );

    testWidgets('a Nudge on Home\'s Discovery tab draws on its shoulder and '
        'retires on a tap', (tester) async {
      final seen = await _pump(
        tester,
        section: BottomNavBarItem.forYou,
        body: const ForYouScreen(pageBuilder: _homePage),
        dots: const [
          {
            'id': 'discovery-tab',
            'rev': 1,
            'target': 'home.tab.discovery',
            'trail': ['home.nav.home'],
            'message': 'Collections, Likes and News live here.',
          },
        ],
      );
      expect(dotIn('Discovery'), findsOneWidget);
      expect(dotIn('Today'), findsNothing);
      expect(dotIn('My Space'), findsNothing);
      // Off the word's top-right shoulder, inside the bar's row.
      final word = tester.getRect(find.text('Discovery').first);
      final dot = tester.getRect(dotIn('Discovery'));
      expect(dot.left, greaterThan(word.right));
      expect(dot.left - word.right, lessThan(6));
      expect(dot.top, greaterThanOrEqualTo(word.top - 1));
      expect(dot.bottom, lessThan(word.center.dy));

      await tester.tap(find.text('Discovery').first);
      await _frames(tester);
      expect(find.byType(DiscoveryDotMark), findsNothing);
      expect(seen.seen['discovery-tab'], 1);
      expect(
        find.text('Collections, Likes and News live here.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('a trail through Home\'s My Space tab lights the tab, then the '
        'tile', (tester) async {
      final seen = await _pump(
        tester,
        section: BottomNavBarItem.forYou,
        body: const ForYouScreen(pageBuilder: _homePage),
        dots: const [
          {
            'id': 'prep-launch',
            'rev': 1,
            'target': 'my_space.tile.my_prep',
            'trail': ['home.nav.home', 'home.tab.my_space'],
          },
        ],
      );
      expect(dotIn('My Space'), findsOneWidget);
      await tester.tap(find.text('My Space').first);
      await _frames(tester);
      // Standing on My Space passes the hop; the tile is next.
      expect(dotIn('My Space'), findsNothing);
      expect(seen.seen['prep-launch@home.tab.my_space'], 1);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('my_space_my_prep_tile')),
          matching: find.byType(DiscoveryDotMark),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the page Home opens on is reached without a tap', (
      tester,
    ) async {
      final seen = await _pump(
        tester,
        section: BottomNavBarItem.forYou,
        body: const ForYouScreen(pageBuilder: _homePage),
        dots: const [
          {'id': 'today-tab', 'rev': 1, 'target': 'home.tab.today'},
        ],
      );
      expect(dotIn('Today'), findsNothing);
      expect(seen.seen['today-tab'], 1);
    });

    testWidgets('a Nudge on the Collections tab\'s Authors page draws on the '
        'dock\'s tab and retires on a tap', (tester) async {
      final seen = await _pump(
        tester,
        section: BottomNavBarItem.collections,
        body: const CollectionsScreen(embedded: true),
        dots: const [
          {
            'id': 'authors-tab',
            'rev': 1,
            'target': 'collections.tab.authors',
            'trail': ['home.nav.collections'],
          },
        ],
      );
      expect(dotIn('Authors'), findsOneWidget);
      // Collections is the page on screen: its own tab would retire a Nudge
      // at once, so only Authors is lit.
      expect(dotIn('About'), findsNothing);
      await tester.tap(find.text('Authors').first);
      await _frames(tester);
      expect(
        find.descendant(
          of: find.byType(ForYouPageTabs),
          matching: find.byType(DiscoveryDotMark),
        ),
        findsNothing,
      );
      expect(seen.seen['authors-tab'], 1);
    });
  });
}
