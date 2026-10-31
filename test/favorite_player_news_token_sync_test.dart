import 'dart:convert';

import 'package:chessever2/services/favorite_player_news_token_sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'preferred-service category request uses JWT and installation proof only',
    () async {
      final requests = <http.Request>[];
      final transport = DirectPushDeviceTransport(
        baseUri: Uri.parse('https://local-fixture.invalid'),
        client: MockClient((request) async {
          requests.add(request);
          expect(request.method, 'POST');
          expect(request.url.path, '/v1/devices/preferences');
          expect(request.headers['authorization'], 'Bearer synthetic-jwt');
          expect(jsonDecode(request.body), {
            'installationId': '00000000-0000-4000-8000-000000000001',
            'installationSecret':
                'synthetic-installation-proof-not-a-real-secret',
            'registrationRevision': 9,
            'favoritePlayerNews': false,
          });
          return http.Response(
            jsonEncode({
              'id': '00000000-0000-4000-8000-000000000001',
              'registrationRevision': 9,
              'favoritePlayerNews': false,
              'newsProtocol': 1,
              'newsDrainPending': false,
            }),
            200,
          );
        }),
      );
      final ack = await transport.post('/v1/devices/preferences', {
        'installationId': '00000000-0000-4000-8000-000000000001',
        'installationSecret': 'synthetic-installation-proof-not-a-real-secret',
        'registrationRevision': 9,
        'favoritePlayerNews': false,
      }, accessToken: 'synthetic-jwt');
      expect(
        validNewsDeviceAck(
          ack,
          installationId: '00000000-0000-4000-8000-000000000001',
          revision: 9,
          enabled: false,
        ),
        true,
      );
      expect(requests, hasLength(1));
    },
  );

  test('strict acknowledgements reject old servers and mismatched state', () {
    final good = <String, dynamic>{
      'id': 'installation-a',
      'registrationRevision': 9,
      'favoritePlayerNews': false,
      'newsProtocol': 1,
      'newsDrainPending': false,
    };
    for (final ack in <Map<String, dynamic>>[
      {},
      {...good}..remove('newsProtocol'),
      {...good}..remove('newsDrainPending'),
      {...good, 'newsDrainPending': true},
      {...good, 'newsDrainPending': null},
      {...good, 'newsDrainPending': 0},
      {...good, 'newsProtocol': 1.0},
      {...good, 'newsProtocol': 2},
      {...good, 'id': 'installation-b'},
      {...good, 'registrationRevision': 8},
      {...good, 'registrationRevision': 9.0},
      {...good, 'favoritePlayerNews': true},
      {...good}..remove('favoritePlayerNews'),
    ]) {
      expect(
        validNewsDeviceAck(
          ack,
          installationId: 'installation-a',
          revision: 9,
          enabled: false,
        ),
        false,
      );
    }
    expect(
      validNewsDeviceAck(
        {...good, 'detached': true},
        installationId: 'installation-a',
        revision: 9,
        detached: true,
      ),
      true,
    );
    expect(
      validNewsDeviceAck(
        good,
        installationId: 'installation-a',
        revision: 9,
        detached: true,
      ),
      false,
    );
  });

  for (final code in [400, 401, 403, 404, 409, 503]) {
    test('HTTP $code never acknowledges or exposes response secrets', () async {
      final transport = DirectPushDeviceTransport(
        baseUri: Uri.parse('https://local-fixture.invalid'),
        client: MockClient(
          (_) async => http.Response('synthetic-private-response', code),
        ),
      );
      await expectLater(
        transport.post('/v1/devices/preferences', {}),
        throwsA(
          isA<DirectPushDeviceException>()
              .having((e) => e.statusCode, 'status', code)
              .having(
                (e) => e.toString().contains('synthetic-private-response'),
                'redacted',
                false,
              ),
        ),
      );
    });
  }
  for (final body in ['[]', 'null', '"bad"', 'not-json']) {
    test('malformed success $body fails closed', () async {
      final transport = DirectPushDeviceTransport(
        baseUri: Uri.parse('https://local-fixture.invalid'),
        client: MockClient((_) async => http.Response(body, 200)),
      );
      await expectLater(
        transport.post('/v1/devices/logout', {}),
        throwsFormatException,
      );
    });
  }
}
