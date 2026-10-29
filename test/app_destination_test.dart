import 'package:chessever2/screens/library/miniatures/miniatures_share.dart';
import 'package:chessever2/screens/library/miniatures/miniatures_mode_provider.dart';
import 'package:chessever2/screens/feed/news/news_content.dart';
import 'package:chessever2/screens/for_you/discovery/models/discovery_models.dart';
import 'package:chessever2/services/app_destination.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Miniatures tab and date links round trip through every supported scheme',
    () {
      for (final tab in MiniaturesScreenMode.values) {
        for (final date in [
          null,
          if (tab == MiniaturesScreenMode.games) '2026-10-28',
        ]) {
          final uri = miniaturesShareUri(tab, date: date);
          expect(newsInAppRoute(uri), uri);
          for (final raw in [
            uri.toString(),
            '${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}',
            uri
                .replace(
                  scheme: 'com.chessever.app',
                  host: 'app',
                  path: uri.path.replaceFirst('/app', ''),
                )
                .toString(),
          ]) {
            final target = parseAppDestination(raw)!;
            expect(target.kind, AppDestinationKind.miniatures);
            expect(target.section, tab.name);
            expect(target.query['date'], date);
          }
        }
      }
      for (final raw in [
        '/app/miniatures/unknown',
        '/app/miniatures/games/extra',
        '/app/miniatures/about?date=2026-10-28',
        '/app/miniatures/players?date=2026-10-28',
        '/app/miniatures/games?date=2026-02-30',
        '/app/miniatures/games?date=today',
        '/app/miniatures/games?unknown=value',
        '/app/miniatures/games?date=2026-10-28&date=2026-10-29',
      ]) {
        expect(parseAppDestination(raw), isNull, reason: raw);
      }
      expect(
        () =>
            miniaturesShareUri(MiniaturesScreenMode.games, date: '2026-02-30'),
        throwsArgumentError,
      );
    },
  );

  test('Likes shares round trip for every section, range and view', () {
    for (final period in MostLikedPeriod.values) {
      for (final view in MostLikedView.values) {
        for (final date in [null, DateTime(2026, 9, 23)]) {
          final uri = mostLikedShareUri(period, date: date, view: view);
          expect(newsInAppRoute(uri), uri);
          for (final raw in [
            uri.toString(),
            uri
                .replace(
                  scheme: 'com.chessever.app',
                  host: 'app',
                  path: uri.path.replaceFirst('/app', ''),
                )
                .toString(),
          ]) {
            final destination = parseAppDestination(raw)!;
            expect(destination.kind, AppDestinationKind.likes);
            expect(destination.section, period.name);
            expect(destination.query['view'], view.name);
            expect(
              destination.query['date'],
              date == null
                  ? null
                  : MostLikedQuery(
                      period,
                      date,
                    ).start.toIso8601String().split('T').first,
            );
          }
        }
      }
    }
  });

  test('Likes rejects invalid periods, dates, views and extra parameters', () {
    for (final raw in [
      '/app/likes/decade',
      '/app/likes/week/extra',
      '/app/likes/week?date=2026-02-30',
      '/app/likes/week?date=bad',
      '/app/likes/week?view=about',
      '/app/likes/week?unknown=value',
    ]) {
      expect(parseAppDestination(raw), isNull, reason: raw);
    }
  });

  final routes = <String, AppDestinationKind>{
    '/app': AppDestinationKind.home,
    '/app/home': AppDestinationKind.home,
    '/app/home/today': AppDestinationKind.home,
    '/app/home/my-space': AppDestinationKind.home,
    '/app/home/discovery': AppDestinationKind.home,
    '/app/events': AppDestinationKind.events,
    '/app/collections': AppDestinationKind.collections,
    '/app/collections/world-champions': AppDestinationKind.collection,
    '/app/inbox': AppDestinationKind.inbox,
    '/app/inbox/message-42': AppDestinationKind.inbox,
    '/app/feed': AppDestinationKind.feed,
    '/app/likes': AppDestinationKind.likes,
    '/app/miniatures': AppDestinationKind.miniatures,
    '/app/reports': AppDestinationKind.reports,
    '/app/my-prep': AppDestinationKind.myPrep,
    '/app/my-prep/local-profile': AppDestinationKind.prepProfile,
    '/app/my-prep/local-profile?account=lichess%3Aplayer':
        AppDestinationKind.prepProfile,
    '/app/library': AppDestinationKind.library,
    '/app/library/database': AppDestinationKind.database,
    '/app/library/database?event=Tata+Steel+2026': AppDestinationKind.database,
    '/app/my-likes': AppDestinationKind.myLikes,
    '/app/calendar': AppDestinationKind.calendar,
    '/app/calendar?date=2028-02-29': AppDestinationKind.calendar,
    '/app/favorites': AppDestinationKind.favorites,
    '/app/favorites/list': AppDestinationKind.favorites,
    '/app/favorites/events': AppDestinationKind.favorites,
    '/app/favorites/games': AppDestinationKind.favorites,
    '/app/favorites/players': AppDestinationKind.favorites,
    '/app/settings': AppDestinationKind.settings,
    '/app/settings/board': AppDestinationKind.settings,
    '/app/settings/engine': AppDestinationKind.settings,
    '/app/settings/botvinnik': AppDestinationKind.settings,
    '/app/settings/notifications': AppDestinationKind.settings,
    '/app/settings/customization': AppDestinationKind.settings,
    '/app/players/1503014': AppDestinationKind.player,
    '/app/players/1503014/about': AppDestinationKind.player,
    '/app/players/1503014/games?name=Magnus+Carlsen': AppDestinationKind.player,
    '/app/players/1503014/events': AppDestinationKind.player,
    '/app/players/1503014/openings': AppDestinationKind.playerOpenings,
    '/app/players/1503014/openings?color=black&moves=d4+Nf6':
        AppDestinationKind.playerOpenings,
    '/app/streaks': AppDestinationKind.streaks,
    '/app/streaks?tc=standard': AppDestinationKind.streaks,
    '/app/streaks/1503014?tc=rapid': AppDestinationKind.streaks,
    '/app/explorer': AppDestinationKind.explorer,
    '/app/explorer?moves=1.e4+c5+2.Nf3': AppDestinationKind.explorer,
    '/app/openings/B90': AppDestinationKind.explorer,
    '/app/games/game-id?src=gamebase': AppDestinationKind.legacy,
    '/app/books/share-token': AppDestinationKind.legacy,
    '/app/databases/folder-id': AppDestinationKind.legacy,
    '/app/folders/folder-id': AppDestinationKind.legacy,
    '/app/player/1503014': AppDestinationKind.legacy,
    '/app/player/magnus-carlsen/1503014': AppDestinationKind.legacy,
    '/app/player/jose-raul-capablanca/memorial-capablanca':
        AppDestinationKind.legacy,
    '/app/broadcast/event-id?tab=games': AppDestinationKind.legacy,
    '/app/broadcast/world-cup/event-id?tab=bracket': AppDestinationKind.legacy,
    '/app/broadcast/world-cup/event-id/player/1503014':
        AppDestinationKind.legacy,
    '/app/broadcast/olympiad/event-id/team/United%20States':
        AppDestinationKind.legacy,
  };

  for (final entry in routes.entries) {
    test('recognizes the complete route ${entry.key}', () {
      expect(parseAppDestination(entry.key)?.kind, entry.value);
    });
    test('rejects unknown extra path below ${entry.key}', () {
      final uri = Uri.parse(entry.key);
      final deeper = uri.replace(
        path: '${uri.path}/unsupported-leaf/extra/deeper',
      );
      expect(parseAppDestination(deeper.toString()), isNull);
    });
    test('rejects unknown query on ${entry.key}', () {
      final uri = Uri.parse(entry.key);
      final unknown = uri.replace(
        queryParameters: {...uri.queryParameters, 'unsupported': 'true'},
      );
      expect(parseAppDestination(unknown.toString()), isNull);
    });
  }

  for (final raw in [
    '/app/settings/notifications/',
    'https://chessever.com/app/settings/notifications',
    'https://www.chessever.com/app/settings/notifications',
    'https://chessever.com:443/app/settings/notifications',
    'com.chessever.app://app/settings/notifications',
    'com.chessever.app:///app/settings/notifications',
  ]) {
    test('normalizes internal route transport $raw', () {
      final target = parseAppDestination(raw)!;
      expect(target.kind, AppDestinationKind.settings);
      expect(target.section, 'notifications');
      expect(
        target.uri.toString(),
        'https://chessever.com/app/settings/notifications',
      );
    });
  }

  for (final raw in [
    '',
    '/',
    '/home_screen',
    'app/home',
    '//chessever.com/app/home',
    'http://chessever.com/app/home',
    'https://evil.example/app/home',
    'https://chessever.com.evil.example/app/home',
    'https://admin.chessever.com/app/home',
    'https://chessever.com:8443/app/home',
    'https://user@chessever.com/app/home',
    'com.chessever.app://settings/notifications',
    'com.chessever.app://app:123/settings',
    '/app/home#missing',
    '/app/home#',
    '/app//home',
    '/app/home//',
    '/app/home/../reports',
    '/app/%2e%2e/reports',
    '/app/settings%2fnotifications',
    '/app/inbox/message%5Cid',
    '/app/inbox/%00',
    '/app/inbox/%7f',
    '/app/inbox/%20message',
    '/app/inbox/%',
    '/app/inbox/%zz',
    '/app/settings/notifications?tab=board',
    '/app/streaks/0',
    '/app/streaks/-1',
    '/app/streaks/1234567890123',
    '/app/streaks?tc=classical',
    '/app/streaks?tc=rapid&tc=blitz',
    '/app/streaks?tc=',
    '/app/players/0/games',
    '/app/players/not-a-fide-id/games',
    '/app/players/1503014/ratings',
    '/app/players/1503014/games?color=white',
    '/app/players/1503014/openings?color=invalid',
    '/app/calendar?date=2026-02-29',
    '/app/calendar?date=2026-13-01',
    '/app/calendar?date=2026-01-32',
    '/app/calendar?date=2026-1-2',
    '/app/calendar?date=2026-01-02T00%3A00%3A00Z',
    '/app/my-prep?account=lichess%3Aplayer',
    '/app/library/database?event=%0a',
    '/app/explorer?fen=broken',
    '/app/explorer?moves=e4+impossible',
    '/app/explorer?moves=1.',
    '/app/positions',
    '/app/positions?moves=e4',
    '/app/openings/Z00',
    '/app/openings/B900',
    '/app/games/game?src=unknown',
    '/app/games/game?fen=broken',
    '/app/broadcast/event?tab=missing',
    '/app/broadcast/slug/event/player/0',
    '/app/broadcast/slug/event/player/1503014?tab=about',
  ]) {
    test('rejects invalid or ambiguous route $raw', () {
      expect(parseAppDestination(raw), isNull);
    });
  }

  test('routes exact inbox identity separately from the inbox hub', () {
    expect(parseAppDestination('/app/inbox')!.id, isNull);
    expect(parseAppDestination('/app/inbox/immutable-id')!.id, 'immutable-id');
  });

  test('preserves decoded team name and creates a safe legacy URL', () {
    final target = parseAppDestination(
      '/app/broadcast/olympiad/event/team/United%20States',
    )!;
    expect(
      target.legacyLink,
      'https://chessever.com/broadcast/olympiad/event/team/United%20States',
    );
    expect(Uri.parse(target.legacyLink!).pathSegments.last, 'United States');
  });

  test('preserves legacy game query parameters without app prefix', () {
    final link = Uri(
      path: '/app/games/uuid',
      queryParameters: {'fen': Chess.initial.fen, 'src': 'gamebase'},
    );
    final target = parseAppDestination(link.toString())!;
    final legacy = Uri.parse(target.legacyLink!);
    expect(legacy.path, '/games/uuid');
    expect(legacy.queryParameters, link.queryParameters);
  });

  test('positions open their validated FEN and full legal UCI line', () {
    final route = Uri(
      path: '/app/positions',
      queryParameters: {
        'fen': Chess.initial.play(NormalMove.fromUci('e2e4')).fen,
        'moves': 'e4',
      },
    );
    final line = parseAppDestination(route.toString())!.line!;
    expect(line.moves, ['e2e4']);
    expect(line.fen, route.queryParameters['fen']);
  });

  test('a mismatched position cannot silently discard the requested line', () {
    final route = Uri(
      path: '/app/explorer',
      queryParameters: {'fen': Chess.initial.fen, 'moves': 'e4'},
    );
    expect(parseAppDestination(route.toString()), isNull);
  });

  test('SAN and common UCI castling reach the same complete line', () {
    final san = parseAppDestination(
      '/app/explorer?moves=e4+e5+Nf3+Nc6+Bc4+Nf6+O-O',
    )!.line!;
    final uci = parseAppDestination(
      '/app/explorer?moves=e2e4+e7e5+g1f3+b8c6+f1c4+g8f6+e1g1',
    )!.line!;
    expect(san.moves.last, 'e1g1');
    expect(uci.moves, san.moves);
    expect(uci.fen, san.fen);
  });

  test('catalog opening is populated with legal moves', () {
    final line = parseAppDestination('/app/openings/B90')!.line!;
    expect(line.moves.take(4), ['e2e4', 'c7c5', 'g1f3', 'd7d6']);
    expect(line.moves, isNotEmpty);
  });
}
