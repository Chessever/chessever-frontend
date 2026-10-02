import 'dart:async';
import 'dart:io';

import 'package:chessever2/config/app_environment.dart';
import 'package:chessever2/services/att_prompt_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

abstract final class RewardedAdsConfig {
  // Store builds enable the validated production flow without an extra CI flag.
  // Debug/profile validation remains opt-in; the test flavor is excluded below.
  static const enabled = bool.fromEnvironment(
    'REWARDED_PREMIUM_ENABLED',
    defaultValue: kReleaseMode,
  );
  static bool get available =>
      !AppEnvironment.isTest &&
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS) &&
      enabled &&
      (kDebugMode ||
          (RegExp(r'^ca-app-pub-\d+/\d+$').hasMatch(liveUnitId) &&
              RegExp(r'^ca-app-pub-\d+~\d+$').hasMatch(liveAppId)));
  static String get liveAppId => Platform.isAndroid
      ? const String.fromEnvironment(
          'ADMOB_ANDROID_APP_ID',
          defaultValue: 'ca-app-pub-3681310687796023~4858872090',
        )
      : const String.fromEnvironment(
          'ADMOB_IOS_APP_ID',
          defaultValue: 'ca-app-pub-3681310687796023~5640461560',
        );
  static String get liveUnitId => Platform.isAndroid
      ? const String.fromEnvironment(
          'ADMOB_ANDROID_REWARDED_ID',
          defaultValue: 'ca-app-pub-3681310687796023/8590975808',
        )
      : const String.fromEnvironment(
          'ADMOB_IOS_REWARDED_ID',
          defaultValue: 'ca-app-pub-3681310687796023/8331032066',
        );
  static String get unitId => kDebugMode
      ? (Platform.isAndroid
            ? 'ca-app-pub-3940256099942544/5224354917'
            : 'ca-app-pub-3940256099942544/1712485313')
      : liveUnitId;
}

class RewardedAds {
  Future<void>? _consent;
  bool privacyOptionsRequired = false;

  Future<void> prepare(BuildContext context) async {
    if (!RewardedAdsConfig.available) {
      throw StateError('Rewarded ads unavailable');
    }
    await prepareConsent(context);
  }

  /// Shared ATT, UMP and SDK setup for rewarded and native placements.
  Future<void> prepareConsent(BuildContext context) async {
    await AttPromptService.instance.ensurePrompted(context);
    if (!context.mounted) return;
    await (_consent ??= _requestConsent());
    if (!await ConsentInformation.instance.canRequestAds()) {
      throw StateError('Ads are unavailable with the current privacy settings');
    }
    final testDevices = const String.fromEnvironment(
      'ADMOB_TEST_DEVICE_IDS',
    ).split(',').map((id) => id.trim()).where((id) => id.isNotEmpty).toList();
    if (testDevices.isNotEmpty) {
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(testDeviceIds: testDevices),
      );
    }
    await MobileAds.instance.initialize();
  }

  Future<void> _requestConsent() async {
    final result = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () async {
        try {
          await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
          privacyOptionsRequired =
              await ConsentInformation.instance
                  .getPrivacyOptionsRequirementStatus() ==
              PrivacyOptionsRequirementStatus.required;
          result.complete();
        } catch (e, stack) {
          result.completeError(e, stack);
        }
      },
      (_) {
        _consent = null;
        result.complete();
      },
    );
    try {
      await result.future;
    } catch (_) {
      _consent = null;
      rethrow;
    }
  }

  Future<void> showPrivacyOptions() async {
    final done = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((error) {
      if (error == null) {
        done.complete();
      } else {
        done.completeError(StateError(error.message));
      }
    });
    await done.future;
  }

  Future<bool> show({required String attemptId, required String userId}) async {
    final loaded = Completer<RewardedAd>();
    var abandoned = false;
    await RewardedAd.load(
      adUnitId: RewardedAdsConfig.unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (abandoned) {
            ad.dispose();
          } else {
            loaded.complete(ad);
          }
        },
        onAdFailedToLoad: (error) => loaded.completeError(
          StateError('No ad available. Please try again later.'),
        ),
      ),
    );
    final ad = await loaded.future.timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        abandoned = true;
        throw TimeoutException('Ad load timed out');
      },
    );
    try {
      await ad.setServerSideOptions(
        ServerSideVerificationOptions(userId: userId, customData: attemptId),
      );
    } catch (_) {
      await ad.dispose();
      rethrow;
    }
    final dismissed = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!dismissed.isCompleted) {
          dismissed.complete(earned);
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!dismissed.isCompleted) {
          dismissed.completeError(
            StateError('The ad could not be shown. Please try again.'),
          );
        }
      },
    );
    await ad.show(
      onUserEarnedReward: (_, _) {
        earned = true;
      },
    );
    return dismissed.future;
  }
}
