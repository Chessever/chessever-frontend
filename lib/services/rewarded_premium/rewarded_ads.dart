import 'dart:async';
import 'dart:io';

import 'package:chessever2/config/app_environment.dart';
import 'package:chessever2/services/att_prompt_service.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_ad_diagnostics.dart';
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
  // Production uses dedicated rewarded-interstitial units. Never
  // use a rewarded/native unit, or Google's test units, in a store build.
  static String get liveInterstitialUnitId => Platform.isAndroid
      ? const String.fromEnvironment(
          'ADMOB_ANDROID_REWARDED_INTERSTITIAL_ID',
          defaultValue: 'ca-app-pub-3681310687796023/2102597268',
        )
      : const String.fromEnvironment(
          'ADMOB_IOS_REWARDED_INTERSTITIAL_ID',
          defaultValue: 'ca-app-pub-3681310687796023/1181317704',
        );
  static bool get interstitialConfigured =>
      kDebugMode ||
      (RegExp(r'^ca-app-pub-\d+/\d+$').hasMatch(liveInterstitialUnitId) &&
          liveInterstitialUnitId != liveUnitId);
  static String get interstitialUnitId => kDebugMode
      ? (Platform.isAndroid
            ? 'ca-app-pub-3940256099942544/5354046379'
            : 'ca-app-pub-3940256099942544/6978759866')
      : liveInterstitialUnitId;

  static String get unitId => kDebugMode
      ? (Platform.isAndroid
            ? 'ca-app-pub-3940256099942544/5224354917'
            : 'ca-app-pub-3940256099942544/1712485313')
      : liveUnitId;
}

class RewardedAds {
  Future<void>? _consent;
  bool privacyOptionsRequired = false;
  static const _setupTimeout = Duration(seconds: 30);

  Future<T> _step<T>(
    String stage,
    Future<T> Function() operation,
    RewardedAdDiagnostics? diagnostics, {
    Duration? timeout,
  }) {
    if (diagnostics != null) {
      return diagnostics.step(stage, operation, timeout: timeout);
    }
    final future = Future<T>.sync(operation);
    return timeout == null ? future : future.timeout(timeout);
  }

  Future<void> prepare(
    BuildContext context, {
    RewardedAdDiagnostics? diagnostics,
  }) async {
    if (!RewardedAdsConfig.available) {
      throw StateError('Rewarded ads unavailable');
    }
    await prepareConsent(context, diagnostics: diagnostics);
  }

  /// Human consent prompts intentionally have no deadline. Automatic network
  /// and platform setup steps are bounded and can be retried after failure.
  Future<void> prepareConsent(
    BuildContext context, {
    RewardedAdDiagnostics? diagnostics,
  }) async {
    await _step(
      'tracking_consent',
      () => AttPromptService.instance.ensurePrompted(context),
      diagnostics,
    );
    if (!context.mounted) throw StateError('Feature was closed');
    final consent = _consent ??= _requestConsent(diagnostics);
    try {
      await consent;
    } catch (_) {
      if (identical(_consent, consent)) _consent = null;
      rethrow;
    }
    await _step(
      'consent_check',
      () async {
        if (!await ConsentInformation.instance.canRequestAds()) {
          throw StateError(
            'Ads are unavailable with the current privacy settings',
          );
        }
      },
      diagnostics,
      timeout: _setupTimeout,
    );
    final testDevices = const String.fromEnvironment(
      'ADMOB_TEST_DEVICE_IDS',
    ).split(',').map((id) => id.trim()).where((id) => id.isNotEmpty).toList();
    if (testDevices.isNotEmpty) {
      await _step(
        'request_configuration',
        () => MobileAds.instance.updateRequestConfiguration(
          RequestConfiguration(testDeviceIds: testDevices),
        ),
        diagnostics,
        timeout: _setupTimeout,
      );
    }
    await _step(
      'sdk_initialize',
      () => MobileAds.instance.initialize(),
      diagnostics,
      timeout: _setupTimeout,
    );
  }

