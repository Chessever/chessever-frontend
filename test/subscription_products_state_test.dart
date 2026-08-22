import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unrelated subscription updates preserve the offerings error', () {
    final failed = SubscriptionState(
      productsError: "Couldn't load plans.",
      isLoadingProducts: false,
    );

    final entitlementUpdate = failed.copyWith(isLoading: false);

    expect(entitlementUpdate.productsError, "Couldn't load plans.");
  });

  test('an offerings retry can explicitly clear the previous error', () {
    final failed = SubscriptionState(
      productsError: "Couldn't load plans.",
      isLoadingProducts: false,
    );

    final retrying = failed.copyWith(
      clearProductsError: true,
      isLoadingProducts: true,
    );

    expect(retrying.productsError, isNull);
  });
}
