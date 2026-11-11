import 'package:chessever2/widgets/paywall/premium_paywall_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

Package package(PackageType type, double price, String label) => Package(
  type.name,
  type,
  StoreProduct(type.name, '', '', price, label, 'USD'),
  const PresentedOfferingContext('default', null, null),
);

void main() {
  for (final size in [
    const Size(390, 844),
    const Size(375, 667),
    const Size(360, 640),
  ]) {
    for (final trigger in PaywallTrigger.values) {
      testWidgets(
        '$trigger at $size keeps checkout pinned and updates renewal',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final plan = ValueNotifier(PlanType.annual);
          addTearDown(plan.dispose);
          var purchases = 0;
          await tester.pumpWidget(
            MaterialApp(
              home: ValueListenableBuilder<PlanType>(
                valueListenable: plan,
                builder: (_, selected, _) => PremiumPaywallView(
                  trigger: trigger,
                  plan: selected,
                  annual: package(PackageType.annual, 119.99, r'$119.99'),
                  monthly: package(PackageType.monthly, 11.99, r'$11.99'),
                  busy: false,
                  loadingProducts: false,
                  onSelect: (value) => plan.value = value,
                  onPurchase: () => purchases++,
                  onRestore: () {},
                  onRedeem: () {},
                  onClose: () {},
                  onRetry: () {},
                  onOpenUrl: (_) {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final headline = switch (trigger) {
            PaywallTrigger.settings => 'Your chess.\nWithout limits.',
            PaywallTrigger.favorites => 'Follow every player\nyou care about.',
            PaywallTrigger.database => 'Keep every game\nyou play.',
          };
          expect(find.text(headline), findsOneWidget);
          expect(find.text('SAVE 17%'), findsOneWidget);
          expect(
            find.textContaining(r'Renews at $119.99/year'),
            findsOneWidget,
          );
          final checkoutTop = tester.getTopLeft(find.text('Annual')).dy;
          await tester.drag(
            find.byType(SingleChildScrollView).first,
            const Offset(0, -200),
          );
          await tester.pumpAndSettle();
          expect(tester.getTopLeft(find.text('Annual')).dy, checkoutTop);
          for (final link in [
            'Get Premium',
            'Restore purchases',
            'Privacy',
            'Terms',
          ]) {
            expect(find.text(link).hitTestable(), findsOneWidget);
          }
          await tester.tap(find.text('Monthly'));
          await tester.pumpAndSettle();
          expect(
            find.textContaining(r'Renews at $11.99/month'),
            findsOneWidget,
          );
          await tester.tap(find.text('Get Premium'));
          expect(purchases, 1);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
