import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:intl/intl.dart';

import '../../../revenue_cat_service/subscribe_state.dart';
import '../../../widgets/app_button.dart';

class SubscriptionInfoWidget extends ConsumerWidget {
  final CustomerInfo customerInfo;

  const SubscriptionInfoWidget({super.key, required this.customerInfo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get active subscriptions
    final activeSubscriptions = customerInfo.entitlements.active;

    if (activeSubscriptions.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('No active subscription'),
        ),
      );
    }

    // Get the first active subscription (you can loop through all if needed)
    final subscription = activeSubscriptions.values.first;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 10),
            Text(
              subscription.identifier,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildInfoRow(
              'Status',
              subscription.isActive ? '✓ Active' : 'Inactive',
            ),
            _buildInfoRow(
              'Plan',
              _formatProductId(subscription.productIdentifier),
            ),
            _buildInfoRow('Will Renew', subscription.willRenew ? 'Yes' : 'No'),
            if (subscription.expirationDate != null)
              _buildInfoRow(
                'Expires',
                DateFormat(
                  'MMM dd, yyyy HH:mm',
                ).format(DateTime.parse(subscription.expirationDate!).toLocal()),
              ),
            if (subscription.latestPurchaseDate != null)
              _buildInfoRow(
                'Purchased',
                DateFormat(
                  'MMM dd, yyyy',
                ).format(DateTime.parse(subscription.latestPurchaseDate!)),
              ),
            SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: MediaQuery.of(context).size.width / 2,
                child: AppButton(
                  text: 'Cancel',
                  onPressed: () {
                    ref.read(subscriptionProvider.notifier).cancel();
                    // Handle the button press
                  },
                  height: 48,
                  width: double.infinity,
                  borderRadius: 12,
                ),
              ),
            ),
            SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ],
      ),
    );
  }

  String _formatProductId(String productId) {
    // Convert "rc_chessever_annual" to "Annual"
    if (productId.contains('annual')) return 'Annual';
    if (productId.contains('monthly')) return 'Monthly';
    return productId;
  }
}
