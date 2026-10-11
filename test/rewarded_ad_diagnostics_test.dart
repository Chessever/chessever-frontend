// Native SDK errors are constructed here to simulate plugin callbacks.
// ignore_for_file: invalid_use_of_protected_member
import 'dart:async';

import 'package:chessever2/services/rewarded_premium/rewarded_ad_diagnostics.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_ads.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_mobile_ads/src/ad_instance_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<Map<String, dynamic>> events;
  late RewardedAdDiagnostics diagnostics;
  setUp(() {
    events = [];
    // In-memory telemetry only. These tests never send to external services.
    diagnostics = RewardedAdDiagnostics(
      userId: 'guest-account',
      adUnit: 'unit',
      sink: (data, _) => events.add(data),
    )..attemptId = 'attempt';
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(instanceManager.channel, null);
  });

  test(
    'load failure retains SDK details and emits one correlated failure',
    () async {
      final error = LoadAdError(
        3,
        'com.google.android.gms.ads',
        'No fill',
        ResponseInfo(responseId: 'response', responseExtras: {}),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(instanceManager.channel, (call) async {
            if (call.method == 'loadRewardedAd') {
              final ad =
                  instanceManager.adFor(call.arguments['adId']) as RewardedAd;
              ad.rewardedAdLoadCallback.onAdFailedToLoad(error);
              await ad.dispose();
            }
            return null;
          });
      await expectLater(
        diagnostics.step(
          'outer',
          () => RewardedAds().show(
            attemptId: 'attempt',
            userId: diagnostics.userId,
            diagnostics: diagnostics,
          ),
        ),
        throwsA(
          isA<RewardedAdFailure>()
              .having((e) => e.stage, 'stage', 'ad_load')
              .having((e) => e.cause, 'original SDK error', same(error)),
        ),
      );
      final failure = events.singleWhere((e) => e['status'] == 'failed');
      expect(failure, containsPair('error_code', 3));
      expect(
        failure,
        containsPair('error_domain', 'com.google.android.gms.ads'),
      );
      expect(failure, containsPair('error_message', 'No fill'));
      expect(failure, containsPair('response_id', 'response'));
      expect(failure, containsPair('attempt_id', 'attempt'));
      expect(failure, containsPair('user_id', 'guest-account'));
    },
  );

  testWidgets('stuck platform load times out and disposes late ads', (
    tester,
  ) async {
    final platform = Completer<void>();
    RewardedAd? lateAd;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(instanceManager.channel, (call) async {
          calls.add(call.method);
          if (call.method == 'loadRewardedAd') {
            lateAd =
                instanceManager.adFor(call.arguments['adId']) as RewardedAd;
            await platform.future;
          }
          return null;
        });
    final result = RewardedAds().show(
      attemptId: 'attempt',
      userId: diagnostics.userId,
      diagnostics: diagnostics,
    );
    final assertion = expectLater(
      result,
      throwsA(
        isA<RewardedAdFailure>().having(
          (e) => e.cause,
          'timeout',
          isA<TimeoutException>(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 46));
    await assertion;
    lateAd!.rewardedAdLoadCallback.onAdLoaded(lateAd!);
    platform.complete();
    await tester.pump();
    expect(calls, contains('disposeAd'));
    expect(calls, isNot(contains('showAdWithoutView')));
    expect(
      events.where((e) => e['status'] == 'failed').single['timed_out'],
      true,
    );
  });

  test('full-screen failure retains its distinct SDK reason', () async {
    final error = AdError(2, 'com.google.android.gms.ads', 'Not ready');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(instanceManager.channel, (call) async {
          final id = call.arguments is Map ? call.arguments['adId'] : null;
          if (call.method == 'loadRewardedAd') {
            final ad = instanceManager.adFor(id) as RewardedAd;
            ad.rewardedAdLoadCallback.onAdLoaded(ad);
          } else if (call.method == 'showAdWithoutView') {
            final ad = instanceManager.adFor(id) as RewardedAd;
            ad.fullScreenContentCallback!.onAdFailedToShowFullScreenContent!(
              ad,
              error,
            );
          }
          return null;
        });
    await expectLater(
      RewardedAds().show(
        attemptId: 'attempt',
        userId: diagnostics.userId,
        diagnostics: diagnostics,
      ),
      throwsA(
        isA<RewardedAdFailure>().having((e) => e.stage, 'stage', 'ad_show'),
      ),
    );
    expect(
      events.singleWhere((e) => e['status'] == 'failed')['error_message'],
      'Not ready',
    );
  });

  test('broken telemetry never prevents reward operations', () async {
    final broken = RewardedAdDiagnostics(
      userId: 'guest',
      sink: (_, _) => throw StateError('telemetry'),
    );
    expect(await broken.step('activate', () async => true), true);
  });
}
