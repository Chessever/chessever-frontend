import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chessever2/screens/premium/feature_row.dart';
import 'package:chessever2/screens/premium/plan_toggle_button.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:flutter/material.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:flutter_svg/flutter_svg.dart';

class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  @override
  Widget build(BuildContext context) {
    final subscriptionState = ref.watch(subscriptionProvider);
    if (subscriptionState.isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (subscriptionState.isSubscribed) {
      return Scaffold(
        body: Center(
          child: Text(
            'Error loading subscription state',
            style: AppTypography.textSmBold.copyWith(color: kBoardColorGrey),
          ),
        ),
      );
    }
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        BackDropFilterWidget(),
        Container(
          decoration: const BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kWhiteColor70,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'Premium',
                style: AppTypography.textLgMedium.copyWith(color: kWhiteColor),
              ),
              const SizedBox(height: 12),

              Align(
                alignment: Alignment.topLeft,
                child: Text(
                  'You are currently on the free plan. upgrade to\npremium to access cool features',
                  textAlign: TextAlign.start,
                  style: AppTypography.textSmBold.copyWith(
                    color: kBoardColorGrey,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Feature list
              FeatureRow(
                icon: SvgAsset.libary_book,
                text: 'Unlock Library & Database features',
                iconColor: Colors.cyanAccent,
              ),
              const SizedBox(height: 12),
              FeatureRow(
                icon: SvgAsset.tour_list,
                text: 'Fully customizable tournament list',
                iconColor: Colors.greenAccent,
              ),
              const SizedBox(height: 12),
              FeatureRow(
                icon: SvgAsset.zero_ads,
                text: 'Zero Ads',
                iconColor: Colors.redAccent,
              ),
              const SizedBox(height: 24),

              // Pricing
              Text(
                '\$8.99/month',
                style: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor,
                  decoration: TextDecoration.lineThrough,
                ),

                // style: TextStyle(
                //   decoration: TextDecoration.lineThrough,
                //   color: Colors.grey,
                // ),
              ),
              Text(
                '\$58.99/year',
                style: AppTypography.textXlRegular.copyWith(color: kWhiteColor),
              ),

              const SizedBox(height: 16),

              ...subscriptionState.products.map(
                (package) => Card(
                  child: ListTile(
                    title: Text(package.storeProduct.title),
                    subtitle: Text(package.storeProduct.description),
                    trailing: Text(package.storeProduct.priceString),
                    onTap:
                        () => ref
                            .read(subscriptionProvider.notifier)
                            .purchaseSubscription(package),
                  ),
                ),
              ),
              // Row(
              //   mainAxisAlignment: MainAxisAlignment.center,
              //   children: [
              //     PlanToggleButton(
              //       isSelected: true,
              //       text: 'Yearly',
              //       onTap: () {},
              //     ),
              //     const SizedBox(width: 12),
              //     PlanToggleButton(
              //       isSelected: false,
              //       text: 'Monthly',
              //       onTap: () {},
              //     ),
              //   ],
              // ),
              const SizedBox(height: 20),

              // Try for free button
              // SizedBox(
              //   width: double.infinity,
              //   child: _PremiumButton(
              //     onPressed: () {},
              //     style: ElevatedButton.styleFrom(
              //       backgroundColor: Colors.cyan,
              //       foregroundColor: Colors.black,
              //       padding: const EdgeInsets.symmetric(vertical: 14),
              //       shape: RoundedRectangleBorder(
              //         borderRadius: BorderRadius.circular(12),
              //       ),
              //     ),
              //     child: Text(
              //       'Try for free',
              //       style: AppTypography.textLgMedium.copyWith(
              //         color: kBlackColor,
              //       ),
              //     ),
              //   ),
              // ),
              AppButton(
                text: 'Try for free',
                onPressed: () {
                  // Handle the button press
                },
                height: 48,
                width: double.infinity,
                borderRadius: 12,
              ),
              const SizedBox(height: 12),

              Text(
                "You'll be billed at the end of your free trial. Feel free to cancel anytime through Google Play.",
                textAlign: TextAlign.center,
                style: AppTypography.textSmBold.copyWith(
                  color: kBoardColorGrey,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ],
    );
  }
}
