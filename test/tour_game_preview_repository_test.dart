import 'dart:async';
import 'dart:convert';

import 'package:chessever2/repository/supabase/game/game_repository.dart';
import 'package:chessever2/repository/supabase/game/games.dart';
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

Map<String, dynamic> _row(int index) => {
  'id': 'g$index',
  'round_id': 'round-${index ~/ 400}',
  'round_slug': 'round-${index ~/ 400}',
  'tour_id': 'tour',
  'tour_slug': 'tour',
  'status': index == 0 ? '*' : '1-0',
  'board_nr': index % 400,
  'players': [
    for (final name in ['White', 'Black'])
      {
        'name': '$name $index',
        'rating': index == 1 ? 0 : 2600,
        'title': 'GM',
        'fideId': index + 1,
        'fed': 'USA',
        'clock': 6000,
        'team': '',
      },
  ],
  'search': ['White $index', 'Black $index'],
};

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://placeholder.supabase.co',
      publishableKey: 'placeholder',
    );
  });

  test(
    '2400-game index is complete and fetches PGN only for required fallbacks',
    () async {
      final pages = <int>[];
      final fullRequests = <String>[];
      final client = SupabaseClient(
        'https://example.test',
        'placeholder',
        httpClient: MockClient((request) async {
          final query = request.url.queryParameters;
          final columns = query['select']!.split(',');
          List<Map<String, dynamic>> rows;
          if (query.containsKey('id')) {
            expect(columns, contains('pgn'));
            fullRequests.add(query['id']!);
            rows = [
              for (var i = 0; i < 2; i++)
                {
                  ..._row(i),
                  'pgn': '[WhiteElo "2600"]\n[BlackElo "2600"]\n\n1. e4 *',
                },
            ];
          } else {
            expect(columns, isNot(contains('pgn')));
            expect(columns, contains('search'));
            expect(query['tour_id'], 'eq.tour');
            expect(query['order'], startsWith('id.asc'));
            final offset = int.parse(query['offset'] ?? '0');
            pages.add(offset);
            final limit = int.parse(query['limit']!);
            final end = (offset + limit).clamp(0, 2400);
            rows = [for (var i = offset; i < end; i++) _row(i)];
          }
          return http.Response(
            jsonEncode(rows),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final games = await _Repository(client).getTourGamePreviews('tour');
      expect(pages, [0, 1000, 2000]);
      expect(fullRequests.length, 1);
      expect(fullRequests.single.replaceAll('"', ''), 'in.(g0,g1)');
      expect(games.length, 2400);
      expect(games.map((g) => g.id).toSet().length, 2400);
      expect(games.where((g) => g.pgn != null).length, 2);
      expect(games.first.isPgnDeferred, isFalse);
      expect(games.last.isPgnDeferred, isTrue);
      expect(games.last.search, ['White 2399', 'Black 2399']);
      // Disk-cache round trips must retain the demand-loading marker.
      expect(Games.fromJson(games.last.toJson()).isPgnDeferred, isTrue);
    },
  );

  test('nonstandard results and absent ratings preserve PGN fallbacks', () {
    final finished = Games.fromJson(_row(2));
    expect(tourIndexNeedsPgn(finished), isFalse);
    for (final status in ['*', '', '0-0', '+:-', '½-½', 'unknown']) {
      expect(tourIndexNeedsPgn(finished.copyWith(status: status)), isTrue);
    }
    expect(tourIndexNeedsPgn(Games.fromJson(_row(1))), isTrue);
  });

  test('a failed snapshot cannot publish an incomplete tournament', () async {
    final client = SupabaseClient(
      'https://example.test',
      'placeholder',
      httpClient: MockClient((request) async {
        final query = request.url.queryParameters;
        final snapshot = query.containsKey('id');
        final offset = int.parse(query['offset'] ?? '0');
        if (offset > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        return http.Response(
          jsonEncode(
            snapshot
                ? {'message': 'offline'}
                : [
                  if (offset == 0)
                    for (var i = 0; i < 1000; i++) _row(i),
                ],
          ),
          snapshot ? 503 : 200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    await expectLater(
      _Repository(client).getTourGamePreviews('tour'),
      throwsException,
    );
  });

  test('large live events hydrate while paging with bounded requests', () async {
    final secondPageRequested = Completer<void>();
    final release = Completer<void>();
    var active = 0;
    var peakActive = 0;
    var fullRequests = 0;
    final client = SupabaseClient(
      'https://example.test',
      'placeholder',
      httpClient: MockClient((request) async {
        final query = request.url.queryParameters;
        active++;
        if (active > peakActive) peakActive = active;
        final ids = query['id'];
        late List<Map<String, dynamic>> rows;
        if (ids != null) {
          fullRequests++;
          await release.future;
          rows = [
            for (final id in ids
                .substring(4, ids.length - 1)
                .replaceAll('"', '')
                .split(','))
              {
                ..._row(int.parse(id.substring(1))),
                'pgn': '[Result "*"]\n\n1. e4 *',
              },
          ];
        } else {
          final offset = int.parse(query['offset'] ?? '0');
          if (offset != 0) {
            secondPageRequested.complete();
            await release.future;
          }
          rows = [
            for (var i = offset; i < (offset + 1000).clamp(0, 1632); i++)
              {..._row(i), 'status': '*'},
          ];
        }
        active--;
        return http.Response(
          jsonEncode(rows),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.dispose);
    final loading = _Repository(client).getTourGamePreviews('tour');
    try {
      await secondPageRequested.future;
      await Future<void>.delayed(Duration.zero);
      expect(
        fullRequests,
        4,
        reason:
            'The Games tab must not serialize PGN downloads behind the entire index.',
      );
    } finally {
      release.complete();
      await loading;
    }
    final games = await loading;
    expect(games.length, 1632);
    expect(games.map((g) => g.id).toSet().length, 1632);
    expect(games.every((g) => g.pgn != null && !g.isPgnDeferred), isTrue);
    expect(peakActive, lessThanOrEqualTo(5));
  });
}
