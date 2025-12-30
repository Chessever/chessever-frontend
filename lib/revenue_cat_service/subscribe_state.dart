import 'dart:async';

import 'package:chessever2/revenue_cat_service/revenue_cat_service.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart' show CustomerInfo, Package;

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>((ref) {
      final notifier = SubscriptionNotifier();
      // Register global callback for app resume sync
      RevenueCatService().onAppResumeCallback = notifier.syncAndRefresh;
      ref.onDispose(() {
        RevenueCatService().onAppResumeCallback = null;
        // Note: notifier.dispose() is called automatically by StateNotifier
      });
      return notifier;
    });

class SubscriptionNotifier extends StateNotifier<SubscriptionState> {
  final _revenueCat = RevenueCatService();
  Timer? _periodicSyncTimer;
  Timer? _expirationTimer;

  /// How often to sync with RevenueCat when app stays open (1 hour)
  static const _periodicSyncInterval = Duration(hours: 1);

  SubscriptionNotifier() : super(SubscriptionState()) {
    _revenueCat.setCustomerInfoListener((customerInfo) {
      _updateStateFromCustomerInfo(customerInfo);
    });
    _initialize();
    _startPeriodicSync();
  }

  @override
  void dispose() {
    _periodicSyncTimer?.cancel();
    _expirationTimer?.cancel();
    super.dispose();
  }

