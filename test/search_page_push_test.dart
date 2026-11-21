// Search left the dock (Collections took its slot) for Today's floating
// button, which opens it over Home as a page of its own: the pushed pages'
// back row (the chevron where every pushed page's is, the field after it),
// no cursor on arrival, the chevron, the iOS back swipe and Android's back
// all leaving it. Its landing stays read between visits once opened, as the
// dock's tab kept it.
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
import 'package:chessever2/screens/for_you/for_you_screen.dart';
import 'package:chessever2/screens/group_event/providers/home_live_first_provider.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/search/search_landing.dart';
import 'package:chessever2/screens/search/search_tab_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/ink_fab.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:chessever2/widgets/search_mode/search_mode.dart'
    show PageBackButton, SearchHeaderMetrics;
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

class _Broadcasts implements GroupBroadcastRepository {
  @override
  Future<List<GroupBroadcast>> getGroupBroadcastsByIdsOrNames(
    List<String> identifiers,
  ) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Home as the shell holds it, reduced to what this needs: Today's floating
/// buttons over a page, and the shell keeping Search's landing warm.
class _Home extends ConsumerWidget {
  const _Home();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    keepSearchLandingWarm(ref);
    return const Scaffold(
      floatingActionButton: ForYouTodayFabs(),
      body: Center(child: Text('home page')),
    );
  }
}

final Finder _searchButton = find.byKey(const ValueKey(kForYouSearchButtonKey));
final Finder _back = find.byKey(const ValueKey('search_back'));
final Finder _field = find.byKey(const ValueKey('search_tab_field'));

