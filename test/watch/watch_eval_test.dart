import 'dart:async';
import 'dart:convert';
import 'package:chessever2/watch/core/watch_eval.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const fen = '7k/8/8/8/8/8/8/K7 w - - 0 1';

  test(
    'cloud scores complete for all readers and are reused from cache',
    () async {
      final reply = Completer<http.Response>();
      var requests = 0;
      final source = WatchEvalSource(
        client: MockClient((_) {
          requests++;
          return reply.future;
        }),
      );
      addTearDown(source.dispose);
      final first = source.eval(fen);
      final second = source.eval(fen);
      reply.complete(
        http.Response(
          jsonEncode({
            'depth': 24,
            'pvs': [
              {'cp': 130},
            ],
          }),
          200,
        ),
      );
      final scores = await Future.wait([
        first,
        second,
      ]).timeout(const Duration(seconds: 2));
      expect(scores.map((score) => score?.label), ['+1.3', '+1.3']);
      expect((await source.eval(fen))?.depth, 24);
      expect(requests, 1);
    },
  );

  test('missing cloud positions complete as unknown', () async {
    final source = WatchEvalSource(
      client: MockClient((_) async => http.Response('', 404)),
    );
    addTearDown(source.dispose);
    expect(await source.eval(fen).timeout(const Duration(seconds: 2)), isNull);
  });
}
