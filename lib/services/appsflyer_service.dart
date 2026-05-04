import 'dart:async';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart';
import 'package:chessever2/services/deep_link_service.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:chessever2/repository/local_storage/local_storage_repository.dart';

/// AppsFlyer predefined event names.
///
/// These match AppsFlyer's "Rich In-App Events" taxonomy so the dashboard
/// classifies them correctly and attribution / partner revenue reporting
/// works without extra mapping in the AppsFlyer console.
abstract class AFEvents {
  static const completeRegistration = 'af_complete_registration';
  static const login = 'af_login';
  static const initiatedCheckout = 'af_initiated_checkout';
  static const purchase = 'af_purchase';
  static const subscribe = 'af_subscribe';
  static const startTrial = 'af_start_trial';
  static const contentView = 'af_content_view';
  static const listView = 'af_list_view';
  static const search = 'af_search';
  static const tutorialCompletion = 'af_tutorial_completion';

  // Chessever-specific custom events (prefixed to stay out of AF namespace).
  static const affiliateAttributed = 'chessever_affiliate_attributed';
  static const paywallDismissed = 'chessever_paywall_dismissed';
  // Offer-code / promo-code funnel — separate from `af_purchase` so partners
  // can split organic conversions from code-driven ones in their dashboards.
  static const redemptionInitiated = 'chessever_redemption_initiated';
  static const redemptionCompleted = 'chessever_redemption_completed';
}

abstract class AFParams {
  static const revenue = 'af_revenue';
  static const currency = 'af_currency';
  static const contentId = 'af_content_id';
  static const contentType = 'af_content_type';
  static const content = 'af_content';
  static const registrationMethod = 'af_registration_method';
  static const searchString = 'af_search_string';
  static const price = 'af_price';
  static const quantity = 'af_quantity';
}

/// Service to handle AppsFlyer SDK integration for attribution, deep linking
/// and in-app conversion events.
class AppsflyerService {
  static final AppsflyerService instance = AppsflyerService._();
  AppsflyerService._();

  AppsflyerSdk? _appsflyerSdk;
  bool _isInitialized = false;
  bool _sdkStarted = false;
  Timer? _autoStartTimer;

  // Holds a CUID that arrived from the auth listener before the SDK finished
  // initializing. Flushed when startSDK fires so the install event carries
  // the identifier.
  String? _pendingCustomerUserId;

  static const String _kCachedAffiliateDataKey = 'appsflyer_cached_affiliate_data';
  static const List<String> _oneLinkCustomDomains = ['get.chessever.com'];

  // Fallback before auto-firing startSDK if no explicit trigger arrives.
  // Covers: returning users who skip onboarding, and users who close the app
  // before reaching the ATT pre-prompt.
  static const Duration _autoStartFallback = Duration(seconds: 120);

  static String _resolveDevKey() {
    const releaseKey = String.fromEnvironment('APPSFLYER_DEV_KEY', defaultValue: '');
    if (kDebugMode) {
      final envKey = dotenv.env['APPSFLYER_DEV_KEY']?.trim();
      if (envKey != null && envKey.isNotEmpty) return envKey;
    }
    if (releaseKey.isNotEmpty) return releaseKey;

    debugPrint('⚠️ APPSFLYER_DEV_KEY is missing. Add it to .env and --dart-define for CI.');
    return '';
  }

