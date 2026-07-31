import 'package:chessever2/providers/push_token_sync_retry_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PushTokenSyncRetryState', () {
    test('failed sync remains eligible for a bounded retry', () {
      final state = PushTokenSyncRetryState(maxAttempts: 3);

      expect(state.shouldSync('user|subscription|token|true'), isTrue);
      expect(
        state.recordFailure('user|subscription|token|true'),
        const Duration(seconds: 2),
      );
      expect(state.shouldSync('user|subscription|token|true'), isTrue);
      expect(
        state.recordFailure('user|subscription|token|true'),
        const Duration(seconds: 5),
      );
      expect(state.shouldSync('user|subscription|token|true'), isTrue);
      expect(state.recordFailure('user|subscription|token|true'), isNull);
      expect(state.shouldSync('user|subscription|token|true'), isFalse);
    });

    test('successful sync suppresses duplicate writes', () {
      final state = PushTokenSyncRetryState(maxAttempts: 3);
      const signature = 'user|subscription|token|true';

      state.recordSuccess(signature);

      expect(state.shouldSync(signature), isFalse);
    });

    test('a new subscription resets the retry budget', () {
      final state = PushTokenSyncRetryState(maxAttempts: 2);

      expect(state.recordFailure('old'), const Duration(seconds: 2));
      expect(state.recordFailure('old'), isNull);
      expect(state.shouldSync('old'), isFalse);

      expect(state.shouldSync('new'), isTrue);
      expect(state.recordFailure('new'), const Duration(seconds: 2));
      expect(state.shouldSync('new'), isTrue);
    });
  });
}
