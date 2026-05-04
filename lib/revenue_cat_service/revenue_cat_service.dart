import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

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

class RevenueCatService {
  static final RevenueCatService _instance = RevenueCatService._internal();
  factory RevenueCatService() => _instance;
  RevenueCatService._internal();

  /// The entitlement identifier for ChessEver premium
  /// Must match the lookup_key in RevenueCat dashboard
  static const String premiumEntitlement = 'Chessever Subscription';

  /// Callback to be invoked on app resume to sync subscription state.
  /// Set by SubscriptionNotifier to ensure state is updated after sync.
  Future<void> Function()? onAppResumeCallback;

  /// Login user to RevenueCat with their app user ID
  /// Call this when user logs in to your auth system (Supabase)
  Future<void> logIn(String userId) async {
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
    } catch (e) {
      debugPrint('❌ RevenueCat login error: $e');
    }
  }

  /// Logout user from RevenueCat
  /// Call this when user logs out of your auth system
  Future<void> logOut() async {
    try {
      await Purchases.logOut();
      debugPrint('✅ RevenueCat user logged out');
    } catch (e) {
      debugPrint('❌ RevenueCat logout error: $e');
    }
  }

  /// Check if user has active premium subscription
  Future<bool> isSubscribed() async {
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      // Check for our specific entitlement
      final hasEntitlement = customerInfo.entitlements.active.containsKey(
        premiumEntitlement,
      );
      // Fallback: also check if any entitlement is active
      final hasAnyEntitlement = customerInfo.entitlements.active.isNotEmpty;
      return hasEntitlement || hasAnyEntitlement;
    } catch (e) {
      debugPrint('Error checking subscription: $e');
      return false;
    }
  }

  /// Get current customer info
  Future<CustomerInfo?> getCustomerInfo() async {
    try {
      return await Purchases.getCustomerInfo();
    } catch (e) {
      debugPrint('Error getting customer info: $e');
      return null;
    }
  }

  /// Get available products/packages
  Future<List<Package>> getProducts() async {
    try {
      final offerings = await Purchases.getOfferings();
      if (offerings.current != null) {
        debugPrint('📦 Current offering: ${offerings.current!.identifier}');
        debugPrint(
          '📦 Available packages: ${offerings.current!.availablePackages.length}',
        );
        for (final pkg in offerings.current!.availablePackages) {
          debugPrint(
            '  - ${pkg.packageType}: ${pkg.storeProduct.identifier} @ ${pkg.storeProduct.priceString}',
          );
        }
        return offerings.current!.availablePackages;
      }
      debugPrint('⚠️ No current offering found');
      return [];
    } catch (e) {
      debugPrint('Error getting products: $e');
      return [];
    }
  }

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
      run:
          () => Purchases.purchase(
            PurchaseParams.subscriptionOption(option),
          ),
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
    Purchases.addCustomerInfoUpdateListener(listener);
  }

  /// iOS only. Opens Apple's native offer-code redemption sheet.
  /// On Android this is a no-op — codes are redeemed on the Play Store.
  Future<void> presentCodeRedemptionSheet() async {
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
