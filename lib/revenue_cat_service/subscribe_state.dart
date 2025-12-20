import 'package:chessever2/revenue_cat_service/revenue_cat_service.dart';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:purchases_flutter/models/package_wrapper.dart';

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>((ref) {
      return SubscriptionNotifier();
    });

class SubscriptionNotifier extends StateNotifier<SubscriptionState> {
  final _revenueCat = RevenueCatService();

  SubscriptionNotifier() : super(SubscriptionState()) {
    _revenueCat.setCustomerInfoListener((customerInfo) {
      final hasPremiumEntitlement = customerInfo.entitlements.active
          .containsKey(RevenueCatService.premiumEntitlement);
      final hasAnyEntitlement = customerInfo.entitlements.active.isNotEmpty;

      state = state.copyWith(
        isSubscribed: hasPremiumEntitlement || hasAnyEntitlement,
      );
    });
    _initialize();
  }

  Future<void> _initialize() async {
    state = state.copyWith(isLoading: true);

    try {
      final isSubscribed = await _revenueCat.isSubscribed();
      final products = await _revenueCat.getProducts();
      final customerInfo = await _revenueCat.getCustomerInfo();

      DateTime? expirationDate;
      String? managementUrl;

      if (customerInfo != null) {
        // Get expiration date from active entitlements
        final activeEntitlements = customerInfo.entitlements.active;
        if (activeEntitlements.isNotEmpty) {
          final entitlement = activeEntitlements.values.first;
          if (entitlement.expirationDate != null) {
            expirationDate = DateTime.tryParse(entitlement.expirationDate!);
          }
        }
        // Get management URL
        managementUrl = customerInfo.managementURL;
      }

      state = state.copyWith(
        isSubscribed: isSubscribed,
        products: products,
        isLoading: false,
        expirationDate: expirationDate,
        managementUrl: managementUrl,
      );
    } catch (e) {
      debugPrint('❌ Subscription initialization error: $e');
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  /// Refresh subscription status (call after auth changes)
  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final isSubscribed = await _revenueCat.isSubscribed();
      final products = await _revenueCat.getProducts();
      final customerInfo = await _revenueCat.getCustomerInfo();

      DateTime? expirationDate;
      String? managementUrl;

      if (customerInfo != null) {
        final activeEntitlements = customerInfo.entitlements.active;
        if (activeEntitlements.isNotEmpty) {
          final entitlement = activeEntitlements.values.first;
          if (entitlement.expirationDate != null) {
            expirationDate = DateTime.tryParse(entitlement.expirationDate!);
          }
        }
        managementUrl = customerInfo.managementURL;
      }

      state = state.copyWith(
        isSubscribed: isSubscribed,
        products: products,
        isLoading: false,
        expirationDate: expirationDate,
        managementUrl: managementUrl,
      );
    } catch (e) {
      debugPrint('❌ Subscription refresh error: $e');
      state = state.copyWith(error: e.toString(), isLoading: false);
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

  SubscriptionState({
    this.isSubscribed = false,
    this.isLoading = false,
    this.products = const [],
    this.error,
    this.expirationDate,
    this.managementUrl,
  });

  SubscriptionState copyWith({
    bool? isSubscribed,
    bool? isLoading,
    List<Package>? products,
    String? error,
    DateTime? expirationDate,
    String? managementUrl,
  }) {
    return SubscriptionState(
      isSubscribed: isSubscribed ?? this.isSubscribed,
      isLoading: isLoading ?? this.isLoading,
      products: products ?? this.products,
      error: error,
      expirationDate: expirationDate ?? this.expirationDate,
      managementUrl: managementUrl ?? this.managementUrl,
    );
  }
}