  Future<void> _requestConsent(RewardedAdDiagnostics? diagnostics) async {
    final updated = Completer<void>();
    var waiting = true;
    try {
      await _step(
        'consent_update',
        () {
          ConsentInformation.instance.requestConsentInfoUpdate(
            ConsentRequestParameters(),
            () {
              if (waiting && !updated.isCompleted) updated.complete();
            },
            (error) {
              if (waiting && !updated.isCompleted) updated.completeError(error);
            },
          );
          return updated.future;
        },
        diagnostics,
        timeout: _setupTimeout,
      );
    } catch (_) {
      // UMP permits using cached consent when refreshing consent fails. Keep
      // the original error in diagnostics, but don't reject eligible users.
      if (!await _step(
        'cached_consent_check',
        () => ConsentInformation.instance.canRequestAds(),
        diagnostics,
        timeout: _setupTimeout,
      )) {
        rethrow;
      }
      _consent = null;
      return;
    } finally {
      waiting = false; // Ignore callbacks from a timed-out refresh.
    }
    try {
      await _step('consent_form', () async {
        FormError? formError;
        await ConsentForm.loadAndShowConsentFormIfRequired((error) {
          formError = error;
        });
        if (formError != null) throw formError!;
      }, diagnostics);
    } catch (_) {
      if (!await _step(
        'cached_consent_check',
        () => ConsentInformation.instance.canRequestAds(),
        diagnostics,
        timeout: _setupTimeout,
      )) {
        rethrow;
      }
      _consent = null;
    }
    privacyOptionsRequired =
        await _step(
          'privacy_options_status',
          () =>
              ConsentInformation.instance.getPrivacyOptionsRequirementStatus(),
          diagnostics,
          timeout: _setupTimeout,
        ) ==
        PrivacyOptionsRequirementStatus.required;
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

  /// Only load-stage failures may select another format. Known connectivity
  /// failures won't improve with a different ad unit; neither will consent,
  /// setup, showing, early dismissal, or pending reward confirmation failures.
  static bool canUseInterstitialFallback(Object error) {
    if (error is! RewardedAdFailure || error.stage != 'ad_load') return false;
    final cause = error.cause;
    if (cause is LoadAdError &&
        cause.code == 2 &&
        (cause.domain == 'com.google.android.gms.ads' ||
            cause.domain == 'com.google.admob')) {
      return false;
    }
    return cause is LoadAdError || cause is TimeoutException;
  }

  Future<bool> show({
    required String attemptId,
    required String userId,
    RewardedAdDiagnostics? diagnostics,
  }) async {
    final ad = await _load<RewardedAd>(
      'ad_load',
      (onLoaded, onFailed) => RewardedAd.load(
        adUnitId: RewardedAdsConfig.unitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: onLoaded,
          onAdFailedToLoad: onFailed,
        ),
      ),
      diagnostics,
    );
    return _present<RewardedAd>(
      ad,
      attemptId: attemptId,
      userId: userId,
      stage: 'ad_show',
      optionsStage: 'server_verification_options',
      setOptions: ad.setServerSideOptions,
      setCallbacks: (callbacks) => ad.fullScreenContentCallback = callbacks,
      display: (callback) => ad.show(onUserEarnedReward: callback),
      diagnostics: diagnostics,
    );
  }

  /// The caller must present reward messaging and a skip option first.
  Future<bool> showInterstitial({
    required String attemptId,
    required String userId,
    RewardedAdDiagnostics? diagnostics,
  }) async {
    if (!RewardedAdsConfig.interstitialConfigured) {
      throw StateError('Rewarded interstitial is not configured');
    }
    final ad = await _load<RewardedInterstitialAd>(
      'interstitial_load',
      (onLoaded, onFailed) => RewardedInterstitialAd.load(
        adUnitId: RewardedAdsConfig.interstitialUnitId,
        request: const AdRequest(),
        rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
          onAdLoaded: onLoaded,
          onAdFailedToLoad: onFailed,
        ),
      ),
      diagnostics,
    );
    return _present<RewardedInterstitialAd>(
      ad,
      attemptId: attemptId,
      userId: userId,
      stage: 'interstitial_show',
      optionsStage: 'interstitial_verification_options',
      setOptions: ad.setServerSideOptions,
      setCallbacks: (callbacks) => ad.fullScreenContentCallback = callbacks,
      display: (callback) => ad.show(onUserEarnedReward: callback),
      diagnostics: diagnostics,
    );
  }

  Future<T> _load<T extends Ad>(
    String stage,
    Future<void> Function(void Function(T), void Function(LoadAdError)) start,
    RewardedAdDiagnostics? diagnostics,
  ) => _step(stage, () async {
    final loaded = Completer<T>();
    var abandoned = false;
    final invocation = start(
      (ad) {
        if (abandoned || loaded.isCompleted) {
          ad.dispose();
        } else {
          loaded.complete(ad);
        }
      },
      (error) {
        if (!abandoned && !loaded.isCompleted) loaded.completeError(error);
      },
    );
    // Register both error listeners immediately. Callback completion does not
    // depend on the platform invocation completing, so its stall is bounded.
    unawaited(
      invocation.catchError((Object error, StackTrace stack) {
        if (!abandoned && !loaded.isCompleted) {
          loaded.completeError(error, stack);
        }
      }),
    );
    try {
      return await loaded.future.timeout(const Duration(seconds: 45));
    } finally {
      abandoned = true;
    }
  }, diagnostics);

  Future<bool> _present<T extends AdWithoutView>(
    T ad, {
    required String attemptId,
    required String userId,
    required String stage,
    required String optionsStage,
    required Future<void> Function(ServerSideVerificationOptions) setOptions,
    required void Function(FullScreenContentCallback<T>) setCallbacks,
    required Future<void> Function(OnUserEarnedRewardCallback) display,
    RewardedAdDiagnostics? diagnostics,
  }) async {
    try {
      await _step(
        optionsStage,
        () => setOptions(
          ServerSideVerificationOptions(userId: userId, customData: attemptId),
        ),
        diagnostics,
        timeout: _setupTimeout,
      );
    } catch (_) {
      await ad.dispose();
      rethrow;
    }
    final dismissed = Completer<bool>();
    var earned = false;
    setCallbacks(
      FullScreenContentCallback<T>(
        onAdShowedFullScreenContent: (_) =>
            diagnostics?.event(stage, 'visible'),
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          if (!dismissed.isCompleted) dismissed.complete(earned);
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          if (!dismissed.isCompleted) dismissed.completeError(error);
        },
      ),
    );
    return _step(stage, () {
      // No deadline on the user's time watching an ad.
      unawaited(
        display((_, _) {
          earned = true;
          diagnostics?.event('reward', 'earned');
        }).catchError((Object error, StackTrace stack) {
          ad.dispose();
          if (!dismissed.isCompleted) dismissed.completeError(error, stack);
        }),
      );
      return dismissed.future;
    }, diagnostics);
  }
}
