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
}
