import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/gamebase/models/models.dart';
import 'package:chessever2/screens/library/providers/gamebase_database_games_provider.dart';
import 'package:chessever2/screens/library/providers/gamebase_filter_provider.dart';
import 'package:chessever2/screens/library/providers/twic_event_aggregates_provider.dart';
import 'package:chessever2/screens/library/utils/event_game_search_match.dart';
import 'package:chessever2/screens/library/widgets/library_gamebase_filter_dialog.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

// The event chips in the ChessEver database must agree with the games list:
// counted under the same search and filters, ordered by those counts, and a
// picked chip must return the games it counted, broadcast tournaments too.
void main() {
  group('eco token', () {
    test('a broad family is sent as its prefixes joined by +', () {
      final family = GameEcoFilter.forCode('E6+E7+E8+E9');
      expect(family.hasMultiplePrefixes, isTrue);
      expect(gamebaseEcoToken(family), 'eco:${family.ecoPrefixes.join('+')}');
    });

    test('a single code is unchanged', () {
      expect(gamebaseEcoToken(GameEcoFilter.forCode('C45')), 'eco:C45');
    });
  });

  group('chip order', () {
    final oct = DateTime.utc(2026, 10, 20);
    final sep = DateTime.utc(2026, 9, 20);

    test('an older server answer is sorted by matching games', () {
      final ordered = orderEventChips([
        _aggregate('Almaty', 1, oct),
        _aggregate('Freestyle Friday', 6, sep),
        _aggregate('Ganja Open', 3, oct),
        _aggregate('Atyrau Open', 3, sep),
      ]);

      expect(ordered.map((e) => e.event), [
        'Freestyle Friday',
        'Ganja Open',
        'Atyrau Open',
        'Almaty',
      ]);
    });

    test('a ranked server answer keeps its order', () {
      final ranked = [
        _aggregate('Freestyle Friday', 6, sep, playerMatches: 6),
        _aggregate('Serbian Super League', 9, oct, playerMatches: 0),
      ];

      expect(orderEventChips(ranked), same(ranked));
    });
  });

  group('requests', () {
    late List<RequestOptions> requests;
    late Map<String, dynamic> Function(RequestOptions) answer;
    late GamebaseRepository repo;

    setUp(() {
      requests = [];
      answer = (_) => _gamesAnswer();
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (r, h) {
              requests.add(r);
              h.resolve(
                Response(requestOptions: r, statusCode: 200, data: answer(r)),
              );
            },
          ),
        );
      repo = GamebaseRepository(dio, apiKey: 'test');
    });

    test('chips carry the games list search and ask for count order', () async {
      final filter = GamebaseFilter(
        eco: GameEcoFilter.forCode('C45'),
        isOnline: GameOnlineFilter.online,
      );
      answer = (_) => _eventsAnswer(playerMatchCount: null);
      final container = ProviderContainer(
        overrides: [
          gamebaseRepositoryProvider.overrideWithValue(repo),
          gamebaseFilterProvider.overrideWith((ref) => filter),
        ],
      );
      addTearDown(container.dispose);
      container.read(librarySearchQueryProvider.notifier).state = 'carlsen';

      container.listen(twicEventAggregatesPaginatedProvider, (_, __) {});
      await pumpEventQueue();

      final request = requests.single;
      expect(request.path, endsWith('/api/search/events'));
      expect(request.queryParameters['q'], 'eco:C45 carlsen');
      expect(request.queryParameters['sort'], 'games');
      expect(request.queryParameters['isOnline'], isTrue);
      expect(repo.filesEventsExactly, isFalse);
    });

    test('a picked chip uses the event token on an older server', () async {
      final container = _gamesContainer(repo, event: 'Ganja Open 2026');
      addTearDown(container.dispose);

      container.listen(gamebaseDatabaseGamesPaginatedProvider, (_, __) {});
      await pumpEventQueue();

      // The token search runs first; it found nothing here, so the
      // tournament fallback (below) follows it.
      final request = requests.first;
      expect(request.path, endsWith('/api/search'));
      expect(request.queryParameters['q'], 'carlsen event:"Ganja Open 2026"');
      expect(request.queryParameters.containsKey('event'), isFalse);
    });

    test('a picked chip is sent as the exact event once the server files '
        'events like the chips', () async {
      answer = (_) => _eventsAnswer(playerMatchCount: 2);
      await repo.searchEvents(query: 'carlsen');
      expect(repo.filesEventsExactly, isTrue);

      answer = (_) => _gamesAnswer();
      requests.clear();
      final container = _gamesContainer(
        repo,
        event: 'Serbian Super League 2026',
        // Without a pick these route to the exact POST query, which cannot
        // reach a broadcast tournament.
        filter: GamebaseFilter(minYear: 2026),
        query: '',
      );
      addTearDown(container.dispose);

      container.listen(gamebaseDatabaseGamesPaginatedProvider, (_, __) {});
      await pumpEventQueue();

      final request = requests.single;
      expect(request.method, 'GET');
      expect(request.path, endsWith('/api/search'));
      expect(request.queryParameters['q'], '*');
      expect(request.queryParameters['event'], 'Serbian Super League 2026');
    });

    // Live 2026-10-29: the "carlsen" chips listed Serbian Super League 2026
    // with 2 games (two "QGD: Exchange Variation, Carlsen Variation" games)
    // and `carlsen event:"Serbian Super League 2026"` found none, because the
    // tournament's games carry pairings as their event.
    test(
      'an older server: a broadcast tournament chip opens with its games',
      () async {
        answer = (r) =>
            r.path.endsWith('/api/event') ? _serbianLeagueView : _gamesAnswer();
        final container = _gamesContainer(
          repo,
          event: 'Serbian Super League 2026',
        );
        addTearDown(container.dispose);

        container.listen(gamebaseDatabaseGamesPaginatedProvider, (_, __) {});
        await pumpEventQueue();

        final state = container.read(gamebaseDatabaseGamesPaginatedProvider);
        expect(state.error, isNull);
        expect(state.games.map((g) => g.gameId), [
          '18a3377c-94aa-52dd-9da3-e684b955b59e',
          '1fec7945-7eaa-5dbd-84d5-fb80ae8d4a74',
        ]);
        expect(state.totalCount, 2);
        expect(state.hasMore, isFalse);
        expect(requests.map((r) => r.path.split('/').last), [
          'search',
          'event',
        ]);
        expect(
          requests.last.queryParameters['name'],
          'Serbian Super League 2026',
        );
      },
    );

    test(
      'an older server: the tournament fallback keeps the filters',
      () async {
        answer = (r) =>
            r.path.endsWith('/api/event') ? _serbianLeagueView : _gamesAnswer();
        final container = _gamesContainer(
          repo,
          event: 'Serbian Super League 2026',
          filter: GamebaseFilter(result: GameResultFilter.draw),
        );
        addTearDown(container.dispose);

        container.listen(gamebaseDatabaseGamesPaginatedProvider, (_, __) {});
        await pumpEventQueue();

        expect(
          container
              .read(gamebaseDatabaseGamesPaginatedProvider)
              .games
              .map((g) => g.gameId),
          ['1fec7945-7eaa-5dbd-84d5-fb80ae8d4a74'],
        );
      },
    );
  });

  group('event game matching', () {
    final games = GamebaseEventView.fromData(
      _serbianLeagueView['data']! as Map<String, dynamic>,
    ).games;
    List<String> matching(String query, [GamebaseFilter? filter]) => games
        .where(
          (g) => eventGameMatchesSearch(
            g,
            query: query,
            filter: filter ?? GamebaseFilter(),
          ),
        )
        .map((g) => g.white.name!)
        .toList();

    test(
      'one long word is a prefix over players, FIDE ids, ECO and opening',
      () {
        expect(matching('carlsen'), ['Atalik, Suat', 'Alimpic, Aleksa']);
        expect(matching('gaponen'), ['Gaponenko, Inna']);
        expect(matching('14101181'), ['Gaponenko, Inna']);
      },
    );

    test('several words must all appear', () {
      expect(matching('exchange carlsen'), ['Atalik, Suat', 'Alimpic, Aleksa']);
      expect(matching('magnus carlsen'), isEmpty);
    });

    test('text under three letters is ignored, as the server does', () {
      expect(matching('ab'), hasLength(games.length));
    });

    test('ECO, result, year and rating filters apply per game', () {
      expect(matching('', GamebaseFilter(eco: GameEcoFilter.forCode('C4'))), [
        'Gaponenko, Inna',
      ]);
      expect(matching('', GamebaseFilter(result: GameResultFilter.whiteWins)), [
        'Alimpic, Aleksa',
      ]);
      expect(matching('', GamebaseFilter(maxYear: 2025)), isEmpty);
      expect(matching('', GamebaseFilter(minRating: 2350)), [
        'Atalik, Suat',
        'Gaponenko, Inna',
      ]);
    });
  });
}

