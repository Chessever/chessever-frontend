import 'dart:convert';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/watch/core/watch_account.dart';
import 'package:chessever2/watch/core/watch_models.dart';
import 'package:chessever2/watch/core/watch_notification_route.dart';
import 'package:chessever2/watch/core/watch_repository.dart';
import 'package:chessever2/watch/ui/watch_board.dart';
import 'package:chessever2/watch/ui/watch_game_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> fixtureGame(String id, {String round = 'round1'}) => {
  'id': id,
  'tour_id': 'tour1',
  'tour_slug': 'open',
  'round_id': round,
  'round_slug': round,
  'status': '*',
  'board_nr': 1,
  'players': [
    {'name': 'Player One', 'fideId': 123, 'rating': 2750, 'clock': 8100},
    {'name': 'Player Two', 'fideId': 456, 'rating': 2740},
  ],
  'fen': 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
  'last_clock_white': 0,
  'last_clock_black': 125,
};

void main() {
  test('public event reads use only production Current and paginate', () async {
    final requests = <http.Request>[];
    final repository = WatchRepository(
      apiKey: 'public-key',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode([
            {'id': 'current', 'name': 'Current Open'},
          ]),
          200,
        );
      }),
    );
    final events = await repository.events(offset: 30);
    final request = requests.single;
    expect(request.url.host, 'oelbsuggrzyqwzmvidju.supabase.co');
    expect(request.url.path, '/rest/v1/group_broadcasts_current');
    expect(request.url.queryParameters['offset'], '30');
    expect(request.url.queryParameters['limit'], '30');
    expect(request.url.queryParameters['order'], contains('id.asc'));
    expect(request.headers['apikey'], 'public-key');
    expect(events.single.name, 'Current Open');
    repository.dispose();
  });

  test('no key and feed failures never substitute invented games', () async {
    final missing = WatchRepository(apiKey: '');
    await expectLater(missing.events(), throwsA(isA<WatchDataException>()));
    missing.dispose();
    final down = WatchRepository(
      apiKey: 'key',
      client: MockClient((_) async => http.Response('Unavailable', 503)),
    );
    await expectLater(down.events(), throwsA(isA<WatchDataException>()));
    down.dispose();
  });

  test(
    'scorecard filters on the server, reads every page, and follows round order',
    () async {
      final offsets = <String>[];
      final repository = WatchRepository(
        apiKey: 'key',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/rounds')) {
            return http.Response(
              jsonEncode([
                {'id': 'round1', 'name': 'Round 1'},
                {'id': 'round2', 'name': 'Round 2'},
              ]),
              200,
            );
          }
          final query = request.url.queryParameters;
          expect(query['tour_id'], 'eq.tour1');
          expect(query['players'], 'cs.[{"fideId":123}]');
          offsets.add(query['offset']!);
          final rows = query['offset'] == '0'
              ? List.generate(1000, (i) => fixtureGame('$i', round: 'round2'))
              : [fixtureGame('last')];
          return http.Response(jsonEncode(rows), 200);
        }),
      );
      final games = await repository.scorecard(
        'tour1',
        const WatchStanding(name: 'Player One', fideId: '123'),
      );
      expect(offsets, ['0', '1000']);
      expect(games.length, 1001);
      expect(games.first.roundId, 'round1');
      repository.dispose();
    },
  );

  test(
    'published rankings win over score sorting; ties preserve feed order',
    () {
      final tour = WatchTour.fromJson({
        'id': 't',
        'name': 'Open',
        'group_broadcast_id': 'e',
        'players': [
          {'name': 'Published first', 'rank': 1, 'score': 3},
          {'name': 'Published second', 'rank': 2, 'score': 4},
        ],
      });
      expect(tour.standings.first.name, 'Published first');
      final ties = WatchTour.fromJson({
        'id': 't',
        'group_broadcast_id': 'e',
        'players': [
          {'name': 'B', 'score': 3},
          {'name': 'A', 'score': 3},
        ],
      });
      expect(ties.standings.map((p) => p.name), ['B', 'A']);
      expect(
        WatchStanding.fromJson({
          'name': 'P',
          'score': '4.5',
          'performances': {'rapid': 2800},
          'ratingDiffs': {'rapid': -5},
        }).performance,
        2800,
      );
      expect(watchScore(4.5), '4½');
      expect(watchScore(null), 'Unavailable');
      final scoreOnly = WatchStanding.fromJson({'name': 'P', 'score': 3.5});
      expect(watchStandingScore(scoreOnly), '3½');
      expect(
        watchStandingScore(const WatchStanding(name: 'P', score: 0, played: 0)),
        '0 / 0',
      );
    },
  );

  test('game identities and reported zero clocks are preserved', () {
    final game = Games.fromJson(fixtureGame('g'));
    expect(watchGameIsLive(game), isTrue);
    expect(game.lastClockWhite, 0);
    expect(watchClock(game.lastClockWhite!), '0:00');
    expect(watchClock(125), '2:05');
    expect(
      watchPlayerMatches(
        game.players!.first,
        const WatchStanding(name: 'Renamed player', fideId: '123'),
      ),
      isTrue,
    );
    expect(watchResult('1/2-1/2'), '½–½');
    expect(
      watchPlayerMatches(
        game.players!.first,
        const WatchStanding(name: 'Player One', fideId: '0'),
      ),
      isTrue,
    );
  });

  test(
    'account clearing strips private display state and retains only public configuration',
    () {
      final account = WatchAccount.fromJson({
        'kind': WatchAccount.kind,
        'revision': 2,
        'userId': null,
        'name': 'Old user',
        'eventIds': ['event'],
        'playerIds': ['123'],
        'playerNames': ['Old player'],
        'preferences': {'favorite_event_alerts': true},
        'publicApiKey': 'publishable',
      });
      expect(account.name, isEmpty);
      expect(account.eventIds, isEmpty);
      expect(account.preferences, isEmpty);
      expect(account.publicApiKey, 'publishable');
      expect(account.toJson().keys, isNot(contains('access_token')));
      expect(account.toJson().keys, isNot(contains('refresh_token')));
      const followed = WatchAccount(
        revision: 1,
        userId: 'u',
        eventIds: ['cal_event_current_open'],
      );
      expect(followed.followsEvent('real-id', 'Current Open'), isTrue);
      expect(followed.followsEvent('other', 'Other Open'), isFalse);
    },
  );

  test(
    'FCM and OneSignal notification contracts resolve to the same route',
    () {
      final fcm = WatchNotificationRoute.fromPayload({
        'game_id': 'g1',
        'group_broadcast_id': 'e1',
      });
      final oneSignal = WatchNotificationRoute.fromPayload({
        'custom': jsonEncode({
          'a': {'gameId': 'g1', 'groupBroadcastId': 'e1'},
        }),
      });
      expect(fcm.gameId, oneSignal.gameId);
      expect(fcm.eventId, oneSignal.eventId);
      expect(
        WatchNotificationRoute.fromPayload({
          'url': 'https://chessever.com/games/g1',
        }).gameId,
        'g1',
      );
      expect(
        WatchNotificationRoute.fromPayload({
          'url': 'https://chessever.com/broadcast/open/e1',
        }).eventId,
        'e1',
      );
      expect(
        WatchNotificationRoute.fromPayload({
          'url': 'https://other.example/games/g1',
        }).gameId,
        isNull,
      );
      expect(
        WatchNotificationRoute.fromPayload({'game_id': 'bad/../path'}).gameId,
        isNull,
      );
    },
  );

  test(
    'board FEN and last move keep orientation and reject malformed ranks',
    () {
      final squares = watchFenSquares(fixtureGame('g')['fen'] as String);
      expect(squares!.first, 'r');
      expect(squares.last, 'R');
      expect(watchFenSquares('9/8/8/8/8/8/8/8'), isNull);
      expect(watchFenSquares('8/8'), isNull);
      expect(watchLastMoveSquares('e2e4'), {52, 36});
      expect(watchLastMoveSquares('Nf3'), {45});
    },
  );
}
