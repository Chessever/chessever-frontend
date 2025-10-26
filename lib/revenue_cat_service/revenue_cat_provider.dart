import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class RevenueCatService {
  static final RevenueCatService _instance = RevenueCatService._internal();
  factory RevenueCatService() => _instance;
  RevenueCatService._internal();

  /// Initialize RevenueCat SDK
  static Future<void> init() async {
    await Purchases.setDebugLogsEnabled(true);

    // Get API key (Replace with your real key or use an env getter)
    final apiKey = _getEnv('RevenueCatAPIKey');

    if (Platform.isIOS) {
      await Purchases.configure(
        PurchasesConfiguration("appl_hggBdZrNsqmMHEorxxxLYjyHTzz"),
      ).whenComplete(() {});
    } else {
      await Purchases.configure(
        PurchasesConfiguration("goog_ZmINjxirbMFvSsVMUfviZwrpfBY"),
      );
    }

    // Configure RevenueCat

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

  Future<CustomerInfo?> getCustomerInfo() async {
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      return customerInfo;
    } catch (e) {
      debugPrint('⚠️ Error checking subscription: $e');
    }
    return null;
  }

  /// Get available product packages from RevenueCat
  Future<List<Package>> getProducts() async {
    try {
      final offerings = await Purchases.getOfferings();
      print(offerings);
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

  Future<void> cancelSubscription() async {
    final customerInfo = await Purchases.getCustomerInfo();
    if (customerInfo.managementURL != null) {
      if (await canLaunchUrl(Uri.parse(customerInfo.managementURL!))) {
        await launchUrl(Uri.parse(customerInfo.managementURL!));
      }
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
