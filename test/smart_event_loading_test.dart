import 'dart:async';
import 'dart:convert';

import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
import 'package:chessever2/screens/group_event/smart_event/smart_aggregate_event_provider.dart';
import 'package:chessever2/widgets/game_filter/game_filter_model.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Repository extends GameRepository {
  _Repository(this.client);
  final SupabaseClient client;
  @override
  SupabaseClient get supabase => client;
}

Map<String, dynamic> _game(int id, {String day = '2026-09-29'}) => {
  'id': 'g$id',
  'round_id': 'round',
  'round_slug': 'round',
  'tour_id': 'tour',
  'tour_slug': 'tour',
  'status': '1-0',
  'game_day': day,
  'players': [
    for (final name in ['White', 'Black'])
      {'name': name, 'rating': 2600, 'fideId': id, 'fed': 'USA'},
  ],
};

http.Response _response(http.Request request, Object? body) => http.Response(
  jsonEncode(body),
  200,
  request: request,
  headers: {'content-type': 'application/json'},
);

SmartEventRequest _request({
  Set<String> formats = const {},
  int floor = 0,
  GameEcoFilter eco = GameEcoFilter.all,
}) => SmartEventRequest(
  source: SmartEventSource.forYou,
  tierLabel: 'All',
  titleSuffix: 'Games',
  minElo: floor,
  maxElo: 3200,
  caption: '',
  countSingular: 'event',
  countPlural: 'events',
  events: [],
  formatsAndStates: formats,
  eco: eco,
);

class _SparseHistoryRepository extends GameRepository {
  int dayReads = 0;
  final newest = DateTime(2026, 9, 29);
  @override
  Future<DateTime?> getCurrentSmartEventDay({
    bool liveOnly = false,
    bool completedOnly = false,
    int? minGameAverageElo,
    int? maxGameAverageElo,
    List<String>? eventTimeControls,
    DateTime? before,
    String? searchQuery,
    GameFilter? extraFilter,
  }) async => newest;