  /// Initialize the AppsFlyer SDK.
  ///
  /// Call from a post-frame callback so the ATT dialog can reliably appear.
  Future<void> initialize(GlobalKey<NavigatorState> navigatorKey, WidgetRef ref) async {
    if (_isInitialized) return;

    final String devKey = _resolveDevKey();
    if (devKey.isEmpty) {
      debugPrint('AppsflyerService: Skipping init — APPSFLYER_DEV_KEY missing.');
      return;
    }

    final appId = Platform.isIOS ? '6752567269' : '';

    final options = AppsFlyerOptions(
      afDevKey: devKey,
      appId: appId,
      showDebug: kDebugMode,
      // ATT prompt is not shown, so wait time is zero. We deliberately do NOT
      // set disableAdvertisingIdentifier — that flag also suppresses GAID
      // collection on Android, which would break deterministic attribution
      // there. iOS returns a zero IDFA without ATT consent regardless.
      timeToWaitForATTUserAuthorization: 0,
      disableCollectASA: false,
      manualStart: true, // required to set CUID before first launch event
    );

    _appsflyerSdk = AppsflyerSdk(options);
    _appsflyerSdk?.setOneLinkCustomDomain(_oneLinkCustomDomains);

    try {
      await _appsflyerSdk?.initSdk(
        // GCD — fires onInstallConversionData with af_sub1 etc.
        registerConversionDataCallback: true,
        // Legacy direct-deeplink callback. Per official docs, registering
        // the UDL callback below overrides this, so leave it off.
        registerOnAppOpenAttributionCallback: false,
        // UDL — modern unified deep-link callback, fires onDeepLinking.
        registerOnDeepLinkingCallback: true,
      );

      _isInitialized = true;
      debugPrint('AppsflyerService: SDK initialized');

      _appsflyerSdk?.onInstallConversionData((data) {
        debugPrint('AppsflyerService: onInstallConversionData: $data');
        _handleConversionData(data, navigatorKey, ref);
      });

      _appsflyerSdk?.onDeepLinking((DeepLinkResult res) {
        debugPrint('AppsflyerService: onDeepLinking status: ${res.status}');
        if (res.status == Status.FOUND) {
          _handleUnifiedDeepLink(res.deepLink, navigatorKey, ref);
        } else if (res.status == Status.ERROR) {
          debugPrint('AppsflyerService: Deep link error: ${res.error}');
        }
      });

      // Android-only: flush any pending deep-link resolution through the
      // onDeepLinking callback. Required when manualStart is true and we
      // delay startSDK to set CUID first — otherwise the deep-link payload
      // (and the af_sub1 it carries) can be stranded on the native side.
      if (Platform.isAndroid) {
        _appsflyerSdk?.performOnDeepLinking();
      }

      // startSDK timing strategy:
      //  - Returning users (session already restored): fire now so session
      //    events flow promptly. ATT was decided in a previous launch.
      //  - New users: defer until the onboarding ATT pre-prompt completes,
      //    so the install event carries the correct ATT/IDFA state.
      //  - Auth listener in main.dart calls startSdkIfNotYetStarted on every
      //    auth-state change, covering users who skip the ATT pre-prompt by
      //    signing in directly from the welcome page.
      //  - Fallback timer covers everyone else (guests, app closed early).
      final existingUser = Supabase.instance.client.auth.currentUser;
      if (existingUser != null) {
        debugPrint(
          'AppsflyerService: Session restored at init — starting SDK now',
        );
        startSdkIfNotYetStarted();
      } else {
        _autoStartTimer = Timer(_autoStartFallback, () {
          debugPrint(
            'AppsflyerService: ATT pre-prompt timeout — auto-starting SDK',
          );
          startSdkIfNotYetStarted();
        });
      }
    } catch (e, stackTrace) {
      debugPrint('AppsflyerService: Initialization failed: $e');
      unawaited(Sentry.captureException(e, stackTrace: stackTrace));
    }
  }

