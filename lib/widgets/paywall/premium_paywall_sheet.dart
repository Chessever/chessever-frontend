import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/revenue_cat_service/revenue_cat_service.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/services/appsflyer_service.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/extensioms/string_extensions.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/paywall/premium_celebration_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Show the premium paywall sheet.
/// Returns `true` if the user successfully subscribed.
Future<bool> showPremiumPaywallSheet({required BuildContext context}) async {
  // Sync purchases when paywall opens (user might have subscribed externally)
  unawaited(RevenueCatService().syncPurchases());

  // AppsFlyer funnel: paywall view counts as checkout intent.
  unawaited(AppsflyerService.instance.logInitiatedCheckout());

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: ResponsiveHelper.bottomSheetConstraints,
    builder: (_) => _PremiumPaywallSheet(hostContext: context),
  );
  return result ?? false;
}

/// Guard that checks subscription and shows paywall if needed.
/// Returns true if user has premium or just subscribed.
/// Note: Requires authentication first - shows auth upgrade sheet if user is anonymous.
Future<bool> requirePremiumGuard(BuildContext context, WidgetRef ref) async {
  if (kDebugMode) return true;

  // First ensure user is authenticated (not anonymous)
  final isAuthenticated = await requireFullAuthGuard(context);
  if (!isAuthenticated) return false;

  final subscriptionState = ref.read(subscriptionProvider);
  if (subscriptionState.isSubscribed) return true;
  if (!context.mounted) return false;

  return await showPremiumPaywallSheet(context: context);
}

/// Guard variant for places where WidgetRef is not conveniently available.
/// Returns true if user has premium or just subscribed from paywall.
Future<bool> requirePremiumGuardNoRef(BuildContext context) async {
  if (kDebugMode) return true;

  final isAuthenticated = await requireFullAuthGuard(context);
  if (!isAuthenticated) return false;

  final isSubscribed = await RevenueCatService().isSubscribed();
  if (isSubscribed) return true;
  if (!context.mounted) return false;

  return await showPremiumPaywallSheet(context: context);
}

class _PremiumPaywallSheet extends HookWidget {
  const _PremiumPaywallSheet({required this.hostContext});

