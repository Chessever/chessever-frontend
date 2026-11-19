import 'dart:async';

import 'package:chessever2/repository/authentication/auth_repository.dart';
import 'package:chessever2/repository/authentication/model/auth_state.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_broadcast.dart';
import 'package:chessever2/repository/supabase/group_broadcast/group_tour_repository.dart';
import 'package:chessever2/repository/supabase/tour/tour.dart';
import 'package:chessever2/repository/supabase/tour/tour_repository.dart';
import 'package:chessever2/screens/for_you/open_for_you_event.dart'
    show ForYouEventSource;
import 'package:chessever2/screens/group_event/providers/group_event_screen_provider.dart'
    show tournamentNavigationProvider, TournamentNavigationController;
import 'package:chessever2/screens/group_event/providers/live_group_broadcast_id_provider.dart'
    show liveGroupBroadcastIdsProvider;
import 'package:chessever2/screens/player_profile/player_profile_data_source.dart';
import 'package:chessever2/screens/player_profile/provider/player_profile_provider.dart'
    show PlayerProfileEventCardRequest;
import 'package:chessever2/screens/player_profile/widgets/player_profile_resolved_event_card.dart'
    show playerProfileFallbackEventSpaceDraft;
import 'package:chessever2/screens/tour_detail/provider/tour_detail_mode_provider.dart';
import 'package:chessever2/screens/tour_detail/provider/tour_detail_repo_provider.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/screens/countrymen/countrymen_tab_screen.dart';
import 'package:chessever2/screens/group_event/group_event_screen.dart'
    show GroupEventCategory;
import 'package:chessever2/screens/library/providers/library_folders_provider.dart'
    show kTwicBookId;
import 'package:chessever2/screens/my_space/actions/space_share.dart';
import 'package:chessever2/screens/my_space/models/space_shortcut.dart';
import 'package:chessever2/screens/my_space/navigation/space_shortcut_navigator.dart';
import 'package:chessever2/screens/my_space/providers/space_shortcuts_provider.dart';
import 'package:chessever2/repository/supabase/calendar_event/calendar_event.dart';
import 'package:chessever2/screens/group_event/model/tour_event_card_model.dart';
import 'package:chessever2/widgets/event_card/event_context_menu.dart'
    show eventSpaceDraft;
import 'package:chessever2/widgets/space_shortcut_drafts.dart';
import 'package:chessever2/widgets/search/search_overlay_widget.dart'
    show searchEventSpaceDraft;
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/paywall/past_event_access.dart'
    show currentEventMembershipProvider, pastEventMembershipProvider;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SpaceShortcut _s(
  SpaceShortcutKind kind,
  String targetId, {
  String title = 'Title',
  Map<String, dynamic> params = const {},
}) => SpaceShortcut(
  id: 'x',
  kind: kind,
  targetId: targetId,
  title: title,
  params: params,
);