/// Pumps Home on [platform]; [topPlayerReads] counts the landing's reads of
/// the top players.
Future<void> _pump(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.iOS,
  List<int>? topPlayerReads,
}) async {
  tester.view
    ..physicalSize = const Size(393, 852) * 3
    ..devicePixelRatio = 3
    ..padding = const FakeViewPadding(top: _statusBar * 3, bottom: 34 * 3)
    ..viewPadding = const FakeViewPadding(top: _statusBar * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        liveGroupBroadcastIdsProvider.overrideWith(
          (ref) => Stream.value(const <String>[]),
        ),
        groupBroadcastRepositoryProvider.overrideWith((ref) => _Broadcasts()),
        searchTopPlayersProvider.overrideWith((ref) async {
          topPlayerReads?.add(1);
          return [];
        }),
        searchLandingOpeningsProvider.overrideWith((ref) async => []),
        searchUpcomingProvider.overrideWith((ref) async => []),
        favoriteEventsProvider.overrideWith(_NoFavoriteEvents.new),
        favoritePlayersProviderNew.overrideWith(_NoFavoritePlayers.new),
        spaceShortcutsProvider.overrideWith(_NoShortcuts.new),
        recentSearchStorageProvider.overrideWithValue(_MemoryRecentSearches()),
        currentUserProvider.overrideWithValue(
          AppUser(id: 'u1', displayName: 'Test', createdAt: DateTime(2026)),
        ),
        subscriptionProvider.overrideWith((ref) => _FreeSubscription()),
        supabaseCombinedSearchProvider.overrideWith(
          (ref, query) async => EnhancedSearchResult.empty(),
        ),
        // Nothing live: Today floats Search alone.
        todayLiveEventCountProvider.overrideWith((ref) => 0),
      ],
      child: MaterialApp(
        theme: AppTheme.darkTheme.copyWith(platform: platform),
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return const _Home();
          },
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<void> _openSearch(WidgetTester tester) async {
  await tester.tap(_searchButton);
  await _settle(tester);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('Today floats Search where the filter stood, and its tap opens '
      'Search over Home with the field at rest', (tester) async {
    await _pump(tester);
    expect(_searchButton, findsOneWidget);
    expect(tester.widget(_searchButton), isA<SearchInkFab>());
    expect(find.byIcon(Icons.tune_rounded), findsNothing);
    // The main, regular button in the corner every page's stands in.
    expect(tester.getSize(_searchButton), Size.square(InkFabSize.regular.side));

    await _openSearch(tester);
    expect(find.byType(SearchTabScreen), findsOneWidget);
    expect(_field, findsOneWidget);
    // No autofocus: arriving never takes the cursor or the keyboard.
    expect(tester.testTextInput.isVisible, isFalse);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus,
      isFalse,
    );
    expect(find.byKey(const ValueKey('search_landing')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _unmount(tester);
  });

  testWidgets('the back row is the pushed pages\': the chevron where every '
      'pushed page\'s is, the field after it on its line, the page under '
      'the row', (tester) async {
    await _pump(tester);
    await _openSearch(tester);
    final context = tester.element(find.byType(SearchTabScreen));
    final back = tester.getRect(_back);
    expect(back.left, closeTo(SearchHeaderMetrics.leadingInset, 0.01));
    // The back row every pushed page wears sits right under the top inset.
    expect(back.top, closeTo(_statusBar + 4.h, 0.5));
    expect(back.size, const Size.square(SearchHeaderMetrics.backTarget));
    expect(tester.widget(_back), isA<PageBackButton>());
    final field = tester.getRect(find.byType(EditableText));
    expect(field.left, greaterThan(back.right));
    expect(
      tester.getCenter(_field).dy,
      closeTo(back.center.dy, 1),
      reason: 'the field on the chevron\'s line',
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('search_tab_page'))).dy,
      greaterThanOrEqualTo(back.bottom),
    );
    expect(MediaQuery.viewPaddingOf(context).top, _statusBar);
    await _unmount(tester);
  });

  testWidgets('the chevron goes back to Home', (tester) async {
    await _pump(tester);
    await _openSearch(tester);
    await tester.tap(_back);
    await _settle(tester);
    expect(find.byType(SearchTabScreen), findsNothing);
    expect(find.text('home page'), findsOneWidget);
    expect(_searchButton, findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('the iOS back swipe goes back to Home', (tester) async {
    await _pump(tester);
    await _openSearch(tester);
    expect(find.byType(SearchTabScreen), findsOneWidget);
    final gesture = await tester.startGesture(const Offset(4, 420));
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump();
    await gesture.up();
    await _settle(tester);
    expect(find.byType(SearchTabScreen), findsNothing);
    expect(find.text('home page'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('Android\'s back goes back to Home', (tester) async {
    await _pump(tester, platform: TargetPlatform.android);
    await _openSearch(tester);
    expect(find.byType(SearchTabScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _settle(tester);
    expect(find.byType(SearchTabScreen), findsNothing);
    expect(find.text('home page'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('read down, the row steps away and the floating back keeps a '
      'way out in reach', (tester) async {
    await _pump(tester);
    await _openSearch(tester);
    final chrome = tester
        .widget<ScrollChromeRegion>(
          find.descendant(
            of: find.byType(SearchTabScreen),
            matching: find.byType(ScrollChromeRegion),
          ),
        )
        .controller;
    expect(chrome.value, 1);
    chrome.hide(animate: false);
    await tester.pump();
    expect(_back.hitTestable(), findsNothing);
    final float = find.byKey(const ValueKey('page_back_float'));
    expect(float.hitTestable(), findsOneWidget);
    await tester.tap(float);
    await _settle(tester);
    expect(find.byType(SearchTabScreen), findsNothing);
    await _unmount(tester);
  });

  testWidgets('once opened, the landing stays read between visits, as the '
      'dock\'s tab kept it', (tester) async {
    final reads = <int>[];
    await _pump(tester, topPlayerReads: reads);
    expect(reads, isEmpty, reason: 'nothing is read before Search opens');
    await _openSearch(tester);
    expect(reads, hasLength(1));
    await tester.tap(_back);
    await _settle(tester);
    await tester.pump(const Duration(seconds: 2));
    await _openSearch(tester);
    expect(find.byType(SearchTabScreen), findsOneWidget);
    expect(reads, hasLength(1), reason: 'the second visit reads nothing again');
    await _unmount(tester);
  });

  test('the route is named for the screen views analytics records', () {
    expect(searchRouteName, '/search_screen');
  });
}