/// Trimmed live `GET /api/event?name=Serbian Super League 2026` (2026-10-29).
const _serbianLeagueView = <String, Object>{
  'status': 'success',
  'data': <String, Object?>{
    'event': 'Serbian Super League 2026',
    'site':
        'https://lichess.org/broadcast/serbian-super-league-2026-women/round-3/0OH4UhHT/L63dvPSi',
    'truncated': false,
    'games': [
      {
        'id': '1fec7945-7eaa-5dbd-84d5-fb80ae8d4a74',
        'round': '1.15',
        'white': {
          'name': 'Atalik, Suat',
          'fideId': '14401487',
          'title': 'GM',
          'elo': 2371,
          'fed': 'SRB',
        },
        'black': {
          'name': 'Klukin, Kirill',
          'fideId': '24199273',
          'title': 'IM',
          'elo': 2382,
          'fed': 'SRB',
        },
        'result': '1/2-1/2',
        'date': '2026-10-04T00:00:00.000Z',
        'eco': 'D35',
        'opening':
            "Queen's Gambit Declined: Exchange Variation, Carlsen Variation",
      },
      {
        'id': '18a3377c-94aa-52dd-9da3-e684b955b59e',
        'round': '10.26',
        'white': {
          'name': 'Alimpic, Aleksa',
          'fideId': '974323',
          'title': 'FM',
          'elo': 2247,
          'fed': 'SRB',
        },
        'black': {
          'name': 'Radovic, Luka',
          'fideId': '911569',
          'title': 'FM',
          'elo': 2283,
          'fed': 'SRB',
        },
        'result': '1-0',
        'date': '2026-10-13T00:00:00.000Z',
        'eco': 'D35',
        'opening':
            "Queen's Gambit Declined: Exchange Variation, Carlsen Variation",
      },
      {
        'id': '009c5180-fdba-57b9-b5ff-94ccaba906ba',
        'round': '3.1',
        'white': {
          'name': 'Gaponenko, Inna',
          'fideId': '14101181',
          'title': 'IM',
          'elo': 2308,
          'fed': 'UKR',
        },
        'black': {
          'name': 'Injac, Teodora',
          'fideId': '932400',
          'title': 'IM',
          'elo': 2405,
          'fed': 'SRB',
        },
        'result': '1/2-1/2',
        'date': '2026-09-26T00:00:00.000Z',
        'eco': 'C47',
        'opening': 'Four Knights Game: Scotch Variation Accepted',
      },
    ],
  },
};

