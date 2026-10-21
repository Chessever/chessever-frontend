// Local doubles for the subscription state without a connection. These never
// contact RevenueCat, Supabase or the device database.
import 'package:chessever2/revenue_cat_service/offline_premium_cache.dart';
import 'package:chessever2/revenue_cat_service/revenue_cat_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart'
    show CustomerInfo, EntitlementInfo, EntitlementInfos;

class MemoryPremiumCache extends OfflinePremiumCache {
  MemoryPremiumCache(Map<String, OfflinePremiumSnapshot> snapshots)
    : snapshots = {...snapshots};

  final Map<String, OfflinePremiumSnapshot> snapshots;

  /// While set, writes wait on it, as a slow device database would.
  Future<void>? writesWaitOn;

  @override
  Future<OfflinePremiumSnapshot?> read(String userId) async =>
      snapshots[userId];

  @override
  Future<void> write(String userId, OfflinePremiumSnapshot snapshot) async {
    await writesWaitOn;
    snapshots[userId] = snapshot;
  }

  @override
  Future<void> clear(String userId) async => snapshots.remove(userId);
}

/// RevenueCat with no connection: no customer info, no offerings, and an
/// `entitlement` function that answers whatever the test says.
class OfflineRevenueCat implements RevenueCatService {
  OfflineRevenueCat(this._backend);

  final Future<BackendEntitlementSnapshot?> Function() _backend;

  /// The notifier's customer info listener, for a test to call as the SDK
  /// would with its cached customer info.
  void Function(CustomerInfo)? customerInfoListener;
  CustomerInfo? customerInfo;

  @override
  bool get isSdkReady => false;

  @override
  void setCustomerInfoListener(void Function(CustomerInfo) listener) =>
      customerInfoListener = listener;

  @override
  Future<CustomerInfo?> getCustomerInfo() async => customerInfo;

  @override
  Future<CustomerInfo?> syncPurchases() async => null;

  @override
  Future<bool> restorePurchases() async => false;

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

/// RevenueCat's customer info for a reader whose plan is active.
CustomerInfo premiumCustomerInfo({required DateTime expiresAt}) {
  final now = DateTime.now().toUtc().toIso8601String();
  final entitlement = EntitlementInfo(
    RevenueCatService.premiumEntitlement,
    true,
    true,
    now,
    now,
    'chessever_monthly',
    false,
    expirationDate: expiresAt.toUtc().toIso8601String(),
  );
  final entitlements = {RevenueCatService.premiumEntitlement: entitlement};
  return CustomerInfo(
    EntitlementInfos(entitlements, entitlements),
    const {},
    const ['chessever_monthly'],
    const ['chessever_monthly'],
    const [],
    now,
    'reader',
    const {},
    now,
  );
}
