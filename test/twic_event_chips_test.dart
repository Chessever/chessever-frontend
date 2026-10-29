import 'package:chessever2/repository/gamebase/gamebase_repository.dart';
import 'package:chessever2/screens/library/providers/gamebase_database_games_provider.dart';
import 'package:chessever2/screens/library/providers/gamebase_filter_provider.dart';
import 'package:chessever2/screens/library/providers/twic_event_aggregates_provider.dart';
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
      final dio =
          Dio()..interceptors.add(
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

      final request = requests.single;
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
  });
}

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