ProviderContainer _gamesContainer(
  GamebaseRepository repo, {
  required String event,
  GamebaseFilter? filter,
  String query = 'carlsen',
}) {
  final container = ProviderContainer(
    overrides: [
      gamebaseRepositoryProvider.overrideWithValue(repo),
      if (filter != null) gamebaseFilterProvider.overrideWith((ref) => filter),
    ],
  );
  container.read(librarySearchQueryProvider.notifier).state = query;
  container.read(twicSelectedEventProvider.notifier).state = event;
  return container;
}

TwicEventAggregate _aggregate(
  String event,
  int games,
  DateTime end, {
  int? playerMatches,
}) {
  return TwicEventAggregate(
    id: event,
    event: event,
    gameCount: games,
    endDate: end,
    playerMatchCount: playerMatches,
  );
}

Map<String, dynamic> _eventsAnswer({required int? playerMatchCount}) => {
  'status': 'success',
  'data': {
    'events': [
      {
        'id': 'event_1',
        'event': 'Serbian Super League 2026',
        'gameCount': 2,
        if (playerMatchCount != null) 'playerMatchCount': playerMatchCount,
      },
    ],
    'metadata': {'pageNumber': 1, 'pageSize': 20, 'hasMore': false},
  },
};

Map<String, dynamic> _gamesAnswer() => {
  'status': 'success',
  'data': {
    'results': const [],
    'metadata': {
      'pageNumber': 1,
      'pageSize': 20,
      'totalCount': 0,
      'totalCountIsEstimate': false,
      'hasMore': false,
    },
  },
};
