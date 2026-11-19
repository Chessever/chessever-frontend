import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/providers/board_settings_provider_new.dart';
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
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart'
    show SmartEventRequest;
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/screens/group_event/widget/player_search_cards.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/repository/supabase/chess_player/chess_player_repository.dart';
import 'package:chessever2/repository/gamebase/collections/collection_search_query.dart';
import 'package:chessever2/repository/gamebase/collections/collections_models.dart'
    show CollectionsPage;
import 'package:chessever2/screens/collections/collections_data.dart'
    show
        Collection,
        CollectionKind,
        CollectionsRepository,
        collectionsRepositoryProvider;
import 'package:chessever2/screens/feed/news/news_reader_pager.dart';
import 'package:chessever2/screens/library/widgets/library_context_menu.dart'
    show LibraryMenuAction;
import 'package:chessever2/widgets/page_back_row.dart';
import 'package:chessever2/screens/collections/collections_screen.dart'
    show CollectionCard, CollectionsScreen;
import 'package:chessever2/screens/favorites/provider/favorites_mode_provider.dart';
import 'package:chessever2/screens/favorites/rankings/ranking_filters.dart';
import 'package:chessever2/screens/feed/news/news_models.dart' show FeedNews;
import 'package:chessever2/screens/for_you/discovery/news_screen.dart'
    show NewsArticleCard, NewsScreen;
import 'package:chessever2/screens/group_event/providers/home_live_first_provider.dart'
    show homeEventsLiveFirstProvider;
import 'package:chessever2/screens/search/search_carousel.dart'
    show SearchCarouselPhysics;
import 'package:chessever2/screens/search/search_feeds.dart';
import 'package:chessever2/screens/search/search_landing_section.dart'
    show SearchLandingSection;
