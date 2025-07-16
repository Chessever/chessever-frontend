import 'package:purchases_flutter/purchases_flutter.dart';

class RevenueCatService {
  static final RevenueCatService _instance = RevenueCatService._internal();
  factory RevenueCatService() => _instance;
  RevenueCatService._internal();

  Future<bool> isSubscribed() async {
    try {
      final purchaserInfo = await Purchases.getCustomerInfo();
      return purchaserInfo.entitlements.active.isNotEmpty;
    } catch (e) {
      print('Error checking subscription: $e');
      return false;
    }
  }

  // Get available products
  Future<List<Package>> getProducts() async {
    try {
      final offerings = await Purchases.getOfferings();
      if (offerings.current != null) {
        return offerings.current!.availablePackages;
      }
      return [];
    } catch (e) {
      print('Error getting products: $e');
      return [];
    }
  }

  // Purchase subscription
  Future<bool> purchaseSubscription(Package package) async {
    try {
      final purchaserInfo = await Purchases.purchasePackage(package);
      return purchaserInfo.entitlements.active.isNotEmpty;
    } catch (e) {
      print('Purchase error: $e');
      return false;
    }
  }

  // Restore purchases
  Future<bool> restorePurchases() async {
    try {
      final purchaserInfo = await Purchases.restorePurchases();
      return purchaserInfo.entitlements.active.isNotEmpty;
    } catch (e) {
      print('Restore error: $e');
      return false;
    }
  }
}
