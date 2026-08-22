import 'dart:async';

import 'package:chessever2/services/push_notifications_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of a purchase attempt
class PurchaseAttemptResult {
  final bool success;
  final bool wasCancelled;
  final String? errorMessage;

  const PurchaseAttemptResult({
    required this.success,
    this.wasCancelled = false,
    this.errorMessage,
  });

  factory PurchaseAttemptResult.success() =>
      const PurchaseAttemptResult(success: true);

  factory PurchaseAttemptResult.cancelled() =>
      const PurchaseAttemptResult(success: false, wasCancelled: true);

  factory PurchaseAttemptResult.error(String message) =>
      PurchaseAttemptResult(success: false, errorMessage: message);
}

/// Outcome of an offerings fetch. The paywall must distinguish these: only
/// [OfferingsFetchStatus.empty] means "there is genuinely nothing to sell".
enum OfferingsFetchStatus {
  /// Packages were returned.
  success,

  /// `Purchases.configure` has not completed yet. Transient — retry when
  /// [RevenueCatService.onSdkStateChanged] fires.
  notConfigured,

  /// The store was reachable but returned no current offering / no packages.
  empty,

  /// Every attempt threw (offline, store outage, SDK error).
  failure,
}

@immutable
class OfferingsFetch {
  const OfferingsFetch._(this.status, this.packages, this.errorMessage);

  const OfferingsFetch.success(List<Package> packages)
    : this._(OfferingsFetchStatus.success, packages, null);

  const OfferingsFetch.notConfigured()
    : this._(OfferingsFetchStatus.notConfigured, const [], null);

  const OfferingsFetch.empty()
    : this._(OfferingsFetchStatus.empty, const [], null);

  const OfferingsFetch.failure(String? errorMessage)
    : this._(OfferingsFetchStatus.failure, const [], errorMessage);

  final OfferingsFetchStatus status;
  final List<Package> packages;
  final String? errorMessage;

  bool get isSuccess => status == OfferingsFetchStatus.success;

  /// True when retrying later could plausibly succeed.
  bool get isRetryable =>
      status == OfferingsFetchStatus.notConfigured ||
      status == OfferingsFetchStatus.failure;
}

class RevenueCatService {
  static final RevenueCatService _instance = RevenueCatService._internal();
  factory RevenueCatService() => _instance;
  RevenueCatService._internal();

  /// The entitlement identifier for ChessEver premium
  /// Must match the lookup_key in RevenueCat dashboard
  static const String premiumEntitlement = 'Chessever Subscription';

  /// True only after [Purchases.configure] succeeded. ChessEver Test can boot
  /// without a RevenueCat key; every SDK call must no-op until this is true.
  bool _sdkReady = false;
  bool get isSdkReady => _sdkReady;
  Object? _sdkConfigurationError;

  void Function(CustomerInfo)? _pendingCustomerInfoListener;

  /// Invoked once [markSdkReady] runs. `Purchases.configure` is kicked off
  /// fire-and-forget during startup, so every provider that reads the SDK on
  /// the first frame loses the race and sees an unconfigured SDK. Subscribers
  /// use this to re-run whatever they gave up on.
  void Function()? onSdkStateChanged;

  /// Mark the Purchases SDK as configured. Call once after successful
  /// `Purchases.configure` in app startup.
  void markSdkReady() {
    _sdkReady = true;
    _sdkConfigurationError = null;
    final pending = _pendingCustomerInfoListener;
    if (pending != null) {
      _pendingCustomerInfoListener = null;
      Purchases.addCustomerInfoUpdateListener(pending);
    }
    try {
      onSdkStateChanged?.call();
    } catch (e) {
      debugPrint('RevenueCatService: SDK state callback failed: $e');
    }
  }

  /// Record a configuration failure so callers see a terminal error instead
  /// of treating the SDK as if startup were still in progress. A late success
  /// clears this through [markSdkReady].
  void markSdkConfigurationFailed(Object error) {
    _sdkReady = false;
    _sdkConfigurationError = error;
    try {
      onSdkStateChanged?.call();
    } catch (callbackError) {
      debugPrint('RevenueCatService: SDK state callback failed: $callbackError');
    }
  }

  /// Callback to be invoked on app resume to sync subscription state.
  /// Set by SubscriptionNotifier to ensure state is updated after sync.
  Future<void> Function()? onAppResumeCallback;

