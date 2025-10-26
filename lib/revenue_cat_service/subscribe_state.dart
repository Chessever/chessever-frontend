import 'package:chessever2/revenue_cat_service/revenue_cat_provider.dart';
import 'package:chessever2/screens/premium/provider/premiun_popup_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:purchases_flutter/models/package_wrapper.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>((ref) {
      return SubscriptionNotifier(ref);
    });

class SubscriptionNotifier extends StateNotifier<SubscriptionState> {
  final _revenueCat = RevenueCatService();

  final Ref ref;

  SubscriptionNotifier(this.ref) : super(SubscriptionState()) {
    // initialize();
  }

  void selectPackage(Package package) {
    state = state.copyWith(selectedPackage: package);
  }

  Future<void> initialize() async {
    state = state.copyWith(isLoading: true);

    try {
      CustomerInfo? customerInfo;
      List<Package>? products;
      final isSubscribed = await _revenueCat.isSubscribed();
      if (isSubscribed) {
        customerInfo = await _revenueCat.getCustomerInfo();
      } else {
        products = await _revenueCat.getProducts();
      }

      state = state.copyWith(
        isSubscribed: isSubscribed,
        products: products,
        isLoading: false,
        selectedPackage: products?.first,
        customerInfo: customerInfo,
      );
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  Future<void> purchaseSubscription(Package package) async {
    try {
      final success = await _revenueCat.purchaseSubscription(package);
      state = state.copyWith(
        isSubscribed: success,
        isLoading: false,
        error: success ? null : 'Purchase failed',
      );
      if (success) {
        ref.read(premiumPopupProvider.notifier).hide();
      }
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  Future<void> checkSubscriptionAnsShowPopup() async {
    final isSubscribed = await _revenueCat.isSubscribed();
    if(!isSubscribed){
      ref.read(premiumPopupProvider.notifier).show();
    }
    state = state.copyWith(isSubscribed: isSubscribed);
  }

  Future<void> restorePurchases() async {
    state = state.copyWith(isLoading: true);

    try {
      final success = await _revenueCat.restorePurchases();
      state = state.copyWith(isSubscribed: success, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }

  Future<void> cancel() async {
      await _revenueCat.cancelSubscription();
  }
}

class SubscriptionState {
  final bool isSubscribed;
  final bool isLoading;
  final List<Package> products;
  final Package? selectedPackage;
  final String? error;
  final CustomerInfo? customerInfo;

  SubscriptionState({
    this.isSubscribed = false,
    this.isLoading = false,
    this.products = const [],
    this.selectedPackage,
    this.error,
    this.customerInfo,
  });

  SubscriptionState copyWith({
    bool? isSubscribed,
    bool? isLoading,
    List<Package>? products,
    String? error,
    Package? selectedPackage,
    CustomerInfo? customerInfo,
  }) {
    return SubscriptionState(
      isSubscribed: isSubscribed ?? this.isSubscribed,
      isLoading: isLoading ?? this.isLoading,
      products: products ?? this.products,
      error: error ?? this.error,
      selectedPackage: selectedPackage ?? this.selectedPackage,
      customerInfo: customerInfo ?? this.customerInfo,
    );
  }
}
