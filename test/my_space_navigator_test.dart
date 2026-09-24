import 'package:chessever2/screens/countrymen/countrymen_tab_screen.dart';
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
import 'package:flutter_test/flutter_test.dart';

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
        'com.chessever.app://broadcast/abc123',
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
}