  @override
  Future<CurrentSmartEventDayPage> getCurrentSmartEventGamesOnDay({
    required DateTime day,
    bool liveOnly = false,
    bool completedOnly = false,
    int? minGameAverageElo,
    int? maxGameAverageElo,
    List<String>? eventTimeControls,
    String? searchQuery,
    GameFilter? extraFilter,
    bool deferNextDayLookup = false,
  }) async {
    dayReads++;
    final last = dayReads == 15;
    return CurrentSmartEventDayPage(
      day: day,
      games: last ? [Games.fromJson(_game(1))] : [],
      nextDay: last ? null : day.subtract(const Duration(days: 1)),
    );
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder',
    );
  });

  test('a loaded day does not wait for an older history lookup', () async {
    final history = Completer<http.Response>();
    var historyRequests = 0;
    final client = SupabaseClient(
      'https://example.test',
      'placeholder',
      httpClient: MockClient((request) async {
        if (request.url.queryParameters['limit'] == '1') {
          historyRequests++;
          return history.future;
        }
        return _response(request, [_game(1)]);
      }),
    );
    addTearDown(client.dispose);
    try {
      final page = await _Repository(client)
          .getCurrentSmartEventGamesOnDay(
            day: DateTime(2026, 9, 29),
            deferNextDayLookup: true,
          )
          .timeout(const Duration(seconds: 2));
      expect(page.games.map((g) => g.id), ['g1']);
      expect(historyRequests, 0);
      expect(page.nextDay, DateTime(2026, 9, 29));
    } finally {
      history.complete(http.Response('[]', 200));
    }
  });
  test(
    'the real aggregate publishes Games while older history is still pending',
    () async {
      final historyStarted = Completer<void>();
      final history = Completer<http.Response>();
      late http.Request olderRequest;
      final client = SupabaseClient(
        'https://example.test',
        'placeholder',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/get_current_smart_event_day')) {
            final params = jsonDecode(request.body);
            if (params['p_before'] != null) {
              olderRequest = request;
              historyStarted.complete();
              return history.future;
            }
            return _response(request, '2026-09-29');
          }
          return _response(request, [_game(1)]);
        }),
      );
      addTearDown(client.dispose);
      final container = ProviderContainer(
        overrides: [
          gameRepositoryProvider.overrideWithValue(_Repository(client)),
        ],
      );
      final query = SmartEventGamesQuery(request: _request());
      final loaded = Completer<SmartAggregateEvent>();
      container.listen(smartAggregateEventRepositoryProvider(query), (
        _,
        value,
      ) {
        value.when(
          data: (data) {
            if (!loaded.isCompleted) loaded.complete(data);
          },
          error: (error, trace) {
            if (!loaded.isCompleted) loaded.completeError(error, trace);
          },
          loading: () {},
        );
      }, fireImmediately: true);
      try {
        final first = await loaded.future.timeout(const Duration(seconds: 2));
        expect(first.games.map((g) => g.gameId), ['g1']);
        await historyStarted.future.timeout(const Duration(seconds: 2));
        expect(history.isCompleted, isFalse);
        expect(
          container
              .read(smartAggregateEventRepositoryProvider(query))
              .requireValue
              .games,
          hasLength(1),
        );
      } finally {
        container.dispose();
        if (historyStarted.isCompleted) {
          history.complete(_response(olderRequest, null));
        }
      }
    },
  );

  test(
    'legacy resolved-day callers keep their original cursor contract',
    () async {
      var historyCalls = 0;
      final client = SupabaseClient(
        'https://example.test',
        'placeholder',
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/get_current_smart_event_day')) {
            historyCalls++;
            expect(jsonDecode(request.body)['p_before'], '2026-09-29');
            return _response(request, '2026-09-12');
          }
          return _response(request, [_game(1)]);
        }),
      );
      addTearDown(client.dispose);
      final page = await _Repository(
        client,
      ).getCurrentSmartEventGamesOnDay(day: DateTime(2026, 9, 29));
      expect(page.nextDay, DateTime(2026, 9, 12));
      expect(page.nextDayIsBoundary, isFalse);
      expect(historyCalls, 1);
    },
  );

  test(
    'a sparse collection is not declared empty after thirteen candidate days',
    () async {
      final repository = _SparseHistoryRepository();
      final container = ProviderContainer(
        overrides: [gameRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final query = SmartEventGamesQuery(request: _request());
      final loaded = Completer<SmartAggregateEvent>();
      final subscription = container.listen(
        smartAggregateEventRepositoryProvider(query),
        (_, value) {
          value.when(
            data: (data) {
              if (!loaded.isCompleted) loaded.complete(data);
            },
            error: (error, trace) {
              if (!loaded.isCompleted) loaded.completeError(error, trace);
            },
            loading: () {},
          );
        },
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      final result = await loaded.future.timeout(const Duration(seconds: 2));
      expect(result.games.map((g) => g.gameId), ['g1']);
      expect(repository.dayReads, 15);
    },
  );

  test(
    'a day with more than 8000 games is complete and carries no PGN',
    () async {
      final offsets = <int>[];
      final client = SupabaseClient(
        'https://example.test',
        'placeholder',
        httpClient: MockClient((request) async {
          final params = request.url.queryParameters;
          expect(params['select'], isNot(contains('pgn')));
          expect(params['order'], contains('id.asc'));
          final from = int.parse(params['offset'] ?? '0');
          final limit = int.parse(params['limit']!);
          offsets.add(from);
          return _response(request, [
            for (var i = from; i < (from + limit).clamp(0, 8001); i++) _game(i),
          ]);
        }),
      );
      addTearDown(client.dispose);
      final page = await _Repository(client).getCurrentSmartEventGamesOnDay(
        day: DateTime(2026, 9, 29),
        deferNextDayLookup: true,
      );
      expect(page.games, hasLength(8001));
      expect(page.games.map((g) => g.id).toSet(), hasLength(8001));
      expect(offsets, [for (var i = 0; i <= 8000; i += 1000) i]);
    },
  );

  test(
    'C44+GM+Classical resolves only candidate tours, including midnight spillover',
    () async {
      final requests = <String>[];
      final client = SupabaseClient(
        'https://example.test',
        'placeholder',
        httpClient: MockClient((request) async {
          final table = request.url.path.split('/').last;
          requests.add(table);
          final params = request.url.queryParameters;
          switch (table) {
            case 'tours':
              return _response(request, [
                {'id': 'tour', 'group_broadcast_id': 'event'},
              ]);
            case 'group_broadcasts':
              return _response(request, [
                {'id': 'event', 'time_control': 'Classical'},
              ]);
            case 'games':
              expect(params['game_day'], 'eq.2026-09-29');
              expect(params['eco'], 'eq.C44');
              expect(params['player_max_rating'], 'gte.2500');
              if (params['select']!.startsWith('tour_id,')) {
                return _response(request, [
                  {
                    'tour_id': 'tour',
                    'tours': {
                      'group_broadcasts': {'time_control': 'Classical'},
                    },
                  },
                ]);
              }
              return _response(request, [
                {..._game(1), 'eco': 'C44'},
              ]);
            default:
              fail('Unexpected request: $table');
          }
        }),
      );
      addTearDown(client.dispose);
      final page = await _Repository(client).getCurrentSmartEventGamesOnDay(
        day: DateTime(2026, 9, 29),
        minGameAverageElo: 2500,
        eventTimeControls: ['standard', 'classical'],
        extraFilter: GameFilter(eco: GameEcoFilter.forCode('C44')),
        deferNextDayLookup: true,
      );
      expect(page.games.map((g) => g.id), ['g1']);
      expect(requests, ['games', 'games']);
    },
  );

  test(
    '800 creation combinations pass every dimension to the actual day RPC',
    () async {
      final openings = [
        GameEcoFilter.all,
        GameEcoFilter.forCode('C44'),
        GameEcoFilter.forFamily('B9'),
        GameEcoFilter.forCode('D30-D42'),
        GameEcoFilter.forCode('E6+E7+E8+E9'),
      ];
      var calls = 0;
      late SmartEventFetchScope scope;
      late GameEcoFilter opening;
      final client = SupabaseClient(
        'https://example.test',
        'placeholder',
        httpClient: MockClient((request) async {
          expect(
            request.url.path,
            endsWith('/rpc/get_current_smart_event_day'),
          );
          final params = jsonDecode(request.body) as Map<String, dynamic>;
          expect(params['p_live_only'], scope.liveOnly);
          expect(params['p_completed_only'], scope.completedOnly);
          expect(params['p_min_rating'], scope.minGameAverageElo);
          expect(params['p_max_rating'], scope.maxGameAverageElo);
          expect(
            params['p_time_controls'],
            scope.eventTimeControls
                ?.map((v) => v.toLowerCase())
                .toSet()
                .toList(),
          );
          expect(
            params['p_eco_codes'],
            opening.isAll ? null : opening.exactEcoCodes,
          );
          calls++;
          return _response(request, '2026-08-29');
        }),
      );
      addTearDown(client.dispose);
      final repository = _Repository(client);
      for (var state = 0; state < 4; state++) {
        for (var format = 0; format < 8; format++) {
          for (final floor in [0, 2200, 2300, 2400, 2500]) {
            for (final eco in openings) {
              opening = eco;
              final request = _request(
                formats: {
                  if (state & 1 != 0) 'live',
                  if (state & 2 != 0) 'completed',
                  if (format & 1 != 0) 'standard',
                  if (format & 2 != 0) 'rapid',
                  if (format & 4 != 0) 'blitz',
                },
                floor: floor,
                eco: eco,
              );
              final query = SmartEventGamesQuery(request: request);
              scope = smartEventFetchScopeFor(query);
              final result = await repository.getCurrentSmartEventDay(
                liveOnly: scope.liveOnly,
                completedOnly: scope.completedOnly,
                minGameAverageElo: scope.minGameAverageElo,
                maxGameAverageElo: scope.maxGameAverageElo,
                eventTimeControls: scope.eventTimeControls,
                extraFilter: smartEventResidualFilterForTest(
                  null,
                  requestEco: eco,
                ),
              );
              expect(result, DateTime(2026, 8, 29));
            }
          }
        }
      }
      expect(calls, 800);
    },
  );

  test(
    'missing additive RPC falls back; database errors never become empty results',
    () async {
      for (final code in ['PGRST202', '57014']) {
        var legacyRequests = 0;
        final client = SupabaseClient(
          'https://example.test',
          'placeholder',
          httpClient: MockClient((request) async {
            if (request.url.path.endsWith('/get_current_smart_event_day')) {
              return http.Response(
                jsonEncode({'code': code, 'message': 'fixture'}),
                code == 'PGRST202' ? 404 : 500,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            }
            legacyRequests++;
            return _response(request, [
              {'game_day': '2026-09-12'},
            ]);
          }),
        );
        addTearDown(client.dispose);
        final operation = _Repository(client).getCurrentSmartEventDay();
        if (code == 'PGRST202') {
          expect(await operation, DateTime(2026, 9, 12));
          expect(legacyRequests, 1);
        } else {
          await expectLater(operation, throwsException);
          expect(legacyRequests, 0);
        }
      }
    },
  );
}