  /// Start periodic sync timer to catch expirations while app stays open
  void _startPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(_periodicSyncInterval, (_) {
      debugPrint('⏰ Periodic subscription sync triggered');
      syncAndRefresh();
    });
  }

  /// Schedule a sync right when the subscription is about to expire
  void _scheduleExpirationCheck() {
    _expirationTimer?.cancel();

    final expirationDate = state.expirationDate;
    if (expirationDate == null || !state.isSubscribed) return;

    final now = DateTime.now();
    final timeUntilExpiration = expirationDate.difference(now);

    // If already expired, sync immediately
    if (timeUntilExpiration.isNegative) {
      debugPrint('⚠️ Subscription already expired, syncing now');
      syncAndRefresh();
      return;
    }

    // Schedule sync 1 minute after expiration to catch it promptly
    final syncDelay = timeUntilExpiration + const Duration(minutes: 1);

    // Only schedule if within reasonable timeframe (< 7 days)
    if (syncDelay.inDays < 7) {
      debugPrint('📅 Scheduling expiration check in ${syncDelay.inHours}h ${syncDelay.inMinutes % 60}m');
      _expirationTimer = Timer(syncDelay, () {
        debugPrint('⏰ Expiration timer triggered, syncing subscription status');
        syncAndRefresh();
      });
    }
  }

  Future<void> _initialize() async {
    state = state.copyWith(isLoading: true);

    try {
      // Fetch products and customer info in parallel (2 API calls, not 3)
      final results = await Future.wait([
        _revenueCat.getProducts(),
        _revenueCat.getCustomerInfo(),
      ]);
      final products = results[0] as List<Package>;
      final customerInfo = results[1] as CustomerInfo?;

      // Derive isSubscribed from customerInfo (no extra API call)
      bool isSubscribed = false;
      DateTime? expirationDate;
      String? managementUrl;
      bool willRenew = true;

      if (customerInfo != null) {
        // Check entitlements from the already-fetched customerInfo
        final activeEntitlements = customerInfo.entitlements.active;
        isSubscribed = activeEntitlements
                .containsKey(RevenueCatService.premiumEntitlement) ||
            activeEntitlements.isNotEmpty;

        if (activeEntitlements.isNotEmpty) {
          final entitlement = activeEntitlements.values.first;
          if (entitlement.expirationDate != null) {
            expirationDate = DateTime.tryParse(entitlement.expirationDate!);
          }
          willRenew = entitlement.willRenew;
        }
        managementUrl = customerInfo.managementURL;
      }

      state = state.copyWith(
        isSubscribed: isSubscribed,
        products: products,
        isLoading: false,
        expirationDate: expirationDate,
        managementUrl: managementUrl,
        willRenew: willRenew,
      );

      // Schedule expiration check if subscribed
      if (isSubscribed && expirationDate != null) {
        _scheduleExpirationCheck();
      }
    } catch (e) {
      debugPrint('❌ Subscription initialization error: $e');
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  /// Refresh subscription status (call after auth changes)
  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Fetch products and customer info in parallel (2 API calls, not 3)
      final results = await Future.wait([
        _revenueCat.getProducts(),
        _revenueCat.getCustomerInfo(),
      ]);
      final products = results[0] as List<Package>;
      final customerInfo = results[1] as CustomerInfo?;

      // Derive isSubscribed from customerInfo (no extra API call)
      bool isSubscribed = false;
      DateTime? expirationDate;
      String? managementUrl;
      bool willRenew = true;

      if (customerInfo != null) {
        final activeEntitlements = customerInfo.entitlements.active;
        isSubscribed = activeEntitlements
                .containsKey(RevenueCatService.premiumEntitlement) ||
            activeEntitlements.isNotEmpty;

        if (activeEntitlements.isNotEmpty) {
          final entitlement = activeEntitlements.values.first;
          if (entitlement.expirationDate != null) {
            expirationDate = DateTime.tryParse(entitlement.expirationDate!);
          }
          willRenew = entitlement.willRenew;
        }
        managementUrl = customerInfo.managementURL;
      }

      state = state.copyWith(
        isSubscribed: isSubscribed,
        products: products,
        isLoading: false,
        expirationDate: expirationDate,
        managementUrl: managementUrl,
        willRenew: willRenew,
      );

      // Schedule expiration check if subscribed
      if (isSubscribed && expirationDate != null) {
        _scheduleExpirationCheck();
      }
    } catch (e) {
      debugPrint('❌ Subscription refresh error: $e');
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  /// Sync purchases with RevenueCat servers and update local state.
  /// Call this on app resume/foreground to catch expired subscriptions.
  Future<void> syncAndRefresh() async {
    try {
      final customerInfo = await _revenueCat.syncPurchases();
      if (customerInfo != null) {
        _updateStateFromCustomerInfo(customerInfo);
      }
    } catch (e) {
      debugPrint('❌ Subscription sync error: $e');
    }
  }

  /// Update state from CustomerInfo (used by listener and sync)
  void _updateStateFromCustomerInfo(CustomerInfo customerInfo) {
    final hasPremiumEntitlement = customerInfo.entitlements.active
        .containsKey(RevenueCatService.premiumEntitlement);
    final hasAnyEntitlement = customerInfo.entitlements.active.isNotEmpty;
    final isSubscribed = hasPremiumEntitlement || hasAnyEntitlement;

    DateTime? expirationDate;
    bool willRenew = true;
    if (customerInfo.entitlements.active.isNotEmpty) {
      final entitlement = customerInfo.entitlements.active.values.first;
      if (entitlement.expirationDate != null) {
        expirationDate = DateTime.tryParse(entitlement.expirationDate!);
      }
      willRenew = entitlement.willRenew;
    }

    final previouslySubscribed = state.isSubscribed;
    state = state.copyWith(
      isSubscribed: isSubscribed,
      expirationDate: expirationDate,
      managementUrl: customerInfo.managementURL,
      willRenew: willRenew,
    );

    // Log subscription status changes for debugging
    if (previouslySubscribed != isSubscribed) {
      debugPrint('🔄 Subscription status changed: $previouslySubscribed → $isSubscribed');
    }

    // Schedule a check for when subscription expires (if subscribed)
    if (isSubscribed && expirationDate != null) {
      _scheduleExpirationCheck();
    }
  }

  /// Purchase a subscription package
  /// Returns the result indicating success, cancellation, or error
  Future<PurchaseAttemptResult> purchaseSubscription(Package package) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await _revenueCat.purchaseSubscription(package);

      if (result.success) {
        state = state.copyWith(isSubscribed: true, isLoading: false);
      } else if (result.wasCancelled) {
        // User cancelled - not an error, just reset loading state
        state = state.copyWith(isLoading: false);
      } else {
        // Actual error occurred
        state = state.copyWith(
          isLoading: false,
          error: result.errorMessage ?? 'Purchase failed',
        );
      }

      return result;
    } catch (e) {
      debugPrint('❌ Purchase exception: $e');
      state = state.copyWith(error: e.toString(), isLoading: false);
      return PurchaseAttemptResult.error(e.toString());
    }
  }

  Future<bool> restorePurchases() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final success = await _revenueCat.restorePurchases();
      state = state.copyWith(isSubscribed: success, isLoading: false);
      return success;
    } catch (e) {
      debugPrint('❌ Restore purchases error: $e');
      state = state.copyWith(error: e.toString(), isLoading: false);
      return false;
    }
  }

  /// Clear error state
  void clearError() {
    state = state.copyWith(error: null);
  }
}

class SubscriptionState {
  final bool isSubscribed;
  final bool isLoading;
  final List<Package> products;
  final String? error;
  final DateTime? expirationDate;
  final String? managementUrl;
  /// True if the subscription will auto-renew at the end of the billing period.
  /// False if user has cancelled (but may still have access until expirationDate).
  final bool willRenew;

  SubscriptionState({
    this.isSubscribed = false,
    this.isLoading = false,
    this.products = const [],
    this.error,
    this.expirationDate,
    this.managementUrl,
    this.willRenew = true,
  });

  SubscriptionState copyWith({
    bool? isSubscribed,
    bool? isLoading,
    List<Package>? products,
    String? error,
    DateTime? expirationDate,
    String? managementUrl,
    bool? willRenew,
  }) {
    return SubscriptionState(
      isSubscribed: isSubscribed ?? this.isSubscribed,
      isLoading: isLoading ?? this.isLoading,
      products: products ?? this.products,
      error: error,
      expirationDate: expirationDate ?? this.expirationDate,
      managementUrl: managementUrl ?? this.managementUrl,
      willRenew: willRenew ?? this.willRenew,
    );
  }
}
