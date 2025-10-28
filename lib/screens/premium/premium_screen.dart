import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/premium/widget/buy_premium_card.dart';
import 'package:chessever2/screens/premium/widget/subscription_info_card.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      ref.read(subscriptionProvider.notifier).initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final subscriptionState = ref.watch(subscriptionProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (subscriptionState.isLoading) ...[
          Card(
            child: SizedBox(
              height: MediaQuery.of(context).size.height / 2,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
        ] else ...[
          if (subscriptionState.isSubscribed &&
              subscriptionState.customerInfo != null)
            SubscriptionInfoWidget(
              customerInfo: subscriptionState.customerInfo!,
            )
          else
            BuyPremiumCard(subscriptionState: subscriptionState),
        ],
      ],
    );
  }
}