  /// Fire the install/launch event. Idempotent — safe to call from multiple
  /// trigger points (post-ATT-decision, fallback timer, manual). The install
  /// event carries the ATT/IDFA state at the moment this runs, so call it
  /// AFTER the ATT decision has been made.
  void startSdkIfNotYetStarted() {
    if (_sdkStarted) return;
    if (!_isInitialized || _appsflyerSdk == null) return;
    _sdkStarted = true;
    _autoStartTimer?.cancel();
    _autoStartTimer = null;

    // Resolve CUID at start-time (covers the case where auth completed
    // between initialize() and now). Buffered ID wins; otherwise read the
    // current Supabase session.
    String? cuid = _pendingCustomerUserId;
    if (cuid == null) {
      final session = Supabase.instance.client.auth.currentSession;
      final user = Supabase.instance.client.auth.currentUser;
      if (session != null && user != null && !session.isExpired) {
        cuid = user.id;
      }
    }
    if (cuid != null) {
      debugPrint('AppsflyerService: Setting CUID before startSDK: $cuid');
      _appsflyerSdk?.setCustomerUserId(cuid);
      unawaited(_syncAffiliateDataToSupabase(cuid));
    }
    _pendingCustomerUserId = null;

    _appsflyerSdk?.startSDK(
      onSuccess: () async {
        debugPrint('AppsflyerService: SDK started');
        await _forwardUidToRevenueCat();
      },
      onError: (int errorCode, String errorMessage) {
        debugPrint('AppsflyerService: startSDK error: $errorCode - $errorMessage');
      },
    );
  }

  /// Trigger Apple's ATT prompt. No-op on Android, no-op if the user has
  /// already decided. Returns the resulting status (or notDetermined if we
  /// couldn't ask). Call AFTER showing your own pre-prompt explainer.
  Future<TrackingStatus> requestAtt() async {
    if (!Platform.isIOS) return TrackingStatus.notSupported;
    try {
      final current = await AppTrackingTransparency.trackingAuthorizationStatus;
      if (current != TrackingStatus.notDetermined) {
        debugPrint('AppsflyerService: ATT already decided: $current');
        return current;
      }

      // Apple ignores the request if it fires inside a build/layout pass.
      // Wait for the next frame plus a brief scene-active settle delay.
      final completer = Completer<void>();
      SchedulerBinding.instance.addPostFrameCallback((_) => completer.complete());
      await completer.future;
      await Future<void>.delayed(const Duration(milliseconds: 400));

      final status = await AppTrackingTransparency.requestTrackingAuthorization();
      debugPrint('AppsflyerService: ATT status: $status');
      return status;
    } on PlatformException catch (e) {
      debugPrint('AppsflyerService: ATT request failed: $e');
      return TrackingStatus.notDetermined;
    } catch (e) {
      debugPrint('AppsflyerService: ATT unexpected error: $e');
      return TrackingStatus.notDetermined;
    }
  }

  /// Fetch the AppsFlyer UID and forward it to RevenueCat so subscription
  /// events get attributed back to the install.
  Future<void> _forwardUidToRevenueCat() async {
    try {
      final uid = await _appsflyerSdk?.getAppsFlyerUID();
      if (uid == null || uid.isEmpty) return;
      await Purchases.setAppsflyerID(uid);
      debugPrint('AppsflyerService: AppsFlyer UID ($uid) sent to RevenueCat');
    } catch (e) {
      debugPrint('AppsflyerService: Failed to forward UID to RevenueCat: $e');
    }
  }

  /// Forward AppsFlyer install attribution to RevenueCat's campaign-attribution
  /// subscriber attributes. The RC <> AppsFlyer integration uses these to tag
  /// the customer in RC and to enrich postbacks back to AppsFlyer. Empty/null
  /// payload values are skipped so we don't overwrite real data with blanks.
  Future<void> _forwardAttributionToRevenueCat(Map payload) async {
    Future<void> setIfPresent(
      String key,
      Future<void> Function(String) setter,
    ) async {
      final value = payload[key];
      if (value == null) return;
      final str = value.toString().trim();
      if (str.isEmpty || str == 'null') return;
      try {
        await setter(str);
      } catch (e) {
        debugPrint('AppsflyerService: RC $key forward failed: $e');
      }
    }

    await setIfPresent('media_source', Purchases.setMediaSource);
    await setIfPresent('campaign', Purchases.setCampaign);
    await setIfPresent('adset', Purchases.setAdGroup);
    await setIfPresent('af_ad', Purchases.setAd);
    await setIfPresent('af_keywords', Purchases.setKeyword);
    await setIfPresent('af_adset', Purchases.setCreative);
  }