  /// Login user to RevenueCat with their app user ID
  /// Call this when user logs in to your auth system (Supabase)
  Future<void> logIn(String userId) async {
    if (!_sdkReady) return;
    try {
      final result = await Purchases.logIn(userId);
      debugPrint(
        '✅ RevenueCat user logged in: ${result.customerInfo.originalAppUserId}',
      );

      // Capture device identifiers for the RC <> AppsFlyer integration. On
      // iOS this is IDFA (only populated if ATT was granted) + IDFV + IP; on
      // Android this is GAID + Android ID + IP. Idempotent — safe to call on
      // every login.
      try {
        await Purchases.collectDeviceIdentifiers();
      } catch (e) {
        debugPrint('RevenueCatService: collectDeviceIdentifiers failed: $e');
      }

      // Forward the device's OneSignal subscription ID to the new RC customer
      // profile so RC's OneSignal integration can target this device with
      // subscription-state push notifications (trial expiring, billing issue,
      // etc.). The subscription ID is device-scoped, but RC scopes attributes
      // per-customer — so every user switch needs to re-stamp it.
      try {
        final osId =
            PushNotificationsService.instance.currentOneSignalSubscriptionId;
        if (osId != null && osId.isNotEmpty) {
          await Purchases.setOnesignalID(osId);
        }
      } catch (e) {
        debugPrint('RevenueCatService: setOnesignalID failed: $e');
      }
    } catch (e) {
      debugPrint('❌ RevenueCat login error: $e');
    }
  }

  /// Logout user from RevenueCat
  /// Call this when user logs out of your auth system
  Future<void> logOut() async {
    if (!_sdkReady) return;
    try {
      await Purchases.logOut();
      debugPrint('✅ RevenueCat user logged out');
    } catch (e) {
      debugPrint('❌ RevenueCat logout error: $e');
    }
  }

  /// Check if user has active premium subscription
  Future<bool> isSubscribed() async {
    if (_sdkReady) {
      try {
        final customerInfo = await Purchases.getCustomerInfo();
        // Check for our specific entitlement
        final hasEntitlement = customerInfo.entitlements.active.containsKey(
          premiumEntitlement,
        );
        // Fallback: also check if any entitlement is active
        final hasAnyEntitlement = customerInfo.entitlements.active.isNotEmpty;
        if (hasEntitlement || hasAnyEntitlement) return true;
      } catch (e) {
        debugPrint('Error checking subscription: $e');
      }
    }

    final backendEntitlement = await getBackendEntitlement();
    return backendEntitlement?.isActive ?? false;
  }

  /// Get current customer info
  Future<CustomerInfo?> getCustomerInfo() async {
    if (!_sdkReady) return null;
    try {
      return await Purchases.getCustomerInfo();
    } catch (e) {
      debugPrint('Error getting customer info: $e');
      return null;
    }
  }