void main() {
  // A free reader's past-event gate raises the real Premium prompt, which
  // asks Supabase who is signed in (nobody: the sign-in step).
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.app_links/events'),
          (_) async => null,
        );
    await Supabase.initialize(
      url: 'https://fixture.invalid',
      publishableKey: 'fixture-publishable-key',
    );
  });

  group('a saved event opens as the Events lists open it', () {
    final now = DateTime.now();
    GroupBroadcast broadcast(DateTime start, DateTime end) => GroupBroadcast(
      id: 'gb-1',
      createdAt: start,
      name: 'Norway Chess',
      search: const [],
      dateStart: start,
      dateEnd: end,
    );
    final finished = broadcast(
      now.subtract(const Duration(days: 40)),
      now.subtract(const Duration(days: 30)),
    );
    final running = broadcast(
      now.subtract(const Duration(days: 2)),
      now.add(const Duration(days: 5)),
    );
    final upcoming = broadcast(
      now.add(const Duration(days: 5)),
      now.add(const Duration(days: 12)),
    );

    test('a finished event asks as a Past card does', () {
      expect(
        spaceEventOpenCategory(finished, const []),
        GroupEventCategory.past,
      );
    });

    test('only a live one opens as a Current card does', () {
      expect(
        spaceEventOpenCategory(running, const ['gb-1']),
        GroupEventCategory.current,
      );
      // The live feed outranks finished dates, as on the card.
      expect(
        spaceEventOpenCategory(finished, const ['gb-1']),
        GroupEventCategory.current,
      );
    });

    test('a running or upcoming one asks as a search hit does: the server '
        'decides Past, not the card\'s dates', () {
      expect(
        spaceEventOpenCategory(running, const []),
        GroupEventCategory.search,
      );
      expect(
        spaceEventOpenCategory(upcoming, const []),
        GroupEventCategory.search,
      );
    });
  });

  group('a saved event opens from the broadcast its card holds', () {
    final now = DateTime.now();
    final norway = GroupBroadcast(
      id: 'gb-1',
      createdAt: now,
      name: 'Norway Chess',
      search: const [],
      dateStart: now.subtract(const Duration(days: 2)),
      dateEnd: now.add(const Duration(days: 5)),
    );
    final card = GroupEventCardModel.fromGroupBroadcast(norway, const []);

    test('when the pin names that broadcast', () {
      // The Events list card's own pin, and an older one naming its group.
      expect(spaceEventInHand(eventSpaceDraft(card), [norway]), same(norway));
      expect(
        spaceEventInHand(
          _s(
            SpaceShortcutKind.event,
            'tour-9',
            params: {'groupBroadcastId': 'gb-1'},
          ),
          [norway],
        ),
        same(norway),
      );
    });

    test('never for a pin saved on a category, nor one keyed by a tour id', () {
      // Saved from inside the event, on its Women category.
      expect(
        spaceEventInHand(
          _s(
            SpaceShortcutKind.event,
            'gb-1',
            params: {'groupBroadcastId': 'gb-1', 'tourId': 'tour-9'},
          ),
          [norway],
        ),
        isNull,
      );
      // A player profile's fallback event card keys its pin by the tour.
      final fallback = playerProfileFallbackEventSpaceDraft(
        request: const PlayerProfileEventCardRequest(
          dataSource: PlayerProfileDataSource.supabase,
          tourId: 'tour-9',
          tourName: 'Norway Chess Women',
        ),
        card: card,
      );
      expect(fallback.targetId, 'tour-9');
      expect(spaceEventInHand(fallback, [norway]), isNull);
    });

    test('nor before the card has read its broadcast', () {
      expect(spaceEventInHand(eventSpaceDraft(card), const []), isNull);
    });
  });

  group('tapping a saved event', () {
    final now = DateTime.now();
    final running = GroupBroadcast(
      id: 'gb-1',
      createdAt: now,
      name: 'Norway Chess',
      search: const [],
      dateStart: now.subtract(const Duration(days: 2)),
      dateEnd: now.add(const Duration(days: 5)),
    );
    final finished = GroupBroadcast(
      id: 'gb-2',
      createdAt: now,
      name: 'Tata Steel',
      search: const [],
      dateStart: now.subtract(const Duration(days: 40)),
      dateEnd: now.subtract(const Duration(days: 30)),
    );

    testWidgets('a running event its card holds pushes from it at once, '
        'logged from My Space', (tester) async {
      final pin = eventSpaceDraft(
        GroupEventCardModel.fromGroupBroadcast(running, const []),
      );
      final host = await _EventHost.pump(tester, [pin], [running]);
      await host.open(tester, pin, known: [running, finished]);

      final call = host.opens.single;
      expect(call.id, 'gb-1');
      // Gated as a search hit (Premium passes at once).
      expect(call.category, GroupEventCategory.search);
      expect(call.known, [same(running)]);
      expect(call.source, ForYouEventSource.mySpace.analyticsLabel);
      expect(call.source, 'forYouMySpace');
      // Nothing asked of the network before the push.
      expect(host.groups.requested, isEmpty);
      expect(host.tours.requested, isEmpty);
      expect(host.pushed, ['/tournament_detail_screen']);
      expect(host.read(selectedBroadcastModelProvider), same(running));
      expect(host.store.opened, [pin.id]);
    });

    testWidgets('a finished one asks as a Past card does', (tester) async {
      final pin = eventSpaceDraft(
        GroupEventCardModel.fromGroupBroadcast(finished, const []),
      );
      final host = await _EventHost.pump(tester, [pin], [finished]);
      await host.open(tester, pin, known: [finished]);

      expect(host.opens.single.category, GroupEventCategory.past);
      expect(host.groups.requested, isEmpty);
      expect(host.pushed, ['/tournament_detail_screen']);
    });

    testWidgets('a free reader is asked for Premium when the server lists the '
        'event as past, though its dates say it is running', (tester) async {
      final pin = eventSpaceDraft(
        GroupEventCardModel.fromGroupBroadcast(running, const []),
      );
      final pastAsked = <String>[];
      final host = await _EventHost.pump(
        tester,
        [pin],
        [running],
        premium: false,
        overrides: [
          pastEventMembershipProvider.overrideWith((_, id) async {
            pastAsked.add(id);
            return id == 'gb-1';
          }),
          currentEventMembershipProvider.overrideWith((_, _) async => false),
        ],
      );
      await host.open(tester, pin, known: [running]);

      expect(host.opens.single.category, GroupEventCategory.search);
      // The server's Past list was asked, and it answered past.
      expect(pastAsked, ['gb-1']);
      expect(find.text('Sign in to get Premium'), findsOneWidget);
      expect(host.pushed, isEmpty);
      expect(host.read(selectedBroadcastModelProvider), isNull);

      // Backing out of the paywall opens nothing and is not a dead shortcut.
      Navigator.of(tester.element(find.text('Sign in to get Premium'))).pop();
      await _settle(tester);
      expect(host.pushed, isEmpty);
      expect(find.text('This shortcut can no longer open'), findsNothing);
      // Nothing asked of the network for the event itself.
      expect(host.groups.requested, isEmpty);
    });

    testWidgets('a free reader opens a running event the server does not '
        'list as past at once', (tester) async {
      final pin = eventSpaceDraft(
        GroupEventCardModel.fromGroupBroadcast(running, const []),
      );
      final pastAsked = <String>[];
      final host = await _EventHost.pump(
        tester,
        [pin],
        [running],
        premium: false,
        overrides: [
          pastEventMembershipProvider.overrideWith((_, id) async {
            pastAsked.add(id);
            return false;
          }),
          currentEventMembershipProvider.overrideWith((_, _) async => false),
        ],
      );
      await host.open(tester, pin, known: [running]);

      expect(pastAsked, ['gb-1']);
      expect(find.text('Sign in to get Premium'), findsNothing);
      expect(host.pushed, ['/tournament_detail_screen']);
      expect(host.read(selectedBroadcastModelProvider), same(running));
    });

    testWidgets('a pin keyed by a tour id reopens on that category', (
      tester,
    ) async {
      final pin = playerProfileFallbackEventSpaceDraft(
        request: const PlayerProfileEventCardRequest(
          dataSource: PlayerProfileDataSource.supabase,
          tourId: 'tour-9',
          tourName: 'Norway Chess Women',
        ),
        card: GroupEventCardModel.fromGroupBroadcast(running, const []),
      );
      final host = await _EventHost.pump(tester, [pin], [running]);
      // Its group's broadcast is in hand, read by the group's id.
      await host.open(tester, pin, known: [running]);

      expect(host.opens, isEmpty);
      expect(host.tours.requested, ['tour-9']);
      expect(host.groups.requested, ['gb-1']);
      expect(host.selection.saved, [('gb-1', 'tour-9')]);
      expect(host.pushed, ['/tournament_detail_screen']);
      expect(host.read(selectedBroadcastModelProvider)?.id, 'gb-1');
    });

    testWidgets('a pin saved on a category reopens on it, broadcast in hand '
        'or not', (tester) async {
      final pin = SpaceShortcut(
        id: 'women',
        kind: SpaceShortcutKind.event,
        targetId: 'gb-1',
        title: 'Norway Chess',
        params: const {'groupBroadcastId': 'gb-1', 'tourId': 'tour-9'},
      );
      final host = await _EventHost.pump(tester, [pin], [running]);
      await host.open(tester, pin, known: [running]);

      expect(host.opens, isEmpty);
      expect(host.selection.saved, [('gb-1', 'tour-9')]);
      expect(host.pushed, ['/tournament_detail_screen']);
    });

    testWidgets('one whose broadcast is not read yet still opens, through the '
        'resolver', (tester) async {
      final pin = eventSpaceDraft(
        GroupEventCardModel.fromGroupBroadcast(running, const []),
      );
      final host = await _EventHost.pump(tester, [pin], [running]);
      await host.open(tester, pin, known: const []);

      expect(host.opens, isEmpty);
      // Probed as a tour id first, then opened as the group it is.
      expect(host.tours.requested, ['gb-1']);
      expect(host.groups.requested, ['gb-1']);
      expect(host.selection.saved, isEmpty);
      expect(host.pushed, ['/tournament_detail_screen']);
    });
  });

  group('ChessEver Database event folders', () {
    test('open the database filtered to the pinned event', () {
      expect(
        spaceTwicEventName(
          _s(
            SpaceShortcutKind.folder,
            '$kTwicBookId:Tata Steel Masters 2026',
            params: {'event': 'Tata Steel Masters 2026'},
          ),
        ),
        'Tata Steel Masters 2026',
      );
      // The event survives in the target alone.
      expect(
        spaceTwicEventName(
          _s(SpaceShortcutKind.folder, '$kTwicBookId:Norway Chess'),
        ),
        'Norway Chess',
      );
    });

    test('leave the whole database and every other folder as they were', () {
      expect(
        spaceTwicEventName(_s(SpaceShortcutKind.folder, kTwicBookId)),
        isNull,
      );
      expect(
        spaceTwicEventName(_s(SpaceShortcutKind.folder, 'uuid-1')),
        isNull,
      );
      expect(
        spaceTwicEventName(_s(SpaceShortcutKind.event, '$kTwicBookId:X')),
        isNull,
      );
    });
  });

  group('calendar events', () {
    test('new pins say so in source, old ones by their card', () {
      expect(
        isSpaceCalendarEvent(
          _s(
            SpaceShortcutKind.event,
            'cal_event_fide_world_cup_2027',
            params: {
              'source': 'calendar',
              'calendarEventId': 'FIDE World Cup 2027',
            },
          ),
        ),
        isTrue,
      );
      expect(
        isSpaceCalendarEvent(
          _s(
            SpaceShortcutKind.event,
            'anything',
            params: {'eventSource': 'communityEvent'},
          ),
        ),
        isTrue,
      );
      expect(
        isSpaceCalendarEvent(_s(SpaceShortcutKind.event, 'cal_event_x')),
        isTrue,
      );
    });

    test('broadcast pins with unknown params still open as broadcasts', () {
      expect(
        isSpaceCalendarEvent(
          _s(
            SpaceShortcutKind.event,
            'gb-123',
            params: {
              'eventSource': 'lichessBroadcast',
              'somethingNew': {'nested': true},
              'tourId': 't1',
            },
          ),
        ),
        isFalse,
      );
      expect(
        isSpaceCalendarEvent(
          _s(SpaceShortcutKind.round, 'r1', params: {'source': 'calendar'}),
        ),
        isFalse,
      );
    });

    test('are looked up by name, never by the card id', () {
      expect(
        spaceCalendarEventNames(
          _s(
            SpaceShortcutKind.event,
            'cal_event_fide_world_cup_2027',
            title: 'FIDE World Cup 2027',
            params: {
              'source': 'calendar',
              'calendarEventId': 'FIDE World Cup 2027',
            },
          ),
        ),
        ['FIDE World Cup 2027'],
      );
      expect(
        spaceCalendarEventNames(
          _s(
            SpaceShortcutKind.event,
            'cal_event_open',
            title: 'Open, Round (A)',
            params: {'calendarEventId': 'cal_event_open'},
          ),
        ),
        ['Open, Round (A)'],
      );
    });
  });

  group('links', () {
    test('team and scorecard share URLs are routable', () {
      for (final url in [
        'https://chessever.com/broadcast/olympiad-2026/abc123/team/Norway',
        'https://chessever.com/broadcast/olympiad-2026/abc123/player/1503014',
        'https://chessever.com/broadcast/olympiad-2026/abc123?tab=standings',
        'https://chessever.com/player/1503014',
        'https://chessever.com/games/AbCdEfGh',
        'https://chessever.com/collections/tata-steel-2026',
        'com.chessever.app://broadcast/abc123',
        'com.chessever.app://collections/tata-steel-2026',
      ]) {
        expect(isRoutableSpaceLink(Uri.parse(url)), isTrue, reason: url);
      }
    });

    test('anything else is not', () {
      for (final url in [
        'https://chessever.com/events/olympiad',
        'https://evil.com/broadcast/x/y',
        'https://notchessever.com/player/1',
      ]) {
        expect(isRoutableSpaceLink(Uri.parse(url)), isFalse, reason: url);
      }
    });

    test('broadcast links read as the shared-link router reads them', () {
      SpaceBroadcastLinkTarget? read(String url) =>
          spaceBroadcastLinkTarget(Uri.parse(url));

      final team = read(
        'https://chessever.com/broadcast/olympiad-2026/abc123/team/Norway%20B',
      )!;
      expect(team.eventId, 'abc123');
      expect(team.teamName, 'Norway B');
      expect(team.playerFideId, isNull);

      final player = read(
        'https://chessever.com/broadcast/olympiad-2026/abc123/player/1503014',
      )!;
      expect(player.eventId, 'abc123');
      expect(player.playerFideId, 1503014);
      expect(player.teamName, isNull);

      final tab = read(
        'https://chessever.com/broadcast/olympiad-2026/abc123?tab=standings',
      )!;
      expect(tab.eventId, 'abc123');
      expect(tab.tab, 'standings');
      expect(tab.playerFideId, isNull);
      expect(tab.teamName, isNull);

      expect(read('https://chessever.com/broadcast/abc123')!.eventId, 'abc123');
      expect(read('https://chessever.com/broadcast/abc123')!.tab, isNull);
      // A player segment with no FIDE id still opens the event.
      final noFide = read(
        'https://chessever.com/broadcast/slug/abc123/player/nope',
      )!;
      expect(noFide.eventId, 'abc123');
      expect(noFide.playerFideId, isNull);

      final appTeam = read('com.chessever.app://broadcast/slug/abc123/team/X')!;
      expect(appTeam.eventId, 'abc123');
      expect(appTeam.teamName, 'X');
      expect(read('com.chessever.app://broadcast/abc123')!.eventId, 'abc123');

      expect(read('https://chessever.com/broadcast'), isNull);
      expect(read('https://chessever.com/games/AbCdEfGh'), isNull);
      expect(read('https://evil.com/broadcast/x/y'), isNull);
    });

    test('game links keep their move and source', () {
      final game = spaceGameLinkTarget(
        Uri.parse(
          'https://chessever.com/games/AbCdEfGh?src=gamebase&fen=8/8/8/8/8/8/8/K6k%20w%20-%20-%200%201',
        ),
      )!;
      expect(game.gameId, 'AbCdEfGh');
      expect(game.preferGamebase, isTrue);
      expect(game.fen, '8/8/8/8/8/8/8/K6k w - - 0 1');

      final app = spaceGameLinkTarget(
        Uri.parse('com.chessever.app://games/AbCdEfGh'),
      )!;
      expect(app.gameId, 'AbCdEfGh');
      expect(app.preferGamebase, isFalse);
      expect(app.fen, isNull);

      expect(
        spaceGameLinkTarget(Uri.parse('https://chessever.com/games')),
        isNull,
      );
    });
  });

  group('countrymen', () {
    test('takes an ISO or a FIDE federation code', () {
      expect(CountrymenTabScreen.countryFor('NO')?.countryCode, 'NO');
      expect(CountrymenTabScreen.countryFor('us')?.countryCode, 'US');
      expect(CountrymenTabScreen.countryFor('NOR')?.countryCode, 'NO');
      expect(CountrymenTabScreen.countryFor('XYZ'), isNull);
      expect(CountrymenTabScreen.countryFor(''), isNull);
      expect(CountrymenTabScreen.countryFor(null), isNull);
    });
  });

  group('share links', () {
    test('come from the same helpers as the app', () {
      expect(
        spaceShortcutShareUrl(
          _s(SpaceShortcutKind.player, '1503014', params: {'fideId': 1503014}),
        ),
        'https://chessever.com/player/1503014',
      );
      expect(
        spaceShortcutShareUrl(_s(SpaceShortcutKind.game, 'AbCdEfGh')),
        'https://chessever.com/games/AbCdEfGh',
      );
      expect(
        spaceShortcutShareUrl(
          _s(
            SpaceShortcutKind.game,
            '0b8f7d1e-2c3a-4b5d-8e9f-0a1b2c3d4e5f',
            params: {'source': 'gamebase'},
          ),
        ),
        'https://chessever.com/games/0b8f7d1e-2c3a-4b5d-8e9f-0a1b2c3d4e5f'
        '?src=gamebase',
      );
      expect(
        spaceShortcutShareUrl(
          _s(SpaceShortcutKind.event, 'gb1', title: 'Norway Chess 2026'),
        ),
        'https://chessever.com/broadcast/norway-chess-2026/gb1',
      );
      expect(
        spaceShortcutShareUrl(
          _s(
            SpaceShortcutKind.streak,
            '1503014',
            params: {'timeClass': 'blitz'},
          ),
        ),
        'https://streaks.chessever.com/p/1503014?tc=blitz',
      );
      expect(
        spaceShortcutShareUrl(
          _s(SpaceShortcutKind.link, 'https://chessever.com/player/1'),
        ),
        'https://chessever.com/player/1',
      );
      expect(
        spaceShortcutShareUrl(
          _s(
            SpaceShortcutKind.collection,
            'c1',
            params: {'slug': 'tata-steel-2026'},
          ),
        ),
        'https://chessever.com/collections/tata-steel-2026',
      );
    });

    test('are withheld where no one else could open them', () {
      for (final s in [
        _s(SpaceShortcutKind.event, 'cal_event_x'),
        _s(SpaceShortcutKind.event, 'gamebase::Tata Steel'),
        _s(SpaceShortcutKind.round, 'r1'),
        _s(SpaceShortcutKind.folder, 'f1'),
        _s(SpaceShortcutKind.position, 'fen'),
        _s(SpaceShortcutKind.link, 'com.chessever.app://games/abc'),
        _s(SpaceShortcutKind.game, 'saved_analysis_1'),
        _s(SpaceShortcutKind.collection, 'c1'),
      ]) {
        expect(spaceShortcutShareUrl(s), isNull, reason: s.key);
      }
    });
  });

  group('realtime echoes', () {
    const base = SpaceShortcut(
      id: 'a',
      kind: SpaceShortcutKind.player,
      targetId: '1',
      title: 'Carlsen',
      params: {'fideId': 1},
      sortIndex: 2,
      openCount: 3,
    );

    test('an echo of what the list already shows matches', () {
      expect(
        spaceShortcutsMatch(base, base.copyWith(id: 'server-uuid')),
        isTrue,
      );
      final opened = DateTime(2026, 9, 23, 12);
      expect(
        spaceShortcutsMatch(
          base.copyWith(lastOpenedAt: opened),
          base.copyWith(
            lastOpenedAt: opened.add(const Duration(milliseconds: 400)),
          ),
        ),
        isTrue,
      );
    });

    test('a real change from elsewhere does not', () {
      expect(spaceShortcutsMatch(base, base.copyWith(sortIndex: 5)), isFalse);
      expect(spaceShortcutsMatch(base, base.copyWith(openCount: 4)), isFalse);
      expect(
        spaceShortcutsMatch(base, base.copyWith(params: {'fideId': 2})),
        isFalse,
      );
    });
  });

  group('draft helpers round-trip through the opener', () {
    test('database event cards retain their archive route', () {
      final card = GroupEventCardModel(
        id: 'gamebase::Archive event',
        title: 'Archive event',
        dates: '',
        maxAvgElo: 0,
        timeUntilStart: '',
        tourEventCategory: TourEventCategory.completed,
        timeControl: 'Standard',
        startDate: null,
        endDate: null,
        eventSource: EventSource.communityEvent,
      );
      final draft = eventSpaceDraft(card);
      expect(draft.params['source'], 'gamebase');
      expect(draft.params.containsKey('calendarEventId'), isFalse);
      expect(isSpaceCalendarEvent(draft), isFalse);
      final searchDraft = searchEventSpaceDraft(card)!;
      expect(searchDraft.key, draft.key);
      expect(isSpaceCalendarEvent(searchDraft), isFalse);
    });

    test('ChessEver Database event', () {
      final draft = spaceTwicEventDraft(eventName: 'Tata Steel Masters');
      expect(draft.targetId, '$kTwicBookId:Tata Steel Masters');
      expect(spaceTwicEventName(draft), 'Tata Steel Masters');
    });

    test('calendar event cards open by name', () {
      final card = GroupEventCardModel.fromCalendarEvent(
        CalendarEvent(
          name: 'FIDE World Cup 2027',
          createdAt: DateTime(2026),
          startDate: DateTime(2027, 7, 1),
          endDate: DateTime(2027, 7, 25),
        ),
      );
      final draft = eventSpaceDraft(card);
      expect(draft.targetId, 'cal_event_fide_world_cup_2027');
      expect(isSpaceCalendarEvent(draft), isTrue);
      expect(spaceCalendarEventNames(draft).first, 'FIDE World Cup 2027');
      expect(spaceShortcutShareUrl(draft), isNull);
    });

    test('countrymen keys on the ISO code whatever it was given', () {
      expect(spaceCountrymenDraft('NOR')?.targetId, 'NO');
      expect(spaceCountrymenDraft('NO')?.key, spaceCountrymenDraft('NOR')?.key);
      expect(spaceCountrymenDraft('???'), isNull);
    });
  });

  group('explorer lines', () {
    const najdorf = [
      'e2e4', 'c7c5', 'g1f3', 'd7d6', 'd2d4', 'c5d4', //
      'f3d4', 'g8f6', 'b1c3', 'a7a6',
    ];

    test('a saved position is its moves from the start, reaching its FEN', () {
      final line = resolveSpaceLine(moves: najdorf)!;
      final pin = _s(
        SpaceShortcutKind.position,
        line.fen,
        params: {'moves': najdorf},
      );
      final got = spaceShortcutLine(pin)!;
      expect(got.fen, line.fen);
      expect(got.ucis, najdorf);
      expect(spaceShortcutFen(pin), line.fen);
    });

    test('a saved opening code plays its catalogue line', () {
      final got = spaceShortcutLine(_s(SpaceShortcutKind.opening, 'B90'))!;
      expect(got.ucis, isNotEmpty);
      expect(got.ucis.take(4), ['e2e4', 'c7c5', 'g1f3', 'd7d6']);
    });

    test('moves that do not reach the saved FEN are dropped, not trusted', () {
      final pin = _s(
        SpaceShortcutKind.position,
        resolveSpaceLine(moves: najdorf)!.fen,
        params: {
          'moves': ['d2d4', 'd7d5'],
        },
      );
      expect(spaceShortcutLine(pin)!.ucis, isEmpty);
    });

    test('everything else has no line', () {
      expect(spaceShortcutLine(_s(SpaceShortcutKind.event, 'ev')), isNull);
      expect(spaceShortcutLine(_s(SpaceShortcutKind.game, 'g')), isNull);
    });
  });
}

