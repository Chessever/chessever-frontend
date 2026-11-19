// Search is the fifth root (root_header_parity_test.dart holds the other
// four): its field sits on the same centre line, in the same bar, and its
// page starts at the same y as every other root's, so switching tabs never
// makes the page jump.
import 'dart:async';

import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/search/search_landing.dart';
import 'package:chessever2/screens/search/search_tab_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

const double _statusBar = 47;

class _MemoryRecentSearches implements RecentSearchStorage {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}
}

class _FreeSubscription extends SubscriptionNotifier {
  _FreeSubscription() : super() {
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

class _NothingLive extends SearchLiveNowNotifier {
  @override
  SearchLiveNow build() => const SearchLiveNow(events: []);
}

class _Broadcasts implements GroupBroadcastRepository {
  @override
  Future<List<GroupBroadcast>> getGroupBroadcastsByIdsOrNames(
    List<String> identifiers,
  ) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Shell extends StatefulWidget {
  const _Shell();

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
      bottomNavigationBar: CollapsingChrome(
        controller: chrome,
        edge: VerticalDirection.down,
        child: SizedBox(
          height: 56 + MediaQuery.viewPaddingOf(context).bottom,
          width: double.infinity,
        ),
      ),
      body: ScrollChromeRegion(
        controller: chrome,
        child: const SearchTabScreen(),
      ),
    );
  }
}

void main() {
  for (final light in [false, true]) {
    testWidgets('Search wears the one bar: inset, height, centre line and '
        'page start (${light ? 'light' : 'dark'})', (tester) async {
      tester.view
        ..physicalSize = const Size(393, 852) * 3
        ..devicePixelRatio = 3
        ..padding = const FakeViewPadding(top: _statusBar * 3, bottom: 34 * 3)
        ..viewPadding = const FakeViewPadding(
          top: _statusBar * 3,
          bottom: 34 * 3,
        );
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            searchLiveNowProvider.overrideWith(_NothingLive.new),
            liveGroupBroadcastIdsProvider.overrideWith(
              (ref) => Stream.value(const <String>[]),
            ),
            groupBroadcastRepositoryProvider.overrideWith(
              (ref) => _Broadcasts(),
            ),
            searchTopPlayersProvider.overrideWith((ref) async => []),
            searchLandingOpeningsProvider.overrideWith((ref) async => []),
            searchUpcomingProvider.overrideWith((ref) async => []),
            favoriteEventsProvider.overrideWith(_NoFavoriteEvents.new),
            favoritePlayersProviderNew.overrideWith(_NoFavoritePlayers.new),
            spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
            selectedBottomNavBarItemProvider.overrideWith(
              (ref) => BottomNavBarItem.search,
            ),
            recentSearchStorageProvider.overrideWithValue(
              _MemoryRecentSearches(),
            ),
            currentUserProvider.overrideWithValue(
              AppUser(id: 'u1', displayName: 'Test', createdAt: DateTime(2026)),
            ),
            subscriptionProvider.overrideWith((ref) => _FreeSubscription()),
            supabaseCombinedSearchProvider.overrideWith(
              (ref, query) async => EnhancedSearchResult.empty(),
            ),
          ],
          child: MaterialApp(
            theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: Builder(
              builder: (context) {
                ResponsiveHelper.init(context);
                return const _Shell();
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final context = tester.element(find.byType(SearchTabScreen));
      final header = HomeTopBarMetrics.headerExtent(context);
      final centre =
          _statusBar +
          HomeTopBarMetrics.topGap +
          HomeTopBarMetrics.rowExtent(context) / 2;
      final field = tester.getRect(
        find.byKey(const ValueKey('search_tab_field')),
      );
      expect(field.center.dy, closeTo(centre, 0.5));
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('search_tab_page'))).dy,
        closeTo(header, 0.5),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }
}
