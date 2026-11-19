import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/favorite_events_provider.dart';
import 'package:chessever2/providers/favorite_players_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/favorites/models/favorite_event.dart';
import 'package:chessever2/repository/favorites/models/favorite_player.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/favorites/favorites_tab_screen.dart';
import 'package:chessever2/screens/favorites/tabs/favorites_players_tab.dart'
    show playerPhotoProvider;
import 'package:chessever2/screens/for_you/discovery/providers/discovery_providers.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/screens/group_event/widget/player_search_cards.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/search/search_landing.dart';
import 'package:chessever2/screens/search/search_page_landing.dart';
import 'package:chessever2/screens/search/search_page_results.dart';
import 'package:chessever2/screens/search/search_page_sections.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/event_image_provider.dart';
import 'package:chessever2/widgets/event_card/event_next_round_provider.dart';
import 'package:chessever2/widgets/event_card/smart_event_card.dart';
import 'package:chessever2/widgets/event_card/smart_event_request_card.dart';
import 'package:chessever2/widgets/figma_player_card.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/scroll_chrome.dart';
import 'package:chessever2/widgets/search/enhanced_rounded_search_bar.dart';
import 'package:chessever2/widgets/search/opening_search_suggestion.dart';
import 'package:chessever2/widgets/search/search_overlay_widget.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
import 'package:chessever2/screens/search/search_tab_screen.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/search/enhanced_group_broadcast_local_storage.dart';
import 'package:chessever2/widgets/search/recent_searches_provider.dart';
import 'package:chessever2/widgets/search/search_result_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The app-wide search lives on the Search tab; the Events lists (opened
/// from Profile) keep a search field of their own. Both drive the same
/// app-wide search providers, so neither may show the other's query.
///
/// The tab's page draws nothing of its own: every event, player, opening and
/// smart event is the card the app draws it in elsewhere, with that card's
/// own tap and long-press.
void main() {
  testWidgets('the Search tab opens with the cursor in its field', (
    tester,
  ) async {
    final app = await _pump(tester);
    final field = find.byKey(const ValueKey('search_tab_field'));
    expect(field, findsOneWidget);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    await app.dispose();
  });

  testWidgets('the field starts where every root tab\'s bar starts', (
    tester,
  ) async {
    final app = await _pump(tester);
    final field = tester.getRect(find.byType(EnhancedRoundedSearchBar));
    final context = tester.element(find.byType(SearchTabScreen));
    expect(field.left, closeTo(HomeTopBarMetrics.horizontalPadding, 0.01));
    // On the bar's one centre line, and the page starts where every root's
    // page starts.
    expect(
      field.center.dy,
      closeTo(
        HomeTopBarMetrics.topInset(context) +
            HomeTopBarMetrics.rowExtent(context) / 2,
        0.5,
      ),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('search_tab_page'))).dy,
      closeTo(HomeTopBarMetrics.headerExtent(context), 0.5),
    );
    await app.dispose();
  });

  testWidgets('one page: no drop-down, no placeholder copy, results in '
      'place as you type', (tester) async {
    final app = await _pump(
      tester,
      live: [_liveEvent],
      openings: _landingOpenings,
    );
    final page = find.byKey(const ValueKey('search_tab_page'));
    expect(page, findsOneWidget);
    // Nothing typed: the landing, real cards and no placeholder copy.
    expect(find.byKey(const ValueKey('search_landing')), findsOneWidget);
    _expectNoPlaceholderCopy();
    // The page is the only results surface: no panel drops over it.
    expect(find.byType(SearchOverlay), findsOneWidget);

    await _type(tester, const ValueKey('search_tab_field'), 'carlsen');
    expect(
      find.descendant(of: page, matching: find.textContaining('Carlsen')),
      findsWidgets,
    );
    // The results replace the landing.
    expect(find.byKey(const ValueKey('search_landing')), findsNothing);
    expect(find.text('Live now'), findsNothing);
    expect(find.byType(SearchOverlay), findsOneWidget);

    // Keyboard down: the same page, the same results.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.descendant(of: page, matching: find.textContaining('Carlsen')),
      findsWidgets,
    );
    await app.dispose();
  });

  testWidgets('one letter shows nothing yet, never "No results"', (
    tester,
  ) async {
    final app = await _pump(tester);
    await _type(tester, const ValueKey('search_tab_field'), 'k');

    expect(find.textContaining('No matches'), findsNothing);
    expect(find.text('No results found'), findsNothing);
    expect(find.textContaining('No events match'), findsNothing);
    expect(find.byKey(const ValueKey('search_landing')), findsOneWidget);
    await app.dispose();
  });

  testWidgets(
    'Events searched "carlsen", Search searches "nakamura": the cards are '
    'Nakamura',
    (tester) async {
      final app = await _pump(tester);

      // 1. Events (from Profile): search carlsen, then back.
      app.page.value = _Page.events;
      await tester.pump();
      await _type(tester, e2eKey(E2eIds.eventsSearchField), 'carlsen');
      expect(app.read(searchTabQueryProvider), 'carlsen');
      app.page.value = _Page.search;
      await tester.pump();

      // 2. The Search tab: search nakamura.
      await _type(tester, const ValueKey('search_tab_field'), 'nakamura');
      final results = find.byKey(const ValueKey('search_tab_page'));
      expect(results, findsOneWidget);
      expect(
        find.descendant(of: results, matching: find.textContaining('Nakamura')),
        findsWidgets,
      );
      expect(
        find.descendant(of: results, matching: find.textContaining('Carlsen')),
        findsNothing,
      );
      await app.dispose();
    },
  );

  testWidgets(
    'one letter on Events keeps the dropdown off "No results found"',
    (tester) async {
      final app = await _pump(tester);
      app.page.value = _Page.events;
      await tester.pump();

      await _type(tester, e2eKey(E2eIds.eventsSearchField), 'k');

      expect(find.text('No results found'), findsNothing);
      expect(find.textContaining('No events match'), findsNothing);
      await app.dispose();
    },
  );

  testWidgets('the bar holds while the field has the keyboard, and steps '
      'away with the page after', (tester) async {
    final app = await _pump(tester, chrome: true);
    final chrome = app.chrome!;
    // The tab puts the cursor in the field on arrival.
    expect(chrome.held, isTrue);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(chrome.held, isFalse);

    await tester.tap(find.byKey(const ValueKey('search_tab_field')));
    await tester.pump();
    expect(chrome.held, isTrue);
    await app.dispose();
  });

  testWidgets('a re-tap of the tab takes the page back to its top on a '
      'spring, brings the bar back and puts the cursor in the field', (
    tester,
  ) async {
    final app = await _pump(
      tester,
      chrome: true,
      live: [_liveEvent, _secondLiveEvent],
      players: () async => _topPlayers,
      openings: _landingOpenings,
      upcoming: [_upcomingEvent],
    );
    final chrome = app.chrome!;
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byKey(const ValueKey('search_landing')),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    expect(position.maxScrollExtent, greaterThan(400));
    position.jumpTo(400);
    await tester.pump();
    chrome.hide(animate: false);
    await tester.pump();
    expect(chrome.value, 0);

    app
        .read(bottomNavBarReTapRequestProvider.notifier)
        .request(BottomNavBarItem.search);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    // On its way, not there in one frame.
    expect(position.pixels, inExclusiveRange(0, 400));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(position.pixels, moreOrLessEquals(0, epsilon: 0.01));
    expect(chrome.value, 1);
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('search_tab_field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.focusNode.hasFocus, isTrue);
    await app.dispose();
  });

  group('the landing (nothing typed)', () {
    testWidgets('each section in the card the app draws it in elsewhere, '
        'in order', (tester) async {
      final app = await _pump(
        tester,
        size: const Size(393, 3000),
        recents: [RecentSearchEntry.tournament(_event)],
        live: [_liveEvent, _secondLiveEvent],
        players: () async => _topPlayers,
        openings: _landingOpenings,
        upcoming: [_upcomingEvent],
      );
      final landing = find.byKey(const ValueKey('search_landing'));
      expect(landing, findsOneWidget);

      final headings = [
        'Recent searches',
        'Live now',
        'Top players',
        'Openings',
        'Smart events',
        'Coming up',
      ];
      for (final heading in headings) {
        expect(
          find.descendant(of: landing, matching: find.text(heading)),
          findsOneWidget,
          reason: heading,
        );
      }
      for (var i = 1; i < headings.length; i++) {
        expect(
          tester.getTopLeft(find.text(headings[i - 1])).dy,
          lessThan(tester.getTopLeft(find.text(headings[i])).dy),
          reason: '${headings[i - 1]} before ${headings[i]}',
        );
      }

      // Recent and live events, and the events coming up: event cards.
      for (final key in [
        'search-recent-${RecentSearchEntry.tournament(_event).identity}',
        'search-live-${_liveEvent.id}',
        'search-live-${_secondLiveEvent.id}',
        'search-upcoming-${_upcomingEvent.id}',
      ]) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(EventCard),
          ),
          findsOneWidget,
          reason: key,
        );
      }
      // The live card reads LIVE, as it does in the Events list.
      expect(
        find.descendant(
          of: find.byKey(ValueKey('search-live-${_liveEvent.id}')),
          matching: find.text('LIVE'),
        ),
        findsOneWidget,
      );

      // Top players: the Events page's player cards, four of them.
      final cards = find.byKey(const ValueKey('search-top-players'));
      expect(tester.widget<PlayerSearchCards>(cards).players, hasLength(4));
      expect(find.text('Magnus Carlsen'), findsOneWidget);

      // Openings and the built-in smart events: smart event cards.
      for (final opening in _landingOpenings) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('opening-result-${opening.id}')),
            matching: find.byType(SmartEventCard),
          ),
          findsOneWidget,
          reason: opening.title,
        );
      }
      for (final preset in kDiscoverySmartPresets) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('search-smart-${preset.tierLabel}')),
            matching: find.byType(SmartEventCard),
          ),
          findsOneWidget,
        );
      }

      _expectNoPlaceholderCopy();
      // Nothing on the page is hidden behind an entrance: every card is
      // fully there on its first frame.
      expect(
        find.descendant(
          of: landing,
          matching: find.byWidgetPredicate(
            (w) =>
                (w is Opacity && w.opacity == 0) ||
                (w is FadeTransition && w.opacity.value == 0),
          ),
        ),
        findsNothing,
      );
      await app.dispose();
    });

    testWidgets('an opening never claims a number of events', (tester) async {
      final app = await _pump(tester, openings: _landingOpenings);
      final sicilian = _landingOpenings.first;
      final card = find.descendant(
        of: find.byKey(ValueKey('opening-result-${sicilian.id}')),
        matching: find.byType(SmartEventCard),
      );
      final smart = tester.widget<SmartEventCard>(card);
      // What it covers, not a count passed off as events, and the thinnest
      // deck on its plate whatever the family's size.
      expect(smart.metaText, 'ECO B20-B99');
      expect(smart.deckEvents, 1);
      expect(smart.liveCount, 0);
      expect(smart.avgElo, 0);
      expect(
        find.descendant(of: card, matching: find.text('ECO B20-B99')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining('event', findRichText: true),
        ),
        findsNothing,
      );
      await app.dispose();
    });

    testWidgets('recent searches come first, each in its kind\'s card; Edit '
        'holds Clear all', (tester) async {
      final najdorf = searchOpeningSuggestions('Najdorf', limit: 1).single;
      final app = await _pump(
        tester,
        size: const Size(393, 2000),
        recents: [
          RecentSearchEntry.tournament(_event),
          RecentSearchEntry.player(_topPlayers[1]),
          RecentSearchEntry.openingSelection(najdorf.selection),
        ],
        live: [_liveEvent],
      );
      final recent = find.text('Recent searches');
      expect(recent, findsOneWidget);
      expect(
        tester.getTopLeft(recent).dy,
        lessThan(tester.getTopLeft(find.text('Live now')).dy),
      );
      Finder slot(RecentSearchEntry entry) =>
          find.byKey(ValueKey('search-recent-${entry.identity}'));
      expect(
        find.descendant(
          of: slot(RecentSearchEntry.tournament(_event)),
          matching: find.byType(EventCard),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: slot(RecentSearchEntry.player(_topPlayers[1])),
          matching: find.byType(PlayerSearchCards),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: slot(RecentSearchEntry.openingSelection(najdorf.selection)),
          matching: find.byType(SmartEventRequestCard),
        ),
        findsOneWidget,
      );

      // Out of Edit, the heading offers Edit alone; the cards are whole.
      expect(find.text('Clear all'), findsNothing);
      expect(find.byType(SearchRecentRemoveButton), findsNothing);
      await tester.tap(find.byKey(const ValueKey('search-recent-edit')));
      await tester.pump();
      expect(find.byType(SearchRecentRemoveButton), findsNWidgets(3));
      await tester.tap(find.byKey(const ValueKey('search-recent-clear')));
      await tester.pump();
      expect(find.text('Recent searches'), findsNothing);
      expect(app.read(recentSearchesProvider).valueOrNull, isEmpty);
      await app.dispose();
    });

    testWidgets('at most four recent searches', (tester) async {
      final app = await _pump(
        tester,
        size: const Size(393, 2400),
        recents: [
          for (var i = 0; i < 6; i++)
            RecentSearchEntry.tournament(_eventNamed('r$i', 'Recent $i')),
        ],
      );
      for (var i = 0; i < 6; i++) {
        expect(
          find.text('Recent $i'),
          i < searchLandingRecentLimit ? findsOneWidget : findsNothing,
          reason: 'Recent $i',
        );
      }
      await app.dispose();
    });

    testWidgets('a swipe removes one recent search; Edit puts a remove '
        'button after each card, which a screen reader reads by name', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final first = RecentSearchEntry.tournament(_event);
      final second = RecentSearchEntry.player(_topPlayers[1]);
      final third = RecentSearchEntry.tournament(_secondLiveEvent);
      final app = await _pump(
        tester,
        size: const Size(393, 1600),
        recents: [first, second, third],
      );
      Finder slot(RecentSearchEntry entry) =>
          find.byKey(ValueKey('search-recent-${entry.identity}'));
      await tester.drag(slot(first), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text(_event.title), findsNothing);
      expect(
        app.read(recentSearchesProvider).valueOrNull!.map((e) => e.identity),
        [second.identity, third.identity],
      );

      // Edit: the cards hold still, each followed by its remove button, on
      // its centre line, inside the gutter. The button's room opens on
      // Edit's spring: the card narrows over frames, never in one.
      final cardWidth = tester.getSize(slot(second)).width;
      final remove = find.byKey(
        ValueKey('search-recent-remove-${second.identity}'),
      );
      final card = find.descendant(
        of: slot(second),
        matching: find.byType(PlayerSearchCards),
      );
      final whole = tester.getSize(card).width;
      final room = math.max(44.0, 44.w) + 4.w;
      await tester.tap(find.byKey(const ValueKey('search-recent-edit')));
      await tester.pump();
      expect(tester.getSize(slot(second)).width, cardWidth);
      expect(tester.getSize(card).width, closeTo(whole, 0.5));
      await tester.pump(const Duration(milliseconds: 60));
      final midway = tester.getSize(card).width;
      expect(midway, lessThan(whole - 1));
      expect(midway, greaterThan(whole - room + 1));
      await tester.pumpAndSettle();
      expect(tester.getSize(slot(second)).width, cardWidth);
      expect(tester.getSize(card).width, closeTo(whole - room, 0.5));
      expect(
        tester.getCenter(remove).dy,
        closeTo(tester.getCenter(card).dy, 0.5),
      );
      expect(
        tester.getRect(remove).right,
        closeTo(393 - HomeTopBarMetrics.horizontalPadding, 0.5),
      );
      expect(tester.getSize(remove).height, greaterThanOrEqualTo(44));
      // A tap on a card in Edit opens nothing; a swipe removes nothing.
      final before = app.read(recentSearchesProvider).valueOrNull!;
      await tester.tap(card, warnIfMissed: false);
      await tester.drag(
        slot(third),
        const Offset(-500, 0),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();
      expect(app.read(recentSearchesProvider).valueOrNull, before);

      // The button is a real control, named for its entry.
      expect(
        tester.getSemantics(remove),
        matchesSemantics(
          label: 'Remove ${second.title} from recent searches',
          isButton: true,
          hasTapAction: true,
        ),
      );
      final rowHeight = tester.getSize(slot(second)).height;
      tester.semantics.tap(
        find.semantics.byLabel('Remove ${second.title} from recent searches'),
      );
      // Its row closes up on the spring, then the entry goes: the card
      // under it rises rather than jumps.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final closing = tester.getSize(slot(second)).height;
      expect(closing, lessThan(rowHeight - 1));
      expect(closing, greaterThan(1));
      await tester.pumpAndSettle();
      expect(slot(second), findsNothing);
      expect(
        app.read(recentSearchesProvider).valueOrNull!.map((e) => e.identity),
        [third.identity],
      );

      // The last one gone ends Edit with the section.
      await tester.tap(
        find.byKey(ValueKey('search-recent-remove-${third.identity}')),
      );
      await tester.pumpAndSettle();
      expect(app.read(recentSearchesProvider).valueOrNull, isEmpty);
      expect(find.text('Recent searches'), findsNothing);
      await app.dispose();
      semantics.dispose();
    });

    testWidgets('Done ends Edit: the cards open again', (tester) async {
      final entry = RecentSearchEntry.tournament(_event);
      final app = await _pump(tester, recents: [entry]);
      await tester.tap(find.byKey(const ValueKey('search-recent-edit')));
      await tester.pump();
      expect(find.byType(SearchRecentRemoveButton), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('search-recent-done')));
      // The buttons leave on Edit's spring.
      await tester.pumpAndSettle();
      expect(find.byType(SearchRecentRemoveButton), findsNothing);
      expect(find.byKey(const ValueKey('search-recent-edit')), findsOneWidget);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byKey(ValueKey('search-recent-${entry.identity}')),
          matching: find.byType(EventCard),
        ),
      );
      await tester.pump();
      final navigation =
          app.read(tournamentNavigationProvider) as _RecordingNavigation;
      expect(navigation.opened.single.$1, _event.id);
      await app.dispose();
    });

    testWidgets('a section with nothing to list is not shown, and a failed '
        'ranking read leaves no trace', (tester) async {
      final app = await _pump(
        tester,
        players: () async => throw Exception('offline'),
        openings: _landingOpenings,
      );
      await tester.pump();
      expect(find.text('Recent searches'), findsNothing);
      expect(find.text('Live now'), findsNothing);
      expect(find.text('Top players'), findsNothing);
      expect(find.text('Coming up'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Openings'), findsOneWidget);
      _expectNoPlaceholderCopy();
      await app.dispose();
    });

    testWidgets('a slow ranking read holds the cards\' room with one quiet '
        'spinner: Openings does not move when the players land', (
      tester,
    ) async {
      final pending = Completer<List<SearchPlayer>>();
      final app = await _pump(
        tester,
        players: () => pending.future,
        openings: _landingOpenings,
      );
      expect(find.text('Top players'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('search-top-players-pending')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      _expectNoPlaceholderCopy();
      final openings = tester.getTopLeft(find.text('Openings')).dy;

      pending.complete(_topPlayers);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Magnus Carlsen'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Openings')).dy, openings);
      await app.dispose();
    });

    testWidgets('the openings, resolved a moment later, land in room '
        'already held: Smart events does not move', (tester) async {
      final later = Completer<List<OpeningSearchSuggestion>>();
      final app = await _pump(
        tester,
        size: const Size(393, 2400),
        openingsLater: later.future,
      );
      expect(
        find.byKey(const ValueKey('search-openings-pending')),
        findsOneWidget,
      );
      final smart = tester.getTopLeft(find.text('Smart events')).dy;

      later.complete(_landingOpenings);
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('search-openings-pending')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('opening-result-${_landingOpenings.first.id}')),
        findsOneWidget,
      );
      expect(tester.getTopLeft(find.text('Smart events')).dy, smart);
      await app.dispose();
    });

    testWidgets('typing replaces it; clearing the field brings it back', (
      tester,
    ) async {
      final app = await _pump(
        tester,
        live: [_liveEvent],
        players: () async => _topPlayers,
        openings: _landingOpenings,
      );
      await _type(tester, const ValueKey('search_tab_field'), 'nakamura');
      expect(find.text('Live now'), findsNothing);
      expect(find.text('Top players'), findsNothing);

      await _type(tester, const ValueKey('search_tab_field'), '');
      expect(find.text('Live now'), findsOneWidget);
      expect(find.text('Top players'), findsOneWidget);
      expect(find.text('Magnus Carlsen'), findsOneWidget);
      await app.dispose();
    });

    testWidgets('a live event card opens as a searched event does, with one '
        'haptic', (tester) async {
      final haptics = _Haptics(tester);
      final app = await _pump(tester, live: [_liveEvent]);
      haptics.calls.clear();
      await tester.tap(find.byKey(ValueKey('search-live-${_liveEvent.id}')));
      await tester.pump();

      final navigation =
          app.read(tournamentNavigationProvider) as _RecordingNavigation;
      expect(navigation.opened, [
        (_liveEvent.id, GroupEventCategory.search, 'forYouSearch'),
      ]);
      expect(haptics.calls, hasLength(1));
      await app.dispose();
    });

    testWidgets('a top player card opens their profile', (tester) async {
      final observer = _PushObserver();
      final app = await _pump(
        tester,
        players: () async => _topPlayers,
        observer: observer,
      );
      await tester.tap(find.text('Magnus Carlsen'));
      await tester.pump();

      final profile = observer.lastPage(tester);
      expect(profile, isA<PlayerProfileScreen>());
      profile as PlayerProfileScreen;
      expect(profile.fideId, 1503014);
      expect(profile.playerName, 'Carlsen, Magnus');
      expect(profile.rating, 2833);
      await app.dispose();
    });

    testWidgets('See all opens Rankings', (tester) async {
      final observer = _PushObserver();
      final app = await _pump(
        tester,
        players: () async => _topPlayers,
        observer: observer,
      );
      await tester.tap(find.textContaining('See all', findRichText: true));
      await tester.pump();
      expect(observer.lastPage(tester), isA<FavoritesTabScreen>());
      await app.dispose();
    });

    testWidgets('an opening opens the smart event its search result opens', (
      tester,
    ) async {
      final observer = _PushObserver();
      final app = await _pump(
        tester,
        openings: _landingOpenings,
        observer: observer,
      );
      final sicilian = searchOpeningSuggestions('Sicilian', limit: 1).single;
      expect(_landingOpenings.first.id, sicilian.id);
      await tester.tap(find.byKey(ValueKey('opening-result-${sicilian.id}')));
      await tester.pump();

      final screen = observer.lastPage(tester);
      expect(screen, isA<SmartEventScreen>());
      screen as SmartEventScreen;
      expect(screen.request.eco.code, sicilian.filter.code);
      await app.dispose();
    });

    testWidgets('a built-in smart event opens itself', (tester) async {
      final observer = _PushObserver();
      final app = await _pump(tester, observer: observer);
      final gm = kDiscoverySmartPresets.first;
      await tester.tap(find.byKey(ValueKey('search-smart-${gm.tierLabel}')));
      await tester.pump();
      final screen = observer.lastPage(tester);
      expect(screen, isA<SmartEventScreen>());
      expect((screen as SmartEventScreen).request.criteriaKey, gm.criteriaKey);
      await app.dispose();
    });

    group('a pick is remembered as a recent search, as a result is', () {
      final sicilian = searchOpeningSuggestions('Sicilian', limit: 1).single;
      for (final (name, row, check)
          in <(String, Finder Function(), void Function(RecentSearchEntry))>[
            (
              'a live event',
              () => find.byKey(ValueKey('search-live-${_liveEvent.id}')),
              (entry) {
                expect(entry.kind, RecentSearchKind.tournament);
                expect(entry.targetId, _liveEvent.id);
              },
            ),
            (
              'a top player',
              () => find.text('Magnus Carlsen'),
              (entry) {
                expect(entry.kind, RecentSearchKind.player);
                expect(entry.targetId, 'fide:1503014');
              },
            ),
            (
              'an opening',
              () => find.byKey(ValueKey('opening-result-${sicilian.id}')),
              (entry) {
                expect(entry.kind, RecentSearchKind.opening);
                expect(
                  entry.toOpeningSelection()?.filter.code,
                  sicilian.filter.code,
                );
              },
            ),
          ]) {
        testWidgets(name, (tester) async {
          final app = await _pump(
            tester,
            live: [_liveEvent],
            players: () async => _topPlayers,
            openings: _landingOpenings,
            observer: _PushObserver(),
          );
          expect(app.read(recentSearchesProvider).valueOrNull, isEmpty);
          await tester.tap(row());
          await tester.pump();
          // The pushed page is never built: only the record is flushed.
          await tester.binding.delayed(Duration.zero);

          final recents = app.read(recentSearchesProvider).valueOrNull!;
          expect(recents, hasLength(1));
          check(recents.single);
          await app.dispose();
        });
      }
    });

    group('a long-press opens the card\'s own menu', () {
      testWidgets('an event card: its event menu, with My Space', (
        tester,
      ) async {
        final app = await _pump(tester, live: [_liveEvent]);
        await tester.longPress(
          find.byKey(ValueKey('search-live-${_liveEvent.id}')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Open event'), findsOneWidget);
        await tester.tap(find.text('Add to My Space'));
        await tester.pumpAndSettle();
        final saved = app.read(spaceShortcutsProvider).requireValue.single;
        expect(saved.kind, SpaceShortcutKind.event);
        expect(saved.targetId, _liveEvent.id);
        await app.dispose();
      });

      testWidgets('an opening\'s smart event: Open, and My Space', (
        tester,
      ) async {
        final app = await _pump(tester, openings: _landingOpenings);
        await tester.longPress(
          find.byKey(ValueKey('opening-result-${_landingOpenings.first.id}')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Open smart event'), findsOneWidget);
        await tester.tap(find.text('Add to My Space'));
        await tester.pumpAndSettle();
        final saved = app.read(spaceShortcutsProvider).requireValue.single;
        expect(saved.kind, SpaceShortcutKind.smartEvent);
        await app.dispose();
      });

      testWidgets('a player card: the shared player menu', (tester) async {
        final app = await _pump(tester, players: () async => _topPlayers);
        await tester.longPress(find.text('Magnus Carlsen'));
        await tester.pumpAndSettle();
        expect(find.text('Open profile'), findsOneWidget);
        expect(find.text('Share profile'), findsOneWidget);
        await app.dispose();
      });
    });

    testWidgets('typing starts no landing work, and clearing asks for '
        'nothing again', (tester) async {
      final builds = _Builds();
      final repo = _Broadcasts();
      final app = await _pump(
        tester,
        builds: builds,
        liveSource: _realLive(
          live: [_liveEvent.id, _secondLiveEvent.id],
          feed: [_liveEvent],
          repo: repo,
          builds: builds,
        ),
        players: () async => _topPlayers,
        openings: _landingOpenings,
      );
      expect(
        (builds.live, builds.players, builds.openings, builds.upcoming),
        (1, 1, 1, 1),
      );
      expect(repo.calls, [
        [_secondLiveEvent.id],
      ]);
      repo.answer([_secondLiveBroadcast]);
      await tester.pump();

      await _type(tester, const ValueKey('search_tab_field'), 'nakamura');
      expect(find.byKey(const ValueKey('search_landing')), findsNothing);
      await _type(tester, const ValueKey('search_tab_field'), '');
      expect(find.text(_secondLiveEvent.title), findsOneWidget);

      expect(
        (builds.live, builds.players, builds.openings, builds.upcoming),
        (1, 1, 1, 1),
      );
      expect(repo.calls, hasLength(1));
      await app.dispose();
    });

    testWidgets('live events found late land in room already held: the '
        'cards on screen and the sections below do not move', (tester) async {
      final repo = _Broadcasts();
      final app = await _pump(
        tester,
        liveSource: _realLive(
          live: [_liveEvent.id, _secondLiveEvent.id],
          feed: [_liveEvent],
          repo: repo,
        ),
        players: () async => _topPlayers,
        openings: _landingOpenings,
      );
      // The feed's event is listed at once, before the lookup answers.
      expect(find.text(_liveEvent.title), findsOneWidget);
      final pendingSlot = find.byKey(const ValueKey('search-live-pending'));
      expect(pendingSlot, findsOneWidget);
      double top(Finder finder) => tester.getTopLeft(finder).dy;
      final listed = top(find.text(_liveEvent.title));
      final held = tester.getSize(pendingSlot).height;
      final players = top(find.text('Top players'));

      repo.answer([_secondLiveBroadcast]);
      await tester.pump();
      final landed = find.byKey(ValueKey('search-live-${_secondLiveEvent.id}'));
      expect(landed, findsOneWidget);
      expect(pendingSlot, findsNothing);
      expect(tester.getSize(landed).height, closeTo(held, 0.01));
      expect(top(find.text(_liveEvent.title)), listed);
      expect(top(find.text('Top players')), players);
      _expectNoPlaceholderCopy();
      await app.dispose();
    });

    for (final size in const [Size(393, 852), Size(375, 667)]) {
      testWidgets('${size.width.round()}x${size.height.round()}: headings '
          'and cards start and end on the field\'s gutter', (tester) async {
        final app = await _pump(
          tester,
          size: Size(size.width, 2400),
          recents: [RecentSearchEntry.tournament(_event)],
          live: [_liveEvent],
          players: () async => _topPlayers,
          openings: _landingOpenings,
        );
        final field = tester.getRect(find.byType(EnhancedRoundedSearchBar));
        expect(field.left, closeTo(HomeTopBarMetrics.horizontalPadding, 0.01));
        for (final heading in [
          'Recent searches',
          'Live now',
          'Top players',
          'Openings',
          'Smart events',
        ]) {
          expect(
            tester.getTopLeft(find.text(heading)).dx,
            closeTo(field.left, 0.01),
            reason: heading,
          );
        }
        for (final card in [
          find.byKey(ValueKey('search-live-${_liveEvent.id}')),
          find.byKey(const ValueKey('search-top-players')),
        ]) {
          final rect = tester.getRect(card);
          expect(rect.left, closeTo(field.left, 0.01));
          expect(rect.right, closeTo(field.right, 0.01));
        }
        // Half cards side by side, flush to both edges, tops in line.
        final a = tester.getRect(
          find.byKey(ValueKey('opening-result-${_landingOpenings[0].id}')),
        );
        final b = tester.getRect(
          find.byKey(ValueKey('opening-result-${_landingOpenings[1].id}')),
        );
        expect(a.left, closeTo(field.left, 0.01));
        expect(b.right, closeTo(field.right, 0.01));
        expect(a.top, b.top);
        expect(a.height, closeTo(b.height, 0.01));

        await _type(tester, const ValueKey('search_tab_field'), 'qqqq');
        expect(
          tester.getTopLeft(find.textContaining('No matches')).dx,
          closeTo(field.left, 0.01),
        );
        await app.dispose();
      });
    }

    testWidgets('tablet: events as the Events list\'s grid, smart events '
        'several to a row, nothing overflowing', (tester) async {
      final app = await _pump(
        tester,
        size: const Size(1024, 2600),
        recents: [RecentSearchEntry.tournament(_event)],
        live: [_liveEvent, _secondLiveEvent],
        players: () async => _topPlayers,
        openings: _landingOpenings,
        upcoming: [_upcomingEvent],
      );
      expect(ResponsiveHelper.isTablet, isTrue);
      expect(tester.takeException(), isNull);
      final a = tester.getRect(
        find.byKey(ValueKey('search-live-${_liveEvent.id}')),
      );
      final b = tester.getRect(
        find.byKey(ValueKey('search-live-${_secondLiveEvent.id}')),
      );
      expect(a.top, b.top);
      expect(a.right, lessThan(b.left));
      final first = tester.getRect(
        find.byKey(ValueKey('opening-result-${_landingOpenings[0].id}')),
      );
      final third = tester.getRect(
        find.byKey(ValueKey('opening-result-${_landingOpenings[2].id}')),
      );
      expect(first.top, third.top);
      await app.dispose();
    });

    testWidgets('text at 1.3x: every section lays out whole', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final najdorf = searchOpeningSuggestions('Najdorf', limit: 1).single;
      final app = await _pump(
        tester,
        size: const Size(393, 4000),
        recents: [
          RecentSearchEntry.tournament(_event),
          RecentSearchEntry.player(_topPlayers[1]),
          RecentSearchEntry.openingSelection(najdorf.selection),
        ],
        live: [_liveEvent],
        players: () async => _topPlayers,
        openings: _landingOpenings,
        upcoming: [_upcomingEvent],
      );
      expect(tester.takeException(), isNull);
      await _type(tester, const ValueKey('search_tab_field'), 'najdorf');
      expect(tester.takeException(), isNull);
      await app.dispose();
    });

    // The event card's own meta line is the Events list's, cut the same way
    // there; this pins the page's own pieces at the largest text.
    testWidgets('text at 2.0x on a 375pt phone: headings, player cards and '
        'smart events lay out whole', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final najdorf = searchOpeningSuggestions('Najdorf', limit: 1).single;
      final app = await _pump(
        tester,
        size: const Size(375, 5000),
        recents: [
          RecentSearchEntry.player(_topPlayers[1]),
          RecentSearchEntry.openingSelection(najdorf.selection),
        ],
        players: () async => _topPlayers,
        openings: _landingOpenings,
      );
      expect(tester.takeException(), isNull);
      await app.dispose();
    });

    for (final (name, theme, colors) in [
      ('light', AppTheme.lightTheme, AppColors.light),
      ('dark', AppTheme.darkTheme, AppColors.dark),
    ]) {
      testWidgets('$name: headings and actions clear AA on the page', (
        tester,
      ) async {
        final app = await _pump(
          tester,
          theme: theme,
          recents: [RecentSearchEntry.tournament(_event)],
          live: [_liveEvent],
          players: () async => _topPlayers,
        );
        for (final text in ['Recent searches', 'Live now', 'Top players']) {
          final ink = tester.widget<Text>(find.text(text)).style!.color!;
          expect(
            _contrast(ink, colors.background),
            greaterThanOrEqualTo(4.5),
            reason: '"$text" on the $name page',
          );
        }
        await app.dispose();
      });
    }
  });

  group('the results (typing)', () {
    testWidgets('players as player cards then Rankings rows, openings as '
        'smart events, events as event cards, in that order', (tester) async {
      final app = await _pump(tester, size: const Size(393, 4000));
      await _type(tester, const ValueKey('search_tab_field'), 'najdorf');

      final results = find.byKey(const ValueKey('search_results'));
      expect(results, findsOneWidget);
      final players = find.text('Players');
      final openings = find.text('Openings');
      final events = find.text('Events');
      expect(
        tester.getTopLeft(players).dy,
        lessThan(tester.getTopLeft(openings).dy),
      );
      expect(
        tester.getTopLeft(openings).dy,
        lessThan(tester.getTopLeft(events).dy),
      );

      // The four strongest as the Events page's player cards...
      final cards = tester.widget<PlayerSearchCards>(
        find.byType(PlayerSearchCards),
      );
      expect(cards.players.map((p) => p.name), [
        for (var i = 0; i < 4; i++) 'Najdorf $i',
      ]);
      // ...the rest as Rankings rows.
      expect(find.byType(FigmaPlayerCard), findsNWidgets(2));
      expect(find.byType(SearchPlayerRow), findsNWidgets(2));

      // Openings: one smart event per ECO code, never the same one twice;
      // beside players and events, one row, with the true count and Show
      // all for the rest.
      final smart = find.descendant(
        of: results,
        matching: find.byType(SmartEventRequestCard),
      );
      List<String> keys() => [
        for (final e in smart.evaluate())
          (e.widget as SmartEventRequestCard).request.criteriaKey,
      ];
      final matched = searchOpeningSmartEvents(
        searchOpeningSuggestions('najdorf'),
      ).where(searchOpeningIsStrong).toList();
      expect(matched.length, greaterThan(2));
      expect(keys(), hasLength(2));
      expect(keys().toSet(), hasLength(2));
      expect(
        find.descendant(
          of: find.ancestor(of: openings, matching: find.byType(Row)).first,
          matching: find.text('${matched.length}'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('search-openings-more')));
      await tester.pump();
      expect(keys(), hasLength(matched.length));
      expect(keys().toSet(), hasLength(matched.length));
      expect(find.text('Show fewer'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('search-openings-more')));
      await tester.pump();
      expect(keys(), hasLength(2));

      // Events: event cards.
      expect(
        find.descendant(
          of: find.byKey(ValueKey('search-event-${_event.id}')),
          matching: find.byType(EventCard),
        ),
        findsOneWidget,
      );
      await app.dispose();
    });

    testWidgets('a player search lists no lookalike openings: Events start '
        'right under the players', (tester) async {
      final app = await _pump(tester, size: const Size(393, 2000));
      // The catalog has typo-tolerant matches for "carlsen" (Nimzovich-
      // Larsen, Mikenas-Carls); beside a player none is shown.
      expect(searchOpeningSuggestions('carlsen'), isNotEmpty);
      await _type(tester, const ValueKey('search_tab_field'), 'carlsen');
      expect(find.text('Players'), findsOneWidget);
      expect(find.text('Openings'), findsNothing);
      expect(find.byType(SmartEventRequestCard), findsNothing);
      await app.dispose();
    });

    testWidgets('openings alone: three rows, typo-tolerant matches '
        'included, Show all for the rest', (tester) async {
      final app = await _pump(tester, size: const Size(393, 2400));
      await _type(tester, const ValueKey('search_tab_field'), 'sicillian');
      final all = searchOpeningSmartEvents(
        searchOpeningSuggestions('sicillian'),
      );
      expect(all.where(searchOpeningIsStrong), isEmpty);
      final cards = find.byType(SmartEventRequestCard);
      expect(cards, findsNWidgets(searchOpeningRows * 2));
      expect(find.text('${all.length}'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('search-openings-more')),
        findsOneWidget,
      );
      // The rows line up: each pair shares its top.
      final tops = [
        for (final e in cards.evaluate())
          tester.getTopLeft(find.byWidget(e.widget)).dy,
      ];
      for (var i = 0; i < tops.length; i += 2) {
        expect(tops[i + 1], closeTo(tops[i], 0.01));
      }
      await app.dispose();
    });

    testWidgets('a Rankings row\'s tap gives no haptic, as Rankings\' does', (
      tester,
    ) async {
      final haptics = _Haptics(tester);
      final app = await _pump(
        tester,
        size: const Size(393, 4000),
        observer: _PushObserver(),
      );
      await _type(tester, const ValueKey('search_tab_field'), 'najdorf');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      haptics.calls.clear();
      await tester.tap(find.byKey(const ValueKey('search-player-100005')));
      await tester.pump();
      expect(haptics.calls, isEmpty);
      await tester.binding.delayed(Duration.zero);
      await app.dispose();
    });

    testWidgets('a Rankings row opens the profile, remembers it, and its '
        'long-press is the player menu with the favorite row', (tester) async {
      final observer = _PushObserver();
      final app = await _pump(
        tester,
        size: const Size(393, 4000),
        observer: observer,
      );
      await _type(tester, const ValueKey('search_tab_field'), 'najdorf');
      final row = find.byKey(const ValueKey('search-player-100005'));
      expect(row, findsOneWidget);

      await tester.longPress(row);
      await tester.pumpAndSettle();
      expect(find.text('Open profile'), findsOneWidget);
      expect(find.text('Add to favorites'), findsOneWidget);
      await tester.tap(find.text('Open profile'));
      await tester.pumpAndSettle();

      final profile = observer.lastPage(tester) as PlayerProfileScreen;
      expect(profile.fideId, 100005);
      await tester.binding.delayed(Duration.zero);
      expect(
        app.read(recentSearchesProvider).valueOrNull!.single.targetId,
        'fide:100005',
      );
      await app.dispose();
    });

    testWidgets('an event card opens as a searched event does', (tester) async {
      final app = await _pump(tester, size: const Size(393, 4000));
      await _type(tester, const ValueKey('search_tab_field'), 'najdorf');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await tester.tap(find.byKey(ValueKey('search-event-${_event.id}')));
      await tester.pump();
      final navigation =
          app.read(tournamentNavigationProvider) as _RecordingNavigation;
      expect(navigation.opened, [
        (_event.id, GroupEventCategory.search, 'forYouSearch'),
      ]);
      await app.dispose();
    });

    testWidgets('the last results stay up while the next search loads', (
      tester,
    ) async {
      final slow = Completer<EnhancedSearchResult>();
      final app = await _pump(tester, slowQuery: ('nakamur', slow));
      await _type(tester, const ValueKey('search_tab_field'), 'nakamura');
      expect(find.text('Hikaru Nakamura'), findsOneWidget);

      await _type(tester, const ValueKey('search_tab_field'), 'nakamur');
      // Still the last search's card, not a spinner.
      expect(find.text('Hikaru Nakamura'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      slow.complete(EnhancedSearchResult.empty());
      await tester.pump();
      await app.dispose();
    });
  });
}

/// Explanatory filler the landing must never show.
void _expectNoPlaceholderCopy() {
  expect(
    find.text('Search players, tournaments, openings, or ECO codes'),
    findsNothing,
  );
  expect(find.textContaining('FIDE countries.'), findsNothing);
  expect(find.textContaining('No recent searches'), findsNothing);
  expect(find.textContaining('Try searching'), findsNothing);
  expect(find.textContaining('Start typing'), findsNothing);
  expect(find.textContaining('No results'), findsNothing);
}

double _contrast(Color ink, Color paper) {
  final fg = Color.alphaBlend(ink, paper).computeLuminance();
  final bg = paper.computeLuminance();
  final hi = fg > bg ? fg : bg;
  final lo = fg > bg ? bg : fg;
  return (hi + 0.05) / (lo + 0.05);
}

/// Every haptic the app asks the platform for.
class _Haptics {
  _Haptics(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
  }

  final calls = <MethodCall>[];
}

/// Records pushed pages without building them: the destinations are whole
/// screens with their own backends.
class _PushObserver extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }

  Widget lastPage(WidgetTester tester) {
    final route = pushed.lastWhere((r) => r is MaterialPageRoute<dynamic>);
    return (route as MaterialPageRoute<dynamic>).builder(
      tester.element(find.byType(SearchTabScreen, skipOffstage: false)),
    );
  }
}

