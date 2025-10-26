import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/premium/widget/buy_premium_card.dart';
import 'package:chessever2/screens/premium/widget/subscription_info_card.dart';
import 'package:chessever2/utils/extensioms/string_extensions.dart';
import 'package:chessever2/widgets/app_button.dart';

import 'package:chessever2/screens/premium/feature_row.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:purchases_flutter/models/package_wrapper.dart';

import '../../utils/get_title_by_subscription_type.dart';

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
    if (subscriptionState.isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    // if (subscriptionState.isSubscribed) {
    //   return Scaffold(
    //     body: Center(
    //       child: Text(
    //         'Error loading subscription state',
    //         style: AppTypography.textSmBold.copyWith(color: kBoardColorGrey),
    //       ),
    //     ),
    //   );
    // }
    return Scaffold(
      body: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          BackDropFilterWidget(),
          if (subscriptionState.isSubscribed &&
              subscriptionState.customerInfo != null)
            SubscriptionInfoWidget(
              customerInfo: subscriptionState.customerInfo!,
            )
          else
            BuyPremiumCard(subscriptionState: subscriptionState),
        ],
      ),
    );
  }
}
