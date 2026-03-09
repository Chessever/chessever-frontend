import 'package:chessever2/e2e/e2e_ids.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/premium/feature_row.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/back_drop_filter_widget.dart';
import 'package:chessever2/widgets/app_button.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:chessever2/utils/svg_asset.dart';
import 'package:chessever2/theme/app_theme.dart';

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
      return Scaffold(
        key: e2eKey(E2eIds.premiumRoot),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (subscriptionState.isSubscribed) {
      return Scaffold(
        key: e2eKey(E2eIds.premiumRoot),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.workspace_premium_rounded,
                color: kPrimaryColor,
                size: 40.ic,
              ),
              SizedBox(height: 12.h),
              Text(
                'Premium active',
                style: AppTypography.textLgMedium.copyWith(color: kWhiteColor),
              ),
              SizedBox(height: 8.h),
              Text(
                'This account already has access to premium features.',
                textAlign: TextAlign.center,
                style: AppTypography.textSmBold.copyWith(
                  color: kBoardColorGrey,
                ),
              ),
            ],
          ),
        ),
      );
    }
    final horizontalPadding = ResponsiveHelper.adaptive(
      phone: 24.0,
      tablet: 32.0,
    );

    return KeyedSubtree(
      key: e2eKey(E2eIds.premiumRoot),
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          BackDropFilterWidget(),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: ResponsiveHelper.isTablet ? 500 : double.infinity,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(24.br),
                  ),
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: 16.h,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40.w,
                      height: 4.h,
                      decoration: BoxDecoration(
                        color: kWhiteColor70,
                        borderRadius: BorderRadius.circular(2.br),
                      ),
                    ),
                    SizedBox(height: 16.h),

                    Text(
                      'Premium',
                      style: AppTypography.textLgMedium.copyWith(
                        color: kWhiteColor,
                      ),
                    ),
                    SizedBox(height: 12.h),

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
                    SizedBox(height: 24.h),

                    // Feature list
                    FeatureRow(
                      icon: SvgAsset.libary_book,
                      text: 'Unlock Library & Database features',
                      iconColor: Colors.cyanAccent,
                    ),
                    SizedBox(height: 12.h),
                    FeatureRow(
                      icon: SvgAsset.tour_list,
                      text: 'Fully customizable tournament list',
                      iconColor: Colors.greenAccent,
                    ),
                    SizedBox(height: 12.h),
                    FeatureRow(
                      icon: SvgAsset.zero_ads,
                      text: 'Zero Ads',
                      iconColor: Colors.redAccent,
                    ),
                    SizedBox(height: 24.h),

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
                      style: AppTypography.textXlRegular.copyWith(
                        color: kWhiteColor,
                      ),
                    ),

                    SizedBox(height: 16.h),

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
                    SizedBox(height: 20.h),

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
                      height: 48.h,
                      width: double.infinity,
                      borderRadius: 12.br,
                    ),
                    SizedBox(height: 12.h),

                    Text(
                      "You'll be billed at the end of your free trial. Feel free to cancel anytime through Google Play.",
                      textAlign: TextAlign.center,
                      style: AppTypography.textSmBold.copyWith(
                        color: kBoardColorGrey,
                      ),
                    ),
                    SizedBox(height: 16.h),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