class _RecordingNavigation extends TournamentNavigationController {
  _RecordingNavigation(super.ref);

  final opened = <(String, GroupEventCategory, String?)>[];

  @override
  Future<void> openTournament({
    required BuildContext context,
    required String id,
    required GroupEventCategory category,
    Iterable<GroupBroadcast> knownBroadcasts = const <GroupBroadcast>[],
    String? analyticsSource,
  }) async {
    opened.add((id, category, analyticsSource));
  }
}

enum _Page { search, events }

class _App {
  _App(this._tester, this._container, this.page, this.chrome);

  final WidgetTester _tester;
  final ProviderContainer _container;
  final ValueNotifier<_Page> page;
  final ScrollChromeController? chrome;

  T read<T>(ProviderListenable<T> provider) => _container.read(provider);

  Future<void> dispose() async {
    await _tester.pumpWidget(const SizedBox.shrink());
    await _tester.pump(const Duration(seconds: 61));
    page.dispose();
  }
}

/// The Search tab under test. The landing's sources are fixtures: nothing
/// live, no ranking, no openings and nothing coming up unless a test passes
/// them.
///
/// [liveSource] runs the real Live now instead ([_realLive]); [builds]
/// counts how often each landing source is built. [chrome] puts the tab
/// under a scroll chrome, as the home shell does.
Future<_App> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  Size size = const Size(393, 852),
  List<RecentSearchEntry> recents = const [],
  List<GroupEventCardModel> live = const [],
  List<Override>? liveSource,
  Future<List<SearchPlayer>> Function()? players,
  List<OpeningSearchSuggestion> openings = const [],
  Future<List<OpeningSearchSuggestion>>? openingsLater,
  List<GroupEventCardModel> upcoming = const [],
  NavigatorObserver? observer,
  _Builds? builds,
  bool chrome = false,
  (String, Completer<EnhancedSearchResult>)? slowQuery,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  addTearDown(tester.view.reset);
  final page = ValueNotifier(_Page.search);
  final chromeController = chrome
      ? ScrollChromeController(vsync: const TestVSync())
      : null;
  if (chromeController != null) addTearDown(chromeController.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...liveSource ??
            [
              searchLiveNowProvider.overrideWith(
                () => _FixedLiveNow(SearchLiveNow(events: live), builds),
              ),
              liveGroupBroadcastIdsProvider.overrideWith(
                (ref) => Stream.value(const <String>[]),
              ),
              groupBroadcastRepositoryProvider.overrideWith(
                (ref) => _Broadcasts(),
              ),
            ],
        searchTopPlayersProvider.overrideWith((ref) {
          builds?.players++;
          return players == null ? <SearchPlayer>[] : players();
        }),
        searchLandingOpeningsProvider.overrideWith((ref) async {
          builds?.openings++;
          return openingsLater ?? openings;
        }),
        searchUpcomingProvider.overrideWith((ref) async {
          builds?.upcoming++;
          return upcoming;
        }),
        discoverySmartEventMembersProvider.overrideWith(
          (ref, criteria) async => const <GroupEventCardModel>[],
        ),
        favoriteEventsProvider.overrideWith(_NoFavoriteEvents.new),
        favoritePlayersProviderNew.overrideWith(_NoFavoritePlayers.new),
        spaceShortcutsProvider.overrideWith(_MemorySpaceShortcuts.new),
        eventImageProvider.overrideWith(
          (ref, id) async => const EventImageData(),
        ),
        eventNextRoundProvider.overrideWith((ref, id) async => null),
        eventNoSpoilersProvider.overrideWith(
          (ref, tourId) => _MemoryNoSpoilers(ref, tourId),
        ),
        playerPhotoProvider.overrideWith((ref, id) async => null),
        tournamentNavigationProvider.overrideWith(_RecordingNavigation.new),
        selectedBottomNavBarItemProvider.overrideWith(
          (ref) => BottomNavBarItem.search,
        ),
        recentSearchStorageProvider.overrideWithValue(_MemoryRecentSearches()),
        currentUserProvider.overrideWithValue(
          AppUser(
            id: 'u1',
            displayName: 'Test User',
            createdAt: DateTime(2026),
          ),
        ),
        subscriptionProvider.overrideWith((ref) => _FreeSubscription()),
        supabaseCombinedSearchProvider.overrideWith((ref, query) async {
          final slow = slowQuery;
          if (slow != null && slow.$1 == query.trim()) return slow.$2.future;
          return _resultsByQuery[query.trim()] ?? EnhancedSearchResult.empty();
        }),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        navigatorObservers: [?observer],
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            Widget tab = const SearchTabScreen();
            if (chromeController != null) {
              tab = ScrollChromeRegion(
                controller: chromeController,
                child: tab,
              );
            }
            return Scaffold(
              resizeToAvoidBottomInset: false,
              body: ValueListenableBuilder(
                valueListenable: page,
                builder: (context, shown, _) => switch (shown) {
                  _Page.search => tab,
                  _Page.events => const GroupEventScreen(
                    pageBuilder: _eventsPage,
                  ),
                },
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(Scaffold).first),
  );
  for (final entry in recents.reversed) {
    await container.read(recentSearchesProvider.notifier).record(entry);
  }
  await tester.pump();
  await tester.pump();
  return _App(tester, container, page, chromeController);
}

