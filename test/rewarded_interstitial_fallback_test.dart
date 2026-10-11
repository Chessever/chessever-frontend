import 'package:chessever2/services/rewarded_premium/rewarded_session.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_unlock_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late RewardedSession session;
  late RewardedUnlockFlow flow;
  final loadError = StateError('load');
  final now = DateTime.utc(2026, 10, 10);
  setUp(() {
    session = RewardedSession(elapsed: () => Duration.zero)..bindUser('guest');
    flow = RewardedUnlockFlow(session, pollCount: 1, pollDelay: Duration.zero);
  });
  Map<String, dynamic> active() => {
    'status': 'active',
    'expires_at': now.add(const Duration(minutes: 10)).toIso8601String(),
    'server_now': now.toIso8601String(),
  };

  test(
    'fallback reward activates its own attempt; retry never shows another ad',
    () async {
      var primaryAds = 0;
      var fallbackAds = 0;
      var confirmed = false;
      final activations = <String?>[];
      Future<bool> unlock() => flow.unlock(
        prepareAds: () async {},
        showAd: (_) async {
          primaryAds++;
          throw loadError;
        },
        shouldUseFallback: (error) => identical(error, loadError),
        prepareFallback: (token) async {
          expect(token, session.token);
          return {'attempt_id': 'interstitial-attempt'};
        },
        showFallbackAd: (attempt) async {
          expect(attempt, 'interstitial-attempt');
          fallbackAds++;
          return true;
        },
        request: (action, token, {attempt}) async {
          if (action == 'prepare') return {'attempt_id': 'primary-attempt'};
          activations.add(attempt);
          return confirmed ? active() : {'status': 'pending'};
        },
        onPending: () {},
      );
      expect(await unlock(), false);
      expect(flow.pending, true);
      expect(flow.attemptId, 'interstitial-attempt');
      confirmed = true;
      expect(await unlock(), true);
      expect(activations, ['interstitial-attempt', 'interstitial-attempt']);
      expect(primaryAds, 1);
      expect(fallbackAds, 1);
      expect(session.active, true);
    },
  );

  test('successful primary reward never invokes fallback', () async {
    expect(
      await flow.unlock(
        prepareAds: () async {},
        showAd: (_) async => true,
        shouldUseFallback: (_) => true,
        prepareFallback: (_) async => fail('Unexpected fallback'),
        showFallbackAd: (_) async => fail('Unexpected interstitial'),
        request: (action, token, {attempt}) async =>
            action == 'prepare' ? {'attempt_id': 'primary'} : active(),
        onPending: () {},
      ),
      true,
    );
  });

  test('skip intro never shows fallback or activates reward', () async {
    expect(
      await flow.unlock(
        prepareAds: () async {},
        showAd: (_) async => throw loadError,
        shouldUseFallback: (_) => true,
        prepareFallback: (_) async => null,
        showFallbackAd: (_) async => fail('Skipped ad must not show'),
        request: (action, token, {attempt}) async {
          expect(action, 'prepare');
          return {'attempt_id': 'primary'};
        },
        onPending: () => fail('No pending reward'),
      ),
      false,
    );
    expect(flow.pending, false);
    expect(session.active, false);
  });

  test('early dismissal of either format never activates', () async {
    for (final primaryDismissed in [true, false]) {
      expect(
        await flow.unlock(
          prepareAds: () async {},
          showAd: (_) async {
            if (primaryDismissed) return false;
            throw loadError;
          },
          shouldUseFallback: (_) => true,
          prepareFallback: (_) async {
            expect(primaryDismissed, false);
            return {'attempt_id': 'fallback'};
          },
          showFallbackAd: (_) async => false,
          request: (action, token, {attempt}) async {
            expect(action, 'prepare');
            return {'attempt_id': 'primary'};
          },
          onPending: () => fail('No earned reward'),
        ),
        false,
      );
    }
    expect(session.active, false);
  });

  test(
    'ineligible failures and fallback failures never trigger more ads',
    () async {
      for (final eligible in [false, true]) {
        var fallbackAds = 0;
        await expectLater(
          flow.unlock(
            prepareAds: () async {},
            showAd: (_) async => throw loadError,
            shouldUseFallback: (_) => eligible,
            prepareFallback: (_) async {
              expect(eligible, true);
              return {'attempt_id': 'fallback'};
            },
            showFallbackAd: (_) async {
              fallbackAds++;
              throw loadError;
            },
            request: (action, token, {attempt}) async => {
              'attempt_id': 'primary',
            },
            onPending: () {},
          ),
          throwsA(same(loadError)),
        );
        expect(fallbackAds, eligible ? 1 : 0);
        expect(flow.busy, false);
        expect(flow.pending, false);
      }
    },
  );

  test('account switch during primary loading suppresses fallback', () async {
    expect(
      await flow.unlock(
        prepareAds: () async {},
        showAd: (_) async {
          session.bindUser('other');
          throw loadError;
        },
        shouldUseFallback: (_) => true,
        prepareFallback: (_) async => fail('Stale account fallback'),
        showFallbackAd: (_) async => fail('Stale account ad'),
        request: (action, token, {attempt}) async => {'attempt_id': 'primary'},
        onPending: () {},
      ),
      false,
    );
  });
}