  /// Read the Supabase entitlement authority shared by web, desktop, and
  /// mobile. This makes Stripe subscriptions purchased outside the app unlock
  /// mobile while RevenueCat still handles App Store / Play Store purchases.
  Future<BackendEntitlementSnapshot?> getBackendEntitlement() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) return null;

    try {
      // HARD TIMEOUT — do not remove.
      //
      // This call used to sit inside the same `Future.wait` as the offerings
      // fetch in SubscriptionNotifier._initialize. With no timeout, a hung
      // Edge Function meant `Future.wait` never resolved, so the already-
      // fetched packages were never written to state and the paywall
      // shimmered forever. Regions with poor Supabase connectivity hit this
      // reliably — see Sentry CHESSEVER-XM (521s from India, Retry-After:
      // 120) and CHESSEVER-15J (connection timeouts to the same host).
      //
      // The load is now decoupled, but this call must still be bounded: it
      // gates the entitlement state the whole subscription UI reads.
      final response = await Supabase.instance.client.functions
          .invoke('entitlement', method: HttpMethod.get)
          .timeout(const Duration(seconds: 8));
      if (response.status != 200 || response.data is! Map) {
        debugPrint(
          'Backend entitlement returned ${response.status}: ${response.data}',
        );
        return null;
      }
      return BackendEntitlementSnapshot.fromJson(
        Map<String, dynamic>.from(response.data as Map),
      );
    } catch (e) {
      debugPrint('Error getting backend entitlement: $e');
      return null;
    }
  }

  /// Fetch the current offering's packages.
  ///
  /// Retries with backoff: a single transient failure here used to strand the
  /// paywall on skeleton prices for the whole session, because nothing
  /// re-fetched offerings afterwards. Returns [OfferingsFetch.notConfigured]
  /// when the SDK has not been configured yet — that is a *temporary* state
  /// during startup, not an empty catalog, and callers must retry on
  /// [onSdkStateChanged] rather than treat it as "no products exist".
  Future<OfferingsFetch> fetchProducts({
    int attempts = 3,
    Duration requestTimeout = const Duration(seconds: 5),
  }) async {
    if (!_sdkReady) {
      final configurationError = _sdkConfigurationError;
      return configurationError == null
          ? const OfferingsFetch.notConfigured()
          : OfferingsFetch.failure(
            'RevenueCat configuration failed: $configurationError',
          );
    }

    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final offerings = await Purchases.getOfferings().timeout(requestTimeout);
        final current = offerings.current;
        if (current != null && current.availablePackages.isNotEmpty) {
          debugPrint('📦 Current offering: ${current.identifier}');
          debugPrint(
            '📦 Available packages: ${current.availablePackages.length}',
          );
          for (final pkg in current.availablePackages) {
            debugPrint(
              '  - ${pkg.packageType}: ${pkg.storeProduct.identifier} @ ${pkg.storeProduct.priceString}',
            );
          }
          return OfferingsFetch.success(current.availablePackages);
        }
        // Reachable but empty. Two very different causes, so keep them
        // distinguishable — this is the branch a device lands in when the
        // STORE returns no products for that particular account (wrong
        // storefront/region, app not installed from Play, sandbox account)
        // even though RevenueCat itself answered fine.
        final hasOffering = current != null;
        debugPrint(
          hasOffering
              ? '⚠️ Current offering "${current.identifier}" has no packages '
                  '— the store returned no products for this account'
              : '⚠️ No current offering returned by RevenueCat',
        );
        unawaited(
          Sentry.captureMessage(
            hasOffering
                ? 'Offering resolved but store returned no products'
                : 'RevenueCat returned no current offering',
            level: SentryLevel.error,
            withScope: (scope) {
              scope.setTag('rc_offerings_error', 'empty');
              scope.setTag('rc_has_current_offering', '$hasOffering');
              if (hasOffering) {
                scope.setTag('rc_offering_id', current.identifier);
              }
            },
          ),
        );
        return const OfferingsFetch.empty();
      } catch (e, stackTrace) {
        lastError = e;
        lastStackTrace = stackTrace;
        debugPrint('Error getting products (attempt $attempt/$attempts): $e');
        // A timed-out method-channel request is still running natively. Do not
        // overlap it with more StoreKit / Play Billing calls.
        if (e is TimeoutException) break;
        if (attempt < attempts) {
          await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        }
      }
    }

    // Every attempt failed. Surface it — this path is what customers see as a
    // paywall that never loads, and it was previously invisible in production.
    if (lastError != null) {
      final code = _storeErrorCode(lastError);
      unawaited(
        Sentry.captureException(
          lastError,
          stackTrace: lastStackTrace,
          withScope: (scope) {
            scope.setTag('rc_offerings_error', code);
            scope.setTag('rc_sdk_ready', '$_sdkReady');
          },
        ),
      );
      return OfferingsFetch.failure('$code: $lastError');
    }
    return const OfferingsFetch.failure(null);
  }

  /// Best-effort extraction of the underlying store/SDK error code.
  ///
  /// Every one of these reaches Dart as the same generic `PlatformException`,
  /// so without the code they are indistinguishable in Sentry — yet they mean
  /// completely different things and have different fixes:
  ///
  /// * `STORE_PROBLEM` / `BILLING_UNAVAILABLE` — Play Billing could not bind:
  ///   app not installed from Play (sideloaded), stale Play Store, no Play
  ///   account. Device-side, not ours.
  /// * `CONFIGURATION_ERROR` — SDK key / bundle id / package name mismatch.
  /// * `PRODUCT_NOT_AVAILABLE_FOR_PURCHASE` — store returned no product for
  ///   this account's storefront or region.
  /// * `NETWORK_ERROR` — transient; the retry above usually absorbs it.
  static String _storeErrorCode(Object error) {
    if (error is PlatformException) {
      final details = error.details;
      if (details is Map) {
        final readable = details['readableErrorCode'];
        if (readable is String && readable.isNotEmpty) return readable;
      }
      return error.code;
    }
    if (error is PurchasesErrorCode) return error.name;
    return error.runtimeType.toString();
  }

  /// Back-compat wrapper. Prefer [fetchProducts] — it distinguishes "not
  /// configured yet" and "fetch failed" from "the catalog is empty".
  Future<List<Package>> getProducts() async => (await fetchProducts()).packages;

  /// Purchase subscription with proper error handling
  Future<PurchaseAttemptResult> purchaseSubscription(Package package) async {
    return _runPurchase(
      label: package.storeProduct.identifier,
      run: () => Purchases.purchase(PurchaseParams.package(package)),
    );
  }

  /// Android-only. Purchase a specific [SubscriptionOption] (a Google Play
  /// subscription offer attached to a base plan) so a percentage-discount
  /// offer can be applied. Use the matching SubscriptionOption id from
  /// `package.storeProduct.subscriptionOptions` — the base plan itself is
  /// also a SubscriptionOption (`isBasePlan == true`), so this method is
  /// only meaningful when invoking a non-base offer.
  Future<PurchaseAttemptResult> purchaseSubscriptionOption(
    SubscriptionOption option,
  ) async {
    return _runPurchase(
      label: '${option.productId} / offer=${option.id}',
      run: () => Purchases.purchase(PurchaseParams.subscriptionOption(option)),
    );
  }

  /// Search across [packages] for a Google Play subscription offer tagged
  /// with [code] (case-insensitive). Returns the matching `(package, option)`
  /// or null if no offer carries that tag.
  ///
  /// Tagging convention: in Play Console, when creating a subscription offer
  /// (eligibility "Developer determined"), add the lowercase code as a tag —
  /// e.g., the offer for code `GOATOTB` is tagged `goatotb`. Tags are exposed
  /// to the SDK as [SubscriptionOption.tags] and survive offer expiration —
  /// when the offer expires or is archived in Play Console, Google stops
  /// returning it, so this lookup naturally fails. No app release is needed
  /// to add, remove, or rotate codes.
  ({Package package, SubscriptionOption option})? findOfferByCode(
    Iterable<Package> packages,
    String code,
  ) {
    final canonical = code.trim().toLowerCase();
    if (canonical.isEmpty) return null;

    for (final package in packages) {
      final options = package.storeProduct.subscriptionOptions;
      if (options == null) continue;
      for (final option in options) {
        if (option.isBasePlan) continue;
        for (final tag in option.tags) {
          if (tag.toLowerCase() == canonical) {
            return (package: package, option: option);
          }
        }
      }
    }
    return null;
  }

  Future<PurchaseAttemptResult> _runPurchase({
    required String label,
    required Future<PurchaseResult> Function() run,
  }) async {
    if (!_sdkReady) {
      return PurchaseAttemptResult.error('Purchases is not configured');
    }
    try {
      debugPrint('🛒 Starting purchase for: $label');

      final purchaseResult = await run();

      final isActive =
          purchaseResult.customerInfo.entitlements.active.isNotEmpty;
      debugPrint('✅ Purchase completed. Active: $isActive');

      return isActive
          ? PurchaseAttemptResult.success()
          : PurchaseAttemptResult.error(
            'Purchase completed but no entitlement activated',
          );
    } on PurchasesErrorCode catch (errorCode) {
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        debugPrint('ℹ️ Purchase cancelled by user');
        return PurchaseAttemptResult.cancelled();
      }
      debugPrint('❌ RevenueCat error code: $errorCode');
      return PurchaseAttemptResult.error('Purchase failed: $errorCode');
    } on PlatformException catch (e) {
      if (e.code == 'PURCHASE_CANCELLED' ||
          e.message?.contains('cancelled') == true ||
          e.message?.contains('canceled') == true) {
        debugPrint('ℹ️ Purchase cancelled by user (platform)');
        return PurchaseAttemptResult.cancelled();
      }
      debugPrint('❌ Platform error: ${e.code} - ${e.message}');
      return PurchaseAttemptResult.error(
        e.message ?? 'Platform error occurred',
      );
    } catch (e) {
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('cancel') || errorStr.contains('user')) {
        debugPrint('ℹ️ Purchase likely cancelled by user');
        return PurchaseAttemptResult.cancelled();
      }
      debugPrint('❌ Purchase error: $e');
      return PurchaseAttemptResult.error(e.toString());
    }
  }

  /// Restore purchases
  Future<bool> restorePurchases() async {
    if (!_sdkReady) return false;
    try {
      final customerInfo = await Purchases.restorePurchases();
      final hasEntitlement =
          customerInfo.entitlements.active.containsKey(premiumEntitlement) ||
          customerInfo.entitlements.active.isNotEmpty;
      debugPrint('✅ Restore completed. Has entitlement: $hasEntitlement');
      return hasEntitlement;
    } catch (e) {
      debugPrint('❌ Restore error: $e');
      return false;
    }
  }

  /// Sync purchases with RevenueCat servers.
  /// Call this at critical points: app foreground, app startup, after auth changes.
  /// This ensures subscription status is always up-to-date.
  /// Returns the latest CustomerInfo after sync.
  Future<CustomerInfo?> syncPurchases() async {
    if (!_sdkReady) return null;
    try {
      // Invalidate cache first to ensure we get fresh data from RevenueCat servers
      await Purchases.invalidateCustomerInfoCache();
      await Purchases.syncPurchases();
      debugPrint('✅ RevenueCat purchases synced');
      // Always fetch fresh customer info after sync to ensure state is up-to-date
      // This handles edge cases where the listener doesn't fire (e.g., expired subscriptions)
      return await Purchases.getCustomerInfo();
    } catch (e) {
      debugPrint('❌ RevenueCat sync error: $e');
      return null;
    }
  }

  /// Set up listener for customer info changes
  void setCustomerInfoListener(void Function(CustomerInfo) listener) {
    if (!_sdkReady) {
      // Provider may construct before configure finishes, or ChessEver Test
      // may intentionally skip RC. Attach later via [markSdkReady].
      _pendingCustomerInfoListener = listener;
      return;
    }
    Purchases.addCustomerInfoUpdateListener(listener);
  }

  /// iOS only. Opens Apple's native offer-code redemption sheet.
  /// On Android this is a no-op — codes are redeemed on the Play Store.
  Future<void> presentCodeRedemptionSheet() async {
    if (!_sdkReady) return;
    try {
      await Purchases.presentCodeRedemptionSheet();
    } catch (e) {
      debugPrint('❌ Code redemption sheet error: $e');
    }
  }

  /// Tag the customer record with metadata describing the in-flight code
  /// redemption. RC stores these as customer attributes — they appear in the
  /// RC dashboard and ride along on the webhooks RC fires to integrations
  /// (AppsFlyer, Stripe, Mixpanel), so partner reporting can attribute the
  /// resulting subscription to the correct campaign.
  ///
  /// `affiliateContext` is the parsed AppsFlyer install context
  /// (install_at/af_status plus affiliate_code/campaign/media_source when the
  /// install is non-organic). It is passed in rather than read here so this
  /// layer stays free of AppsFlyer dependencies.
  Future<void> tagRedemptionAttempt({
    required String source,
    String? code,
    Map<String, String>? affiliateContext,
  }) async {
    if (!_sdkReady) return;
    try {
      final attrs = <String, String>{
        'redemption_source': source,
        'redemption_initiated_at': DateTime.now().toUtc().toIso8601String(),
        if (code != null && code.isNotEmpty) 'redemption_code': code,
        if (affiliateContext != null)
          for (final entry in affiliateContext.entries)
            'redemption_${entry.key}': entry.value,
      };
      await Purchases.setAttributes(attrs);
      debugPrint('✅ RevenueCat redemption attributes set: $attrs');
    } catch (e) {
      debugPrint('❌ tagRedemptionAttempt error: $e');
    }
  }
}

