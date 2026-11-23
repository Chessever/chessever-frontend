import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/main.dart' show routeObserver;
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
import 'package:chessever2/screens/my_space/widgets/space_avatar.dart'
    show SpacePlayerAvatar;
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
    show SearchCarousel, SearchCarouselPhysics, SearchSeeMoreCard;
import 'package:chessever2/screens/search/search_feeds.dart';
import 'package:chessever2/screens/search/search_landing_section.dart'
    show SearchLandingSection, SearchSectionHeading;
import 'package:chessever2/screens/search/search_landing.dart';
import 'package:chessever2/screens/search/sections/search_openings_page.dart';
import 'package:chessever2/screens/search/sections/search_section_pages.dart';
import 'package:chessever2/screens/search/sections/search_smart_events_page.dart';
import 'package:chessever2/screens/search/search_page_landing.dart';
import 'package:chessever2/screens/search/search_page_results.dart';
import 'package:chessever2/screens/search/search_page_sections.dart';
import 'package:chessever2/screens/search/search_recents_store.dart';
import 'package:chessever2/screens/search/search_recents_view.dart';
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
import 'package:chessever2/widgets/search_mode/search_mode.dart'
    show SearchHeaderMetrics;
import 'package:chessever2/screens/search/search_tab_screen.dart';
import 'package:chessever2/screens/home/widget/bottom_nav_bar.dart';
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

  testWidgets('the Search tab opens with its field at rest: no cursor, no '
      'keyboard, no Cancel, the landing to read', (tester) async {
    final app = await _pump(tester);
    final field = find.byKey(const ValueKey('search_tab_field'));
    expect(field, findsOneWidget);
    expect(_fieldHasFocus(tester), isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.byKey(const ValueKey('search_tab_cancel')), findsNothing);
    expect(find.byKey(const ValueKey('search_landing')), findsOneWidget);

    // The field takes the cursor only when tapped.
    await tester.tap(field);
    await tester.pump();
    expect(_fieldHasFocus(tester), isTrue);
    await app.dispose();
  });

  testWidgets('the way back and the field share one row, the back where '
      'every pushed page\'s is; the page starts under the row', (tester) async {
    final app = await _pump(tester);
    final field = tester.getRect(find.byType(EnhancedRoundedSearchBar));
    final back = tester.getRect(find.byKey(const ValueKey('search_back')));
    expect(back.left, closeTo(SearchHeaderMetrics.leadingInset, 0.01));
    expect(field.left, greaterThanOrEqualTo(back.right - 0.01));
    expect(field.center.dy, closeTo(back.center.dy, 0.5));
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('search_tab_page'))).dy,
      greaterThanOrEqualTo(math.max(field.bottom, back.bottom)),
    );
    await app.dispose();
  });

  testWidgets('one page: no drop-down, no placeholder copy, results in '
      'place as you type', (tester) async {
    final app = await _pump(tester, openings: _landingOpenings);
    final page = find.byKey(const ValueKey('search_tab_page'));
    expect(page, findsOneWidget);
    // Nothing typed: the landing, real cards and no placeholder copy.
    expect(find.byKey(const ValueKey('search_landing')), findsOneWidget);
    _expectNoPlaceholderCopy();
    // The page is the only results surface: no panel drops over it.
    expect(find.byType(SearchOverlay), findsNothing);
    expect(find.byType(SearchTabPage), findsOneWidget);

    await _type(tester, const ValueKey('search_tab_field'), 'carlsen');
    expect(
      find.descendant(of: page, matching: find.textContaining('Carlsen')),
      findsWidgets,
    );
    // The results replace the landing.
    expect(find.byKey(const ValueKey('search_landing')), findsNothing);
    expect(find.text('Smart events'), findsNothing);
    expect(find.byType(SearchOverlay), findsNothing);

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
    final app = await _pump(tester);
    final chrome = _pageChrome(tester);
    // Arriving leaves the field at rest: the bar is free to step away.
    expect(chrome.held, isFalse);

    await tester.tap(find.byKey(const ValueKey('search_tab_field')));
    await tester.pump();
    expect(chrome.held, isTrue);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(chrome.held, isFalse);
    await app.dispose();
  });

  group('the field and its recent searches, as X has them', () {
    Finder field() => find.byKey(const ValueKey('search_tab_field'));
    Finder cancel() => find.byKey(const ValueKey('search_tab_cancel'));
    String fieldText(WidgetTester tester) => tester
        .widget<EditableText>(
          find.descendant(of: field(), matching: find.byType(EditableText)),
        )
        .controller
        .text;

    testWidgets('Cancel stands outside the field while it has the cursor or '
        'text, the field narrowing for it on a spring; no clear button in '
        'the field', (tester) async {
      final app = await _pump(tester);
      final bar = find.byType(EnhancedRoundedSearchBar);
      final rest = tester.getSize(bar).width;
      expect(cancel(), findsNothing);

      await tester.tap(field());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final midway = tester.getSize(bar).width;
      // On its way, not there in one frame.
      expect(midway, lessThan(rest - 1));
      await _frames(tester);
      final narrowed = tester.getSize(bar).width;
      expect(midway, greaterThan(narrowed + 1));
      expect(cancel(), findsOneWidget);
      expect(
        find.descendant(of: cancel(), matching: find.text('Cancel')),
        findsOneWidget,
      );
      // At the row's end, on the gutter, beside the field: never in it.
      final button = tester.getRect(cancel());
      expect(
        button.left,
        greaterThanOrEqualTo(tester.getRect(bar).right - 0.5),
      );
      expect(
        button.right,
        closeTo(393 - HomeTopBarMetrics.horizontalPadding, 0.5),
      );
      expect(button.height, greaterThanOrEqualTo(44));
      expect(button.width, greaterThanOrEqualTo(44));
      // The magnifier stays in the field; no clear button beside it.
      expect(
        find.descendant(of: bar, matching: find.byIcon(Icons.close)),
        findsNothing,
      );

      // With text and no cursor, Cancel stays.
      await tester.enterText(field(), 'carlsen');
      FocusManager.instance.primaryFocus?.unfocus();
      await _frames(tester);
      expect(cancel(), findsOneWidget);
      await app.dispose();
    });

    testWidgets('Cancel clears the query, drops the keyboard and brings the '
        'landing back; the field widens again', (tester) async {
      final app = await _pump(tester);
      final bar = find.byType(EnhancedRoundedSearchBar);
      final rest = tester.getSize(bar).width;
      await _type(tester, const ValueKey('search_tab_field'), 'carlsen');
      expect(find.byKey(const ValueKey('search_results')), findsOneWidget);
      expect(tester.testTextInput.isVisible, isTrue);

      await tester.tap(cancel());
      await tester.pump();
      expect(fieldText(tester), isEmpty);
      expect(_fieldHasFocus(tester), isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(app.read(searchQueryProvider), isEmpty);
      expect(app.read(debouncedSearchQueryProvider), isEmpty);
      expect(find.byKey(const ValueKey('search_landing')), findsOneWidget);
      expect(find.text('Smart events'), findsOneWidget);
      await _frames(tester);
      expect(cancel(), findsNothing);
      expect(tester.getSize(bar).width, closeTo(rest, 0.01));
      // Typed and cancelled is not a search the reader made.
      expect(app.read(searchRecentsProvider).queries, isEmpty);
      await app.dispose();
    });

    testWidgets('under reduced motion Cancel and the field land at once', (
      tester,
    ) async {
      final app = await _pump(tester, reduceMotion: true);
      final bar = find.byType(EnhancedRoundedSearchBar);
      await tester.tap(field());
      await tester.pump();
      expect(cancel(), findsOneWidget);
      final open = tester.getSize(bar).width;
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getSize(bar).width, open);
      await app.dispose();
    });

    testWidgets('Recent: a row of the things last opened (a face, or the '
        'plate its card leads with, and a short name), then the queries; '
        'every name on one line', (tester) async {
      final najdorf = searchOpeningSuggestions('Najdorf', limit: 1).single;
      final picks = [
        SearchRecentPick.player(_topPlayers[1]),
        SearchRecentPick.event(_event),
        SearchRecentPick.opening(najdorf.selection),
        SearchRecentPick.smartEvent(kSuperGmSmartPreset),
        SearchRecentPick.collection(_collection),
        SearchRecentPick.news(_story),
      ];
      final app = await _pump(
        tester,
        recentPicks: picks,
        recentQueries: ['nakamura', 'najdorf'],
      );
      await tester.tap(field());
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Recent'), findsOneWidget);

      final tiles = find.byType(SearchRecentTile);
      expect(
        tester
            .widgetList<SearchRecentTile>(tiles)
            .map((tile) => tile.pick.identity),
        picks.map((pick) => pick.identity),
      );
      Finder tile(SearchRecentPick pick) =>
          find.byKey(ValueKey('search-recent-pick-${pick.identity}'));
      // Each from its card's own pieces.
      expect(
        find.descendant(
          of: tile(picks[0]),
          matching: find.byType(SpacePlayerAvatar),
        ),
        findsOneWidget,
      );
      for (final pick in [picks[2], picks[3]]) {
        expect(
          find.descendant(
            of: tile(pick),
            matching: find.byType(SmartEventPlate),
          ),
          findsOneWidget,
          reason: pick.name,
        );
      }
      // Short names: a surname, a level.
      expect(
        find.descendant(of: tile(picks[0]), matching: find.text('Nakamura')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile(picks[3]), matching: find.text('Super GM')),
        findsOneWidget,
      );
      // Pictures one height, names on one line.
      final tops = {
        for (final pick in picks.take(4))
          tester
              .getTopLeft(
                find
                    .descendant(of: tile(pick), matching: find.byType(Text))
                    .last,
              )
              .dy
              .toStringAsFixed(1),
      };
      expect(tops, hasLength(1));

      // The queries, newest first, under the row.
      final nakamura = tester.getTopLeft(find.text('nakamura')).dy;
      expect(nakamura, lessThan(tester.getTopLeft(find.text('najdorf')).dy));
      expect(nakamura, greaterThan(tester.getRect(tile(picks[0])).bottom));
      await app.dispose();
    });

    testWidgets('a recent thing opens as its card does, and moves to the '
        'front', (tester) async {
      final event = SearchRecentPick.event(_event);
      final player = SearchRecentPick.player(_topPlayers[0]);
      final observer = _PushObserver();
      final app = await _pump(
        tester,
        recentPicks: [player, event],
        observer: observer,
      );
      await tester.tap(field());
      await tester.pump();
      await tester.tap(
        find.byKey(ValueKey('search-recent-pick-${event.identity}')),
      );
      await tester.pump();
      await tester.binding.delayed(Duration.zero);
      final navigation =
          app.read(tournamentNavigationProvider) as _RecordingNavigation;
      expect(navigation.opened.single.$1, _event.id);
      expect(_fieldHasFocus(tester), isFalse);
      expect(app.read(searchRecentsProvider).picks.map((p) => p.identity), [
        event.identity,
        player.identity,
      ]);
      await app.dispose();
    });

    testWidgets('a recent query\'s row searches it again; its arrow puts it '
        'back in the field, the keyboard still up', (tester) async {
      final app = await _pump(tester, recentQueries: ['carlsen', 'nakamura']);
      await tester.tap(field());
      await tester.pump();
      await tester.tap(find.text('nakamura'));
      await tester.pump();
      expect(fieldText(tester), 'nakamura');
      expect(_fieldHasFocus(tester), isFalse);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('search_results')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('search_results')),
          matching: find.textContaining('Nakamura'),
        ),
        findsWidgets,
      );
      expect(app.read(searchRecentsProvider).queries, ['nakamura', 'carlsen']);

      // Back to Recent, then the arrow of "carlsen".
      await tester.tap(cancel());
      await tester.pump();
      await tester.tap(field());
      await tester.pump();
      expect(find.text('Recent'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('search-recent-fill-carlsen')),
      );
      await tester.pump();
      expect(fieldText(tester), 'carlsen');
      expect(_fieldHasFocus(tester), isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('search_results')),
          matching: find.textContaining('Carlsen'),
        ),
        findsWidgets,
      );
      await app.dispose();
    });

    testWidgets('a query is kept once committed: searched with the '
        'keyboard\'s key, or typed and then a result opened', (tester) async {
      final app = await _pump(tester, observer: _PushObserver());
      await _type(tester, const ValueKey('search_tab_field'), 'carlsen');
      expect(app.read(searchRecentsProvider).queries, isEmpty);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(app.read(searchRecentsProvider).queries, ['carlsen']);

      await _type(tester, const ValueKey('search_tab_field'), 'nakamura');
      await tester.tap(find.textContaining('Nakamura').first);
      await tester.pump();
      await tester.binding.delayed(Duration.zero);
      final recents = app.read(searchRecentsProvider);
      expect(recents.queries, ['nakamura', 'carlsen']);
      expect(recents.picks.first.kind, SearchRecentKind.player);
      expect(recents.picks.first.name, 'Nakamura, Hikaru');
      await app.dispose();
    });

    testWidgets('the cross clears every recent search, with an Undo; with '
        'none left the landing is back', (tester) async {
      final app = await _pump(
        tester,
        recents: [RecentSearchEntry.tournament(_event)],
        recentQueries: ['nakamura'],
      );
      await tester.tap(field());
      await tester.pump();
      final clear = find.byKey(const ValueKey('search-recent-clear-all'));
      expect(tester.getSize(clear).height, greaterThanOrEqualTo(44));
      await tester.tap(clear);
      await tester.pump();
      expect(app.read(searchRecentsProvider).isEmpty, isTrue);
      expect(find.text('Recent'), findsNothing);
      expect(find.text('Smart events'), findsOneWidget);
      // The cursor stays: the reader was about to type.
      expect(_fieldHasFocus(tester), isTrue);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Recent searches cleared'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      final back = app.read(searchRecentsProvider);
      expect(back.picks.single.name, _event.title);
      expect(back.queries, ['nakamura']);
      await app.dispose();
    });

    testWidgets('kept on the device: a new session shows the same Recent', (
      tester,
    ) async {
      final storage = _MemorySearchRecents();
      var app = await _pump(tester, recentsStorage: storage);
      await _type(tester, const ValueKey('search_tab_field'), 'carlsen');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.binding.delayed(Duration.zero);
      expect(storage.stored, contains('carlsen'));
      await app.dispose();

      app = await _pump(tester, recentsStorage: storage);
      await tester.tap(field());
      await tester.pump();
      await tester.binding.delayed(Duration.zero);
      await tester.pump();
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('carlsen'), findsOneWidget);
      await app.dispose();
    });
  });

  group('the landing (nothing typed)', () {
    testWidgets('each section in the card the app draws it in elsewhere, '
        'in order, each a row of its cards', (tester) async {
      final app = await _pump(
        tester,
        size: const Size(393, 3600),
        // Recent searches wait for the field's cursor: never on the landing.
        recents: [RecentSearchEntry.tournament(_event)],
        // Events in play: a search finds them; the landing has no section
        // of its own for them.
        liveIds: [_liveEvent.id, _secondLiveEvent.id],
        players: () async => _topPlayers,
        openings: _landingOpenings,
        upcoming: [_upcomingEvent, _secondUpcomingEvent],
        collections: [_collection, _secondCollection],
        news: [_story, _secondStory],
      );
      expect(tester.takeException(), isNull);
      final landing = find.byKey(const ValueKey('search_landing'));
      expect(landing, findsOneWidget);

      expect(find.text('Recent searches'), findsNothing);
      expect(find.text('Recent'), findsNothing);
      expect(find.text('Live now'), findsNothing);
      expect(find.byKey(const ValueKey('search-live-open')), findsNothing);
      final headings = [
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

      // The events coming up: event cards, soonest first.
      for (final key in [
        'search-upcoming-${_secondUpcomingEvent.id}',
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
      // A row: the later event stands beside the sooner, peeking in past
      // the screen's edge.
      final soonest = tester.getRect(
        find.byKey(ValueKey('search-upcoming-${_secondUpcomingEvent.id}')),
      );
      final later = tester.getRect(
        find.byKey(ValueKey('search-upcoming-${_upcomingEvent.id}')),
      );
      expect(later.top, soonest.top);
      expect(later.left, greaterThan(soonest.right));
      expect(later.left, lessThan(393));
      expect(later.right, greaterThan(393));

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
      expect(_topCarlsen(), findsOneWidget);

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

    testWidgets('recent searches are never on the landing; they stand in '
        'for it while the field has the cursor', (tester) async {
      final app = await _pump(
        tester,
        recents: [RecentSearchEntry.tournament(_event)],
      );
      expect(find.text('Recent'), findsNothing);
      expect(find.byKey(const ValueKey('search_landing')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('search_tab_field')));
      await tester.pump();
      expect(find.text('Recent'), findsOneWidget);
      // The landing waits under it, kept where it was.
      expect(find.byKey(const ValueKey('search_landing')), findsNothing);
      expect(
        find.byKey(const ValueKey('search_landing'), skipOffstage: false),
        findsOneWidget,
      );

      // The keyboard down with nothing typed: the landing again.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(find.text('Recent'), findsNothing);
      expect(find.byKey(const ValueKey('search_landing')), findsOneWidget);
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
      expect(_topCarlsen(), findsOneWidget);
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
        players: () async => _topPlayers,
        openings: _landingOpenings,
      );
      await _type(tester, const ValueKey('search_tab_field'), 'nakamura');
      expect(find.text('Smart events'), findsNothing);
      expect(find.text('Top players'), findsNothing);

      await _type(tester, const ValueKey('search_tab_field'), '');
      expect(find.text('Smart events'), findsOneWidget);
      expect(find.text('Top players'), findsOneWidget);
      expect(_topCarlsen(), findsOneWidget);
      await app.dispose();
    });

    testWidgets('an event card coming up opens as a searched event does, '
        'with one haptic', (tester) async {
      final haptics = _Haptics(tester);
      final app = await _pump(tester, upcoming: [_upcomingEvent]);
      haptics.calls.clear();
      await tester.tap(
        find.byKey(ValueKey('search-upcoming-${_upcomingEvent.id}')),
      );
      await tester.pump();

      final navigation =
          app.read(tournamentNavigationProvider) as _RecordingNavigation;
      expect(navigation.opened, [
        (_upcomingEvent.id, GroupEventCategory.search, 'forYouSearch'),
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
      await tester.tap(_topCarlsen());
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
        upcoming: [_upcomingEvent],
        favorites: () => favorites,
      );
      final key = eventSpaceDraft(_upcomingEvent).key;
      expect(app.read(spaceShortcutExistsProvider(key)), isFalse);
      final star = find.descendant(
        of: find.byKey(ValueKey('search-upcoming-${_upcomingEvent.id}')),
        matching: find.bySemanticsLabel('Favorite Icon'),
      );
      expect(star, findsOneWidget);

      await tester.tap(star);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(favorites.toggles, [_upcomingEvent.id]);
      expect(app.read(spaceShortcutExistsProvider(key)), isTrue);
      expect(find.text('Added to My Space'), findsOneWidget);

      await tester.tap(star);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(favorites.toggles, [_upcomingEvent.id, _upcomingEvent.id]);
      expect(app.read(spaceShortcutExistsProvider(key)), isTrue);
      await app.dispose();
    });

    group('a pick is remembered as a recent search, as a result is', () {
      final sicilian = searchOpeningSuggestions('Sicilian', limit: 1).single;
      for (final (name, row, check)
          in <(String, Finder Function(), void Function(RecentSearchEntry))>[
            (
              'an event coming up',
              () =>
                  find.byKey(ValueKey('search-upcoming-${_upcomingEvent.id}')),
              (entry) {
                expect(entry.kind, RecentSearchKind.tournament);
                expect(entry.targetId, _upcomingEvent.id);
              },
            ),
            (
              'a top player',
              () => _topCarlsen(),
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
            // Every row on screen at once, Coming up included.
            size: const Size(393, 2400),
            upcoming: [_upcomingEvent],
            players: () async => _topPlayers,
            openings: _landingOpenings,
            observer: _PushObserver(),
          );
          expect(app.read(recentSearchesProvider).valueOrNull, isEmpty);
          expect(app.read(searchRecentsProvider).isEmpty, isTrue);
          await tester.tap(row());
          await tester.pump();
          // The pushed page is never built: only the record is flushed.
          await tester.binding.delayed(Duration.zero);

          // The Events page's field shares this history...
          final recents = app.read(recentSearchesProvider).valueOrNull!;
          expect(recents, hasLength(1));
          check(recents.single);
          // ...and the tab keeps its own: the pick, and no query (nothing
          // was typed).
          final own = app.read(searchRecentsProvider);
          expect(own.picks, hasLength(1));
          check(own.picks.single.entry!);
          expect(own.queries, isEmpty);
          await app.dispose();
        });
      }
    });

    group('a long-press opens the card\'s own menu', () {
      testWidgets('an event card: its event menu, with My Space', (
        tester,
      ) async {
        final app = await _pump(tester, upcoming: [_upcomingEvent]);
        await tester.longPress(
          find.byKey(ValueKey('search-upcoming-${_upcomingEvent.id}')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Open event'), findsOneWidget);
        await tester.tap(find.text('Add to My Space'));
        await tester.pumpAndSettle();
        final saved = app.read(spaceShortcutsProvider).requireValue.single;
        expect(saved.kind, SpaceShortcutKind.event);
        expect(saved.targetId, _upcomingEvent.id);
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
        await tester.longPress(_topCarlsen());
        await tester.pumpAndSettle();
        expect(find.text('Open profile'), findsOneWidget);
        expect(find.text('Share profile'), findsOneWidget);
        await app.dispose();
      });
    });

    testWidgets('typing starts no landing work, and clearing asks for '
        'nothing again; events in play are never looked up', (tester) async {
      final builds = _Builds();
      final repo = _Broadcasts();
      final app = await _pump(
        tester,
        builds: builds,
        // In play, and in no list Search holds: Search lists no events in
        // play of its own, so it asks for none of them.
        liveIds: [_liveEvent.id, _secondLiveEvent.id],
        broadcasts: repo,
        players: () async => _topPlayers,
        openings: _landingOpenings,
      );
      expect((builds.players, builds.openings, builds.upcoming), (1, 1, 1));

      await _type(tester, const ValueKey('search_tab_field'), 'nakamura');
      expect(find.byKey(const ValueKey('search_landing')), findsNothing);
      await _type(tester, const ValueKey('search_tab_field'), '');
      expect(_topCarlsen(), findsOneWidget);

      expect((builds.players, builds.openings, builds.upcoming), (1, 1, 1));
      expect(repo.calls, isEmpty);
      await app.dispose();
    });

    for (final size in const [Size(393, 852), Size(375, 667)]) {
      testWidgets('${size.width.round()}x${size.height.round()}: headings '
          'and cards start and end on the page\'s gutter', (tester) async {
        final app = await _pump(
          tester,
          size: Size(size.width, 2400),
          recents: [RecentSearchEntry.tournament(_event)],
          players: () async => _topPlayers,
          openings: _landingOpenings,
          upcoming: [_upcomingEvent],
        );
        final gutter = HomeTopBarMetrics.horizontalPadding;
        final end = size.width - gutter;
        // The field ends on the same gutter.
        expect(
          tester.getRect(find.byType(EnhancedRoundedSearchBar)).right,
          closeTo(end, 0.01),
        );
        for (final heading in [
          'Top players',
          'Openings',
          'Smart events',
          'Coming up',
        ]) {
          expect(
            tester.getTopLeft(find.text(heading)).dx,
            closeTo(gutter, 0.01),
            reason: heading,
          );
        }
        // A row's first card starts on the gutter, nine tenths of the
        // row wide: the next card peeks in past the gutter's end.
        final row = end - gutter;
        for (final card in [
          find.byKey(const ValueKey('search-top-players-0')),
          find.byKey(ValueKey('opening-result-${_landingOpenings[0].id}')),
          find.byKey(ValueKey('search-upcoming-${_upcomingEvent.id}')),
        ]) {
          final rect = tester.getRect(card);
          expect(rect.left, closeTo(gutter, 0.01));
          expect(
            rect.width,
            closeTo((row + searchCardGap) / 1.1 - searchCardGap, 0.01),
          );
        }
        // Cards of a row side by side, a card's gap apart, tops and
        // bottoms in line, the second past the gutter's end.
        final a = tester.getRect(
          find.byKey(ValueKey('opening-result-${_landingOpenings[0].id}')),
        );
        final b = tester.getRect(
          find.byKey(ValueKey('opening-result-${_landingOpenings[1].id}')),
        );
        expect(b.left, closeTo(a.right + searchCardGap, 0.01));
        expect(b.right, greaterThan(end));
        expect(a.top, b.top);
        expect(a.height, closeTo(b.height, 0.01));

        await _type(tester, const ValueKey('search_tab_field'), 'qqqq');
        expect(
          tester.getTopLeft(find.textContaining('No matches')).dx,
          closeTo(gutter, 0.01),
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
        players: () async => _topPlayers,
        openings: _landingOpenings,
        upcoming: [_upcomingEvent, _secondUpcomingEvent],
      );
      expect(ResponsiveHelper.isTablet, isTrue);
      expect(tester.takeException(), isNull);
      final a = tester.getRect(
        find.byKey(ValueKey('search-upcoming-${_secondUpcomingEvent.id}')),
      );
      final b = tester.getRect(
        find.byKey(ValueKey('search-upcoming-${_upcomingEvent.id}')),
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
          players: () async => _topPlayers,
        );
        for (final text in ['Top players', 'Smart events']) {
          final ink = tester.widget<Text>(find.text(text)).style!.color!;
          expect(
            _contrast(ink, colors.background),
            greaterThanOrEqualTo(4.5),
            reason: '"$text" on the $name page',
          );
        }
        // The field's Cancel and the recent searches' words, on the same
        // page.
        await tester.tap(find.byKey(const ValueKey('search_tab_field')));
        await _frames(tester);
        for (final text in ['Cancel', 'Recent', _event.title]) {
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
    testWidgets('an event in play is found under Events, at its head and '
        'LIVE on its card, with no Live now heading; one coming up under '
        'Coming up, from the landing\'s own list', (tester) async {
      final app = await _pump(
        tester,
        size: const Size(393, 2400),
        liveIds: [_liveEvent.id, _secondLiveEvent.id],
        upcoming: [_upcomingEvent, _secondUpcomingEvent],
      );
      await _type(tester, const ValueKey('search_tab_field'), 'tata');
      final results = find.byKey(const ValueKey('search_results'));
      expect(results, findsOneWidget);
      final live = find.byKey(ValueKey('search-event-${_liveEvent.id}'));
      final past = find.byKey(ValueKey('search-event-${_pastTataEvent.id}'));
      final upcoming = find.byKey(
        ValueKey('search-event-${_secondUpcomingEvent.id}'),
      );
      for (final card in [live, past, upcoming]) {
        expect(
          find.descendant(of: card, matching: find.byType(EventCard)),
          findsOneWidget,
        );
      }
      // The search found it as a running event; the live set makes its
      // card read LIVE, as the Events list draws it.
      expect(
        find.descendant(of: live, matching: find.text('LIVE')),
        findsOneWidget,
      );
      // Only what the words name.
      expect(
        find.byKey(ValueKey('search-event-${_secondLiveEvent.id}')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('search-event-${_upcomingEvent.id}')),
        findsNothing,
      );
      expect(
        find.descendant(of: results, matching: find.text('Live now')),
        findsNothing,
      );
      final upcomingHeading = find.descendant(
        of: results,
        matching: find.text('Coming up'),
      );
      final eventsHeading = find.descendant(
        of: results,
        matching: find.text('Events'),
      );
      expect(upcomingHeading, findsOneWidget);
      expect(eventsHeading, findsOneWidget);
      double top(Finder finder) => tester.getTopLeft(finder).dy;
      // Coming up, then Events, the event in play first though the search
      // found it second.
      expect(top(upcomingHeading), lessThan(top(upcoming)));
      expect(top(upcoming), lessThan(top(eventsHeading)));
      expect(top(eventsHeading), lessThan(top(live)));
      expect(top(live), lessThan(top(past)));

      await tester.tap(live);
      await tester.pump();
      final navigation =
          app.read(tournamentNavigationProvider) as _RecordingNavigation;
      expect(navigation.opened.single.$1, _liveEvent.id);
      // Typed, then a result opened: the query is kept with the pick.
      await tester.binding.delayed(Duration.zero);
      expect(app.read(searchRecentsProvider).queries, ['tata']);
      await app.dispose();
    });

    testWidgets('a level or a time control finds the built-in smart events, '
        'each opening itself without Filters', (tester) async {
      final observer = _PushObserver();
      final app = await _pump(tester, observer: observer);
      await _type(tester, const ValueKey('search_tab_field'), 'grandmaster');
      for (final tier in ['Super GM', 'GM']) {
        expect(
          find.byKey(ValueKey('search-result-smart-$tier')),
          findsOneWidget,
          reason: tier,
        );
      }

      await _type(tester, const ValueKey('search_tab_field'), 'blitz');
      final results = find.byKey(const ValueKey('search_results'));
      expect(
        find.descendant(of: results, matching: find.text('Smart events')),
        findsOneWidget,
      );
      final card = find.byKey(const ValueKey('search-result-smart-Blitz'));
      expect(
        find.descendant(of: card, matching: find.byType(SmartEventCard)),
        findsOneWidget,
      );
      await tester.tap(card);
      await tester.pump();
      final screen = observer.lastPage(tester);
      expect(screen, isA<SmartEventScreen>());
      expect((screen as SmartEventScreen).showFilters, isFalse);
      await tester.binding.delayed(Duration.zero);
      final recents = app.read(searchRecentsProvider);
      expect(recents.picks.single.kind, SearchRecentKind.smartEvent);
      expect(recents.queries, ['blitz']);
      await app.dispose();
    });

    testWidgets('a collection opened from the landing\'s Collections row is '
        'remembered, as one opened from the results is', (tester) async {
      final app = await _pump(
        tester,
        size: const Size(393, 3600),
        collections: [_collection, _secondCollection],
      );
      final card = tester.widget<CollectionCard>(
        find.byKey(ValueKey('search-collection-${_collection.id}')),
      );
      // Every open of the card (a tap, the menu's Open, the lifted copy)
      // reports through onOpened; the push itself is the card's own.
      expect(card.onOpened, isNotNull);
      card.onOpened!();
      await tester.binding.delayed(Duration.zero);
      final recents = app.read(searchRecentsProvider);
      expect(recents.picks.single.kind, SearchRecentKind.collection);
      expect(recents.picks.single.id, _collection.slug);
      // Nothing was typed: no query is kept with it.
      expect(recents.queries, isEmpty);
      await app.dispose();
    });

    testWidgets('collections come from the catalog\'s own search, news from '
        'the stories the landing read, each in its own card', (tester) async {
      final app = await _pump(
        tester,
        size: const Size(393, 2400),
        collections: [_collection, _secondCollection],
        news: [_story, _secondStory],
      );
      await _type(tester, const ValueKey('search_tab_field'), 'memorable');
      final results = find.byKey(const ValueKey('search_results'));
      expect(
        find.descendant(of: results, matching: find.text('Collections')),
        findsOneWidget,
      );
      expect(
        tester.widget(
          find.byKey(ValueKey('search-result-collection-${_collection.id}')),
        ),
        isA<CollectionCard>(),
      );
      expect(
        find.byKey(
          ValueKey('search-result-collection-${_secondCollection.id}'),
        ),
        findsNothing,
      );

      await _type(tester, const ValueKey('search_tab_field'), 'gukesh');
      expect(
        find.descendant(of: results, matching: find.text('News')),
        findsOneWidget,
      );
      expect(
        tester.widget(
          find.byKey(ValueKey('search-result-news-${_secondStory.key}')),
        ),
        isA<NewsArticleCard>(),
      );
      expect(
        find.byKey(ValueKey('search-result-news-${_story.key}')),
        findsNothing,
      );
      await app.dispose();
    });

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
  group('results opened from are there on the way back', () {
    String fieldText(WidgetTester tester) => tester
        .widget<EditableText>(
          find.descendant(
            of: find.byKey(const ValueKey('search_tab_field')),
            matching: find.byType(EditableText),
          ),
        )
        .controller
        .text;

    NavigatorState navigator(WidgetTester tester) =>
        tester.state<NavigatorState>(find.byType(Navigator).first);

    // Bug found 2026-11-22: an event page leaving resets the app-wide query
    // (TournamentDetailScreen's cleanup), and the page read its results
    // from it: back from an event, the field still said "tata" over Recent.
    testWidgets('an event page leaving resets the shared query; the page '
        'takes its words back and the results stay', (tester) async {
      final app = await _pump(tester, observer: routeObserver);
      await _type(tester, const ValueKey('search_tab_field'), 'tata');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(find.byKey(const ValueKey('search_results')), findsOneWidget);

      navigator(tester).push(
        MaterialPageRoute<void>(builder: (_) => const _LeavingEventPage()),
      );
      await _frames(tester);
      navigator(tester).pop();
      // Every frame of the way back shows the results, never the landing.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.byKey(const ValueKey('search_results')), findsOneWidget);
      }
      expect(find.byType(_LeavingEventPage), findsNothing);
      expect(fieldText(tester), 'tata');
      expect(app.read(searchQueryProvider), 'tata');
      expect(app.read(debouncedSearchQueryProvider), 'tata');
      expect(find.text('Tata Steel Masters 2026'), findsWidgets);
      await app.dispose();
    });

    testWidgets('a failed search says so with Try again, which asks it '
        'again; a pull on the results asks again too', (tester) async {
      var asked = 0;
      final app = await _pump(
        tester,
        answer: (query) {
          if (query != 'tata') return null;
          asked++;
          if (asked == 1) return Future.error(StateError('offline'));
          return Future.value(_eventResults([_pastTataEvent]));
        },
      );
      await _type(tester, const ValueKey('search_tab_field'), 'tata');
      FocusManager.instance.primaryFocus?.unfocus();
      await _frames(tester);
      expect(find.text('Search failed'), findsOneWidget);
      expect(asked, 1);

      await tester.tap(find.byKey(const ValueKey('search_failed_retry')));
      await _frames(tester);
      expect(asked, 2);
      expect(find.text('Search failed'), findsNothing);
      expect(find.text('Tata Steel Masters 2026'), findsWidgets);

      await tester.fling(
        find.byKey(const ValueKey('search_results')),
        const Offset(0, 400),
        1000,
      );
      await _frames(tester);
      expect(asked, 3);
      expect(find.text('Tata Steel Masters 2026'), findsWidgets);
      await app.dispose();
    });

    testWidgets('reset while another page covers Search, the words come back '
        'as Search is uncovered', (tester) async {
      final app = await _pump(tester, observer: routeObserver);
      await _type(tester, const ValueKey('search_tab_field'), 'carlsen');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(find.byKey(const ValueKey('search_results')), findsOneWidget);

      // Search > a profile > an event, then back twice.
      navigator(tester).push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('a profile')),
        ),
      );
      await _frames(tester);
      navigator(tester).push(
        MaterialPageRoute<void>(builder: (_) => const _LeavingEventPage()),
      );
      await _frames(tester);
      navigator(tester).pop();
      await _frames(tester);
      // Covered, the page leaves the shared query alone.
      expect(app.read(searchQueryProvider), isEmpty);
      navigator(tester).pop();
      await _frames(tester);
      expect(app.read(searchQueryProvider), 'carlsen');
      expect(fieldText(tester), 'carlsen');
      expect(find.byKey(const ValueKey('search_results')), findsOneWidget);
      expect(find.text('Magnus Carlsen'), findsWidgets);
      await app.dispose();
    });
  });

  group('the sections: a row each, and its own page', () {
    /// Every section the landing shows, as the fixtures hold them.
    Future<_App> pumpAll(
      WidgetTester tester, {
      Size size = const Size(393, 3600),
      NavigatorObserver? observer,
      bool reduceMotion = false,
      EdgeInsets padding = EdgeInsets.zero,
      _Ranking? ranking,
      List<Override> overrides = const [],
    }) => _pump(
      tester,
      overrides: overrides,
      size: size,
      players: () async => _topPlayers,
      openings: _landingOpenings,
      upcoming: [_upcomingEvent, _secondUpcomingEvent],
      collections: [_collection, _secondCollection],
      news: [_story, _secondStory],
      observer: observer,
      reduceMotion: reduceMotion,
      padding: padding,
      ranking: ranking,
    );

    testWidgets('every title is a button: its words and a chevron, 44pt '
        'tall, heard as a heading that opens its page; no See all is left', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final app = await _pump(
        tester,
        size: const Size(393, 3600),
        recents: [RecentSearchEntry.tournament(_event)],
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
      expect(find.textContaining('See all', findRichText: true), findsNothing);
      semantics.dispose();
      await app.dispose();
    });

    for (final (section, check)
        in <(SearchSectionId, void Function(_App, Route<dynamic>, Widget))>[
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

    // Over the home shell (Search pushed over Home, as Today's button opens
    // it): Coming up closes Search onto the dock's Events on Upcoming, never
    // a second Events page; Collections has no slot and pushes its page.
    testWidgets('over the home shell, Coming up opens the dock\'s Events on '
        'Upcoming, pushing nothing; Collections pushes its page', (
      tester,
    ) async {
      final observer = _PushObserver();
      final app = await pumpAll(
        tester,
        observer: observer,
        // The dock's sections, Botvinnik's switch (SQLite) left alone.
        overrides: [botvinnikTabAvailableProvider.overrideWithValue(true)],
      );
      final searchPage = tester.element(
        find.byType(SearchTabScreen, skipOffstage: false),
      );
      final shell = ModalRoute.of(searchPage);
      registerHomeShellRoute(shell);
      addTearDown(() => unregisterHomeShellRoute(shell));
      final section = ProviderScope.containerOf(
        searchPage,
      ).listen(selectedBottomNavBarItemProvider, (_, _) {});
      addTearDown(section.close);
      final pushes = observer.pushed.length;

      await tester.tap(find.byKey(const ValueKey('search-upcoming-open')));
      await tester.pump();
      expect(observer.pushed, hasLength(pushes));
      expect(section.read(), BottomNavBarItem.tournaments);
      expect(
        app.read(selectedGroupCategoryProvider),
        GroupEventCategory.upcoming,
      );

      await tester.tap(find.byKey(const ValueKey('search-collections-open')));
      await tester.pump();
      expect(observer.pushed, hasLength(pushes + 1));
      expect(observer.lastPage(tester), isA<CollectionsScreen>());
      expect(section.read(), BottomNavBarItem.tournaments);
      await app.dispose();
    });

    testWidgets('Top players never draws a player alone while more of the '
        'ranking is coming; once it is spent, a last player alone stands '
        'whole in its row, clear of the next section', (tester) async {
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
      // The row stands as tall as the lone card: drawn whole inside it,
      // never over the next section's heading.
      expect(
        tester.getRect(lone).bottom,
        lessThanOrEqualTo(tester.getRect(_row('top-players')).bottom + 0.01),
      );
      expect(
        tester.getRect(lone).bottom,
        lessThan(
          tester.getRect(find.byKey(const ValueKey('search-smart-open'))).top,
        ),
      );
      expect(tester.takeException(), isNull);
      await app.dispose();
    });

    testWidgets('a row snaps to its cards\' new width once it changes (a '
        'rotation, split view)', (tester) async {
      final app = await pumpAll(tester, size: const Size(393, 3600));
      final physics =
          _rowPosition(tester, 'upcoming').physics as SearchCarouselPhysics;
      final before = physics.slot;
      tester.view.physicalSize = const Size(430, 3600) * 2;
      await tester.pump();
      await tester.pump();
      expect(
        (_rowPosition(tester, 'upcoming').physics as SearchCarouselPhysics)
            .slot,
        greaterThan(before),
      );
      expect(physics.slot, greaterThan(before));
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

    testWidgets('nothing stands under a row: no See more or Show less '
        'toggle, the next section\'s heading one section gap below', (
      tester,
    ) async {
      final app = await pumpAll(tester);
      // A row read to its end shows its See more card: the only See more
      // on the landing is that card, at the end of a row.
      final row = _rowPosition(tester, 'smart');
      row.jumpTo(row.maxScrollExtent);
      await tester.pump();
      final cards = find.descendant(
        of: find.byType(SearchSeeMoreCard),
        matching: find.text('See more'),
      );
      expect(cards, findsWidgets);
      expect(find.text('See more').evaluate().length, cards.evaluate().length);
      expect(find.text('Show less'), findsNothing);
      expect(find.byIcon(Icons.expand_more_rounded), findsNothing);
      expect(find.byIcon(Icons.expand_less_rounded), findsNothing);
      const sections = SearchSectionId.values;
      for (final section in sections) {
        expect(_row(section.slug), findsOneWidget, reason: section.title);
        for (final end in ['expand', 'collapse', 'fold']) {
          expect(
            find.byKey(ValueKey('search-${section.slug}-$end')),
            findsNothing,
          );
        }
      }
      // Each row is followed by the section gap, then straight by the next
      // section's heading.
      for (var i = 0; i + 1 < sections.length; i++) {
        final heading = find.ancestor(
          of: find.byKey(ValueKey('search-${sections[i + 1].slug}-open')),
          matching: find.byType(SearchSectionHeading),
        );
        expect(
          tester.getRect(heading).top -
              tester.getRect(_row(sections[i].slug)).bottom,
          closeTo(searchSectionGap, 0.01),
          reason: '${sections[i].title} to ${sections[i + 1].title}',
        );
      }
      await app.dispose();
    });

    testWidgets('a row scrolled sideways never moves the bars; the page '
        'scrolled down does', (tester) async {
      final app = await pumpAll(tester, size: const Size(393, 852));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      final chrome = _pageChrome(tester);
      expect(chrome.value, 1);
      await tester.drag(
        find.byKey(const ValueKey('search-top-players-0')),
        const Offset(-260, 0),
      );
      await _frames(tester);
      expect(_rowPosition(tester, 'top-players').pixels, greaterThan(0));
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
        'top-players',
        () => _topCarlsen(),
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
      testWidgets('$slug in its row: a long-press is the card\'s own menu', (
        tester,
      ) async {
        final observer = _PushObserver();
        final app = await pumpAll(
          tester,
          reduceMotion: true,
          observer: observer,
        );
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

    testWidgets('the landing ends clear of the floating dock\'s inset', (
      tester,
    ) async {
      const inset = 90.0;
      final app = await pumpAll(
        tester,
        size: const Size(393, 852),
        padding: const EdgeInsets.only(bottom: inset),
      );
      final page = _landingPosition(tester);
      page.jumpTo(page.maxScrollExtent);
      await tester.pump();
      // The last section's row, its story whole above the dock.
      final last = _row('news');
      expect(last, findsOneWidget);
      expect(tester.getRect(last).bottom, lessThanOrEqualTo(852 - inset));
      final story = find.byKey(ValueKey('search-news-${_story.key}'));
      expect(tester.getRect(story).bottom, lessThanOrEqualTo(852 - inset));
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
  _App(this._tester, this._container, this.page);

  final WidgetTester _tester;
  final ProviderContainer _container;
  final ValueNotifier<_Page> page;

  T read<T>(ProviderListenable<T> provider) => _container.read(provider);

  Future<void> dispose() async {
    await _tester.pumpWidget(const SizedBox.shrink());
    await _tester.pump(const Duration(seconds: 61));
    page.dispose();
  }
}

/// The Search tab under test. The landing's sources are fixtures: no
/// ranking, no openings and nothing coming up unless a test passes them.
///
/// [liveIds] is the live set (nothing in play by default); [broadcasts]
/// answers the group broadcast reads. [builds] counts how often each
/// landing source is built.
Future<_App> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  Size size = const Size(393, 852),
  List<RecentSearchEntry> recents = const [],
  List<SearchRecentPick> recentPicks = const [],
  List<String> recentQueries = const [],
  List<String> liveIds = const [],
  _Broadcasts? broadcasts,
  Future<List<SearchPlayer>> Function()? players,
  List<OpeningSearchSuggestion> openings = const [],
  Future<List<OpeningSearchSuggestion>>? openingsLater,
  List<GroupEventCardModel> upcoming = const [],
  NavigatorObserver? observer,
  _Builds? builds,
  (String, Completer<EnhancedSearchResult>)? slowQuery,
  Future<EnhancedSearchResult>? Function(String query)? answer,
  FavoriteEventsNotifier Function()? favorites,
  List<Collection> collections = const [],
  List<FeedNews> news = const [],
  SearchNewsFeed Function()? newsFeed,
  _Ranking? ranking,
  bool reduceMotion = false,
  EdgeInsets padding = EdgeInsets.zero,
  _MemorySearchRecents? recentsStorage,
  List<Override> overrides = const [],
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  addTearDown(tester.view.reset);
  final page = ValueNotifier(_Page.search);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        liveGroupBroadcastIdsProvider.overrideWith(
          (ref) => Stream.value(liveIds),
        ),
        groupBroadcastRepositoryProvider.overrideWith(
          (ref) => broadcasts ?? _Broadcasts(),
        ),
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
        recentSearchStorageProvider.overrideWithValue(_MemoryRecentSearches()),
        searchRecentsStorageProvider.overrideWithValue(
          recentsStorage ?? _MemorySearchRecents(),
        ),
        // The catalog's own search, over the collections the landing lists.
        collectionsRepositoryProvider.overrideWithValue(
          _SearchedCollections(collections),
        ),
        currentUserProvider.overrideWithValue(
          AppUser(
            id: 'u1',
            displayName: 'Test User',
            createdAt: DateTime(2026),
          ),
        ),
        subscriptionProvider.overrideWith((ref) => _FreeSubscription()),
        supabaseCombinedSearchProvider.overrideWith((ref, query) async {
          final answered = answer?.call(query.trim());
          if (answered != null) return answered;
          final slow = slowQuery;
          if (slow != null && slow.$1 == query.trim()) return slow.$2.future;
          return _resultsByQuery[query.trim()] ?? EnhancedSearchResult.empty();
        }),
        ...overrides,
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
            const tab = SearchTabScreen();
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
  // The tab's own history, newest first as given.
  final history = container.read(searchRecentsProvider.notifier);
  for (final pick in [
    ...recents.map(SearchRecentPick.fromEntry),
    ...recentPicks,
  ].reversed) {
    await history.recordPick(pick);
  }
  for (final query in recentQueries.reversed) {
    await history.recordQuery(query);
  }
  await tester.pump();
  await tester.pump();
  return _App(tester, container, page);
}

/// Magnus Carlsen's name on the first Top players card, in whichever form
/// the card's width allows (the full name, "M. Carlsen", the surname).
Finder _topCarlsen() => find.descendant(
  of: find.byKey(const ValueKey('search-top-players-0')),
  matching: find.textContaining('Carlsen'),
);

/// Search's own bars: its field's row steps away with the page and back.
ScrollChromeController _pageChrome(WidgetTester tester) => tester
    .widget<CollapsingChrome>(
      find
          .descendant(
            of: find.byType(SearchTabScreen),
            matching: find.byType(CollapsingChrome),
          )
          .first,
    )
    .controller;

/// Whether the Search tab's field has the cursor.
bool _fieldHasFocus(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey('search_tab_field')),
        matching: find.byType(EditableText),
      ),
    )
    .focusNode
    .hasFocus;

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

/// The Search tab's history on a pretend device: [stored] is what a write
/// left there.
class _MemorySearchRecents implements SearchRecentsStorage {
  String? stored;

  @override
  Future<String?> read() async => stored;

  @override
  Future<void> write(String value) async => stored = value;
}

/// The collections catalog's search over [items]: a book whose title or
/// author holds the words.
class _SearchedCollections implements CollectionsRepository {
  _SearchedCollections(this.items);

  final List<Collection> items;
  final queries = <String>[];

  @override
  Future<CollectionsPage> searchBooks(
    CollectionSearchQuery query,
    int offset,
  ) async {
    queries.add(query.text);
    final words = query.text.toLowerCase();
    final found = [
      for (final item in items)
        if ('${item.title} ${item.author ?? ''}'.toLowerCase().contains(words))
          item,
    ];
    return CollectionsPage(
      items: found,
      total: found.length,
      limit: 40,
      offset: offset,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  int players = 0;
  int openings = 0;
  int upcoming = 0;
}

/// Group broadcast reads: a by-id lookup recorded (and never answered),
/// and the tours behind any event card's long-press, answered at once.
class _Broadcasts implements GroupBroadcastRepository {
  final calls = <List<String>>[];

  @override
  Future<List<GroupBroadcast>> getGroupBroadcastsByIdsOrNames(
    List<String> identifiers,
  ) {
    calls.add(List.of(identifiers));
    return Completer<List<GroupBroadcast>>().future;
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

/// The landing's openings, resolved by the opening search as the app does.
final _landingOpenings = resolveSearchLandingOpenings(
  searchLandingOpeningQueries,
);

final _resultsByQuery = {
  'carlsen': _playerResults('Carlsen, Magnus', 1503014),
  'nakamura': _playerResults('Nakamura, Hikaru', 2016192),
  'najdorf': _najdorfResults(),
  'tata': _eventResults([_pastTataEvent, _liveEventAsFound]),
};

/// The app-wide search's answer of [events], in that order.
EnhancedSearchResult _eventResults(List<GroupEventCardModel> events) =>
    EnhancedSearchResult(
      tournamentResults: [
        for (final event in events)
          SearchResult(
            tournament: event,
            score: 1,
            matchedText: event.title,
            type: SearchResultType.tournament,
          ),
      ],
      playerResults: const [],
    );

/// Last year's edition: found by the search, finished.
final _pastTataEvent = GroupEventCardModel(
  id: 'tata-2026',
  title: 'Tata Steel Masters 2026',
  dates: 'Jan 16 - Feb 1, 2026',
  maxAvgElo: 2740,
  timeUntilStart: '',
  tourEventCategory: TourEventCategory.completed,
  timeControl: 'Standard',
  startDate: DateTime.utc(2026, 1, 16),
  endDate: DateTime.utc(2026, 2, 1),
);

/// [_liveEvent] as the app-wide search returns it, nothing on it to say it
/// is live: the live set does.
final _liveEventAsFound = GroupEventCardModel(
  id: _liveEvent.id,
  title: _liveEvent.title,
  dates: _liveEvent.dates,
  maxAvgElo: _liveEvent.maxAvgElo,
  timeUntilStart: '',
  tourEventCategory: TourEventCategory.ongoing,
  timeControl: _liveEvent.timeControl,
  startDate: _liveEvent.startDate,
  endDate: _liveEvent.endDate,
);

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

/// [section]'s row on the landing ([SearchCarousel]).
Finder _row(String section) => find.byWidgetPredicate(
  (widget) => widget is SearchCarousel && widget.section == section,
);

/// An event page as it leaves: TournamentDetailScreen's cleanup resets the
/// app-wide query as its page goes.
class _LeavingEventPage extends ConsumerStatefulWidget {
  const _LeavingEventPage();

  @override
  ConsumerState<_LeavingEventPage> createState() => _LeavingEventPageState();
}

class _LeavingEventPageState extends ConsumerState<_LeavingEventPage> {
  @override
  void deactivate() {
    ref.invalidate(searchQueryProvider);
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('an event'));
}