  /// Set the Customer User ID (CUID). Call on sign-in so the user's events
  /// tie back to the install attribution.
  void setCustomerUserId(String userId) {
    // Buffer the ID if the SDK isn't up yet — initialize() will flush it
    // before startSDK so the install event still carries the CUID. Without
    // this, an auth listener firing during the init window silently drops
    // the assignment.
    if (!_isInitialized || _appsflyerSdk == null) {
      _pendingCustomerUserId = userId;
      debugPrint('AppsflyerService: CUID buffered until SDK init: $userId');
      return;
    }
    try {
      _appsflyerSdk?.setCustomerUserId(userId);
      debugPrint('AppsflyerService: CUID set: $userId');
      unawaited(_syncAffiliateDataToSupabase(userId));
    } catch (e) {
      debugPrint('AppsflyerService: setCustomerUserId failed: $e');
    }
  }

  /// Fire a generic AppsFlyer event. Prefer the typed helpers below.
  Future<bool?> logEvent(String eventName, [Map<String, dynamic>? eventValues]) async {
    if (!_isInitialized || _appsflyerSdk == null) return false;
    try {
      return await _appsflyerSdk?.logEvent(eventName, eventValues ?? const {});
    } catch (e) {
      debugPrint('AppsflyerService: logEvent($eventName) failed: $e');
      return false;
    }
  }

  // =========================================================================
  // Typed conversion events (AppsFlyer predefined taxonomy)
  // =========================================================================

  /// Fire on the very first successful signup (not repeated logins).
  Future<void> logSignUp({required String method, String? userId}) async {
    await logEvent(AFEvents.completeRegistration, {
      AFParams.registrationMethod: method,
      if (userId != null) 'user_id': userId,
    });
  }

  /// Fire on repeat logins (optional — skip for most apps).
  Future<void> logLogin({required String method}) async {
    await logEvent(AFEvents.login, {AFParams.registrationMethod: method});
  }

  /// Fire when the paywall opens or a purchase flow begins.
  Future<void> logInitiatedCheckout({
    String? productId,
    double? price,
    String? currency,
  }) async {
    await logEvent(AFEvents.initiatedCheckout, {
      if (productId != null) AFParams.contentId: productId,
      if (price != null) AFParams.price: price,
      if (currency != null) AFParams.currency: currency,
    });
  }

  /// Fire on successful subscription. Sends both `af_purchase` (generic
  /// revenue event) and `af_subscribe` (subscription-specific) so AppsFlyer
  /// dashboards and affiliate partners see the revenue under whichever
  /// event they configured.
  Future<void> logSubscriptionPurchase({
    required String productId,
    required double price,
    required String currency,
    String? packageType,
    bool isTrial = false,
  }) async {
    final base = <String, dynamic>{
      AFParams.revenue: price,
      AFParams.currency: currency,
      AFParams.contentId: productId,
      AFParams.contentType: packageType ?? 'subscription',
      AFParams.quantity: 1,
    };

    if (isTrial) {
      await logEvent(AFEvents.startTrial, base);
    } else {
      await logEvent(AFEvents.purchase, base);
      await logEvent(AFEvents.subscribe, base);
    }
  }

  /// Fire when the user views a key content screen (premium landing,
  /// player profile, etc.).
  Future<void> logContentView({
    required String contentId,
    String? contentType,
  }) async {
    await logEvent(AFEvents.contentView, {
      AFParams.contentId: contentId,
      if (contentType != null) AFParams.contentType: contentType,
    });
  }

  /// Fire on search queries that qualify as intent signals.
  Future<void> logSearch(String query) async {
    await logEvent(AFEvents.search, {AFParams.searchString: query});
  }

