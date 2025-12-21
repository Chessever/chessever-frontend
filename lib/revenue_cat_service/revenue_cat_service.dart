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
  static const String premiumEntitlement = 'Chessever Subscription';

  /// Callback to be invoked on app resume to sync subscription state.
  /// Set by SubscriptionNotifier to ensure state is updated after sync.
  Future<void> Function()? onAppResumeCallback;

  /// Login user to RevenueCat with their app user ID
  /// Call this when user logs in to your auth system (Supabase)
  Future<void> logIn(String userId) async {
    try {
      final result = await Purchases.logIn(userId);
      debugPrint('✅ RevenueCat user logged in: ${result.customerInfo.originalAppUserId}');
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
      final hasEntitlement =
          customerInfo.entitlements.active.containsKey(premiumEntitlement);
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
        debugPrint('📦 Available packages: ${offerings.current!.availablePackages.length}');
        for (final pkg in offerings.current!.availablePackages) {
          debugPrint('  - ${pkg.packageType}: ${pkg.storeProduct.identifier} @ ${pkg.storeProduct.priceString}');
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
    try {
      debugPrint('🛒 Starting purchase for: ${package.storeProduct.identifier}');

      final purchaseResult = await Purchases.purchase(
        PurchaseParams.package(package),
      );

      final isActive =
          purchaseResult.customerInfo.entitlements.active.isNotEmpty;
      debugPrint('✅ Purchase completed. Active: $isActive');

      return isActive
          ? PurchaseAttemptResult.success()
          : PurchaseAttemptResult.error('Purchase completed but no entitlement activated');
    } on PurchasesErrorCode catch (errorCode) {
      // Handle specific RevenueCat error codes
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        debugPrint('ℹ️ Purchase cancelled by user');
        return PurchaseAttemptResult.cancelled();
      }
      debugPrint('❌ RevenueCat error code: $errorCode');
      return PurchaseAttemptResult.error('Purchase failed: $errorCode');
    } on PlatformException catch (e) {
      // Handle platform-specific errors (includes user cancellation)
      if (e.code == 'PURCHASE_CANCELLED' ||
          e.message?.contains('cancelled') == true ||
          e.message?.contains('canceled') == true) {
        debugPrint('ℹ️ Purchase cancelled by user (platform)');
        return PurchaseAttemptResult.cancelled();
      }
      debugPrint('❌ Platform error: ${e.code} - ${e.message}');
      return PurchaseAttemptResult.error(e.message ?? 'Platform error occurred');
    } catch (e) {
      // Check if error message indicates cancellation
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
}
