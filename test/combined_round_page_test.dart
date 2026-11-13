import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:chessever2/repository/supabase/game/game_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late http.Request request;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://fixture.supabase.co',
      publishableKey: 'fixture-key',
      httpClient: MockClient((r) async {
        request = r;
        return http.Response(
          jsonEncode([
            {
              'id': 'g',
              'tour_id': 't',
              'tour_slug': 't',
              'round_id': 'r',
              'round_slug': 'round-1',
              'status': '*',
              'players': [],
            },
          ]),
          200,
          request: r,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() async {
    await Supabase.instance.dispose();
  });
  test(
    'Combined uses a lightweight, deterministic page scoped to both real ids',
    () async {
      final rows = await GameRepository().getCombinedRoundGamesPage(
        't',
        'r',
        offset: 16,
        limit: 1000,
      );
      final params = request.url.queryParameters;
      expect(params['tour_id'], 'eq.t');
      expect(params['round_id'], 'eq.r');
      expect(params['is_mirror'], 'eq.false');
      expect(params['order'], 'board_nr.asc.nullslast,id.asc.nullslast');
      expect(params['offset'], '16');
      expect(params['limit'], '1000');
      final columns = params['select']!;
      expect(RegExp(r'\bpgn\b').hasMatch(columns), isFalse);
      expect(columns, contains('players'));
      expect(columns, contains('last_clock_white'));
      expect(rows.single.id, 'g');
    },
  );
  test('invalid bounds fail before a request', () async {
    final repo = GameRepository();
    for (final bounds in [(-1, 16), (0, 0), (0, 1001)]) {
      await expectLater(
        repo.getCombinedRoundGamesPage(
          't',
          'r',
          offset: bounds.$1,
          limit: bounds.$2,
        ),
        throwsArgumentError,
      );
    }
  });
}