// ------------------------------------------------------------ event opens

/// The pins in memory; every open recorded.
class _Store extends SpaceShortcutsNotifier {
  _Store(this.seed);

  final List<SpaceShortcut> seed;
  final opened = <String>[];

  @override
  Future<List<SpaceShortcut>> build() async => seed;

  @override
  Future<void> markOpened(String id) async => opened.add(id);
}

class _Authenticated extends AuthController {
  @override
  Future<AppAuthState> build() async =>
      const AppAuthState(status: AppAuthStatus.authenticated);
}

/// One tour, 'tour-9', the Women category of 'gb-1'.
class _Tours implements TourRepository {
  final requested = <String>[];

  @override
  Future<List<Tour>> getToursByIds(List<String> ids) async {
    requested.addAll(ids);
    return [
      if (ids.contains('tour-9'))
        Tour(
          id: 'tour-9',
          name: 'Norway Chess Women',
          slug: 'norway-chess-women',
          info: TourInfo(),
          createdAt: DateTime(2026, 5, 26),
          url: '',
          tier: 0,
          dates: [],
          players: [],
          groupBroadcastId: 'gb-1',
        ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Groups implements GroupBroadcastRepository {
  _Groups(this.byId);

  final Map<String, GroupBroadcast> byId;
  final requested = <String>[];

  @override
  Future<GroupBroadcast> getGroupBroadcastById(String id) async {
    requested.add(id);
    final broadcast = byId[id];
    if (broadcast == null) throw StateError('No rows found');
    return broadcast;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Selection implements TourDetailRepo {
  final saved = <(String, String)>[];

  @override
  Future<void> saveSelectedTourId({
    required String groupEventId,
    required String tourId,
  }) async {
    saved.add((groupEventId, tourId));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

typedef _Open = ({
  String id,
  GroupEventCategory category,
  List<GroupBroadcast> known,
  String? source,
});

/// The Events lists' own opener, every call noted before it runs.
class _Navigation extends TournamentNavigationController {
  _Navigation(super.ref, this.calls);

  final List<_Open> calls;

  @override
  Future<void> openTournament({
    required BuildContext context,
    required String id,
    required GroupEventCategory category,
    Iterable<GroupBroadcast> knownBroadcasts = const <GroupBroadcast>[],
    String? analyticsSource,
  }) {
    calls.add((
      id: id,
      category: category,
      known: knownBroadcasts.toList(),
      source: analyticsSource,
    ));
    return super.openTournament(
      context: context,
      id: id,
      category: category,
      knownBroadcasts: knownBroadcasts,
      analyticsSource: analyticsSource,
    );
  }
}

/// My Space as far as an event's open needs it: the real Events opener and
/// the real shared-link resolver over fake repositories.
class _EventHost {
  _EventHost._(this.store, this.groups);

  final _Store store;
  final _Groups groups;
  final tours = _Tours();
  final selection = _Selection();
  final pushed = <String>[];
  final navigatorKey = GlobalKey<NavigatorState>();

  /// Every open the Events lists' opener was asked for.
  final opens = <_Open>[];
  late BuildContext _context;
  late WidgetRef _ref;
  late ProviderSubscription<Object?> _auth;

  T read<T>(ProviderListenable<T> provider) =>
      ProviderScope.containerOf(navigatorKey.currentContext!).read(provider);

  /// [premium] is the reader's access; a free reader's gate asks for
  /// Premium where the Events lists' gate would. [overrides] come last.
  static Future<_EventHost> pump(
    WidgetTester tester,
    List<SpaceShortcut> pins,
    List<GroupBroadcast> broadcasts, {
    bool premium = true,
    List<Override> overrides = const [],
  }) async {
    // Inside the test's zone, so the app-ready gate opens in it too.
    DeepLinkService.instance.detachNotificationRouter();
    DeepLinkService.instance.dispose();
    addTearDown(DeepLinkService.instance.detachNotificationRouter);
    addTearDown(DeepLinkService.instance.dispose);
    final host = _EventHost._(
      _Store(pins),
      _Groups({for (final b in broadcasts) b.id: b}),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(_Authenticated.new),
          tourRepositoryProvider.overrideWithValue(host.tours),
          groupBroadcastRepositoryProvider.overrideWithValue(host.groups),
          tourDetailRepoProvider.overrideWithValue(host.selection),
          premiumAccessProvider.overrideWithValue(premium),
          liveGroupBroadcastIdsProvider.overrideWith(
            (ref) => Stream.value(const <String>[]),
          ),
          tournamentNavigationProvider.overrideWith(
            (ref) => _Navigation(ref, host.opens),
          ),
          spaceShortcutsProvider.overrideWith(() => host.store),
          ...overrides,
        ],
        child: MaterialApp(
          navigatorKey: host.navigatorKey,
          initialRoute: '/',
          onGenerateRoute: (settings) {
            host.pushed.add(settings.name ?? '');
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => Consumer(
                builder: (context, ref, _) {
                  if (settings.name == '/') {
                    // The Premium prompt sizes itself off the screen.
                    ResponsiveHelper.init(context);
                    host._context = context;
                    host._ref = ref;
                    ref.watch(spaceShortcutsProvider);
                  }
                  return const SizedBox.shrink();
                },
              ),
            );
          },
        ),
      ),
    );
    host._auth = ProviderScope.containerOf(
      host.navigatorKey.currentContext!,
    ).listen(authStateProvider, (_, _) {});
    addTearDown(host._auth.close);
    await tester.pump();
    DeepLinkService.instance.attachNotificationRouter(
      host.navigatorKey,
      host._ref,
    );
    DeepLinkService.notifyAppReady();
    host.pushed.clear();
    return host;
  }

  Future<void> open(
    WidgetTester tester,
    SpaceShortcut pin, {
    required List<GroupBroadcast> known,
  }) async {
    unawaited(openSpaceShortcut(_context, _ref, pin, knownBroadcasts: known));
    await _settle(tester);
  }
}

/// Lets real async work (the Premium prompt's) land between frames, then
/// settles.
Future<void> _settle(WidgetTester tester) async {
  for (var n = 0; n < 6; n++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 160));
  }
  await tester.pumpAndSettle();
}