@immutable
class BackendEntitlementSnapshot {
  const BackendEntitlementSnapshot({
    required this.isActive,
    this.provider,
    this.expiresAt,
    this.willRenew = false,
    this.productId,
    this.status,
    this.inBillingGracePeriod = false,
    this.billingIssueDetectedAt,
  });

  final bool isActive;
  final String? provider;
  final DateTime? expiresAt;
  final bool willRenew;
  final String? productId;

  /// Raw lifecycle status from the backend mirror — 'active' / 'trialing' /
  /// 'past_due' / 'canceled' / 'paused'. Kept for callers that want the raw
  /// value; the convenience flag below is derived from it.
  final String? status;

  /// True when the backend reports a payment failure but the entitlement
  /// is still honored (Stripe past_due, App Store/Play billing retry that
  /// propagated through the RC webhook). The UI uses this to prompt the
  /// user to update their card before access ends.
  final bool inBillingGracePeriod;

  /// When the billing failure was first observed by the backend. May be
  /// null when the status flips to past_due without a precise timestamp.
  final DateTime? billingIssueDetectedAt;

  factory BackendEntitlementSnapshot.fromJson(Map<String, dynamic> json) {
    final cancelAt = switch (json['cancel_at']) {
      String s => DateTime.tryParse(s),
      _ => null,
    };
    final status = json['status'] as String?;
    return BackendEntitlementSnapshot(
      isActive: json['is_premium'] as bool? ?? false,
      provider: json['provider'] as String?,
      expiresAt: switch (json['expires_at']) {
        String s => DateTime.tryParse(s),
        _ => null,
      },
      willRenew: cancelAt == null,
      productId: json['product_id'] as String?,
      status: status,
      inBillingGracePeriod: status == 'past_due',
      billingIssueDetectedAt: switch (json['billing_issue_detected_at']) {
        String s => DateTime.tryParse(s),
        _ => null,
      },
    );
  }
}