  /// Fire when the user opens the code-redemption flow (taps "Have a code?").
  /// On Android `code` is the value the user typed; on iOS it's null because
  /// Apple's native sheet hides the input from us.
  Future<void> logRedemptionInitiated({
    required String source,
    String? code,
  }) async {
    final affiliate = await getCachedAffiliateContext();
    await logEvent(AFEvents.redemptionInitiated, {
      'redemption_source': source,
      if (code != null && code.isNotEmpty) 'redemption_code': code,
      if (affiliate != null) ...affiliate,
    });
  }

  /// Fire when an entitlement becomes active and we have a pending redemption
  /// — i.e., the user just successfully redeemed a code. Sent in addition to
  /// (not instead of) the existing `af_subscribe`/`af_purchase` events when
  /// applicable, so partners that already key off those still get them.
  Future<void> logRedemptionCompleted({
    required String source,
    String? code,
    String? productId,
  }) async {
    final affiliate = await getCachedAffiliateContext();
    await logEvent(AFEvents.redemptionCompleted, {
      'redemption_source': source,
      if (code != null && code.isNotEmpty) 'redemption_code': code,
      if (productId != null) AFParams.contentId: productId,
      if (affiliate != null) ...affiliate,
    });
  }

  /// Read the affiliate attribution context cached on first install. Used to
  /// stamp every funnel event with the same affiliate_code/campaign/network
  /// so partners' dashboards show the full chain (install → redeem → revenue).
  /// Returns null if there is no affiliate context (organic install).
  Future<Map<String, String>?> getCachedAffiliateContext() async {
    try {
      final prefs = await SharedPreferencesService.instance.ensureInitialized();
      if (prefs == null) return null;

      final cachedDataString = prefs.getString(_kCachedAffiliateDataKey);
      if (cachedDataString == null || cachedDataString.isEmpty) return null;

      final Map<String, dynamic> cached = jsonDecode(cachedDataString);
      final affiliateCode =
          cached['af_sub1']?.toString() ?? cached['deep_link_sub1']?.toString();
      if (affiliateCode == null || affiliateCode.isEmpty) return null;

      return {
        'affiliate_code': affiliateCode,
        if (cached['campaign'] != null) 'campaign': cached['campaign'].toString(),
        if (cached['media_source'] != null)
          'media_source': cached['media_source'].toString(),
      };
    } catch (e) {
      debugPrint('AppsflyerService: getCachedAffiliateContext failed: $e');
      return null;
    }
  }

  // =========================================================================
  // Affiliate attribution caching
  // =========================================================================

  /// Sync cached affiliate data to Supabase on signup.
  Future<void> _syncAffiliateDataToSupabase(String userId) async {
    try {
      final prefs = await SharedPreferencesService.instance.ensureInitialized();
      if (prefs == null) return;

      final cachedDataString = prefs.getString(_kCachedAffiliateDataKey);
      if (cachedDataString == null || cachedDataString.isEmpty) return;

      final Map<String, dynamic> cachedData = jsonDecode(cachedDataString);

      // af_sub1 is the recommended slot for the affiliate code in OneLink.
      // Fall back to deep_link_sub1 for older OneLink templates.
      final String? affiliateCode =
          cachedData['af_sub1']?.toString() ?? cachedData['deep_link_sub1']?.toString();
      final String? campaignName = cachedData['campaign']?.toString();
      final String? network = cachedData['media_source']?.toString();

      if (affiliateCode == null || affiliateCode.isEmpty) {
        await prefs.remove(_kCachedAffiliateDataKey);
        return;
      }

      final platform = Platform.isIOS
          ? 'ios'
          : Platform.isAndroid
              ? 'android'
              : 'unknown';

      await Supabase.instance.client.from('affiliate_referrals').insert({
        'referred_user_id': userId,
        'affiliate_code': affiliateCode,
        'campaign_name': campaignName,
        'network': network,
        'appsflyer_data': cachedData,
        'platform': platform,
        // Partner / admin dashboards filter `is_sandbox = false`. NULL would
        // be filtered out and the row would be invisible. Debug builds are
        // tagged sandbox so my-own-testing rows don't pollute the production
        // payout view; the admin dashboard's sandbox toggle still surfaces them.
        'is_sandbox': kDebugMode,
      });
      debugPrint('AppsflyerService: Affiliate synced for $userId / $affiliateCode');

      // Fire a custom AppsFlyer event so the partner's dashboard reflects the
      // attributed signup in addition to the install.
      unawaited(logEvent(AFEvents.affiliateAttributed, {
        'affiliate_code': affiliateCode,
        if (campaignName != null) 'campaign': campaignName,
        if (network != null) 'media_source': network,
      }));

      await prefs.remove(_kCachedAffiliateDataKey);
    } catch (e) {
      if (e is PostgrestException && e.code == '23505') {
        // UNIQUE(referred_user_id) — already attributed; safe to drop cache.
        debugPrint('AppsflyerService: Referral already exists for user.');
        final prefs = await SharedPreferencesService.instance.ensureInitialized();
        await prefs?.remove(_kCachedAffiliateDataKey);
      } else {
        debugPrint('AppsflyerService: Failed to sync affiliate data: $e');
      }
    }
  }