/// Types into the search field, then waits out every debounce on the path
/// (the bar's 300ms, the Events tab's 300ms, the dropdown's 400ms).
Future<void> _type(WidgetTester tester, Key fieldKey, String text) async {
  final field = find.byKey(fieldKey);
  expect(field, findsOneWidget);
  await tester.tap(field);
  await tester.pump();
  await tester.enterText(field, text);
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget _eventsPage(
  BuildContext context,
  GroupEventCategory category,
  ScrollController controller,
) => ListView(
  controller: controller,
  children: [Text('events:${category.name}')],
);

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

class _MemorySpaceShortcuts extends SpaceShortcutsNotifier {
  @override
  Future<List<SpaceShortcut>> build() async => const [];

  @override
  Future<bool> add(SpaceShortcut draft) async {
    final list = state.requireValue;
    if (!draft.canAddToMySpace || list.any((s) => s.key == draft.key)) {
      return false;
    }
    state = AsyncData([draft, ...list]);
    return true;
  }

  @override
  Future<SpaceShortcut?> remove(String id) async {
    final list = state.requireValue;
    final removed = list.where((s) => s.id == id).firstOrNull;
    state = AsyncData([
      for (final s in list)
        if (s.id != id) s,
    ]);
    return removed;
  }

  @override
  Future<void> restore(SpaceShortcut item) async {
    state = AsyncData([item, ...state.requireValue]);
  }
}

class _MemoryNoSpoilers extends EventNoSpoilersController {
  _MemoryNoSpoilers(Ref ref, String tourId) : super(ref: ref, tourId: tourId);

  @override
  Future<void> load() async {
    state = const EventNoSpoilersState(enabled: false, isLoading: false);
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    state = EventNoSpoilersState(enabled: enabled, isLoading: false);
  }
}

final _event = GroupEventCardModel(
  id: 'tour-1',
  title: 'Sinquefield Cup 2026',
  dates: 'Aug 20, 2026',
  maxAvgElo: 2750,
  timeUntilStart: '',
  tourEventCategory: TourEventCategory.completed,
  timeControl: 'Classical',
  startDate: DateTime.utc(2026, 8, 20),
  endDate: DateTime.utc(2026, 8, 30),
);

GroupEventCardModel _eventNamed(String id, String title) => GroupEventCardModel(
  id: id,
  title: title,
  dates: 'Aug 20, 2026',
  maxAvgElo: 2600,
  timeUntilStart: '',
  tourEventCategory: TourEventCategory.completed,
  timeControl: 'Classical',
  startDate: DateTime.utc(2026, 8, 20),
  endDate: DateTime.utc(2026, 8, 30),
);

final _upcomingEvent = GroupEventCardModel(
  id: 'up-1',
  title: 'Norway Chess 2027',
  dates: 'May 25 - Jun 5, 2027',
  maxAvgElo: 2760,
  timeUntilStart: '',
  tourEventCategory: TourEventCategory.upcoming,
  timeControl: 'Classical',
  startDate: DateTime.utc(2027, 5, 25),
  endDate: DateTime.utc(2027, 6, 5),
);

EnhancedSearchResult _playerResults(String name, int fideId) {
  final player = SearchPlayer(
    id: '$fideId',
    name: name,
    fideId: fideId,
    rating: 2800,
    tournamentId: _event.id,
    tournamentName: _event.title,
  );
  return EnhancedSearchResult(
    tournamentResults: const [],
    playerResults: [
      SearchResult(
        tournament: _event,
        score: 1,
        matchedText: name,
        type: SearchResultType.player,
        player: player,
      ),
    ],
  );
}

/// Six players (four cards, two rows) and one event.
EnhancedSearchResult _najdorfResults() {
  return EnhancedSearchResult(
    tournamentResults: [
      SearchResult(
        tournament: _event,
        score: 1,
        matchedText: _event.title,
        type: SearchResultType.tournament,
      ),
    ],
    playerResults: [
      for (var i = 0; i < 6; i++)
        SearchResult(
          tournament: _event,
          score: 1,
          matchedText: 'Najdorf $i',
          type: SearchResultType.player,
          player: SearchPlayer(
            id: '${100000 + i}',
            name: 'Najdorf $i',
            fideId: 100000 + i,
            rating: 2600 - i,
            fed: 'ARG',
            tournamentId: _event.id,
            tournamentName: _event.title,
          ),
        ),
    ],
  );
}

final _liveEvent = GroupEventCardModel(
  id: 'live-1',
  title: 'Tata Steel Masters 2027',
  dates: 'Jan 17 - Feb 2, 2027',
  maxAvgElo: 2750,
  timeUntilStart: '',
  tourEventCategory: TourEventCategory.live,
  timeControl: 'Standard',
  startDate: DateTime.utc(2027, 1, 17),
  endDate: DateTime.utc(2027, 2, 2),
);

final _secondLiveEvent = GroupEventCardModel(
  id: 'live-2',
  title: 'Gibraltar Masters 2027',
  dates: 'Jan 20 - 29, 2027',
  maxAvgElo: 2580,
  timeUntilStart: '',
  tourEventCategory: TourEventCategory.live,
  timeControl: 'Standard',
  startDate: DateTime.utc(2027, 1, 20),
  endDate: DateTime.utc(2027, 1, 29),
);

const _topPlayers = [
  SearchPlayer(
    id: 'search_1503014',
    name: 'Carlsen, Magnus',
    title: 'GM',
    rating: 2833,
    fideId: 1503014,
    fed: 'NOR',
    tournamentId: 'player_search',
    tournamentName: 'Player Search',
  ),
  SearchPlayer(
    id: 'search_2016192',
    name: 'Nakamura, Hikaru',
    title: 'GM',
    rating: 2802,
    fideId: 2016192,
    fed: 'USA',
    tournamentId: 'player_search',
    tournamentName: 'Player Search',
  ),
  SearchPlayer(
    id: 'search_2020009',
    name: 'Caruana, Fabiano',
    title: 'GM',
    rating: 2795,
    fideId: 2020009,
    fed: 'USA',
    tournamentId: 'player_search',
    tournamentName: 'Player Search',
  ),
  SearchPlayer(
    id: 'search_35009192',
    name: 'Erigaisi Arjun',
    title: 'GM',
    rating: 2782,
    fideId: 35009192,
    fed: 'IND',
    tournamentId: 'player_search',
    tournamentName: 'Player Search',
  ),
];

/// How often each landing source was built.
class _Builds {
  int live = 0;
  int players = 0;
  int openings = 0;
  int upcoming = 0;
}

/// Live now pinned to [value].
class _FixedLiveNow extends SearchLiveNowNotifier {
  _FixedLiveNow(this.value, this.builds);

  final SearchLiveNow value;
  final _Builds? builds;

  @override
  SearchLiveNow build() {
    builds?.live++;
    return value;
  }
}

/// The real Live now, counted.
class _CountingLiveNow extends SearchLiveNowNotifier {
  _CountingLiveNow(this.builds);

  final _Builds? builds;

  @override
  SearchLiveNow build() {
    builds?.live++;
    return super.build();
  }
}

/// The real Live now over the live set [live], the Today feed [feed] and
/// the by-id lookup [repo].
List<Override> _realLive({
  required List<String> live,
  required List<GroupEventCardModel> feed,
  required _Broadcasts repo,
  _Builds? builds,
}) => [
  // The strict stream has not answered, so its mirror is the live set.
  liveGroupBroadcastIdsProvider.overrideWith(
    (ref) => const Stream<List<String>>.empty(),
  ),
  liveBroadcastIdsProvider.overrideWith((ref) => live),
  searchLandingFeedEventsProvider.overrideWith((ref) => feed),
  groupBroadcastRepositoryProvider.overrideWith((ref) => repo),
  searchLiveNowProvider.overrideWith(() => _CountingLiveNow(builds)),
];

/// A by-id lookup the test answers; the tours behind any event card's
/// long-press answer at once.
class _Broadcasts implements GroupBroadcastRepository {
  final calls = <List<String>>[];
  Completer<List<GroupBroadcast>>? pending;

  void answer(List<GroupBroadcast> broadcasts) => pending!.complete(broadcasts);

  @override
  Future<List<GroupBroadcast>> getGroupBroadcastsByIdsOrNames(
    List<String> identifiers,
  ) {
    calls.add(List.of(identifiers));
    return (pending = Completer<List<GroupBroadcast>>()).future;
  }

  @override
  Future<List<String>> getTourIdsForGroupBroadcast(String id) async => [
    '$id-tour',
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [_secondLiveEvent] as the lookup returns it.
final _secondLiveBroadcast = GroupBroadcast(
  id: _secondLiveEvent.id,
  createdAt: DateTime.utc(2026, 12),
  name: _secondLiveEvent.title,
  search: const [],
  maxAvgElo: _secondLiveEvent.maxAvgElo,
  timeControl: 'standard',
  dateStart: _secondLiveEvent.startDate,
  dateEnd: _secondLiveEvent.endDate,
);

/// The landing's openings, resolved by the opening search as the app does.
final _landingOpenings = resolveSearchLandingOpenings(
  searchLandingOpeningQueries,
);

final _resultsByQuery = {
  'carlsen': _playerResults('Carlsen, Magnus', 1503014),
  'nakamura': _playerResults('Nakamura, Hikaru', 2016192),
  'najdorf': _najdorfResults(),
};