  final BuildContext hostContext;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.8,
      maxChildSize: 0.9,
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: kBlack2Color.withOpacity(0.98),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28.sp)),
          ),
          child: _PaywallContent(hostContext: hostContext),
        );
      },
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

    // Auto-close + celebrate when entitlement activates from any source —
    // including offer-code redemption on iOS or returning from Play Store on Android.
    ref.listen<SubscriptionState>(subscriptionProvider, (prev, next) {
      final wasSubscribed = prev?.isSubscribed ?? false;
      if (!wasSubscribed && next.isSubscribed && hostContext.mounted) {
        Navigator.of(hostContext).pop(true);
        unawaited(showPremiumCelebration(hostContext));
      }
    });

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
          // Show celebration animation
          await showPremiumCelebration(hostContext);
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

    Future<void> handleHaveCode() async {
      if (Platform.isIOS) {
        // Apple's native sheet — code is entered inside the OS UI, not ours,
        // so we can't capture the actual code value on this platform. We
        // still tag the funnel step and the cached affiliate context so the
        // resulting entitlement transition can be attributed.
        const source = 'ios_native_sheet';
        final affiliate =
            await AppsflyerService.instance.getCachedAffiliateContext();
        ref
            .read(subscriptionProvider.notifier)
            .markRedemptionPending(source: source);
        await RevenueCatService().tagRedemptionAttempt(
          source: source,
          affiliateContext: affiliate,
        );
        unawaited(
          AppsflyerService.instance.logRedemptionInitiated(source: source),
        );

        await RevenueCatService().presentCodeRedemptionSheet();
        return;
      }

      // Android: Play Store has no in-app sheet, so we collect the code in our
      // own bottom sheet and deep-link to play.google.com/redeem?code=… which
      // the Play Store app intercepts via App Links and opens with the code
      // pre-filled — user just confirms. Attribution happens inside the sheet
      // since that's where we have the actual code.
      if (!context.mounted) return;
      await _showAndroidCodeRedeemSheet(context, ref);
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, topPadding + 16.h, 20.w, 24.h),
      child: Column(
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 36.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: kWhiteColor.withOpacity(0.2),
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
                  color: kWhiteColor.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close_rounded,
                  color: kWhiteColor.withOpacity(0.6),
                  size: 20.ic,
                ),
              ),
            ),
          ),
          // Hero Icon
          Center(
            child: Image.asset(
              'assets/pngs/new_app_logo.webp',
              height: 80.h,
              cacheHeight:
                  (80 * MediaQuery.devicePixelRatioOf(context)).toInt(),
            ),
          ),
          SizedBox(height: 16.h),
          // Title
          Text(
            'Follow Chess\nLike a Pro',
            textAlign: TextAlign.center,
            style: AppTypography.displaySmBold.copyWith(
              color: kWhiteColor,
              height: 1.1,
              letterSpacing: -0.5,
              fontSize: 28.f,
            ),
          ),
          SizedBox(height: 24.h),
          // Features
          _FeaturesList(),
          const Spacer(),

          // Pricing cards
          _PricingSection(
            selectedPlan: selectedPlan,
            monthlyPackage: monthlyPackage,
            annualPackage: annualPackage,
          ),
          SizedBox(height: 24.h),
          // CTA Button
          _PurchaseButton(
            selectedPlan: selectedPlan.value,
            monthlyPackage: monthlyPackage,
            annualPackage: annualPackage,
            isLoading: isLoading.value || subscriptionState.isLoading,
            onTap: handlePurchase,
          ),
          SizedBox(height: 12.h),
          // Restore purchases + redeem code
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: isLoading.value ? null : handleRestore,
                child: Text(
                  'Restore purchases',
                  style: AppTypography.textSmMedium.copyWith(
                    color: kWhiteColor.withOpacity(0.5),
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              Text(
                '·',
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor.withOpacity(0.3),
                ),
              ),
              SizedBox(width: 12.w),
              GestureDetector(
                onTap: isLoading.value ? null : handleHaveCode,
                child: Text(
                  'Have a code?',
                  style: AppTypography.textSmMedium.copyWith(
                    color: kWhiteColor.withOpacity(0.5),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          // Legal links
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _launchUrl('https://chessever.com/privacy-policy'),
                child: Text(
                  'Privacy Policy',
                  style: AppTypography.textXsMedium.copyWith(
                    color: kWhiteColor.withOpacity(0.4),
                    decoration: TextDecoration.underline,
                    decorationColor: kWhiteColor.withOpacity(0.4),
                  ),
                ),
              ),
              SizedBox(width: 16.w),
              Text(
                '|',
                style: AppTypography.textXsMedium.copyWith(
                  color: kWhiteColor.withOpacity(0.3),
                ),
              ),
              SizedBox(width: 16.w),
              GestureDetector(
                onTap: () => _launchUrl('https://chessever.com/terms-of-use'),
                child: Text(
                  'Terms of Use',
                  style: AppTypography.textXsMedium.copyWith(
                    color: kWhiteColor.withOpacity(0.4),
                    decoration: TextDecoration.underline,
                    decorationColor: kWhiteColor.withOpacity(0.4),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
        ],
      ),
    );
  }
}

class _FeaturesList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final features = [
      (Icons.people_rounded, 'Countrymen & Favorites'),
      (Icons.sports_esports_rounded, 'Opponent Prep Tools'),
      (Icons.auto_stories_rounded, 'Database Storage'),
      (Icons.filter_alt_rounded, 'Advanced Search & Filters'),
    ];

    return Column(
      children:
          features.map((f) => _FeatureItem(icon: f.$1, text: f.$2)).toList(),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  const _FeatureItem({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Row(
        children: [
          Icon(icon, size: 20.ic, color: kPrimaryColor),
          SizedBox(width: 12.w),
          Text(
            text,
            style: AppTypography.textMdMedium.copyWith(
              color: kWhiteColor.withOpacity(0.9),
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
    String? monthlyEquivalentFromAnnual; // $4.99/mo

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

      // Calculate monthly equivalent of annual plan
      // Attempt to preserve currency symbol if possible
      final priceStr = monthlyPackage!.storeProduct.priceString;
      // Simple heuristic: take non-digit prefix as symbol
      final currencySymbol = priceStr.replaceAll(RegExp(r'[0-9.,\s]'), '');

      // Fallback if regex fails to isolate symbol cleanly, just use '$' default or empty if weird
      final effectiveSymbol = currencySymbol.isEmpty ? '\$' : currencySymbol;

      monthlyEquivalentFromAnnual =
          '$effectiveSymbol${(annualCost / 12).toStringAsFixed(2)}/mo';
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
            // BILLED AMOUNT is the main price (Apple requirement)
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
        // Annual card - BILLED AMOUNT must be most prominent (Apple Guideline 3.1.2)
        Expanded(
          child: _PricingCard(
            isSelected: selectedPlan.value == PlanType.annual,
            isBestValue: true,
            title: 'Annual',
            // BILLED AMOUNT is the main price (Apple requirement)
            price: annualPackage?.storeProduct.priceString,
            period: '/yr',
            // Monthly equivalent shown as subordinate subtitle
            subtitle: monthlyEquivalentFromAnnual,
            badge: savingsPercent > 0 ? 'SAVE $savingsPercent%' : null,
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
  final bool isLoading;
  final bool isBestValue;

  @override
  Widget build(BuildContext context) {
    final isPressed = useState(false);
    final showLoading = isLoading || price == null;

    final borderColor =
        isSelected ? kPrimaryColor : kWhiteColor.withOpacity(0.1);

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
              constraints: BoxConstraints(
                minHeight: isBestValue ? 130.h : 110.h,
              ),
              padding: EdgeInsets.all(12.sp),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(16.br),
                border: Border.all(
                  color: borderColor,
                  width: isSelected ? 2 : 1.5,
                ),
                boxShadow:
                    isSelected
                        ? [
                          BoxShadow(
                            color: kPrimaryColor.withOpacity(0.15),
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
                              size: 18.ic,
                            ),
                        ],
                      ),
                      if (badge != null) ...[
                        SizedBox(height: 4.h),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 6.w,
                            vertical: 3.h,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22C55E),
                            borderRadius: BorderRadius.circular(16.br),
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

                  SizedBox(height: 8.h),

                  // Pricing Block - BILLED AMOUNT is most prominent (Apple Guideline 3.1.2)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showLoading)
                        Container(
                          width: 60.w,
                          height: 24.h,
                          decoration: BoxDecoration(
                            color: kWhiteColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4.br),
                          ),
                        )
                      else ...[
                        // Main Price (BILLED AMOUNT - most prominent)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              price!,
                              style: AppTypography.displaySmBold.copyWith(
                                color: kWhiteColor,
                                fontSize: 20.sp,
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

                      // Subtitle (monthly equivalent - subordinate)
                      if (subtitle != null && !showLoading) ...[
                        SizedBox(height: 2.h),
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
                top: -10.h,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 10.w,
                      vertical: 3.h,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [kPrimaryColor, kDarkBlue],
                      ),
                      borderRadius: BorderRadius.circular(10.br),
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

    final priceString = storeProduct?.priceString ?? '';
    final periodSuffix = selectedPlan == PlanType.annual ? 'year' : 'month';

    String buttonText;
    if (hasIosFreeTrial) {
      // iOS trial info from introductoryPrice
      final trialCount = introPrice.periodNumberOfUnits;
      final periodUnit = introPrice.periodUnit;
      final unitString = _getPeriodUnitString(periodUnit, trialCount);

      if (trialCount > 0) {
        buttonText =
            'Try $trialCount ${unitString.capitalize()} Free, then $priceString/$periodSuffix';
      } else {
        buttonText = 'Try 1 Week Free, then $priceString/$periodSuffix';
      }
    } else if (hasAndroidFreeTrial) {
      // Android trial info from freePhase.billingPeriod
      final billingPeriod = freePhase.billingPeriod;
      if (billingPeriod != null) {
        final trialCount = billingPeriod.value;
        final periodUnit = billingPeriod.unit;
        final unitString = _getPeriodUnitString(periodUnit, trialCount);

        if (trialCount > 0) {
          buttonText =
              'Try $trialCount ${unitString.capitalize()} Free, then $priceString/$periodSuffix';
        } else {
          buttonText = 'Try 1 Week Free, then $priceString/$periodSuffix';
        }
      } else {
        buttonText = 'Try 1 Week Free, then $priceString/$periodSuffix';
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
                        valueColor: AlwaysStoppedAnimation<Color>(kBlackColor),
                      ),
                    )
                    : Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          buttonText,
                          textAlign: TextAlign.center,
                          style: AppTypography.textLgBold.copyWith(
                            color: kBlackColor,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
          ),
        ),
      ),
    );
  }
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

/// Helper function to launch a URL
Future<void> _launchUrl(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Android-only redemption flow. Plays Store has no in-app native sheet, so we
/// take the code in our own UI and hand off to Play with `?code=` pre-filled.
Future<void> _showAndroidCodeRedeemSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: ResponsiveHelper.bottomSheetConstraints,
    builder: (_) => _AndroidCodeRedeemSheet(parentRef: ref),
  );
}

class _AndroidCodeRedeemSheet extends HookConsumerWidget {
  const _AndroidCodeRedeemSheet({required this.parentRef});

  final WidgetRef parentRef;

  @override
  Widget build(BuildContext context, WidgetRef _) {
    final controller = useTextEditingController();
    final code = useState('');
    final isSubmitting = useState(false);

    Future<void> submit() async {
      final trimmed = code.value.trim().toUpperCase();
      if (trimmed.isEmpty || isSubmitting.value) return;
      isSubmitting.value = true;

      try {
        // Stamp attribution before handing off to Play Store so the metadata
        // is in place when the customer-info listener fires on app resume.
        const source = 'android_play_deep_link';
        final affiliate =
            await AppsflyerService.instance.getCachedAffiliateContext();
        parentRef
            .read(subscriptionProvider.notifier)
            .markRedemptionPending(source: source, code: trimmed);
        await RevenueCatService().tagRedemptionAttempt(
          source: source,
          code: trimmed,
          affiliateContext: affiliate,
        );
        unawaited(
          AppsflyerService.instance.logRedemptionInitiated(
            source: source,
            code: trimmed,
          ),
        );

        // Play Store intercepts this URL via App Links and opens the redeem
        // screen with the code pre-filled. Falls back to a browser tab only if
        // Play Store isn't installed.
        final uri = Uri.parse(
          'https://play.google.com/redeem?code=${Uri.encodeQueryComponent(trimmed)}',
        );
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (context.mounted) Navigator.of(context).pop();
        } else if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open the Play Store. Try again later.'),
            ),
          );
        }
      } finally {
        isSubmitting.value = false;
      }
    }

    return Padding(
      // Lift the sheet above the keyboard so the CTA stays tappable.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: kBlack2Color.withOpacity(0.98),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28.sp)),
        ),
        padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 24.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: kWhiteColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2.br),
                ),
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'Redeem a code',
              style: AppTypography.textLgBold.copyWith(color: kWhiteColor),
            ),
            SizedBox(height: 6.h),
            Text(
              "Enter your code below. We'll open the Play Store with it pre-filled — just tap Redeem to confirm.",
              style: AppTypography.textSmRegular.copyWith(
                color: kWhiteColor.withOpacity(0.6),
              ),
            ),
            SizedBox(height: 16.h),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.go,
              onChanged: (val) => code.value = val,
              onSubmitted: (_) => submit(),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(40),
              ],
              style: AppTypography.textMdMedium.copyWith(
                color: kWhiteColor,
                letterSpacing: 1.2,
              ),
              decoration: InputDecoration(
                hintText: 'XXXXXXXXXX',
                hintStyle: AppTypography.textMdMedium.copyWith(
                  color: kWhiteColor.withOpacity(0.25),
                  letterSpacing: 1.2,
                ),
                filled: true,
                fillColor: kBlack2Color,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.br),
                  borderSide: BorderSide(
                    color: kWhiteColor.withOpacity(0.08),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.br),
                  borderSide: BorderSide(
                    color: kWhiteColor.withOpacity(0.08),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.br),
                  borderSide: const BorderSide(color: kPrimaryColor),
                ),
              ),
            ),
            SizedBox(height: 16.h),
            _RedeemButton(
              isEnabled: code.value.trim().isNotEmpty,
              isLoading: isSubmitting.value,
              onTap: submit,
            ),
            SizedBox(height: 8.h),
            TextButton(
              onPressed:
                  isSubmitting.value
                      ? null
                      : () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: AppTypography.textSmMedium.copyWith(
                  color: kWhiteColor.withOpacity(0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RedeemButton extends HookWidget {
  const _RedeemButton({
    required this.isEnabled,
    required this.isLoading,
    required this.onTap,
  });

  final bool isEnabled;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPressed = useState(false);
    final tappable = isEnabled && !isLoading;

    return GestureDetector(
      onTapDown: tappable ? (_) => isPressed.value = true : null,
      onTapUp:
          tappable
              ? (_) {
                isPressed.value = false;
                onTap();
              }
              : null,
      onTapCancel: tappable ? () => isPressed.value = false : null,
      child: AnimatedScale(
        scale: isPressed.value ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: AnimatedOpacity(
          opacity: tappable ? 1.0 : 0.5,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: double.infinity,
            height: 54.h,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16.br),
              gradient: const LinearGradient(
                colors: [kPrimaryColor, kDarkBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow:
                  tappable
                      ? [
                        BoxShadow(
                          color: kPrimaryColor.withValues(alpha: 0.4),
                          blurRadius: 25,
                          offset: const Offset(0, 8),
                        ),
                      ]
                      : const [],
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
                        'Open Play Store to redeem',
                        style: AppTypography.textLgBold.copyWith(
                          color: kBlackColor,
                          letterSpacing: 0.2,
                        ),
                      ),
            ),
          ),
        ),
      ),
    );
  }
}
