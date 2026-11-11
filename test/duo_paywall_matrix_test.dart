import 'package:chessever2/widgets/paywall/premium_paywall_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'fixtures/duo_window_matrix.dart';

Package _package(PackageType type, double price, String label) => Package(
  type.name,
  type,
  StoreProduct(type.name, '', '', price, label, 'USD'),
  const PresentedOfferingContext('default', null, null),
);

Widget _paywall({String? error, String? productsError}) => PremiumPaywallView(
  plan: PlanType.annual,
  annual: _package(PackageType.annual, 119.99, r'$119.99'),
  monthly: _package(PackageType.monthly, 11.99, r'$11.99'),
  busy: false,
  loadingProducts: false,
  error: error,
  productsError: productsError,
  onSelect: (_) {},
  onPurchase: () {},
  onRestore: () {},
  onRedeem: () {},
  onClose: () {},
  onRetry: () {},
  onOpenUrl: (_) {},
);

void main() {
  for (final window in duoWindowCases) {
    for (final scale in [1.0, 1.3]) {
      for (final errors in [false, true]) {
        testWidgets('paywall fits ${window.name} at ${scale}x text'
            '${errors ? ' with errors' : ''}', (tester) async {
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          applyDuoWindow(tester, window);
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery.withClampedTextScaling(
                minScaleFactor: scale,
                maxScaleFactor: scale,
                child: _paywall(
                  error: errors ? 'Purchase failed. Try again.' : null,
                  productsError: errors
                      ? 'Could not load plans. Check your connection.'
                      : null,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.bySemanticsLabel('Close'), findsOneWidget);
          // Every checkout control is reachable: in the shortest windows the
          // pinned checkout scrolls within itself.
          for (final label in ['Get Premium', 'Privacy', 'Terms']) {
            await tester.ensureVisible(find.text(label));
            await tester.pumpAndSettle();
            expect(
              find.text(label).hitTestable(),
              findsOneWidget,
              reason: label,
            );
          }
        });
      }
    }
  }
}