import 'package:chessever2/screens/search/search_landing.dart';
import 'package:chessever2/screens/search/sections/search_openings_page.dart';
import 'package:chessever2/screens/search/sections/search_section_pages.dart';
import 'package:chessever2/screens/search/sections/search_smart_events_page.dart';
import 'package:chessever2/screens/search/search_page_landing.dart';
import 'package:chessever2/screens/search/search_page_results.dart';
import 'package:chessever2/screens/search/search_page_sections.dart';
import 'package:chessever2/screens/tour_detail/games_tour/providers/event_no_spoilers_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/event_card/event_card.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart'
    show eventSpaceDraft;
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
  // Layout is measured in the app's own face, not the square test font,
  // whose figures run several times wider than any real line.
  setUpAll(() async {
    final fonts = FontLoader('InterDisplay');
    for (final weight in ['Regular', 'Medium', 'Bold']) {
      fonts.addFont(
        File(
          'assets/fonts/Inter-$weight.otf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await fonts.load();
  });

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
      collections: [_collection, _secondCollection],
      news: [_story, _secondStory],
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
        'in order, each a row of its cards', (tester) async {
      final app = await _pump(
        tester,
        size: const Size(393, 3600),
        recents: [RecentSearchEntry.tournament(_event)],
        live: [_liveEvent, _secondLiveEvent],
        players: () async => _topPlayers,
        openings: _landingOpenings,
        upcoming: [_upcomingEvent],
        collections: [_collection, _secondCollection],
        news: [_story, _secondStory],
      );
      expect(tester.takeException(), isNull);
      final landing = find.byKey(const ValueKey('search_landing'));
      expect(landing, findsOneWidget);

      final headings = [
        'Recent searches',
        'Live now',
        'Top players',
        'Openings',
        'Smart events',
        'Coming up',
        'Collections',
        'News',
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
      // A row: the second live event stands beside the first, peeking in
      // past the screen's edge.
      final firstLive = tester.getRect(
        find.byKey(ValueKey('search-live-${_liveEvent.id}')),
      );
      final secondLive = tester.getRect(
        find.byKey(ValueKey('search-live-${_secondLiveEvent.id}')),
      );
      expect(secondLive.top, firstLive.top);
      expect(secondLive.left, greaterThan(firstLive.right));
      expect(secondLive.left, lessThan(393));
      expect(secondLive.right, greaterThan(393));

      // Top players: the Events page's player cards, two to a card's room.
      final pair = find.byKey(const ValueKey('search-top-players-0'));
      expect(tester.widget<PlayerSearchCards>(pair).players, hasLength(2));
      expect(
        tester
            .widget<PlayerSearchCards>(
              find.byKey(const ValueKey('search-top-players-2')),
            )
            .players,
        hasLength(2),
      );
      expect(find.text('Magnus Carlsen'), findsOneWidget);

      // Openings and the built-in smart events: smart event cards, the
      // row cards side by side.
      for (final opening in _landingOpenings.take(2)) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey('opening-result-${opening.id}')),
            matching: find.byType(SmartEventCard),
          ),
          findsOneWidget,
          reason: opening.title,
        );
      }
      SmartEventCard preset(SmartEventRequest r) =>
          tester.widget<SmartEventCard>(
            find.descendant(
              of: find.byKey(ValueKey('search-smart-${r.tierLabel}')),
              matching: find.byType(SmartEventCard),
            ),
          );
      expect(preset(kSuperGmSmartPreset).stacked, isFalse);
      expect(preset(kGmSmartPreset).stacked, isFalse);
      final superGm = tester.getRect(
        find.byKey(ValueKey('search-smart-${kSuperGmSmartPreset.tierLabel}')),
      );
      final gm = tester.getRect(
        find.byKey(ValueKey('search-smart-${kGmSmartPreset.tierLabel}')),
      );
      expect(gm.top, superGm.top);
      expect(gm.left, greaterThan(superGm.right));

      // Collections: the Collections page's card. News: the News page's.
      expect(
        tester.widget(
          find.byKey(ValueKey('search-collection-${_collection.id}')),
        ),
        isA<CollectionCard>(),
      );
      expect(
        tester.widget(find.byKey(ValueKey('search-news-${_story.key}'))),
        isA<NewsArticleCard>(),
      );

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

    testWidgets('the Top players title opens Rankings; no See all is left', (
      tester,
    ) async {
      final observer = _PushObserver();
      final app = await _pump(
        tester,
        players: () async => _topPlayers,
        observer: observer,
      );
      expect(find.textContaining('See all', findRichText: true), findsNothing);
      await tester.tap(find.byKey(const ValueKey('search-top-players-open')));
      await tester.pump();
      final page = observer.lastPage(tester);
      expect(page, isA<FavoritesTabScreen>());
      expect(
        (page as FavoritesTabScreen).initialMode,
        FavoritesScreenMode.players,
      );
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
      // Opened from Search it is exactly what was searched: no Filters.
      expect(screen.showFilters, isFalse);
      await app.dispose();
    });

    for (final preset in [kSuperGmSmartPreset, kGmSmartPreset]) {
      testWidgets('a built-in smart event opens itself, without Filters '
          '(${preset.displayName})', (tester) async {
        final observer = _PushObserver();
        final app = await _pump(tester, observer: observer);
        final card = find.byKey(ValueKey('search-smart-${preset.tierLabel}'));
        // Along the row: brought into view first.
        await tester.ensureVisible(card);
        await tester.pump();
        await tester.tap(card);
        await tester.pump();
        final screen = observer.lastPage(tester);
        expect(screen, isA<SmartEventScreen>());
        screen as SmartEventScreen;
        expect(screen.request.criteriaKey, preset.criteriaKey);
        expect(screen.showFilters, isFalse);
        await app.dispose();
      });
    }

    testWidgets('an event starred here is kept in My Space too; an unstar '
        'leaves it there', (tester) async {
      final favorites = _RecordingFavoriteEvents();
      final app = await _pump(
        tester,
        live: [_liveEvent],
        favorites: () => favorites,
      );
      final key = eventSpaceDraft(_liveEvent).key;
      expect(app.read(spaceShortcutExistsProvider(key)), isFalse);
      final star = find.descendant(
        of: find.byKey(ValueKey('search-live-${_liveEvent.id}')),
        matching: find.bySemanticsLabel('Favorite Icon'),
      );
      expect(star, findsOneWidget);

      await tester.tap(star);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(favorites.toggles, [_liveEvent.id]);
      expect(app.read(spaceShortcutExistsProvider(key)), isTrue);
      expect(find.text('Added to My Space'), findsOneWidget);

      await tester.tap(star);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(favorites.toggles, [_liveEvent.id, _liveEvent.id]);
      expect(app.read(spaceShortcutExistsProvider(key)), isTrue);
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
        // A row's first card starts on the gutter, nine tenths of the
        // row wide: the next card peeks in past the field's end.
        final row = field.width;
        for (final card in [
          find.byKey(ValueKey('search-live-${_liveEvent.id}')),
          find.byKey(const ValueKey('search-top-players-0')),
          find.byKey(ValueKey('opening-result-${_landingOpenings[0].id}')),
        ]) {
          final rect = tester.getRect(card);
          expect(rect.left, closeTo(field.left, 0.01));
          expect(
            rect.width,
            closeTo((row + searchCardGap) / 1.1 - searchCardGap, 0.01),
          );
        }
        // Cards of a row side by side, a card's gap apart, tops and
        // bottoms in line, the second past the field's end.
        final a = tester.getRect(
          find.byKey(ValueKey('opening-result-${_landingOpenings[0].id}')),
        );
        final b = tester.getRect(
          find.byKey(ValueKey('opening-result-${_landingOpenings[1].id}')),
        );
        expect(b.left, closeTo(a.right + searchCardGap, 0.01));
        expect(b.right, greaterThan(field.right));
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
  group('the sections: a row each, its own page, opened in place', () {
    /// Every section the landing shows, as the fixtures hold them.
    Future<_App> pumpAll(
      WidgetTester tester, {
      Size size = const Size(393, 3600),
      NavigatorObserver? observer,
      bool reduceMotion = false,
      bool chrome = false,
      EdgeInsets padding = EdgeInsets.zero,
      _Ranking? ranking,
    }) => _pump(
      tester,
      size: size,
      live: [_liveEvent, _secondLiveEvent],
      players: () async => _topPlayers,
      openings: _landingOpenings,
      upcoming: [_upcomingEvent, _secondUpcomingEvent],
      collections: [_collection, _secondCollection],
      news: [_story, _secondStory],
      observer: observer,
      reduceMotion: reduceMotion,
      chrome: chrome,
      padding: padding,
      ranking: ranking,
    );

    testWidgets('every title but Recent searches is a button: its words and '
        'a chevron, 44pt tall, heard as a heading that opens its page; no '
        'See all is left', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await _pump(
        tester,
        size: const Size(393, 3600),
        recents: [RecentSearchEntry.tournament(_event)],
        live: [_liveEvent],
        players: () async => _topPlayers,
        openings: _landingOpenings,
        upcoming: [_upcomingEvent],
        collections: [_collection],
        news: [_story],
      );
      for (final section in SearchSectionId.values) {
        final button = find.byKey(ValueKey('search-${section.slug}-open'));
        expect(button, findsOneWidget, reason: section.title);
        expect(
          find.descendant(of: button, matching: find.text(section.title)),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: button,
            matching: find.byIcon(Icons.chevron_right_rounded),
          ),
          findsOneWidget,
          reason: section.title,
        );
        expect(
          tester.getSize(button).height,
          greaterThanOrEqualTo(44),
          reason: section.title,
        );
        expect(
          tester.getSemantics(button),
          containsSemantics(
            label: 'Open ${section.title}',
            isButton: true,
            isHeader: true,
            hasTapAction: true,
          ),
          reason: section.title,
        );
        // The title starts on the page's gutter, as the field does.
        expect(
          tester.getTopLeft(find.text(section.title)).dx,
          closeTo(HomeTopBarMetrics.horizontalPadding, 0.01),
        );
      }
      // Recent searches is a heading, not a way anywhere.
      expect(find.text('Recent searches'), findsOneWidget);
      expect(find.byKey(const ValueKey('search-recent-open')), findsNothing);
      expect(find.textContaining('See all', findRichText: true), findsNothing);
      semantics.dispose();
      await app.dispose();
    });

    for (final (section, check)
        in <(SearchSectionId, void Function(_App, Route<dynamic>, Widget))>[
          (
            SearchSectionId.liveNow,
            (app, route, page) {
              expect(page, isA<GroupEventScreen>());
              expect(
                app.read(selectedGroupCategoryProvider),
                GroupEventCategory.current,
              );
              expect(app.read(homeEventsLiveFirstProvider), isTrue);
            },
          ),
          (
            SearchSectionId.topPlayers,
            (app, route, page) {
              expect(page, isA<FavoritesTabScreen>());
              expect(
                (page as FavoritesTabScreen).initialMode,
                FavoritesScreenMode.players,
              );
            },
          ),
          (
            SearchSectionId.openings,
            (app, route, page) {
              expect(page, isA<SearchOpeningsPage>());
            },
          ),
          (
            SearchSectionId.smartEvents,
            (app, route, page) {
              expect(page, isA<SearchSmartEventsPage>());
            },
          ),
          (
            SearchSectionId.comingUp,
            (app, route, page) {
              expect(page, isA<GroupEventScreen>());
              expect(
                app.read(selectedGroupCategoryProvider),
                GroupEventCategory.upcoming,
              );
              // Coming up never turns Live first on.
              expect(app.read(homeEventsLiveFirstProvider), isFalse);
            },
          ),
          (
            SearchSectionId.collections,
            (app, route, page) {
              expect(page, isA<CollectionsScreen>());
            },
          ),
          (
            SearchSectionId.news,
            (app, route, page) {
              expect(page, isA<NewsScreen>());
              expect(route.settings.name, '/news');
            },
          ),
        ]) {
      testWidgets('the ${section.title} title opens its page', (tester) async {
        final observer = _PushObserver();
        final app = await pumpAll(tester, observer: observer);
        await tester.tap(find.byKey(ValueKey('search-${section.slug}-open')));
        // Pushed, not built here: the destinations are whole screens.
        check(app, observer.pushed.last, observer.lastPage(tester));
        await app.dispose();
      });
    }

    testWidgets('Live now lists live events first on its Events page only: '
        'closed, Live first is as it was (Home\'s Today too), unless the '
        'reader pressed it there', (tester) async {
      final observer = _PushObserver();
      final app = await pumpAll(tester, observer: observer);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      final flag = app.read(homeEventsLiveFirstProvider.notifier);
      final title = find.byKey(const ValueKey('search-live-open'));
      // Closed without pushing the destination's own backends: removed.
      Future<void> close() async {
        navigator.removeRoute(observer.pushed.last);
        await tester.pump();
      }

      await tester.tap(title);
      expect(flag.state, isTrue);
      await close();
      expect(flag.state, isFalse);

      // Pressed off and on again on the Events page: the reader's now.
      await tester.tap(title);
      flag.state = false;
      flag.state = true;
      await close();
      expect(flag.state, isTrue);

      // Already on when the page opened: left on.
      await tester.tap(title);
      expect(flag.state, isTrue);
      await close();
      expect(flag.state, isTrue);
      await app.dispose();
    });

    testWidgets('See more opens a section in place, its cards down the page, '
        'growing on a spring with every card drawn; Show less folds it back '
        'on the spring', (tester) async {
      final app = await pumpAll(tester, size: const Size(393, 2400));
      final first = find.byKey(const ValueKey('search-top-players-0'));
      final second = find.byKey(const ValueKey('search-top-players-2'));
      final below = find.text('Openings');
      // Folded: a row, the second card beside the first.
      expect(tester.getTopLeft(second).dy, tester.getTopLeft(first).dy);
      final folded = tester.getTopLeft(below).dy;

      await tester.tap(_toggle('top-players-expand'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final growing = tester.getTopLeft(below).dy;
      // Growing, the cards are there whole: nothing waits on an entrance.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('search_landing')),
          matching: find.byWidgetPredicate(
            (w) => w is Opacity && w.opacity == 0,
          ),
        ),
        findsNothing,
      );
      await _frames(tester);
      final open = tester.getTopLeft(below).dy;
      expect(growing, greaterThan(folded));
      expect(growing, lessThan(open));
      // Down the page: the second card under the first, on the same
      // gutter; Show less at the end and in the head.
      expect(
        tester.getTopLeft(second).dy,
        greaterThan(tester.getBottomLeft(first).dy),
      );
      expect(tester.getTopLeft(second).dx, tester.getTopLeft(first).dx);
      expect(
        find.byKey(const ValueKey('search-top-players-expand')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('search-top-players-fold')),
        findsOneWidget,
      );
      final collapse = find.byKey(
        const ValueKey('search-top-players-collapse'),
      );
      expect(collapse, findsOneWidget);
      expect(
        find.descendant(of: collapse, matching: find.text('Show less')),
        findsOneWidget,
      );
      expect(app.read(searchExpandedSectionsProvider), {'top-players'});

      await tester.tap(_toggle('top-players-collapse'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final folding = tester.getTopLeft(below).dy;
      expect(folding, lessThan(open));
      expect(folding, greaterThan(folded));
      await _frames(tester);
      expect(tester.getTopLeft(below).dy, closeTo(folded, 0.5));
      expect(tester.getTopLeft(second).dy, tester.getTopLeft(first).dy);
      expect(
        find.byKey(const ValueKey('search-top-players-expand')),
        findsOneWidget,
      );
      expect(app.read(searchExpandedSectionsProvider), isEmpty);
      await app.dispose();
    });

    testWidgets('under reduced motion a section opens and folds at once', (
      tester,
    ) async {
      final app = await pumpAll(
        tester,
        size: const Size(393, 2400),
        reduceMotion: true,
      );
      final first = find.byKey(const ValueKey('search-top-players-0'));
      final second = find.byKey(const ValueKey('search-top-players-2'));
      await tester.tap(_toggle('top-players-expand'));
      await tester.pump();
      expect(
        tester.getTopLeft(second).dy,
        greaterThan(tester.getBottomLeft(first).dy),
      );
      await tester.tap(_toggle('top-players-collapse'));
      await tester.pump();
      expect(tester.getTopLeft(second).dy, tester.getTopLeft(first).dy);
      await app.dispose();
    });

    testWidgets('Show less far down an opened section springs the page back '
        'to its head, then folds there', (tester) async {
      final ranking = _Ranking(
        pages: [
          for (var p = 0; p < 4; p++)
            _rankedPage(searchLandingPlayerCount + p * searchPlayersPageSize),
        ],
      );
      final app = await _pump(
        tester,
        players: () async => _topPlayers,
        ranking: ranking,
      );
      await tester.tap(_toggle('top-players-expand'));
      await tester.pump();
      await tester.pump();
      await _frames(tester);
      final page = _landingPosition(tester);
      for (var i = 0; i < 8; i++) {
        page.jumpTo(page.maxScrollExtent);
        await _frames(tester, 10);
      }
      expect(app.read(searchTopPlayersFeedProvider).hasMore, isFalse);
      final collapse = find.byKey(
        const ValueKey('search-top-players-collapse'),
      );
      await tester.ensureVisible(collapse);
      await tester.pump();
      final from = page.pixels;
      final head = find.byKey(const ValueKey('search-top-players-open'));
      final top = tester.getTopLeft(
        find.byKey(const ValueKey('search_landing')),
      );
      // Far down: the head is screens above.
      expect(from, greaterThan(2000));

      await tester.tap(_toggle('top-players-collapse'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      // On the way back, never there in one frame.
      expect(page.pixels, lessThan(from));
      expect(page.pixels, greaterThan(from / 2));
      expect(app.read(searchExpandedSectionsProvider), {'top-players'});
      await _frames(tester, 120);
      // At the head, the section folded under it.
      expect(page.pixels, closeTo(0, 0.5));
      expect(tester.getTopLeft(head).dy, greaterThanOrEqualTo(top.dy));
      expect(app.read(searchExpandedSectionsProvider), isEmpty);
      expect(
        find.byKey(const ValueKey('search-top-players-expand')),
        findsOneWidget,
      );
      await app.dispose();
    });

    testWidgets('Top players never draws a player alone while more of the '
        'ranking is coming; once it is spent, a last player alone stands '
        'clear of See more', (tester) async {
      final named = _rankedPage(searchLandingPlayerCount);
      final ranking = _Ranking(
        pages: [
          // A nameless row, read and skipped: the page lands odd.
          [
            ...named.take(searchPlayersPageSize - 1),
            const ChessPlayer(fideid: 8999999, name: ' ', country: 'NOR'),
          ],
          // The end of the ranking, odd again over all.
          _rankedPage(
            searchLandingPlayerCount + searchPlayersPageSize,
          ).take(4).toList(),
        ],
      );
      final app = await _pump(
        tester,
        players: () async => _topPlayers,
        ranking: ranking,
      );
      List<List<SearchPlayer>> cards() => tester
          .widget<SearchLandingSection<List<SearchPlayer>>>(
            find.byWidgetPredicate(
              (w) => w is SearchLandingSection<List<SearchPlayer>>,
            ),
          )
          .items;
      expect(ranking.offsets, [searchLandingPlayerCount]);
      expect(app.read(searchTopPlayersFeedProvider).items, hasLength(15));
      // The fifteenth waits for the next page.
      expect(cards(), hasLength(7));
      expect(cards().every((pair) => pair.length == 2), isTrue);

      // The row read to its end (its extent known once it lays out there).
      final row = _rowPosition(tester, 'top-players');
      for (var i = 0; i < 3 && ranking.offsets.length < 2; i++) {
        row.jumpTo(row.maxScrollExtent);
        await tester.pump();
        await tester.pump();
      }
      expect(ranking.offsets, [
        searchLandingPlayerCount,
        searchLandingPlayerCount + searchPlayersPageSize,
      ]);
      expect(app.read(searchTopPlayersFeedProvider).hasMore, isFalse);
      expect(cards(), hasLength(10));
      expect(cards().last, hasLength(1));
      row.jumpTo(row.maxScrollExtent);
      await tester.pump();
      final lone = find.byKey(const ValueKey('search-top-players-18'));
      expect(lone, findsOneWidget);
      expect(
        tester.getRect(lone).bottom,
        lessThanOrEqualTo(
          tester
              .getRect(find.byKey(const ValueKey('search-top-players-expand')))
              .top,
        ),
      );
      expect(tester.takeException(), isNull);
      await app.dispose();
    });

    testWidgets('a row snaps to its cards\' new width once it changes (a '
        'rotation, split view)', (tester) async {
      final app = await pumpAll(tester, size: const Size(393, 3600));
      double slot() =>
          (_rowPosition(tester, 'live').physics as SearchCarouselPhysics).slot;
      final before = slot();
      tester.view.physicalSize = const Size(430, 3600) * 2;
      await tester.pump();
      await tester.pump();
      expect(slot(), greaterThan(before));
      expect(
        const SearchCarouselPhysics(
          slot: 300,
        ).shouldUpdate(const SearchCarouselPhysics(slot: 300)),
        isFalse,
      );
      await app.dispose();
    });

    testWidgets('a section left open while a search was typed and cleared is '
        'still open, and folds back on the spring', (tester) async {
      final app = await pumpAll(tester, size: const Size(393, 2400));
      final below = find.text('Openings');
      final folded = tester.getTopLeft(below).dy;
      await tester.tap(_toggle('top-players-expand'));
      await tester.pump();
      await tester.pump();
      await _frames(tester);
      final open = tester.getTopLeft(below).dy;

      await _type(tester, const ValueKey('search_tab_field'), 'nakamura');
      expect(find.byKey(const ValueKey('search_landing')), findsNothing);
      await _type(tester, const ValueKey('search_tab_field'), '');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(tester.getTopLeft(below).dy, closeTo(open, 0.5));

      await tester.tap(_toggle('top-players-collapse'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final folding = tester.getTopLeft(below).dy;
      expect(folding, lessThan(open));
      expect(folding, greaterThan(folded));
      await _frames(tester);
      expect(tester.getTopLeft(below).dy, closeTo(folded, 0.5));
      expect(
        find.byKey(const ValueKey('search-top-players-expand')),
        findsOneWidget,
      );
      await app.dispose();
    });

    testWidgets('a row reads on as it nears its end: a card-sized slot with a '
        'quiet spinner while a page loads, a quiet retry card when one '
        'fails, and See more, opening the page, once the source is spent', (
      tester,
    ) async {
      final ranking = _Ranking(pages: [_rankedPage(searchLandingPlayerCount)])
        ..hold = Completer<void>();
      final observer = _PushObserver();
      final app = await _pump(
        tester,
        players: () async => _topPlayers,
        openings: _landingOpenings,
        ranking: ranking,
        observer: observer,
      );
      // Two cards of four players: the row's end is near at once, so the
      // ranking is read on from where the head stopped.
      expect(ranking.offsets, [searchLandingPlayerCount]);
      final card = tester.getSize(
        find.byKey(const ValueKey('search-top-players-0')),
      );
      final row = _rowPosition(tester, 'top-players');
      row.jumpTo(row.maxScrollExtent);
      await tester.pump();
      final slot = find.byKey(const ValueKey('search-top-players-pending'));
      expect(slot, findsOneWidget);
      expect(tester.getSize(slot), card);
      expect(
        find.descendant(
          of: slot,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      final openings = tester.getTopLeft(find.text('Openings')).dy;
      final at = row.pixels;

      ranking.hold!.complete();
      ranking.hold = null;
      await tester.pump();
      await tester.pump();
      // The page lands where the slot stood: nothing on screen moves.
      expect(row.pixels, at);
      expect(tester.getTopLeft(find.text('Openings')).dy, openings);
      expect(
        find.byKey(const ValueKey('search-top-players-4')),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('search-top-players-4'))),
        card,
      );

      ranking.fail = true;
      row.jumpTo(row.maxScrollExtent);
      await tester.pump();
      await tester.pump();
      expect(ranking.offsets, [
        searchLandingPlayerCount,
        searchLandingPlayerCount + searchPlayersPageSize,
      ]);
      final retry = find.byKey(const ValueKey('search-top-players-retry'));
      expect(retry, findsOneWidget);
      expect(tester.getSize(retry), card);
      expect(find.text("Couldn't load more"), findsOneWidget);

      await tester.tap(retry);
      await tester.pump();
      await tester.pump();
      expect(ranking.offsets, hasLength(3));
      expect(ranking.offsets.last, ranking.offsets[1]);
      final seeMore = find.byKey(const ValueKey('search-top-players-see-more'));
      expect(seeMore, findsOneWidget);
      expect(tester.getSize(seeMore), card);
      await tester.tap(seeMore);
      expect(observer.lastPage(tester), isA<FavoritesTabScreen>());
      await app.dispose();
    });

    testWidgets('opened in place, a section reads on down the page as the '
        'reader nears its end, a quiet line to try again when a page fails', (
      tester,
    ) async {
      final ranking = _Ranking(
        pages: [
          _rankedPage(searchLandingPlayerCount),
          _rankedPage(searchLandingPlayerCount + searchPlayersPageSize),
        ],
      );
      final app = await _pump(
        tester,
        players: () async => _topPlayers,
        ranking: ranking,
        reduceMotion: true,
      );
      // The row asked for one page on its own (its end was near).
      expect(ranking.offsets, [searchLandingPlayerCount]);
      await tester.tap(_toggle('top-players-expand'));
      await _frames(tester, 10);
      final page = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('search_landing')),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      ranking.fail = true;
      final asked = ranking.offsets.length;
      page.jumpTo(page.maxScrollExtent);
      await _frames(tester, 10);
      expect(ranking.offsets, hasLength(asked + 1));
      final line = find.byKey(const ValueKey('search-top-players-rows-retry'));
      expect(line, findsOneWidget);
      expect(tester.getSize(line).height, greaterThanOrEqualTo(44));
      expect(find.text("Couldn't load more"), findsOneWidget);

      await tester.tap(line);
      await _frames(tester, 10);
      // The page that failed, asked for again from where it was.
      expect(ranking.offsets, hasLength(asked + 2));
      expect(ranking.offsets.last, ranking.offsets[asked]);
      expect(line, findsNothing);
      page.jumpTo(page.maxScrollExtent);
      await _frames(tester, 10);
      // Every page in, each player once; the source spent, nothing turns.
      final feed = app.read(searchTopPlayersFeedProvider);
      expect(feed.hasMore, isFalse);
      expect(
        feed.items.length,
        greaterThan(searchLandingPlayerCount + searchPlayersPageSize),
      );
      expect(
        feed.items.map((p) => p.fideId).toSet(),
        hasLength(feed.items.length),
      );
      expect(
        find.byKey(const ValueKey('search-top-players-rows-pending')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('search-top-players-collapse')),
        findsOneWidget,
      );
      await app.dispose();
    });

    testWidgets('text at 1.3x on a 375pt phone: event, player and smart '
        'event cards lay out whole in their rows', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final app = await pumpAll(tester, size: const Size(375, 3600));
      expect(tester.takeException(), isNull);
      await app.dispose();
    });

    testWidgets('a row of a fixed set ends in See more, opening its page', (
      tester,
    ) async {
      final observer = _PushObserver();
      final app = await _pump(tester, observer: observer);
      final row = _rowPosition(tester, 'smart');
      row.jumpTo(row.maxScrollExtent);
      await tester.pump();
      // Every built-in smart event is in the row, the last one beside it.
      expect(
        find.byKey(
          ValueKey('search-smart-${searchSmartEventRequests.last.tierLabel}'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('search-smart-see-more')));
      expect(observer.lastPage(tester), isA<SearchSmartEventsPage>());
      await app.dispose();
    });

    testWidgets('a row scrolled sideways never moves the bars; the page '
        'scrolled down does', (tester) async {
      final app = await pumpAll(
        tester,
        size: const Size(393, 852),
        chrome: true,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      final chrome = app.chrome!;
      expect(chrome.value, 1);
      await tester.drag(
        find.byKey(ValueKey('search-live-${_liveEvent.id}')),
        const Offset(-260, 0),
      );
      await _frames(tester);
      expect(_rowPosition(tester, 'live').pixels, greaterThan(0));
      expect(chrome.value, 1);

      await tester.drag(find.text('Top players'), const Offset(0, -300));
      await _frames(tester);
      expect(chrome.value, lessThan(1));
      await app.dispose();
    });

    // Each card's menu, exactly as its own page holds it: the Events
    // list's event menu, the player menu, the smart event's, the
    // Collections page's; the News page's card has none.
    const eventMenu = {
      'Open event',
      'Turn on No Spoilers',
      'Share',
      'Copy PGN',
      'Add to My Space',
    };
    final menus = <(String, Finder Function(), Set<String>)>[
      (
        'live',
        () => find.byKey(ValueKey('search-live-${_liveEvent.id}')),
        eventMenu,
      ),
      (
        'top-players',
        () => find.text('Magnus Carlsen'),
        const {'Open profile', 'Share profile'},
      ),
      (
        'openings',
        () =>
            find.byKey(ValueKey('opening-result-${_landingOpenings.first.id}')),
        const {'Open smart event', 'Add to My Space'},
      ),
      (
        'smart',
        () => find.byKey(
          ValueKey('search-smart-${kSuperGmSmartPreset.tierLabel}'),
        ),
        const {'Open smart event', 'Add to My Space'},
      ),
      (
        'upcoming',
        // Soonest first: the row's first card.
        () =>
            find.byKey(ValueKey('search-upcoming-${_secondUpcomingEvent.id}')),
        eventMenu,
      ),
      (
        'collections',
        () => find.byKey(ValueKey('search-collection-${_collection.id}')),
        const {'Open', 'Share', 'Add to My Space'},
      ),
      (
        'news',
        () => find.byKey(ValueKey('search-news-${_story.key}')),
        const <String>{},
      ),
    ];
    for (final (slug, card, labels) in menus) {
      for (final inPlace in [false, true]) {
        testWidgets('$slug ${inPlace ? 'opened in place' : 'in its row'}: '
            'a long-press is the card\'s own menu', (tester) async {
          final observer = _PushObserver();
          final app = await pumpAll(
            tester,
            reduceMotion: true,
            observer: observer,
          );
          if (inPlace) {
            await tester.tap(_toggle('$slug-expand'));
            await tester.pump();
            expect(
              find.byKey(ValueKey('search-$slug-collapse')),
              findsOneWidget,
            );
          }
          expect(card(), findsOneWidget);
          await tester.longPress(card());
          await _frames(tester);
          expect(_menuLabels(tester), labels);
          // (The News page's card has no menu: held and let go, it opens
          // the story, as it does there.)
          // Nothing the Search tab adds of its own.
          expect(find.text('Remove from recent searches'), findsNothing);
          await app.dispose();
        });
      }
    }

    testWidgets('a story opens the reader on it, paging on through the same '
        'stories', (tester) async {
      final observer = _PushObserver();
      final app = await pumpAll(tester, observer: observer);
      await tester.tap(find.byKey(ValueKey('search-news-${_secondStory.key}')));
      final reader = observer.lastPage(tester);
      expect(reader, isA<NewsReaderPager>());
      reader as NewsReaderPager;
      expect(reader.articles.map((n) => n.key), [_story.key, _secondStory.key]);
      expect(reader.initialIndex, 1);
      await app.dispose();
    });

    testWidgets('after a page of stories failed, the reader\'s Retry reads it '
        'again', (tester) async {
      final feed = _FlakyNews([_story], [_secondStory]);
      final observer = _PushObserver();
      final app = await _pump(tester, newsFeed: () => feed, observer: observer);
      // The row asked for the next page on its own, and it failed.
      expect(feed.reads, 1);
      expect(app.read(searchNewsFeedProvider).failed, isTrue);
      await tester.tap(find.byKey(ValueKey('search-news-${_story.key}')));
      final reader = observer.lastPage(tester) as NewsReaderPager;
      expect(reader.hasMore!(), isTrue);
      final stories = await reader.loadMore!();
      expect(feed.reads, 2);
      expect(stories.map((n) => n.key), [_story.key, _secondStory.key]);
      expect(app.read(searchNewsFeedProvider).failed, isFalse);
      await app.dispose();
    });

    testWidgets('Openings, its own page: the pushed page\'s back row, the '
        'half cards, each with its own long-press', (tester) async {
      final app = await pumpAll(tester, size: const Size(393, 852));
      await tester.tap(find.byKey(const ValueKey('search-openings-open')));
      await _frames(tester);
      expect(find.byType(SearchOpeningsPage), findsOneWidget);
      expect(find.byType(PageBackRow), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PageBackRow),
          matching: find.text('Openings'),
        ),
        findsOneWidget,
      );
      final first = find.byKey(
        ValueKey('search-openings-page-${_landingOpenings.first.id}'),
      );
      expect(first, findsOneWidget);
      final card = tester.widget<SmartEventCard>(
        find.descendant(of: first, matching: find.byType(SmartEventCard)),
      );
      expect(card.stacked, isTrue);
      await tester.longPress(first);
      await _frames(tester);
      expect(_menuLabels(tester), const {
        'Open smart event',
        'Add to My Space',
      });
      await app.dispose();
    });

    testWidgets('Smart events, its own page: every built-in smart event, each '
        'with its own long-press, the last clear of the bottom inset', (
      tester,
    ) async {
      const inset = 90.0;
      final app = await pumpAll(
        tester,
        size: const Size(393, 852),
        padding: const EdgeInsets.only(bottom: inset),
      );
      await tester.tap(find.byKey(const ValueKey('search-smart-open')));
      await _frames(tester);
      expect(find.byType(SearchSmartEventsPage), findsOneWidget);
      final list = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byType(SearchSmartEventsPage),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      list.jumpTo(list.maxScrollExtent);
      await tester.pump();
      final last = find.byKey(
        ValueKey(
          'search-smart-page-${searchSmartEventRequests.last.tierLabel}',
        ),
      );
      expect(last, findsOneWidget);
      expect(tester.getRect(last).bottom, lessThanOrEqualTo(852 - inset));
      list.jumpTo(0);
      await tester.pump();
      await tester.longPress(
        find.byKey(
          ValueKey(
            'search-smart-page-${searchSmartEventRequests.first.tierLabel}',
          ),
        ),
      );
      await _frames(tester);
      expect(_menuLabels(tester), const {
        'Open smart event',
        'Add to My Space',
      });
      await app.dispose();
    });

    testWidgets('the landing, and a section opened in place, end clear of '
        'the floating dock\'s inset', (tester) async {
      const inset = 90.0;
      final app = await pumpAll(
        tester,
        size: const Size(393, 852),
        padding: const EdgeInsets.only(bottom: inset),
        reduceMotion: true,
      );
      final page = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const ValueKey('search_landing')),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      page.jumpTo(page.maxScrollExtent);
      await tester.pump();
      final last = find.byKey(const ValueKey('search-news-expand'));
      expect(last, findsOneWidget);
      expect(tester.getRect(last).bottom, lessThanOrEqualTo(852 - inset));

      await tester.tap(_toggle('news-expand'));
      await tester.pump();
      page.jumpTo(page.maxScrollExtent);
      await tester.pump();
      final end = find.byKey(const ValueKey('search-news-collapse'));
      expect(end, findsOneWidget);
      expect(tester.getRect(end).bottom, lessThanOrEqualTo(852 - inset));
      await app.dispose();
    });

    testWidgets('results: an event, an opening and a player card each keep '
        'their own long-press', (tester) async {
      final app = await _pump(tester, size: const Size(393, 4000));
      await _type(tester, const ValueKey('search_tab_field'), 'najdorf');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      for (final (card, labels) in <(Finder, Set<String>)>[
        (find.byKey(ValueKey('search-event-${_event.id}')), eventMenu),
        (
          find.byKey(const ValueKey('search-player-100005')),
          // Rankings' row menu: the shared player menu, then the heart's.
          const {'Open profile', 'Share profile', 'Add to favorites'},
        ),
        (
          find.byKey(
            ValueKey(
              'opening-result-'
              '${searchOpeningSuggestions('Najdorf', limit: 1).single.id}',
            ),
          ),
          const {'Open smart event', 'Add to My Space'},
        ),
      ]) {
        expect(card, findsOneWidget);
        await tester.longPress(card);
        await _frames(tester);
        expect(_menuLabels(tester), labels);
        // Closed by a tap on the veil.
        await tester.tapAt(const Offset(4, 4));
        await _frames(tester);
      }
      await app.dispose();
    });
  });

  group('the sections\' sources', () {
    test('Collections reads the catalog a page at a time, never the whole '
        'of it', () async {
      final repository = _PagedCollections(total: 90);
      final container = ProviderContainer(
        overrides: [
          collectionsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      container.listen(searchCollectionsFeedProvider, (_, __) {});
      expect(container.read(searchCollectionsFeedProvider).ready, isFalse);
      await pumpEventQueue();
      var feed = container.read(searchCollectionsFeedProvider);
      expect(feed.items, hasLength(40));
      expect(feed.hasMore, isTrue);
      await container.read(searchCollectionsFeedProvider.notifier).loadMore();
      await container.read(searchCollectionsFeedProvider.notifier).loadMore();
      feed = container.read(searchCollectionsFeedProvider);
      expect(repository.offsets, [0, 40, 80]);
      expect(feed.items, hasLength(90));
      expect(feed.hasMore, isFalse);
    });

    test('Coming up keeps every card it has listed when the upcoming view '
        'is read again, and reads on from where it stopped', () async {
      final read = [
        for (var i = 0; i < searchUpcomingReadLimit; i++) _upcomingNumbered(i),
      ];
      final broadcasts = _Broadcasts();
      final container = ProviderContainer(
        overrides: [
          searchUpcomingProvider.overrideWith((ref) async => List.of(read)),
          searchLiveIdsKeyProvider.overrideWith((ref) => ''),
          groupBroadcastRepositoryProvider.overrideWith((ref) => broadcasts),
        ],
      );
      addTearDown(container.dispose);
      container.listen(searchUpcomingProvider, (_, __) {});
      container.listen(searchComingUpFeedProvider, (_, __) {});
      await pumpEventQueue();
      final notifier = container.read(searchComingUpFeedProvider.notifier);
      expect(
        container.read(searchComingUpFeedProvider).items,
        hasLength(searchLandingUpcomingLimit),
      );
      await notifier.loadMore();
      final listed = [
        for (final event in container.read(searchComingUpFeedProvider).items)
          event.id,
      ];
      expect(listed, hasLength(searchUpcomingReadLimit));

      // Read again (one of them started, or the read grew old): the same
      // events, a new read.
      container.invalidate(searchUpcomingProvider);
      await pumpEventQueue();
      final feed = container.read(searchComingUpFeedProvider);
      expect([for (final event in feed.items) event.id], listed);
      expect(feed.hasMore, isTrue);
      await container.read(searchComingUpFeedProvider.notifier).loadMore();
      expect(broadcasts.upcomingOffsets, [searchUpcomingReadLimit]);
    });

    test('a page that lands after the source was read again is dropped, and '
        'moves no cursor', () async {
      final repository = _PagedCollections(total: 200)..hold = Completer();
      final container = ProviderContainer(
        overrides: [
          collectionsRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      container.listen(searchCollectionsFeedProvider, (_, __) {});
      await pumpEventQueue();
      // The first read is held; the source is read again meanwhile.
      container.invalidate(searchCollectionsFeedProvider);
      container.read(searchCollectionsFeedProvider);
      repository.hold!.complete();
      repository.hold = null;
      await pumpEventQueue();
      await container.read(searchCollectionsFeedProvider.notifier).loadMore();
      expect(repository.offsets, [0, 0, 40]);
      final ids = container
          .read(searchCollectionsFeedProvider)
          .items
          .map((c) => c.id);
      expect(ids, hasLength(80));
      expect(ids.toSet(), hasLength(80));
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
  FavoriteEventsNotifier Function()? favorites,
  List<Collection> collections = const [],
  List<FeedNews> news = const [],
  SearchNewsFeed Function()? newsFeed,
  _Ranking? ranking,
  bool reduceMotion = false,
  EdgeInsets padding = EdgeInsets.zero,
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
        searchCollectionsFeedProvider.overrideWith(
          () => _FixedCollections(collections),
        ),
        searchNewsFeedProvider.overrideWith(newsFeed ?? () => _FixedNews(news)),
        searchOpeningCatalogLoaderProvider.overrideWithValue(
          () async => searchOpeningCatalog(null),
        ),
        chessPlayerRepositoryProvider.overrideWithValue(ranking ?? _Ranking()),
        discoverySmartEventMembersProvider.overrideWith(
          (ref, criteria) async => const <GroupEventCardModel>[],
        ),
        favoriteEventsProvider.overrideWith(favorites ?? _NoFavoriteEvents.new),
        favoritePlayersProviderNew.overrideWith(_NoFavoritePlayers.new),
        spaceShortcutsProvider.overrideWith(_MemorySpaceShortcuts.new),
        boardSettingsProviderNew.overrideWith(_BoardSettings.new),
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion, padding: padding),
          child: child!,
        ),
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

/// Stars in memory: every toggle recorded, starring then unstarring.
class _RecordingFavoriteEvents extends FavoriteEventsNotifier {
  final toggles = <String>[];
  final _starred = <String>{};

  @override
  Future<List<FavoriteEvent>> build() async => const <FavoriteEvent>[];

  @override
  Future<bool> toggleFavorite({
    required String eventId,
    required String eventName,
    String? timeControl,
    int? maxAvgElo,
    String? dates,
    Map<String, dynamic>? extraMetadata,
  }) async {
    toggles.add(eventId);
    if (_starred.remove(eventId)) return false;
    _starred.add(eventId);
    return true;
  }
}

class _BoardSettings extends BoardSettingsNotifierNew {
  @override
  Future<BoardSettingsNew> build() async => const BoardSettingsNew();
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

final _secondUpcomingEvent = GroupEventCardModel(
  id: 'up-2',
  title: 'Tata Steel Chess 2027',
  dates: 'Jan 15 - 31, 2027',
  maxAvgElo: 2740,
  timeUntilStart: '',
  tourEventCategory: TourEventCategory.upcoming,
  timeControl: 'Classical',
  startDate: DateTime.utc(2027, 1, 15),
  endDate: DateTime.utc(2027, 1, 31),
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

  /// The upcoming view past Coming up's first read: [upcomingPages] in turn.
  final upcomingOffsets = <int?>[];
  List<List<GroupBroadcast>> upcomingPages = const [];

  @override
  Future<List<GroupBroadcast>> getUpcomingGroupBroadcasts({
    int? limit,
    int? offset,
    String orderBy = 'max_avg_elo',
    bool ascending = false,
  }) async {
    upcomingOffsets.add(offset);
    final page = upcomingOffsets.length - 1;
    return page < upcomingPages.length ? upcomingPages[page] : const [];
  }

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

/// Collections fixed at [items], the whole catalog in one page.
class _FixedCollections extends SearchCollectionsFeed {
  _FixedCollections(this.items);

  final List<Collection> items;

  @override
  SearchFeed<Collection> build() => SearchFeed(items: items);
}

/// News starting at [first] with more to come: the next page fails once,
/// then brings [next] and ends the stories.
class _FlakyNews extends SearchNewsFeed {
  _FlakyNews(this.first, this.next);

  final List<FeedNews> first;
  final List<FeedNews> next;
  int reads = 0;

  @override
  SearchFeed<FeedNews> build() => SearchFeed(items: first, hasMore: true);

  @override
  Future<SearchFeedPage<FeedNews>> fetchPage(List<FeedNews> loaded) async {
    reads++;
    if (reads == 1) throw const SocketException('offline');
    return SearchFeedPage(next, hasMore: false);
  }
}

/// An event coming up, strongest first by [i], starting [i] days apart.
GroupEventCardModel _upcomingNumbered(int i) => GroupEventCardModel(
  id: 'up-n$i',
  title: 'Upcoming Open $i',
  dates: '',
  maxAvgElo: 2700 - i,
  timeUntilStart: '',
  tourEventCategory: TourEventCategory.upcoming,
  timeControl: 'Classical',
  startDate: DateTime.utc(2027, 3, 1 + i),
  endDate: DateTime.utc(2027, 3, 10 + i),
);

/// News fixed at [items], every story in one page.
class _FixedNews extends SearchNewsFeed {
  _FixedNews(this.items);

  final List<FeedNews> items;

  @override
  SearchFeed<FeedNews> build() => SearchFeed(items: items);
}

/// The ranking on from the landing's head: [pages] answered in turn, each
/// offset recorded; an empty page once they run out. [fail] fails the next
/// read, once.
class _Ranking implements ChessPlayerRepository {
  _Ranking({this.pages = const []});

  final List<List<ChessPlayer>> pages;
  final offsets = <int>[];
  Completer<void>? hold;
  bool fail = false;

  @override
  Future<List<ChessPlayer>> getRankedPlayers({
    required RankingFilters filters,
    String? countryCode,
    String searchQuery = '',
    int limit = 30,
    int offset = 0,
    DateTime? now,
  }) async {
    offsets.add(offset);
    final wait = hold;
    if (wait != null) await wait.future;
    if (fail) {
      fail = false;
      throw const SocketException('offline');
    }
    final page = offsets.length - 1;
    return page < pages.length ? pages[page] : const <ChessPlayer>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A full page of ranked players, numbered from [from].
List<ChessPlayer> _rankedPage(int from) => [
  for (var i = 0; i < searchPlayersPageSize; i++)
    ChessPlayer(
      fideid: 9000000 + from + i,
      name: 'Ranked, Player ${from + i}',
      title: 'GM',
      rating: 2700 - from - i,
      country: 'NOR',
    ),
];

final _collection = Collection(
  id: 'book-1',
  slug: 'my-sixty-memorable-games',
  kind: CollectionKind.book,
  title: 'My 60 Memorable Games',
  author: 'Bobby Fischer',
  gameCount: 60,
  viewCount: 1200,
  starCount: 40,
);

final _secondCollection = Collection(
  id: 'book-2',
  slug: 'zurich-1953',
  kind: CollectionKind.book,
  title: 'Zurich International Chess Tournament 1953',
  author: 'David Bronstein',
  gameCount: 210,
  viewCount: 900,
  starCount: 25,
);

final _story = FeedNews(
  id: 7,
  title: 'Carlsen wins the Champions Showdown',
  summary: 'A clean sweep in the final round.',
  content: 'A clean sweep in the final round.',
  publishedAt: DateTime.utc(2026, 11, 18, 9),
);

final _secondStory = FeedNews(
  id: 8,
  title: 'Gukesh leads the Grand Swiss after round five',
  summary: 'Three wins and two draws.',
  content: 'Three wins and two draws.',
  publishedAt: DateTime.utc(2026, 11, 17, 9),
);

/// Pumps [count] frames 16ms apart: a spring or a menu settles in that
/// time, while a spinner elsewhere on the page keeps turning.
Future<void> _frames(WidgetTester tester, [int count = 60]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// The landing's own scroll position.
ScrollPosition _landingPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('search_landing')),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

/// The scroll position of [section]'s row on the landing.
ScrollPosition _rowPosition(WidgetTester tester, String section) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(PageStorageKey<String>('search-carousel-$section')),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

/// The rows of the open long-press menu, by label.
Set<String> _menuLabels(WidgetTester tester) => {
  for (final element in find.byWidgetPredicate((widget) {
    final type = widget.runtimeType.toString();
    return type == '_ActionRow' || type == '_ActionTile';
  }).evaluate())
    ((element.widget as dynamic).action as LibraryMenuAction).label,
};

/// The collections catalog, [total] books in pages of 40; each read's
/// offset recorded, and held while [hold] is set. The whole catalog is
/// never read.
class _PagedCollections implements CollectionsRepository {
  _PagedCollections({required this.total});

  final int total;
  final offsets = <int>[];
  Completer<void>? hold;

  @override
  Future<CollectionsPage> searchBooks(
    CollectionSearchQuery query,
    int offset,
  ) async {
    offsets.add(offset);
    final wait = hold;
    if (wait != null) await wait.future;
    final end = math.min(offset + 40, total);
    return CollectionsPage(
      items: [
        for (var i = offset; i < end; i++)
          Collection(
            id: 'book-$i',
            slug: 'book-$i',
            kind: CollectionKind.book,
            title: 'Book $i',
            gameCount: 10,
          ),
      ],
      total: total,
      limit: 40,
      offset: offset,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The words of a section's See more or Show less ([key] after `search-`),
/// where the control takes its taps.
Finder _toggle(String key) => find.descendant(
  of: find.byKey(ValueKey('search-$key')),
  matching: find.byType(Text),
);
