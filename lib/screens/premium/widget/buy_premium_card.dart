import 'package:chessever2/utils/extensioms/string_extensions.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:purchases_flutter/models/package_wrapper.dart';

import '../../../revenue_cat_service/subscribe_state.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_typography.dart';
import '../../../utils/get_title_by_subscription_type.dart';
import '../../../utils/svg_asset.dart';
import '../../../widgets/app_button.dart';
import '../feature_row.dart';

class BuyPremiumCard extends ConsumerWidget {
  const BuyPremiumCard({super.key, required this.subscriptionState});

  final SubscriptionState subscriptionState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
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
            style: AppTypography.textLgMedium.copyWith(
              color: kWhiteColor,
            ),
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

          if (subscriptionState.selectedPackage != null)
            _PricingCard(
              package: subscriptionState.selectedPackage!,
              packages: subscriptionState.products,
            ),

          const SizedBox(height: 16),

          SizedBox(
            width: MediaQuery.of(context).size.width,
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ...subscriptionState.products.map((package) {
                    return _PackageCard(
                      onTap: () {
                        ref
                            .read(subscriptionProvider.notifier)
                            .selectPackage(package);
                      },
                      type: package.packageType,
                      selected:
                      package.packageType ==
                          subscriptionState.selectedPackage!.packageType,
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          AppButton(
            text: 'Subscribe',
            onPressed: () {
              ref
                  .read(subscriptionProvider.notifier)
                  .purchaseSubscription(
                subscriptionState.selectedPackage!,
              );
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
    );
  }
}



class _PackageCard extends ConsumerWidget {
  const _PackageCard({
    super.key,
    required this.type,
    this.selected = false,
    this.onTap,
  });

  final PackageType type;
  final bool? selected;
  final Function()? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: selected! ? Border.all(color: Colors.white, width: 1) : null,
        ),
        padding: EdgeInsets.symmetric(horizontal: 40, vertical: 6),
        child: Text(
          getTitleBySubscriptionTye(type).capitalize(),
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}

class _PricingCard extends StatefulWidget {
  const _PricingCard({
    super.key,
    required this.package,
    required this.packages,
  });

  final Package package;
  final List<Package> packages;

  @override
  State<_PricingCard> createState() => _PricingCardState();
}

class _PricingCardState extends State<_PricingCard> {
  late Package monthlyPackage;

  @override
  void initState() {
    monthlyPackage = widget.packages.singleWhere(
          (element) => element.packageType == PackageType.monthly,
    );
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Pricing
        if (widget.package.packageType != PackageType.monthly) ...[
          Text(
            '${monthlyPackage.storeProduct.priceString}/month',
            style: AppTypography.textSmRegular.copyWith(
              color: kWhiteColor,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          Text(
            '\$${(widget.package.storeProduct.price / 12).toStringAsFixed(2)}/month',
            style: AppTypography.textXlRegular.copyWith(color: kWhiteColor),
          ),
        ] else ...[
          Text(
            '\$${(widget.package.storeProduct.price).toStringAsFixed(2)}/month',
            style: AppTypography.textXlRegular.copyWith(color: kWhiteColor),
          ),
        ],
      ],
    );
  }
}

