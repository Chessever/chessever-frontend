import 'dart:async';

import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/providers/auth_state_provider.dart';
import 'package:chessever2/repository/authentication/model/app_user.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart';
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart';
import 'package:chessever2/screens/group_event/providers/supabase_combined_search_provider.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_event_screen.dart';
import 'package:chessever2/screens/player_profile/player_profile_screen.dart';
import 'package:chessever2/screens/player_profile/widgets/lifted_row_menu.dart';
import 'package:chessever2/screens/search/search_landing.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/home_top_bar.dart';
import 'package:chessever2/widgets/live_first_mark.dart';
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
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// The app-wide search now lives on the Search tab; the Events lists (opened
/// from Profile) keep a search field of their own. Both drive the same
/// app-wide search providers, so neither may show the other's query.
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

  testWidgets('one page: no drop-down, no placeholder copy, results in '
      'place as you type', (tester) async {
    final app = await _pump(
      tester,
      live: [_liveEvent],
      openings: _landingOpenings,
    );
    final page = find.byKey(const ValueKey('search_tab_page'));
    expect(page, findsOneWidget);
    // Nothing typed: the landing, real rows and no placeholder copy.
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

  group('the landing (nothing typed)', () {
    testWidgets('lists live events, top players and openings, in that order '
        'and as one list', (tester) async {
      final app = await _pump(
        tester,
        live: [_liveEvent, _secondLiveEvent],
        players: () async => _topPlayers,
        openings: _landingOpenings,
      );
      final landing = find.byKey(const ValueKey('search_landing'));
      expect(landing, findsOneWidget);

      final live = find.text('Live now');
      final players = find.text('Top players');
      final openings = find.text('Openings');
      for (final heading in [live, players, openings]) {
        expect(find.descendant(of: landing, matching: heading), findsOneWidget);
      }
      expect(
        tester.getTopLeft(live).dy,
        lessThan(tester.getTopLeft(players).dy),
      );
      expect(
        tester.getTopLeft(players).dy,
        lessThan(tester.getTopLeft(openings).dy),
      );

      // Live now: the event, the shared Live mark, the average rating.
      final firstLive = find.byKey(ValueKey('search-live-${_liveEvent.id}'));
      expect(
        find.descendant(of: firstLive, matching: find.text(_liveEvent.title)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: firstLive, matching: find.byType(LiveFirstMark)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: firstLive,
          matching: find.textContaining('Ø ${_liveEvent.maxAvgElo}'),
        ),
        findsOneWidget,
      );
      expect(find.text(_secondLiveEvent.title), findsOneWidget);

      // Top players, as a recent player search reads.
      expect(find.text('Carlsen, Magnus'), findsOneWidget);
      expect(find.text('GM · 2833 · NOR'), findsOneWidget);

      // Openings: the opening search's own cards.
      for (final opening in _landingOpenings.take(2)) {
        expect(
          find.byKey(ValueKey('opening-result-${opening.id}')),
          findsOneWidget,
        );
      }

      _expectNoPlaceholderCopy();

      // Every row is a full 44pt target at the least.
      for (final row in [
        firstLive,
        find.byKey(const ValueKey('search-top-player-1503014')),
      ]) {
        expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
      }
      await app.dispose();
    });

    testWidgets('recent searches come first, with Clear', (tester) async {
      final app = await _pump(
        tester,
        recents: [RecentSearchEntry.tournament(_event)],
        live: [_liveEvent],
        openings: _landingOpenings,
      );
      await tester.pump();
      final recent = find.text('Recent searches');
      expect(recent, findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
      expect(
        tester.getTopLeft(recent).dy,
        lessThan(tester.getTopLeft(find.text('Live now')).dy),
      );
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
      expect(find.text('Live now'), findsNothing);
      expect(find.text('Top players'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Openings'), findsOneWidget);
      _expectNoPlaceholderCopy();
      await app.dispose();
    });

    testWidgets('a slow ranking read shows one quiet row, no copy', (
      tester,
    ) async {
      final pending = Completer<List<SearchPlayer>>();
      final app = await _pump(
        tester,
        players: () => pending.future,
        openings: _landingOpenings,
      );
      expect(find.text('Top players'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      _expectNoPlaceholderCopy();

      pending.complete(_topPlayers);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Carlsen, Magnus'), findsOneWidget);
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
      expect(find.text('Carlsen, Magnus'), findsOneWidget);
      await app.dispose();
    });

    testWidgets('a live event opens as a searched event does', (tester) async {
      final app = await _pump(tester, live: [_liveEvent]);
      await tester.tap(find.byKey(ValueKey('search-live-${_liveEvent.id}')));
      await tester.pump();

      final navigation =
          app.read(tournamentNavigationProvider) as _RecordingNavigation;
      expect(navigation.opened, [
        (_liveEvent.id, GroupEventCategory.search, 'forYouSearch'),
      ]);
      await app.dispose();
    });

    testWidgets('a top player opens their profile', (tester) async {
      final observer = _PushObserver();
      final app = await _pump(
        tester,
        players: () async => _topPlayers,
        observer: observer,
      );
      await tester.tap(find.text('Carlsen, Magnus'));

      final profile = observer.lastPage(tester);
      expect(profile, isA<PlayerProfileScreen>());
      profile as PlayerProfileScreen;
      expect(profile.fideId, 1503014);
      expect(profile.playerName, 'Carlsen, Magnus');
      expect(profile.rating, 2833);
      await app.dispose();
    });

    testWidgets('an opening opens what its search result opens', (
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

      final screen = observer.lastPage(tester);
      expect(screen, isA<SmartEventScreen>());
      screen as SmartEventScreen;
      expect(screen.request.eco.code, sicilian.filter.code);
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
              () => find.byKey(const ValueKey('search-top-player-1503014')),
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
          // The pushed page is never built: only the record is flushed.
          await tester.binding.delayed(Duration.zero);

          final recents = app.read(recentSearchesProvider).valueOrNull!;
          expect(recents, hasLength(1));
          check(recents.single);
          await app.dispose();
        });
      }
    });

    testWidgets('each row is one button a screen reader can press', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final app = await _pump(
        tester,
        live: [_liveEvent],
        players: () async => _topPlayers,
      );
      // A row is no semantics boundary of its own, so its node is found by
      // what it reads as, not by walking up from the widget.
      final liveLabel = searchLiveEventSemantics(_liveEvent);
      final playerLabel = searchTopPlayerSemantics(_topPlayers.first, 1);
      for (final heading in ['Live now', 'Top players']) {
        expect(
          find.semantics.byLabel(heading).evaluate().single,
          isSemantics(label: heading, isHeader: true, isButton: false),
          reason: heading,
        );
      }
      for (final label in [liveLabel, playerLabel]) {
        expect(
          find.semantics.byLabel(label).evaluate().single,
          isSemantics(
            label: label,
            isButton: true,
            hasTapAction: true,
            // The row's focus menu, from the lift around it.
            hasLongPressAction: true,
          ),
          reason: label,
        );
      }

      // Pressed through assistive technology, it opens like a touch does.
      tester.semantics.tap(find.semantics.byLabel(liveLabel));
      await tester.pump();
      final navigation =
          app.read(tournamentNavigationProvider) as _RecordingNavigation;
      expect(navigation.opened, [
        (_liveEvent.id, GroupEventCategory.search, 'forYouSearch'),
      ]);
      await app.dispose();
      semantics.dispose();
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
      expect((builds.live, builds.players, builds.openings), (1, 1, 1));
      expect(repo.calls, [
        [_secondLiveEvent.id],
      ]);
      repo.answer([_secondLiveBroadcast]);
      await tester.pump();

      await _type(tester, const ValueKey('search_tab_field'), 'nakamura');
      expect(find.byKey(const ValueKey('search_landing')), findsNothing);
      await _type(tester, const ValueKey('search_tab_field'), '');
      expect(find.text(_secondLiveEvent.title), findsOneWidget);

      expect((builds.live, builds.players, builds.openings), (1, 1, 1));
      expect(repo.calls, hasLength(1));
      await app.dispose();
    });

    testWidgets('live events found late land in room already held: the '
        'rows on screen and the sections below do not move', (tester) async {
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
      expect(find.byKey(const ValueKey('search-live-pending')), findsOneWidget);
      double top(Finder finder) => tester.getTopLeft(finder).dy;
      final listed = top(find.text(_liveEvent.title));
      final players = top(find.text('Top players'));
      final openings = top(find.text('Openings'));

      repo.answer([_secondLiveBroadcast]);
      await tester.pump();
      expect(find.text(_secondLiveEvent.title), findsOneWidget);
      expect(find.byKey(const ValueKey('search-live-pending')), findsNothing);
      expect(top(find.text(_liveEvent.title)), listed);
      expect(top(find.text(_secondLiveEvent.title)), greaterThan(listed));
      expect(top(find.text('Top players')), players);
      expect(top(find.text('Openings')), openings);
      _expectNoPlaceholderCopy();
      await app.dispose();
    });

    testWidgets('a slow ranking read holds its rows\' room: Openings does '
        'not move when the players land', (tester) async {
      final pending = Completer<List<SearchPlayer>>();
      final app = await _pump(
        tester,
        players: () => pending.future,
        openings: _landingOpenings,
      );
      final openings = tester.getTopLeft(find.text('Openings')).dy;

      pending.complete(_topPlayers);
      await tester.pump();
      expect(find.text('Gukesh D'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Openings')).dy, openings);
      await app.dispose();
    });

    testWidgets('every heading sits the same distance above its first row, '
        'with Clear beside it or not', (tester) async {
      final app = await _pump(
        tester,
        recents: [RecentSearchEntry.tournament(_event)],
        live: [_liveEvent],
        players: () async => _topPlayers,
      );
      await tester.pump();
      double gap(String heading, Finder firstRow) =>
          tester.getTopLeft(firstRow).dy -
          tester.getCenter(find.text(heading)).dy;

      final recent = gap(
        'Recent searches',
        find
            .ancestor(
              of: find.text(_event.title),
              matching: find.byType(LiftedRowMenu),
            )
            .first,
      );
      final live = gap(
        'Live now',
        find.byKey(ValueKey('search-live-${_liveEvent.id}')),
      );
      final players = gap(
        'Top players',
        find.byKey(const ValueKey('search-top-player-1503014')),
      );
      expect(recent, closeTo(live, 0.01));
      expect(players, closeTo(live, 0.01));
      await app.dispose();
    });

    for (final size in const [Size(393, 852), Size(375, 667)]) {
      testWidgets('${size.width.round()}x${size.height.round()}: headings, '
          'rows and cards start on the field\'s gutter', (tester) async {
        final app = await _pump(
          tester,
          size: size,
          recents: [RecentSearchEntry.tournament(_event)],
          live: [_liveEvent],
          players: () async => _topPlayers,
          openings: _landingOpenings,
        );
        await tester.pump();
        if (size.height < 852) {
          // The reason for this size: `.w` and `.sp` part here.
          expect(12.w, isNot(closeTo(12.sp, 0.01)));
        }
        final field = tester.getTopLeft(find.byType(EnhancedRoundedSearchBar));
        expect(field.dx, closeTo(HomeTopBarMetrics.horizontalPadding, 0.01));
        // After each row's glyph column.
        final words = field.dx + 17.ic + 10.w;
        for (final text in [
          'Recent searches',
          _event.title,
          'Live now',
          _liveEvent.title,
          'Top players',
          'Carlsen, Magnus',
        ]) {
          expect(
            tester.getTopLeft(find.text(text)).dx,
            closeTo(words, 0.01),
            reason: text,
          );
        }
        await tester.scrollUntilVisible(
          find.text('Openings'),
          200,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('search_landing')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(
          tester.getTopLeft(find.text('Openings')).dx,
          closeTo(words, 0.01),
        );
        expect(
          tester
              .getTopLeft(
                find.byKey(
                  ValueKey('opening-result-${_landingOpenings.first.id}'),
                ),
              )
              .dx,
          closeTo(field.dx, 0.01),
        );

        await _type(tester, const ValueKey('search_tab_field'), 'qqqq');
        expect(
          tester.getTopLeft(find.textContaining('No matches')).dx,
          closeTo(field.dx, 0.01),
        );
        await app.dispose();
      });
    }

    for (final scale in const [1.0, 1.3]) {
      testWidgets('text at ${scale}x: an opening card stands as tall as what '
          'it holds, all of it inside', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final app = await _pump(tester, openings: _landingOpenings);
        for (final opening in _landingOpenings.take(2)) {
          final card = find.byKey(ValueKey('opening-result-${opening.id}'));
          final scope = find.descendant(
            of: card,
            matching: find.text(opening.subtitle),
          );
          final cardBox = tester.getRect(card);
          final scopeBox = tester.getRect(scope);
          expect(cardBox.height, lessThan(100), reason: opening.title);
          // Clear of the bottom edge, with no empty half under it.
          expect(scopeBox.bottom, lessThanOrEqualTo(cardBox.bottom - 8.h));
          expect(cardBox.bottom - scopeBox.bottom, lessThan(8.h + 4));
          expect(
            find.descendant(
              of: card,
              matching: find.byKey(const ValueKey('opening-all-star')),
            ),
            findsOneWidget,
            reason: '${opening.title} is a whole family',
          );
        }
        await app.dispose();
      });
    }

    for (final (name, theme, colors) in [
      ('light', AppTheme.lightTheme, AppColors.light),
      ('dark', AppTheme.darkTheme, AppColors.dark),
    ]) {
      testWidgets('$name: row ink clears AA on the page', (tester) async {
        final app = await _pump(
          tester,
          theme: theme,
          live: [_liveEvent],
          players: () async => _topPlayers,
        );
        for (final text in [
          _liveEvent.title,
          searchLiveEventSubtitle(_liveEvent),
          'Carlsen, Magnus',
          'GM · 2833 · NOR',
          // The rank in the glyph column.
          '1',
          'Live now',
          'Top players',
        ]) {
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

/// Records pushed pages without building them: the destinations are whole
/// screens with their own backends.
class _PushObserver extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }

  Widget lastPage(WidgetTester tester) {
    final route = pushed.last;
    expect(route, isA<MaterialPageRoute<dynamic>>());
    return (route as MaterialPageRoute<dynamic>).builder(
      tester.element(find.byType(SearchTabScreen)),
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

/// The Search tab under test. The landing's sources are fixtures: nothing
/// live, no ranking and no openings unless a test passes them.
///
/// [liveSource] runs the real Live now instead ([_realLive]); [builds]
/// counts how often each landing source is built.
Future<_App> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  Size size = const Size(393, 852),
  List<RecentSearchEntry> recents = const [],
  List<GroupEventCardModel> live = const [],
  List<Override>? liveSource,
  Future<List<SearchPlayer>> Function()? players,
  List<OpeningSearchSuggestion> openings = const [],
  NavigatorObserver? observer,
  _Builds? builds,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  addTearDown(tester.view.reset);
  final page = ValueNotifier(_Page.search);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...liveSource ??
            [
              searchLiveNowProvider.overrideWith(
                () => _FixedLiveNow(SearchLiveNow(events: live), builds),
              ),
            ],
        searchTopPlayersProvider.overrideWith((ref) {
          builds?.players++;
          return players == null ? <SearchPlayer>[] : players();
        }),
        searchLandingOpeningsProvider.overrideWith((ref) async {
          builds?.openings++;
          return openings;
        }),
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
        supabaseCombinedSearchProvider.overrideWith(
          (ref, query) async =>
              _resultsByQuery[query.trim()] ?? EnhancedSearchResult.empty(),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.darkTheme,
        navigatorObservers: [?observer],
        home: Builder(
          builder: (context) {
            ResponsiveHelper.init(context);
            return Scaffold(
              resizeToAvoidBottomInset: false,
              body: ValueListenableBuilder(
                valueListenable: page,
                builder: (context, shown, _) => switch (shown) {
                  _Page.search => const SearchTabScreen(),
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
  return _App(tester, container, page);
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
  SearchPlayer(
    id: 'search_46616543',
    name: 'Gukesh D',
    title: 'GM',
    rating: 2777,
    fideId: 46616543,
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

/// A by-id lookup the test answers.
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
};
