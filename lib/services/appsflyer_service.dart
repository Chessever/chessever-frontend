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

  static const String _kCachedAffiliateDataKey = 'appsflyer_cached_affiliate_data';

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
      // ATT prompt disabled — influencer OneLink attribution rides on af_sub1
      // via onInstallConversionData and does not need IDFA. Keep the SDK from
      // waiting on a dialog that will never appear.
      timeToWaitForATTUserAuthorization: 0,
      disableAdvertisingIdentifier: true,
      disableCollectASA: false,
      manualStart: true, // required to set CUID before first launch event
    );

    _appsflyerSdk = AppsflyerSdk(options);

    try {
      await _appsflyerSdk?.initSdk(
        registerConversionDataCallback: true,
        registerOnAppOpenAttributionCallback: true,
        registerOnDeepLinkingCallback: true,
      );

      _isInitialized = true;
      debugPrint('AppsflyerService: SDK initialized');

      _appsflyerSdk?.onInstallConversionData((data) {
        debugPrint('AppsflyerService: onInstallConversionData: $data');
        _handleConversionData(data, navigatorKey, ref);
      });

      _appsflyerSdk?.onAppOpenAttribution((data) {
        debugPrint('AppsflyerService: onAppOpenAttribution: $data');
        _handleAppOpenAttribution(data, navigatorKey, ref);
      });

      _appsflyerSdk?.onDeepLinking((DeepLinkResult res) {
        debugPrint('AppsflyerService: onDeepLinking status: ${res.status}');
        if (res.status == Status.FOUND) {
          _handleUnifiedDeepLink(res.deepLink, navigatorKey, ref);
        } else if (res.status == Status.ERROR) {
          debugPrint('AppsflyerService: Deep link error: ${res.error}');
        }
      });

      // ATT prompt intentionally disabled for affiliate-only attribution.
      // Re-enable if we start running paid ad campaigns that need IDFA-level
      // ROAS; otherwise SKAN + af_sub1 covers influencer links.
      // if (Platform.isIOS) {
      //   await _requestAttWhenReady();
      // }

      // Set CUID before startSDK if the user is already authenticated, so the
      // install / first-launch event carries the identifier.
      final session = Supabase.instance.client.auth.currentSession;
      final user = Supabase.instance.client.auth.currentUser;
      if (session != null && user != null && !session.isExpired) {
        debugPrint('AppsflyerService: Setting CUID on init: ${user.id}');
        _appsflyerSdk?.setCustomerUserId(user.id);
        unawaited(_syncAffiliateDataToSupabase(user.id));
      }

      _appsflyerSdk?.startSDK(
        onSuccess: () async {
          debugPrint('AppsflyerService: SDK started');
          await _forwardUidToRevenueCat();
        },
        onError: (int errorCode, String errorMessage) {
          debugPrint('AppsflyerService: startSDK error: $errorCode - $errorMessage');
        },
      );
    } catch (e, stackTrace) {
      debugPrint('AppsflyerService: Initialization failed: $e');
      unawaited(Sentry.captureException(e, stackTrace: stackTrace));
    }
  }

  /// Request ATT after the current frame and a brief scene-active delay.
  /// Currently unused — kept so the prompt can be re-enabled if we ever run
  /// paid ad campaigns that need IDFA-level attribution.
  // ignore: unused_element
  Future<void> _requestAttWhenReady() async {
    try {
      final current = await AppTrackingTransparency.trackingAuthorizationStatus;
      if (current != TrackingStatus.notDetermined) {
        debugPrint('AppsflyerService: ATT already decided: $current');
        return;
      }

      final completer = Completer<void>();
      SchedulerBinding.instance.addPostFrameCallback((_) => completer.complete());
      await completer.future;
      await Future<void>.delayed(const Duration(milliseconds: 400));

      final status = await AppTrackingTransparency.requestTrackingAuthorization();
      debugPrint('AppsflyerService: ATT status: $status');
    } on PlatformException catch (e) {
      debugPrint('AppsflyerService: ATT request failed: $e');
    } catch (e) {
      debugPrint('AppsflyerService: ATT unexpected error: $e');
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

  /// Set the Customer User ID (CUID). Call on sign-in so the user's events
  /// tie back to the install attribution.
  void setCustomerUserId(String userId) {
    if (!_isInitialized || _appsflyerSdk == null) return;
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

  // =========================================================================
  // Affiliate attribution caching
  // =========================================================================

  /// Sync cached affiliate data to Supabase on signup.
  Future<void> _syncAffiliateDataToSupabase(String userId) async {
    try {
      final prefs = SharedPreferencesService.instance.prefsOrNull;
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
        final prefs = SharedPreferencesService.instance.prefsOrNull;
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

    final bool isFirstLaunch = data['is_first_launch'] == true || data['is_first_launch'] == 'true';
    if (isFirstLaunch) {
      debugPrint('AppsflyerService: First launch attribution: $data');
      try {
        final prefs = await SharedPreferencesService.instance.ensureInitialized();
        if (prefs != null) {
          final encodableData = Map<String, dynamic>.from(data);
          await prefs.setString(_kCachedAffiliateDataKey, jsonEncode(encodableData));

          final user = Supabase.instance.client.auth.currentUser;
          if (user != null) {
            unawaited(_syncAffiliateDataToSupabase(user.id));
          }
        }
      } catch (e) {
        debugPrint('AppsflyerService: Failed to cache conversion data: $e');
      }
    }

    if (data.containsKey('link')) {
      final String? link = data['link'] as String?;
      if (link != null && link.isNotEmpty) {
        _routeToDeepLink(link, navigatorKey, ref);
      }
    }
  }

  void _handleAppOpenAttribution(
    Map? data,
    GlobalKey<NavigatorState> navigatorKey,
    WidgetRef ref,
  ) {
    if (data == null) return;
    final String? link = data['link'] as String?;
    if (link != null && link.isNotEmpty) {
      _routeToDeepLink(link, navigatorKey, ref);
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
