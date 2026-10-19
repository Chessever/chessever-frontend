// Local doubles for the subscription state without a connection. These never
// contact RevenueCat, Supabase or the device database.
import 'package:chessever2/revenue_cat_service/offline_premium_cache.dart';
import 'package:chessever2/revenue_cat_service/revenue_cat_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show CustomerInfo;

class MemoryPremiumCache extends OfflinePremiumCache {
  MemoryPremiumCache(Map<String, OfflinePremiumSnapshot> snapshots)
    : snapshots = {...snapshots};

  final Map<String, OfflinePremiumSnapshot> snapshots;

  @override
  Future<OfflinePremiumSnapshot?> read(String userId) async =>
      snapshots[userId];

  @override
  Future<void> write(String userId, OfflinePremiumSnapshot snapshot) async =>
      snapshots[userId] = snapshot;

  @override
  Future<void> clear(String userId) async => snapshots.remove(userId);
}

/// RevenueCat with no connection: no customer info, no offerings, and an
/// `entitlement` function that answers whatever the test says.
class OfflineRevenueCat implements RevenueCatService {
  OfflineRevenueCat(this._backend);

  final Future<BackendEntitlementSnapshot?> Function() _backend;

  @override
  bool get isSdkReady => false;

  @override
  void setCustomerInfoListener(void Function(CustomerInfo) listener) {}

  @override
  Future<CustomerInfo?> getCustomerInfo() async => null;

  @override
  Future<CustomerInfo?> syncPurchases() async => null;

  @override
  Future<BackendEntitlementSnapshot?> getBackendEntitlement() => _backend();

  @override
  Future<OfferingsFetch> fetchProducts({
    int attempts = 3,
    Duration requestTimeout = const Duration(seconds: 5),
  }) async => const OfferingsFetch.failure('offline');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
