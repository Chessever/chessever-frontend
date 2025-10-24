import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

class RevenueCatService {
  static final RevenueCatService _instance = RevenueCatService._internal();
  factory RevenueCatService() => _instance;
  RevenueCatService._internal();

  /// Initialize RevenueCat SDK
  static Future<void> init() async {
    await Purchases.setDebugLogsEnabled(true);

    // Get API key (Replace with your real key or use an env getter)
    final apiKey = _getEnv('RevenueCatAPIKey');

    // Configure RevenueCat
    await Purchases.configure(PurchasesConfiguration(apiKey));

    if (kDebugMode) print('✅ RevenueCat initialized');
  }

  /// Check if user is subscribed
  Future<bool> isSubscribed() async {
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      return customerInfo.entitlements.active.isNotEmpty;
    } catch (e) {
      debugPrint('⚠️ Error checking subscription: $e');
      return false;
    }
  }

  /// Get available product packages from RevenueCat
  Future<List<Package>> getProducts() async {
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current?.availablePackages ?? [];
    } catch (e) {
      debugPrint('⚠️ Error getting products: $e');
      return [];
    }
  }

  /// Purchase a subscription package
  Future<bool> purchaseSubscription(Package package) async {
    try {
      final customerInfo = await Purchases.purchasePackage(package);
      return customerInfo.entitlements.active.isNotEmpty;
    } catch (e) {
      debugPrint('⚠️ Purchase error: $e');
      return false;
    }
  }

  /// Restore previous purchases
  Future<bool> restorePurchases() async {
    try {
      final customerInfo = await Purchases.restorePurchases();
      return customerInfo.entitlements.active.isNotEmpty;
    } catch (e) {
      debugPrint('⚠️ Restore error: $e');
      return false;
    }
  }
}

/// 🔒 Helper: get API key securely
String _getEnv(String key) {
  const env = {
    'RevenueCatAPIKey': 'REPLACE_WITH_YOUR_PUBLIC_REVENUECAT_API_KEY',
  };
  return env[key] ?? '';
}
