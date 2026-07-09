import 'dart:async';

import 'package:chessever2/repository/api_utils/api_exceptions.dart';
import 'package:chessever2/utils/transient_request_retry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retries timeout reads', () async {
    var calls = 0;

    final result = await retryTransientRead(() async {
      calls += 1;
      if (calls == 1) {
        throw TimeoutException('slow request');
      }
      return 'ok';
    }, delays: const [Duration.zero]);

    expect(result, 'ok');
    expect(calls, 2);
  });

  test('retries timeout-like network exceptions', () async {
    var calls = 0;

    final result = await retryTransientRead(() async {
      calls += 1;
      if (calls == 1) {
        throw NetworkException('Request timeout');
      }
      return 42;
    }, delays: const [Duration.zero]);

    expect(result, 42);
    expect(calls, 2);
  });

  test('does not retry non-transient errors', () async {
    var calls = 0;

    await expectLater(
      retryTransientRead<void>(() async {
        calls += 1;
        throw StateError('bad state');
      }, delays: const [Duration.zero]),
      throwsStateError,
    );

    expect(calls, 1);
  });
}
