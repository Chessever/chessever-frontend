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
                  // Hero Icon with Glow
                  Center(
                    child: Container(
                          height: 120.h,
                          width: 120.h,
                          decoration: BoxDecoration(
                            color: kPrimaryColor.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: kPrimaryColor.withValues(alpha: 0.2),
                                blurRadius: 40,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.workspace_premium_rounded,
                            size: 64.ic,
                            color: kPrimaryColor,
                          ),
                        )
                        .animate(onPlay: (c) => c.repeat(reverse: true))
                        .scaleXY(
                          begin: 1.0,
                          end: 1.1,
                          duration: 2000.ms,
                          curve: Curves.easeInOut,
                        ),
                  ),
                  SizedBox(height: 20.h),
                  // FOMO Banner
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16.w,
                      vertical: 8.h,
                    ),
                    decoration: BoxDecoration(
                      color: kPrimaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20.br),
                      border: Border.all(
                        color: kPrimaryColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          color: kPrimaryColor,
                          size: 16.sp,
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          'Limited Time Offer: Get 50% OFF',
                          style: AppTypography.textSmBold.copyWith(
                            color: kPrimaryColor,
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(delay: 50.ms).slideY(begin: 0.2, end: 0),

                  SizedBox(height: 16.h),
                  // Title
                  Text(
                        'Unlock Your\nGrandmaster Potential',
                        textAlign: TextAlign.center,
                        style: AppTypography.displaySmBold.copyWith(
                          color: kWhiteColor,
                          height: 1.1,
                          letterSpacing: -0.5,
                        ),
                      )
                      .animate()
                      .fadeIn(delay: 100.ms, duration: 400.ms)
                      .slideY(begin: 0.1, end: 0),
                  SizedBox(height: 8.h),
                  Text(
                    'Join thousands of players improving daily.',
                    textAlign: TextAlign.center,
                    style: AppTypography.textMdMedium.copyWith(
                      color: kWhiteColor.withValues(alpha: 0.6),
                    ),
                  ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.1, end: 0),
                  SizedBox(height: 24.h),
                  // Features Grid
                  _FeaturesGrid()
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

class _FeaturesGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final features = [
      (Icons.storage_rounded, 'Millions of\nChess Games'),
      (Icons.auto_stories_rounded, 'Create Study\nBook Collections'),
      (Icons.filter_alt_rounded, 'Advanced Search\n& Filters'),
      (Icons.people_rounded, 'Countrymen &\nFavorites'),
      (Icons.workspace_premium_rounded, 'Premium\nBadge'),
    ];

    return Wrap(
      spacing: 12.w,
      runSpacing: 12.h,
      alignment: WrapAlignment.center,
      children:
          features
              .map((f) => _CompactFeatureItem(icon: f.$1, text: f.$2))
              .toList(),
    );
  }
}