  void _handleConversionData(
    Map? data,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref,
  ) async {
    if (data == null) return;

    // The Flutter plugin wraps the AppsFlyer GCD response as
    // `{status: 'success', payload: {...attribution fields...}}`. Unwrap it
    // before reading af_sub1 / is_first_launch — those live on the payload,
    // not on the outer envelope.
    final Map payload = data['payload'] is Map ? data['payload'] as Map : data;

    final bool isFirstLaunch = payload['is_first_launch'] == true ||
        payload['is_first_launch'] == 'true';
    if (isFirstLaunch) {
      debugPrint('AppsflyerService: First launch attribution: $payload');
      try {
        final prefs = await SharedPreferencesService.instance.ensureInitialized();
        if (prefs != null) {
          final encodableData = Map<String, dynamic>.from(payload);
          await prefs.setString(_kCachedAffiliateDataKey, jsonEncode(encodableData));

          final user = Supabase.instance.client.auth.currentUser;
          if (user != null) {
            unawaited(_syncAffiliateDataToSupabase(user.id));
          }
        }
      } catch (e) {
        debugPrint('AppsflyerService: Failed to cache conversion data: $e');
      }

      // Forward attribution context to RevenueCat so the customer profile
      // there carries media_source / campaign / etc. RC then surfaces this
      // in its dashboard and forwards through the AppsFlyer integration.
      unawaited(_forwardAttributionToRevenueCat(payload));
    }

    if (payload.containsKey('link')) {
      final String? link = payload['link'] as String?;
      if (link != null && link.isNotEmpty) {
        _routeToDeepLink(link, navigatorKey, ref);
      }
    }
  }

  void _handleUnifiedDeepLink(
    DeepLink? deepLink,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref,
  ) {
    if (deepLink == null) return;
    final String? deepLinkValue = deepLink.deepLinkValue;
    debugPrint('AppsflyerService: Unified deep link value: $deepLinkValue');
    if (deepLinkValue == null || deepLinkValue.isEmpty) return;

    if (deepLinkValue.startsWith('http')) {
      _routeToDeepLink(deepLinkValue, navigatorKey, ref);
    } else {
      final uri = Uri.tryParse('https://chessever.com/$deepLinkValue');
      if (uri != null) {
        DeepLinkService.instance.handleDeepLink(uri, navigatorKey, ref);
      }
    }
  }

  void _routeToDeepLink(
    String link,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref,
  ) {
    final uri = Uri.tryParse(link);
    if (uri != null) {
      DeepLinkService.instance.handleDeepLink(uri, navigatorKey, ref);
    }
  }
}
