import 'package:chessever2/services/rewarded_premium/rewarded_session.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_unlock_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Duration elapsed;
  late RewardedSession session;
  final now = DateTime.utc(2026, 10, 1);
  setUp(() {
    elapsed = Duration.zero;
    session = RewardedSession(elapsed: () => elapsed);
    session.bindUser('guest');
  });
  Map<String, dynamic> active() => {
    'status': 'active',
    'expires_at': now.add(const Duration(minutes: 10)).toIso8601String(),
    'server_now': now.toIso8601String(),
  };

  test('ten elapsed minutes expire even without foreground timer ticks', () {
    session.grant(
      expiresAt: now.add(const Duration(minutes: 10)),
      serverNow: now,
    );
    elapsed = const Duration(minutes: 9, seconds: 59);
    expect(session.active, true);
    elapsed = const Duration(minutes: 10);
    expect(session.active, false);
    expect(session.headers, isEmpty);
  });
  test('new process and account changes cannot reuse a reward token', () {
    session.grant(
      expiresAt: now.add(const Duration(minutes: 10)),
      serverNow: now,
    );
    final token = session.token;
    final fresh = RewardedSession(elapsed: () => elapsed)..bindUser('guest');
    expect(fresh.active, false);
    expect(fresh.token, isNot(token));
    session.bindUser('other');
    expect(session.active, false);
    expect(session.token, isNot(token));
  });
  test('bad duration never creates a grant', () {
    expect(
      () => session.grant(
        expiresAt: now.add(const Duration(minutes: 11)),
        serverNow: now,
      ),
      throwsStateError,
    );
    expect(session.active, false);
  });
  test('early ad dismissal never activates', () async {
    final flow = RewardedUnlockFlow(session);
    final actions = <String>[];
    final result = await flow.unlock(
      prepareAds: () async {},
      showAd: (_) async => false,
      request: (action, token, {attempt}) async {
        actions.add(action);
        return {'attempt_id': 'a'};
      },
      onPending: () {},
    );
    expect(result, false);
    expect(actions, ['prepare']);
    expect(session.active, false);
    expect(flow.pending, false);
  });
  test('delayed confirmation retries without another ad', () async {
    final flow = RewardedUnlockFlow(
      session,
      pollCount: 1,
      pollDelay: Duration.zero,
    );
    var ads = 0;
    var pending = true;
    Future<Map<String, dynamic>> request(
      String action,
      String token, {
      String? attempt,
    }) async {
      if (action == 'prepare') return {'attempt_id': 'a'};
      return pending ? {'status': 'pending'} : active();
    }

    Future<bool> unlock() => flow.unlock(
      prepareAds: () async {},
      showAd: (_) async {
        ads++;
        return true;
      },
      request: request,
      onPending: () {},
    );
    expect(await unlock(), false);
    expect(flow.pending, true);
    pending = false;
    expect(await unlock(), true);
    expect(ads, 1);
    expect(flow.pending, false);
    expect(session.active, true);
  });
  test('network errors preserve the earned attempt', () async {
    final flow = RewardedUnlockFlow(session, pollCount: 1);
    await expectLater(
      flow.unlock(
        prepareAds: () async {},
        showAd: (_) async => true,
        request: (action, token, {attempt}) async {
          if (action == 'prepare') return {'attempt_id': 'a'};
          throw StateError('offline');
        },
        onPending: () {},
      ),
      throwsStateError,
    );
    expect(flow.pending, true);
    expect(session.active, false);
  });
  test('account switch during the ad discards the reward', () async {
    final flow = RewardedUnlockFlow(session);
    final result = await flow.unlock(
      prepareAds: () async {},
      showAd: (_) async {
        session.bindUser('other');
        flow.clear();
        return true;
      },
      request: (action, token, {attempt}) async => {'attempt_id': 'a'},
      onPending: () {},
    );
    expect(result, false);
    expect(flow.pending, false);
    expect(session.active, false);
  });
  test('expired activation never extends the old grant', () async {
    final flow = RewardedUnlockFlow(session, pollCount: 1);
    await expectLater(
      flow.unlock(
        prepareAds: () async {},
        showAd: (_) async => true,
        request: (action, token, {attempt}) async =>
            action == 'prepare' ? {'attempt_id': 'a'} : {'status': 'expired'},
        onPending: () {},
      ),
      throwsStateError,
    );
    expect(flow.pending, false);
    expect(session.active, false);
  });
}