class _CompactFeatureItem extends StatelessWidget {
  const _CompactFeatureItem({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150.w, // About half width minus spacing
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: kWhiteColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12.br),
        border: Border.all(color: kWhiteColor.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20.ic, color: kPrimaryColor),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              text,
              style: AppTypography.textXsMedium.copyWith(
                color: kWhiteColor.withValues(alpha: 0.9),
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Old feature list removed

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
    String? monthlyEquivalentFromAnnual; // $4.99
    String? monthlyPlanPrice; // $9.99

    if (monthlyPackage != null) {
      monthlyCost = monthlyPackage!.storeProduct.price;
      monthlyPlanPrice = monthlyPackage!.storeProduct.priceString;
    }
    if (annualPackage != null) {
      annualCost = annualPackage!.storeProduct.price;
    }

    if (monthlyCost != null && annualCost != null) {
      final yearlyIfMonthly = monthlyCost * 12;
      savingsPercent =
          ((yearlyIfMonthly - annualCost) / yearlyIfMonthly * 100).round();

      // Calculate monthly equivalent of annual plan
      // Attempt to preserve currency symbol if possible
      final priceStr = monthlyPackage!.storeProduct.priceString;
      // Simple heuristic: take non-digit prefix as symbol
      final currencySymbol = priceStr.replaceAll(RegExp(r'[0-9.,\s]'), '');

      // Fallback if regex fails to isolate symbol cleanly, just use '$' default or empty if weird
      final effectiveSymbol = currencySymbol.isEmpty ? '\$' : currencySymbol;

      monthlyEquivalentFromAnnual =
          '$effectiveSymbol${(annualCost / 12).toStringAsFixed(2)}';
    }

    // Don't render pricing cards if packages aren't loaded
    final hasPackages = monthlyPackage != null && annualPackage != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Monthly card
        Expanded(
          child: _PricingCard(
            isSelected: selectedPlan.value == PlanType.monthly,
            title: 'Monthly',
            price: monthlyPackage?.storeProduct.priceString,
            period: '/mo',
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
            isBestValue: true,
            title: 'Annual',
            // Show monthly equivalent as the MAIN price
            price: monthlyEquivalentFromAnnual,
            period: '/mo',
            // Show the actual billing info as subtitle
            subtitle:
                annualPackage != null
                    ? 'Billed ${annualPackage!.storeProduct.priceString} yearly'
                    : null,
            badge: savingsPercent > 0 ? 'SAVE $savingsPercent%' : null,
            // Show monthly plan price as "original" price to strike through
            fakeOriginalPrice: monthlyPlanPrice,
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
    this.subtitle,
    this.fakeOriginalPrice,
    this.isLoading = false,
    this.isBestValue = false,
  });

  final bool isSelected;
  final String title;
  final String? price;
  final String period;
  final VoidCallback? onTap;
  final String? badge;
  final String? subtitle;
  final String? fakeOriginalPrice;
  final bool isLoading;
  final bool isBestValue;

  @override
  Widget build(BuildContext context) {
    final isPressed = useState(false);
    final showLoading = isLoading || price == null;

    final borderColor =
        isSelected
            ? kPrimaryColor
            : kWhiteColor.withValues(alpha: 0.1);

    final backgroundColor =
        isSelected
            ? kPrimaryColor.withValues(alpha: 0.15)
            : kWhiteColor.withValues(alpha: 0.05);

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
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              // Fixed height prevents layout shift when switching plans, taller for Annual to pop
              constraints: BoxConstraints(
                minHeight: isBestValue ? 150.h : 130.h,
              ),
              padding: EdgeInsets.all(16.sp),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(20.br),
                border: Border.all(
                  color: borderColor,
                  width: isSelected ? 2 : 1.5,
                ),
                boxShadow:
                    isSelected
                        ? [
                          BoxShadow(
                            color: kPrimaryColor.withValues(alpha: 0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                        : [],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Header: Title + Checked Icon -> Actually Title + Badge
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            title,
                            style: AppTypography.textMdBold.copyWith(
                              color:
                                  isSelected
                                      ? kWhiteColor
                                      : kWhiteColor.withValues(alpha: 0.7),
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              Icons.check_circle_rounded,
                              color: kPrimaryColor,
                              size: 20.ic,
                            ),
                        ],
                      ),
                      if (badge != null) ...[
                        SizedBox(height: 6.h),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8.w,
                            vertical: 4.h,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E),
                            borderRadius: BorderRadius.circular(20.br),
                          ),
                          child: Text(
                            badge!,
                            style: AppTypography.textXxsBold.copyWith(
                              color: kWhiteColor,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  SizedBox(height: 12.h),

                  // Pricing Block
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showLoading)
                        Container(
                          width: 80.w,
                          height: 32.h,
                          decoration: BoxDecoration(
                            color: kWhiteColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6.br),
                          ),
                        )
                      else ...[
                        // Fake Original Price (Strikethrough) ABOVE the main price for better hierarchy
                        if (fakeOriginalPrice != null)
                          Text(
                            fakeOriginalPrice!,
                            style: AppTypography.textXsMedium.copyWith(
                              color: kWhiteColor.withValues(alpha: 0.4),
                              decoration: TextDecoration.lineThrough,
                              decorationColor: kWhiteColor.withValues(
                                alpha: 0.4,
                              ),
                            ),
                          ),

                        // Main Price
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              price!,
                              style: AppTypography.displaySmBold.copyWith(
                                color: kWhiteColor,
                                fontSize: 24.sp,
                              ),
                            ),
                            SizedBox(width: 2.w),
                            Text(
                              period,
                              style: AppTypography.textSmMedium.copyWith(
                                color: kWhiteColor.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ],

                      // Subtitle (Billed yearly)
                      if (subtitle != null && !showLoading) ...[
                        SizedBox(height: 4.h),
                        Text(
                          subtitle!,
                          style: AppTypography.textXxsRegular.copyWith(
                            color: kWhiteColor.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // "BEST VALUE" Tag floating on top
            if (isBestValue)
              Positioned(
                top: -12.h,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.w,
                          vertical: 4.h,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [kPrimaryColor, kDarkBlue],
                          ),
                          borderRadius: BorderRadius.circular(12.br),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          'BEST VALUE',
                          style: AppTypography.textXxsBold.copyWith(
                            color: kBlack3Color,
                            letterSpacing: 1.0,
                          ),
                        ),
                      )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scaleXY(
                        begin: 1.0,
                        end: 1.05,
                        duration: 1000.ms,
                        curve: Curves.easeInOut,
                      ),
                ),
              ),
          ],
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
                borderRadius: BorderRadius.circular(16.br),
                gradient: LinearGradient(
                  colors: [kPrimaryColor, kDarkBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: kPrimaryColor.withValues(alpha: 0.4),
                    blurRadius: 25,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Center(
                child:
                    isLoading
                        ? SizedBox(
                          width: 24.w,
                          height: 24.h,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              kBlackColor,
                            ),
                          ),
                        )
                        : Text(
                          buttonText,
                          style: AppTypography.textLgBold.copyWith(
                            color: kBlackColor,
                            letterSpacing: 0.5,
                          ),
                        ),
              ),
            )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .boxShadow(
              borderRadius: BorderRadius.circular(16.br),
              begin: BoxShadow(
                color: kPrimaryColor.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              end: BoxShadow(
                color: kPrimaryColor.withValues(alpha: 0.6),
                blurRadius: 35,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
              duration: 2000.ms,
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
    // Primary color accent glow
    final paint1 =
        Paint()
          ..color = kPrimaryColor.withValues(alpha: 0.04 + (animation * 0.02))
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
