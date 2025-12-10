import 'dart:math' as math;

import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/chessboard/widgets/smooth_sheet_config.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:smooth_sheets/smooth_sheets.dart';

/// Show the premium paywall sheet.
/// Returns `true` if the user successfully subscribed.
Future<bool> showPremiumPaywallSheet({required BuildContext context}) async {
  final padding = MediaQuery.viewPaddingOf(context);
  final route = SpringModalSheetRoute<bool>(
    builder: (_) => _PremiumPaywallSheet(hostContext: context),
    springCurve: ChessSheetCurves.bouncy,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    barrierLabel: 'Close paywall',
    viewportPadding: EdgeInsets.only(top: padding.top),
  );

  final result = await Navigator.of(context).push<bool>(route);
  return result ?? false;
}

/// Guard that checks subscription and shows paywall if needed.
/// Returns true if user has premium or just subscribed.
Future<bool> requirePremiumGuard(BuildContext context, WidgetRef ref) async {
  final subscriptionState = ref.read(subscriptionProvider);
  if (subscriptionState.isSubscribed) return true;

  return await showPremiumPaywallSheet(context: context);
}

class _PremiumPaywallSheet extends HookWidget {
  const _PremiumPaywallSheet({required this.hostContext});

  final BuildContext hostContext;

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator(
      onGenerateInitialRoutes:
          (_, __) => [
            SpringPagedSheetRoute(
              scrollConfiguration: const SheetScrollConfiguration(),
              dragConfiguration: ChessSheetConfigs.commentEditor,
              initialOffset: const SheetOffset.proportionalToViewport(0.92),
              snapGrid: SheetSnapGrid(
                snaps: const [
                  SheetOffset.proportionalToViewport(0.7),
                  SheetOffset.proportionalToViewport(0.95),
                ],
                minFlingSpeed: 600.0,
              ),
              builder: (_) => _PaywallContent(hostContext: hostContext),
            ),
          ],
    );

    return SheetKeyboardDismissible(
      dismissBehavior: const DragDownSheetKeyboardDismissBehavior(
        isContentScrollAware: true,
      ),
      child: PagedSheet(
        decoration: ChessSheetDecoration.dark(alpha: 0.98, borderRadius: 28.sp),
        shrinkChildToAvoidDynamicOverlap: true,
        navigator: navigator,
      ),
    );
  }
}

class _PaywallContent extends HookConsumerWidget {
  const _PaywallContent({required this.hostContext});

  final BuildContext hostContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topPadding = MediaQuery.of(context).padding.top;
    final subscriptionState = ref.watch(subscriptionProvider);
    final selectedPlan = useState<PlanType>(PlanType.annual);
    final isLoading = useState(false);

    // Find monthly and annual packages
    Package? monthlyPackage;
    Package? annualPackage;

    for (final package in subscriptionState.products) {
      if (package.packageType == PackageType.monthly) {
        monthlyPackage = package;
      } else if (package.packageType == PackageType.annual) {
        annualPackage = package;
      }
    }

    Future<void> handlePurchase() async {
      final package =
          selectedPlan.value == PlanType.annual
              ? annualPackage
              : monthlyPackage;

      if (package == null) return;

      isLoading.value = true;
      await ref
          .read(subscriptionProvider.notifier)
          .purchaseSubscription(package);
      isLoading.value = false;

      final newState = ref.read(subscriptionProvider);
      if (newState.isSubscribed) {
        if (hostContext.mounted) {
          Navigator.of(hostContext).pop(true);
        }
      }
    }

    Future<void> handleRestore() async {
      isLoading.value = true;
      await ref.read(subscriptionProvider.notifier).restorePurchases();
      isLoading.value = false;

      final newState = ref.read(subscriptionProvider);
      if (newState.isSubscribed) {
        if (hostContext.mounted) {
          Navigator.of(hostContext).pop(true);
        }
      }
    }

