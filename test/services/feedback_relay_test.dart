import 'dart:convert';
import 'dart:typed_data';

import 'package:chessever2/services/feedback_relay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'feedback goes only to the public relay with text and attachment',
    () async {
      final relay = FeedbackRelay(
        client: MockClient((request) async {
          expect(request.url, FeedbackRelay.endpoint);
          expect(request.url.scheme, 'https');
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload.keys, unorderedEquals(['message', 'picture']));
          expect(payload['message'], 'A useful report');
          expect(base64Decode((payload['picture'] as Map)['base64']), [
            1,
            2,
            3,
          ]);
          return http.Response('{"ok":true}', 200);
        }),
      );
      expect(
        await relay.send(
          'A useful report',
          picture: Uint8List.fromList([1, 2, 3]),
        ),
        isTrue,
      );
    },
  );

  test(
    'rate limits, provider failures and invalid responses remain failures',
    () async {
      for (final response in [
        http.Response('{"ok":false}', 429),
        http.Response('{"ok":false}', 502),
        http.Response('{"ok":false}', 200),
        http.Response('invalid JSON', 200),
      ]) {
        final relay = FeedbackRelay(client: MockClient((_) async => response));
        expect(await relay.send('report'), isFalse);
      }
      final relay = FeedbackRelay(
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(await relay.send('report'), isFalse);
    },
  );

  test('oversized or empty feedback never reaches the network', () async {
    final relay = FeedbackRelay(
      client: MockClient((_) async => throw StateError('must not send')),
    );
    expect(await relay.send('   '), isFalse);
    expect(await relay.send('x' * 16001), isFalse);
    expect(
      await relay.send('report', picture: Uint8List(5 * 1024 * 1024 + 1)),
      isFalse,
    );
  });
}