    return Stack(
      children: [
        const Positioned.fill(child: _PremiumAmbientGlow()),
        const Positioned.fill(child: _FloatingChessParticles()),
        MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.fromLTRB(20.w, topPadding + 16.h, 20.w, 24.h),
              child: Column(
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 36.w,
                      height: 4.h,
                      decoration: BoxDecoration(
                        color: kWhiteColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2.br),
                      ),
                    ),
                  ),
                  SizedBox(height: 12.h),
                  // Close button
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () => Navigator.of(hostContext).pop(false),
                      child: Container(
                        padding: EdgeInsets.all(8.sp),
                        decoration: BoxDecoration(
                          color: kWhiteColor.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          color: kWhiteColor.withValues(alpha: 0.6),
                          size: 20.ic,
                        ),
                      ),
                    ),
                  ),
                  // Blurred background preview
                  _BackgroundPreview()
                      .animate()
                      .fadeIn(duration: 500.ms, curve: Curves.easeOut)
                      .scale(begin: const Offset(0.92, 0.92)),
                  SizedBox(height: 20.h),
                  // Title
                  Text(
                        'Everything chess,\nunlocked.',
                        textAlign: TextAlign.center,
                        style: AppTypography.displayXsBold.copyWith(
                          color: kWhiteColor,
                          height: 1.15,
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 100.ms, duration: 400.ms)
                      .slideY(begin: 0.1, end: 0),
                  SizedBox(height: 24.h),
                  // Features
                  _FeaturesList()
                      .animate()
                      .fadeIn(delay: 200.ms, duration: 400.ms)
                      .slideY(begin: 0.1, end: 0),
                  SizedBox(height: 28.h),
                  // Pricing cards
                  _PricingSection(
                        selectedPlan: selectedPlan,
                        monthlyPackage: monthlyPackage,
                        annualPackage: annualPackage,
                      )
                      .animate()
                      .fadeIn(delay: 300.ms, duration: 400.ms)
                      .slideY(begin: 0.1, end: 0),
                  SizedBox(height: 24.h),
                  // CTA Button
                  _PurchaseButton(
                        selectedPlan: selectedPlan.value,
                        monthlyPackage: monthlyPackage,
                        annualPackage: annualPackage,
                        isLoading:
                            isLoading.value || subscriptionState.isLoading,
                        onTap: handlePurchase,
                      )
                      .animate()
                      .fadeIn(delay: 400.ms, duration: 400.ms)
                      .slideY(begin: 0.1, end: 0),
                  SizedBox(height: 12.h),
                  // Restore purchases
                  GestureDetector(
                    onTap: isLoading.value ? null : handleRestore,
                    child: Text(
                      'Restore purchases',
                      style: AppTypography.textSmMedium.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  // Legal text
                  Text(
                    'Cancel anytime. Subscription auto-renews.',
                    textAlign: TextAlign.center,
                    style: AppTypography.textXsRegular.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.35),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () {
                          // TODO: Open terms
                        },
                        child: Text(
                          'Terms',
                          style: AppTypography.textXsRegular.copyWith(
                            color: kWhiteColor.withValues(alpha: 0.35),
                            decoration: TextDecoration.underline,
                            decorationColor: kWhiteColor.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        '  •  ',
                        style: AppTypography.textXsRegular.copyWith(
                          color: kWhiteColor.withValues(alpha: 0.35),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          // TODO: Open privacy
                        },
                        child: Text(
                          'Privacy',
                          style: AppTypography.textXsRegular.copyWith(
                            color: kWhiteColor.withValues(alpha: 0.35),
                            decoration: TextDecoration.underline,
                            decorationColor: kWhiteColor.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12.h),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BackgroundPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120.h,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.br),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            kBlack2Color.withValues(alpha: 0.8),
            kBlack2Color.withValues(alpha: 0.4),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Blurred menu items preview
          Positioned(
            left: 16.w,
            top: 16.h,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BlurredMenuItem(
                  icon: Icons.settings_outlined,
                  label: 'Settings',
                ),
                SizedBox(height: 8.h),
                _BlurredMenuItem(
                  icon: Icons.people_outline_rounded,
                  label: 'Players',
                ),
                SizedBox(height: 8.h),
                _BlurredMenuItem(
                  icon: Icons.favorite_outline_rounded,
                  label: 'Favorites',
                ),
              ],
            ),
          ),
          // Premium badge overlay
          Positioned(
            right: 16.w,
            top: 16.h,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                ),
                borderRadius: BorderRadius.circular(12.br),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                    blurRadius: 8,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.workspace_premium_rounded,
                    size: 14.ic,
                    color: kBlackColor,
                  ),
                  SizedBox(width: 4.w),
                  Text(
                    'PRO',
                    style: AppTypography.textXsBold.copyWith(
                      color: kBlackColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Filter icon
          Positioned(
            right: 20.w,
            bottom: 20.h,
            child: Container(
              padding: EdgeInsets.all(8.sp),
              decoration: BoxDecoration(
                color: kWhiteColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8.br),
              ),
              child: Icon(
                Icons.filter_list_rounded,
                color: kWhiteColor.withValues(alpha: 0.4),
                size: 18.ic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlurredMenuItem extends StatelessWidget {
  const _BlurredMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18.ic, color: kWhiteColor.withValues(alpha: 0.5)),
        SizedBox(width: 8.w),
        Text(
          label,
          style: AppTypography.textSmRegular.copyWith(
            color: kWhiteColor.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }
}

class _FeaturesList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final features = [
      _FeatureData(
        icon: Icons.local_library_outlined,
        title: 'Full Library Access',
        subtitle:
            'Explore openings, players, tournaments,\nand historical games in one place.',
      ),
      _FeatureData(
        icon: Icons.grid_view_rounded,
        title: 'Advanced Analysis Tools',
        subtitle:
            'Instant insights, faster evaluations, clearer\nmove understanding.',
      ),
      _FeatureData(
        icon: Icons.auto_stories_outlined,
        title: 'Book Mode',
        subtitle:
            'Study positions like a real chess manual—\nclean, focused, distraction-free.',
      ),
    ];

    return Column(
      children:
          features.asMap().entries.map((entry) {
            final index = entry.key;
            final feature = entry.value;
            return Padding(
              padding: EdgeInsets.only(
                bottom: index < features.length - 1 ? 16.h : 0,
              ),
              child: _FeatureItem(data: feature),
            );
          }).toList(),
    );
  }
}

class _FeatureData {
  const _FeatureData({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

class _FeatureItem extends StatelessWidget {
  const _FeatureItem({required this.data});

  final _FeatureData data;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40.w,
          height: 40.h,
          decoration: BoxDecoration(
            color: kWhiteColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10.br),
          ),
          child: Center(
            child: Icon(
              data.icon,
              size: 22.ic,
              color: kWhiteColor.withValues(alpha: 0.9),
            ),
          ),
        ),
        SizedBox(width: 14.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.title,
                style: AppTypography.textMdMedium.copyWith(color: kWhiteColor),
              ),
              SizedBox(height: 2.h),
              Text(
                data.subtitle,
                style: AppTypography.textSmRegular.copyWith(
                  color: kWhiteColor.withValues(alpha: 0.5),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum PlanType { monthly, annual }

class _PricingSection extends HookWidget {
  const _PricingSection({
    required this.selectedPlan,
    required this.monthlyPackage,
    required this.annualPackage,
  });

  final ValueNotifier<PlanType> selectedPlan;
  final Package? monthlyPackage;
  final Package? annualPackage;

  @override
  Widget build(BuildContext context) {
    // Calculate savings
    double? monthlyCost;
    double? annualCost;
    int savingsPercent = 0;
    String? fakeMonthlyFromAnnual;

    if (monthlyPackage != null) {
      monthlyCost = monthlyPackage!.storeProduct.price;
    }
    if (annualPackage != null) {
      annualCost = annualPackage!.storeProduct.price;
    }

    if (monthlyCost != null && annualCost != null) {
      final yearlyIfMonthly = monthlyCost * 12;
      savingsPercent =
          ((yearlyIfMonthly - annualCost) / yearlyIfMonthly * 100).round();
      fakeMonthlyFromAnnual = '\$${(annualCost / 12).toStringAsFixed(2)}';
    }

    // Don't render pricing cards if packages aren't loaded
    final hasPackages = monthlyPackage != null && annualPackage != null;

    return Row(
      children: [
        // Monthly card
        Expanded(
          child: _PricingCard(
            isSelected: selectedPlan.value == PlanType.monthly,
            title: 'Monthly',
            price: monthlyPackage?.storeProduct.priceString,
            period: '/month',
            isLoading: !hasPackages,
            onTap:
                hasPackages
                    ? () => selectedPlan.value = PlanType.monthly
                    : null,
          ),
        ),
        SizedBox(width: 12.w),
        // Annual card
        Expanded(
          child: _PricingCard(
            isSelected: selectedPlan.value == PlanType.annual,
            title: 'Annual',
            price: annualPackage?.storeProduct.priceString,
            period: '/yr',
            badge: savingsPercent > 0 ? 'Save $savingsPercent%' : null,
            monthlyEquivalent: fakeMonthlyFromAnnual,
            fakeOriginalPrice:
                monthlyCost != null
                    ? '\$${(monthlyCost * 12).toStringAsFixed(0)}'
                    : null,
            isLoading: !hasPackages,
            onTap:
                hasPackages ? () => selectedPlan.value = PlanType.annual : null,
          ),
        ),
      ],
    );
  }
}

class _PricingCard extends HookWidget {
  const _PricingCard({
    required this.isSelected,
    required this.title,
    required this.period,
    this.price,
    this.onTap,
    this.badge,
    this.monthlyEquivalent,
    this.fakeOriginalPrice,
    this.isLoading = false,
  });

  final bool isSelected;
  final String title;
  final String? price;
  final String period;
  final VoidCallback? onTap;
  final String? badge;
  final String? monthlyEquivalent;
  final String? fakeOriginalPrice;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isPressed = useState(false);
    final showLoading = isLoading || price == null;

    return GestureDetector(
      onTapDown: showLoading ? null : (_) => isPressed.value = true,
      onTapUp:
          showLoading
              ? null
              : (_) {
                isPressed.value = false;
                onTap?.call();
              },
      onTapCancel: showLoading ? null : () => isPressed.value = false,
      child: AnimatedScale(
        scale: isPressed.value ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          // Fixed height prevents layout shift when switching plans
          constraints: BoxConstraints(minHeight: 110.h),
          padding: EdgeInsets.all(16.sp),
          decoration: BoxDecoration(
            color:
                isSelected
                    ? kWhiteColor.withValues(alpha: 0.12)
                    : kWhiteColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16.br),
            border: Border.all(
              color:
                  isSelected
                      ? kWhiteColor.withValues(alpha: 0.3)
                      : kWhiteColor.withValues(alpha: 0.08),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: AppTypography.textSmMedium.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.7),
                    ),
                  ),
                  if (badge != null)
                    Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8.w,
                            vertical: 3.h,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF4ADE80), Color(0xFF22C55E)],
                            ),
                            borderRadius: BorderRadius.circular(6.br),
                          ),
                          child: Text(
                            badge!,
                            style: AppTypography.textXxsBold.copyWith(
                              color: kBlackColor,
                            ),
                          ),
                        )
                        .animate(onPlay: (c) => c.repeat())
                        .shimmer(
                          duration: 2000.ms,
                          color: kWhiteColor.withValues(alpha: 0.4),
                          angle: 0.5,
                        )
                        .scaleXY(
                          end: 1.05,
                          duration: 1000.ms,
                          curve: Curves.easeInOut,
                        )
                        .then()
                        .scaleXY(
                          end: 1.0,
                          duration: 1000.ms,
                          curve: Curves.easeInOut,
                        ),
                ],
              ),
              SizedBox(height: 8.h),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (showLoading)
                    Container(
                      width: 60.w,
                      height: 28.h,
                      decoration: BoxDecoration(
                        color: kWhiteColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6.br),
                      ),
                    )
                  else
                    Text(
                      price!,
                      style: AppTypography.displayXsBold.copyWith(
                        color: kWhiteColor,
                      ),
                    ),
                  Padding(
                    padding: EdgeInsets.only(bottom: 4.h),
                    child: Text(
                      period,
                      style: AppTypography.textSmRegular.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              ),
              // FOMO: Show strikethrough original price for annual
              if (fakeOriginalPrice != null && !showLoading) ...[
                SizedBox(height: 4.h),
                Row(
                  children: [
                    Text(
                      fakeOriginalPrice!,
                      style: AppTypography.textXsRegular.copyWith(
                        color: kWhiteColor.withValues(alpha: 0.35),
                        decoration: TextDecoration.lineThrough,
                        decorationColor: kWhiteColor.withValues(alpha: 0.35),
                      ),
                    ),
                    if (monthlyEquivalent != null) ...[
                      SizedBox(width: 6.w),
                      Text(
                        '$monthlyEquivalent/mo',
                        style: AppTypography.textXsMedium.copyWith(
                          color: const Color(0xFF4ADE80),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PurchaseButton extends HookWidget {
  const _PurchaseButton({
    required this.selectedPlan,
    required this.monthlyPackage,
    required this.annualPackage,
    required this.isLoading,
    required this.onTap,
  });

  final PlanType selectedPlan;
  final Package? monthlyPackage;
  final Package? annualPackage;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPressed = useState(false);

    // Check for trial eligibility from RevenueCat SDK
    final selectedPackage =
        selectedPlan == PlanType.annual ? annualPackage : monthlyPackage;
    final storeProduct = selectedPackage?.storeProduct;

    // iOS: Check introductoryPrice for free trial
    final introPrice = storeProduct?.introductoryPrice;
    final hasIosFreeTrial = introPrice != null && introPrice.price == 0;

    // Android: Check defaultOption.freePhase for free trial
    final freePhase = storeProduct?.defaultOption?.freePhase;
    final hasAndroidFreeTrial = freePhase != null;

    String buttonText;
    if (hasIosFreeTrial) {
      // iOS trial info from introductoryPrice
      final trialCount = introPrice.periodNumberOfUnits;
      final periodUnit = introPrice.periodUnit;
      final unitString = _getPeriodUnitString(periodUnit, trialCount);

      buttonText =
          trialCount > 0
              ? 'Start $trialCount $unitString free trial'
              : 'Start free trial';
    } else if (hasAndroidFreeTrial) {
      // Android trial info from freePhase.billingPeriod
      final billingPeriod = freePhase.billingPeriod;
      if (billingPeriod != null) {
        final trialCount = billingPeriod.value;
        final periodUnit = billingPeriod.unit;
        final unitString = _getPeriodUnitString(periodUnit, trialCount);

        buttonText =
            trialCount > 0
                ? 'Start $trialCount $unitString free trial'
                : 'Start free trial';
      } else {
        buttonText = 'Start free trial';
      }
    } else {
      buttonText = 'Continue';
    }

    return GestureDetector(
      onTapDown: (_) => isPressed.value = true,
      onTapUp: (_) {
        isPressed.value = false;
        if (!isLoading) onTap();
      },
      onTapCancel: () => isPressed.value = false,
      child: AnimatedScale(
        scale: isPressed.value ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
              width: double.infinity,
              height: 54.h,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14.br),
                color: kWhiteColor,
                boxShadow: [
                  BoxShadow(
                    color: kWhiteColor.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child:
                    isLoading
                        ? SizedBox(
                          width: 20.w,
                          height: 20.h,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              kBlackColor,
                            ),
                          ),
                        )
                        : Text(
                          buttonText,
                          style: AppTypography.textMdMedium.copyWith(
                            color: kBlackColor,
                          ),
                        ),
              ),
            )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .boxShadow(
              borderRadius: BorderRadius.circular(14.br),
              begin: BoxShadow(
                color: kWhiteColor.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              end: BoxShadow(
                color: kWhiteColor.withValues(alpha: 0.5),
                blurRadius: 30,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
              duration: 1500.ms,
            )
            .scaleXY(
              begin: 1.0,
              end: 1.02,
              duration: 1500.ms,
              curve: Curves.easeInOutQuad,
            ),
      ),
    );
  }
}

class _PremiumAmbientGlow extends HookWidget {
  const _PremiumAmbientGlow();

  @override
  Widget build(BuildContext context) {
    final controller = useAnimationController(
      duration: const Duration(seconds: 10),
    )..repeat(reverse: true);

    final animation = useAnimation(
      CurvedAnimation(parent: controller, curve: Curves.easeInOut),
    );

    return CustomPaint(
      painter: _AmbientGlowPainter(animation),
      size: Size.infinite,
    );
  }
}

class _AmbientGlowPainter extends CustomPainter {
  _AmbientGlowPainter(this.animation);
  final double animation;

  @override
  void paint(Canvas canvas, Size size) {
    // Golden accent glow
    final paint1 =
        Paint()
          ..color = const Color(
            0xFFFFD700,
          ).withValues(alpha: 0.04 + (animation * 0.02))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);

    canvas.drawCircle(
      Offset(
        size.width * (0.2 + animation * 0.1),
        size.height * (0.15 + animation * 0.05),
      ),
      size.width * 0.35,
      paint1,
    );

    // Primary color subtle glow
    final paint2 =
        Paint()
          ..color = kPrimaryColor.withValues(alpha: 0.03 + (animation * 0.02))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);

    canvas.drawCircle(
      Offset(
        size.width * (0.8 - animation * 0.1),
        size.height * (0.6 - animation * 0.05),
      ),
      size.width * 0.3,
      paint2,
    );
  }

  @override
  bool shouldRepaint(covariant _AmbientGlowPainter oldDelegate) =>
      oldDelegate.animation != animation;
}

class _FloatingChessParticles extends HookWidget {
  const _FloatingChessParticles();

  @override
  Widget build(BuildContext context) {
    final controller = useAnimationController(
      duration: const Duration(seconds: 25),
    )..repeat();

    final animation = useAnimation(controller);

    return CustomPaint(
      painter: _ChessParticlePainter(animation),
      size: Size.infinite,
    );
  }
}

class _ChessParticlePainter extends CustomPainter {
  _ChessParticlePainter(this.animation);
  final double animation;

  static final List<_Particle> particles = List.generate(
    10,
    (i) => _Particle(
      x: (i * 0.1) + 0.05,
      y: (i % 4) * 0.25 + 0.1,
      size: 1.5 + (i % 3) * 1.0,
      speed: 0.2 + (i % 4) * 0.1,
      opacity: 0.1 + (i % 3) * 0.05,
    ),
  );

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final y = ((particle.y + animation * particle.speed) % 1.2) - 0.1;
      final x =
          particle.x +
          math.sin(animation * 2 * math.pi + particle.x * 10) * 0.015;

      final paint =
          Paint()
            ..color = kWhiteColor.withValues(
              alpha: particle.opacity * (1 - y.abs() * 0.5),
            );

      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        particle.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChessParticlePainter oldDelegate) =>
      oldDelegate.animation != animation;
}

class _Particle {
  const _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.opacity,
  });

  final double x, y, size, speed, opacity;
}

/// Helper function to convert PeriodUnit to readable string
String _getPeriodUnitString(PeriodUnit periodUnit, int count) {
  switch (periodUnit) {
    case PeriodUnit.day:
      return count == 1 ? 'day' : 'days';
    case PeriodUnit.week:
      return count == 1 ? 'week' : 'weeks';
    case PeriodUnit.month:
      return count == 1 ? 'month' : 'months';
    case PeriodUnit.year:
      return count == 1 ? 'year' : 'years';
    case PeriodUnit.unknown:
      return count == 1 ? 'day' : 'days';
  }
}
