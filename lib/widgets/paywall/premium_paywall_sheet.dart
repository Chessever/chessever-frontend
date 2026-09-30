import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:chessever2/widgets/auth/auth_upgrade_sheet.dart';
import 'package:chessever2/revenue_cat_service/revenue_cat_service.dart';
import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/services/appsflyer_service.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/theme/app_theme.dart';
import 'package:chessever2/utils/app_typography.dart';
import 'package:chessever2/utils/extensioms/string_extensions.dart';
import 'package:chessever2/utils/responsive_helper.dart';
import 'package:chessever2/widgets/paywall/premium_celebration_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:motor/motor.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// The action a Premium gate resumes once the viewer is entitled: whatever
/// they tapped before the paywall opened (open the archived game, apply the
/// locked filter, step to the earlier day).
typedef PremiumResume = FutureOr<void> Function();

/// Longest identifier the upgrade hand-off forwards to analytics.
const int _kPaywallIdMaxLength = 64;
final RegExp _paywallFeatureIdPattern = RegExp(r'^[a-z][a-z0-9_]*$');
final RegExp _paywallReturnToPattern = RegExp(
  r'^[a-z][a-z0-9_]*(/[a-z][a-z0-9_]*)*$',
);

/// [featureId] as the paywall analytics may carry it: a fixed snake_case
/// identifier ('miniatures_archive'), or null. Anything else (a name, an
/// email, a uuid, a FIDE id) is dropped instead of sent, so a careless caller
/// can never leak user or player data into the checkout funnel.
@visibleForTesting
String? paywallFeatureIdForAnalytics(String? featureId) =>
    _fixedIdentifier(featureId, _paywallFeatureIdPattern);

/// [returnTo] as the paywall analytics may carry it: a fixed route-like name
/// ('for_you/discovery/most_liked'), or null. Same rule as
/// [paywallFeatureIdForAnalytics].
@visibleForTesting
String? paywallReturnToForAnalytics(String? returnTo) =>
    _fixedIdentifier(returnTo, _paywallReturnToPattern);

String? _fixedIdentifier(String? value, RegExp pattern) {
  if (value == null) return null;
  if (value.length > _kPaywallIdMaxLength) return null;
  return pattern.hasMatch(value) ? value : null;
}

/// Hands a confirmed entitlement back to the feature that asked for it: runs
/// [onEntitled] and returns `true`.
///
/// [after] is what still covers the originating screen, the purchase
/// celebration. The action waits for it to close, so a resumed navigation
/// lands where the viewer is looking instead of under the celebration. With
/// no [onEntitled] nothing waits and `true` comes back at once, exactly as
/// before the hand-off existed. When [context] is gone there is no feature
/// left to return to, so the action is skipped.
@visibleForTesting
Future<bool> resumePremiumAction(
  BuildContext context, {
  PremiumResume? onEntitled,
  Future<void>? after,
}) async {
  if (onEntitled == null) return true;
  if (after != null) {
    try {
      await after;
    } catch (_) {
      // A celebration that failed to show must not strand the action.
    }
  }
  if (!context.mounted) return true;
  await onEntitled();
  return true;
}

/// Show the premium paywall sheet, upgrading guests to a full account first.
/// Returns `true` if the user already has Premium or successfully subscribes.
///
/// [featureId] names the feature or CTA that asked for Premium
/// ('most_liked_rankings') and [returnTo] the surface the caller resumes on
/// once entitled ('for_you/discovery/most_liked'), so the checkout funnel
/// knows where each upgrade started. Both reach the paywall analytics event
/// only, never RevenueCat or payment metadata, and must be fixed identifiers:
/// anything shaped like user, player or account data is dropped.
///
/// [onEntitled] resumes the intended action after a confirmed purchase or
/// restore (the sheet closes first), or straight away for a viewer who turns
/// out to be entitled already. See [resumePremiumAction].
Future<bool> showPremiumPaywallSheet({
  required BuildContext context,
  String? featureId,
  String? returnTo,
  PremiumResume? onEntitled,
}) async {
  final initialUser = Supabase.instance.client.auth.currentUser;
  if (initialUser == null || initialUser.isAnonymous) {
    final authenticated = await showAuthUpgradeSheet(
      context: context,
      title: 'Sign in to get Premium',
      message:
          'Choose an account so your subscription can be restored on every device.',
      completeSignInInSheet: true,
    );
    if (!authenticated || !context.mounted) return false;

    final authenticatedUser = Supabase.instance.client.auth.currentUser;
    if (authenticatedUser == null || authenticatedUser.isAnonymous) {
      return false;
    }

    // Guest sessions are already identified to RevenueCat by their Supabase
    // uid. Switch to the upgraded account before opening checkout so the
    // purchase is never attached to the temporary guest identity.
    if (initialUser?.isAnonymous == true) {
      await RevenueCatService().logOut();
    }
    await RevenueCatService().logIn(authenticatedUser.id);
  }
  // Refresh the newly authenticated RevenueCat customer before offering a
  // purchase. The direct CustomerInfo check covers App Store / Play Store;
  // isSubscribed also checks the shared backend entitlement used by Stripe.
  final revenueCat = RevenueCatService();
  final customerInfo = await revenueCat.syncPurchases();
  final hasStoreEntitlement =
      customerInfo?.entitlements.active.isNotEmpty == true;
  final hasActiveSubscription =
      hasStoreEntitlement || await revenueCat.isSubscribed();
  if (!context.mounted) return hasActiveSubscription;
  if (hasActiveSubscription) {
    return resumePremiumAction(context, onEntitled: onEntitled);
  }

  // AppsFlyer funnel: paywall view counts as checkout intent.
  unawaited(
    AppsflyerService.instance.logInitiatedCheckout(
      featureId: paywallFeatureIdForAnalytics(featureId),
      returnTo: paywallReturnToForAnalytics(returnTo),
    ),
  );

  final handoff = _PaywallHandoff();
  final result = await showModalBottomSheet<bool>(
    context: context,
    // Save flow / chess board sheets host their own nested Navigator
    // (smooth_sheets PagedSheet). Without rootNavigator:true the paywall
    // is pushed inside that nested scope and gets clipped to the host
    // sheet's bounds. Route via the root navigator so it spans the screen.
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: ResponsiveHelper.bottomSheetConstraints,
    builder:
        (_) => _PremiumPaywallSheet(hostContext: context, handoff: handoff),
  );
  if (result != true) return false;
  if (!context.mounted) return true;
  return resumePremiumAction(
    context,
    onEntitled: onEntitled,
    after: handoff.celebration,
  );
}

/// Guard that checks subscription and shows paywall if needed.
/// Returns true if user has premium or just subscribed.
/// Note: Requires authentication first - shows auth upgrade sheet if user is anonymous.
/// [featureId], [returnTo] and [onEntitled] are handed to the paywall as-is;
/// see [showPremiumPaywallSheet]. A subscriber skips the paywall, so
/// [onEntitled] runs straight away.
Future<bool> requirePremiumGuard(
  BuildContext context,
  WidgetRef ref, {
  String? featureId,
  String? returnTo,
  PremiumResume? onEntitled,
}) async {
  if (kDebugMode) return resumePremiumAction(context, onEntitled: onEntitled);

  // First ensure user is authenticated (not anonymous)
  final isAuthenticated = await requireFullAuthGuard(context);
  if (!isAuthenticated) return false;

  final subscriptionState = ref.read(subscriptionProvider);
  if (!context.mounted) return subscriptionState.isSubscribed;
  if (subscriptionState.isSubscribed) {
    return resumePremiumAction(context, onEntitled: onEntitled);
  }

  return await showPremiumPaywallSheet(
    context: context,
    featureId: featureId,
    returnTo: returnTo,
    onEntitled: onEntitled,
  );
}

/// Guard variant for places where WidgetRef is not conveniently available.
/// Returns true if user has premium or just subscribed from paywall.
Future<bool> requirePremiumGuardNoRef(
  BuildContext context, {
  String? featureId,
  String? returnTo,
  PremiumResume? onEntitled,
}) async {
  if (kDebugMode) return resumePremiumAction(context, onEntitled: onEntitled);

  final isAuthenticated = await requireFullAuthGuard(context);
  if (!isAuthenticated) return false;

  final isSubscribed = await RevenueCatService().isSubscribed();
  if (!context.mounted) return isSubscribed;
  if (isSubscribed) {
    return resumePremiumAction(context, onEntitled: onEntitled);
  }

  return await showPremiumPaywallSheet(
    context: context,
    featureId: featureId,
    returnTo: returnTo,
    onEntitled: onEntitled,
  );
}

/// What an open paywall hands back to the gate that opened it: the
/// celebration shown on a confirmed purchase or restore, so a resumed action
/// can wait for it to close.
class _PaywallHandoff {
  Future<void>? celebration;
}

class _PremiumPaywallSheet extends HookWidget {
  const _PremiumPaywallSheet({required this.hostContext, this.handoff});

  final BuildContext hostContext;
  final _PaywallHandoff? handoff;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.8,
      maxChildSize: 0.9,
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: BoxDecoration(
            // Opaque: at 0.98 the page behind ghosted through the copy.
            color: context.colors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28.sp)),
          ),
          child: _PaywallContent(hostContext: hostContext, handoff: handoff),
        );
      },
    );
  }
}

class _PaywallContent extends HookConsumerWidget {
  const _PaywallContent({required this.hostContext, this.handoff});

  final BuildContext hostContext;
  final _PaywallHandoff? handoff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topPadding = MediaQuery.of(context).padding.top;
    final subscriptionState = ref.watch(subscriptionProvider);
    final selectedPlan = useState<PlanType>(PlanType.annual);
    final isLoading = useState(false);

    // Self-heal: offerings are fetched once when SubscriptionNotifier is
    // built, which normally happens on the first frame — BEFORE the
    // fire-and-forget `Purchases.configure` has finished. Losing that race
    // (or hitting one transient Play Billing / StoreKit error) used to leave
    // `products` empty for the whole session, so the paywall showed skeleton
    // prices forever and Continue did nothing. Retry every time it opens.
    useEffect(() {
      if (subscriptionState.products.isEmpty) {
        unawaited(ref.read(subscriptionProvider.notifier).loadProducts());
      }
      return null;
    }, const []);

    // Single source of truth for "subscription activated → close paywall +
    // celebrate". Covers every activation path: direct purchase, restore,
    // offer-code redemption (iOS native sheet), Play Store deferred-return,
    // and backend-side Stripe sync. handlePurchase / handleRestore do NOT
    // also pop or celebrate — duplicating that pop here used to race with
    // them and end up popping the *caller's* sheet (e.g. the Save Analysis
    // sheet underneath), leaving its spinner stuck while the action it
    // gated had already completed.
    ref.listen<SubscriptionState>(subscriptionProvider, (prev, next) {
      final wasSubscribed = prev?.isSubscribed ?? false;
      if (!wasSubscribed && next.isSubscribed && hostContext.mounted) {
        Navigator.maybeOf(hostContext, rootNavigator: true)?.pop(true);
        final celebration = showPremiumCelebration(hostContext);
        // The gate that opened this sheet resumes its action once the
        // celebration closes (see resumePremiumAction).
        handoff?.celebration = celebration;
        unawaited(celebration);
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

    // Sentry CHESSEVER-1GT: tapping X crashed with "Null check operator used
    // on a null value" — 95 events / 19 users since 2026-05-30, still firing on
    // 34.7.3+3344. `Navigator.maybeOf` was NOT the fix: maybeOf only returns
    // null when no Navigator ancestor exists, it does not survive a DEFUNCT
    // element. It walks ancestors via findRootAncestorStateOfType, which reads
    // StatefulElement.state (`_state!`), and that throws once hostContext's
    // widget is gone — which happens whenever the screen underneath is disposed
    // while the paywall is open. Check mounted first, and fall back to the
    // sheet's own context, which is valid for as long as the sheet is on screen.
    void closePaywall([bool result = false]) {
      final ctx =
          hostContext.mounted
              ? hostContext
              : (context.mounted ? context : null);
      if (ctx == null) return;
      Navigator.maybeOf(ctx, rootNavigator: true)?.pop(result);
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
      // ref.listen above closes the sheet on success. We only need to
      // unfreeze the button on the cancel / error paths.
      if (context.mounted) isLoading.value = false;
    }

    Future<void> handleRestore() async {
      isLoading.value = true;
      await ref.read(subscriptionProvider.notifier).restorePurchases();
      if (context.mounted) isLoading.value = false;
      // ref.listen closes the sheet if the restore actually reactivated
      // a subscription; otherwise we stay on the paywall so the user can
      // see the "no purchases found" feedback that the notifier surfaces.
    }

    Future<void> handleHaveCode() async {
      if (Platform.isIOS) {
        // Apple's native sheet — code is entered inside the OS UI, not ours,
        // so we can't capture the actual code value on this platform. We
        // still tag the funnel step and the cached affiliate context so the
        // resulting entitlement transition can be attributed.
        const source = 'ios_native_sheet';
        final affiliate =
            await AppsflyerService.instance.getCachedAttributionContext();
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

      // Android: code-gated percentage offers can't be redeemed via the
      // play.google.com/redeem deep link (that path only handles 100%-off
      // promo codes). We collect the code, validate it locally, then launch
      // Google Play Billing with the matching SubscriptionOption (offer
      // token). Attribution happens inside the sheet since that's where we
      // have the actual code.
      if (!context.mounted) return;
      await _showAndroidCodeRedeemSheet(
        context,
        ref,
        monthlyPackage: monthlyPackage,
        annualPackage: annualPackage,
        selectedPlan: selectedPlan.value,
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, topPadding + 16.h, 20.w, 24.h),
      // "Fill or scroll" — on tall screens the Column fills the sheet and
      // Spacer() pushes pricing to the bottom; on shorter heights (tablet
      // landscape) the content scrolls instead of overflowing the flex.
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  children: [
          // Handle bar
          Center(
            child: Container(
              width: 36.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: context.colors.textPrimary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2.br),
              ),
            ),
          ),
          SizedBox(height: 12.h),
          // Close button
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: closePaywall,
              child: Container(
                padding: EdgeInsets.all(8.sp),
                decoration: BoxDecoration(
                  color: context.colors.textPrimary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close_rounded,
                  color: context.colors.textPrimary.withValues(alpha: 0.6),
                  size: 20.ic,
                ),
              ),
            ),
          ),
          // Hero Icon
          // The logo art is a black square, which reads as a hard slab on
          // either sheet (neither is pure black), so it is rounded into the
          // app-icon shape it actually is.
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18.br),
              child: Image.asset(
                'assets/pngs/new_app_logo.webp',
                height: 80.h,
                cacheHeight:
                    (80 * MediaQuery.devicePixelRatioOf(context)).toInt(),
              ),
            ),
          ),
          SizedBox(height: 16.h),
          // Title
          Text(
            'Follow Chess\nLike a Pro',
            textAlign: TextAlign.center,
            style: AppTypography.displaySmBold.copyWith(
              color: context.colors.textPrimary,
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
            productsError: subscriptionState.productsError,
            isRetrying: subscriptionState.isLoadingProducts,
            onRetry:
                () => unawaited(
                  ref
                      .read(subscriptionProvider.notifier)
                      .loadProducts(force: true),
                ),
          ),
          SizedBox(height: 24.h),
          // CTA Button
          _PurchaseButton(
            selectedPlan: selectedPlan.value,
            monthlyPackage: monthlyPackage,
            annualPackage: annualPackage,
            isLoading: isLoading.value || subscriptionState.isLoading,
            // A live-looking CTA that silently returns (handlePurchase bails
            // on a null package) is worse than a visibly inert one.
            isEnabled: monthlyPackage != null && annualPackage != null,
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
                    color:
                        context.isLightTheme
                            ? context.colors.textSecondary
                            : context.textInk(0.5),
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              Text(
                '·',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.textInk(0.3),
                ),
              ),
              SizedBox(width: 12.w),
              GestureDetector(
                onTap: isLoading.value ? null : handleHaveCode,
                child: Text(
                  'Have a code?',
                  style: AppTypography.textSmMedium.copyWith(
                    color:
                        context.isLightTheme
                            ? context.colors.textSecondary
                            : context.textInk(0.5),
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
                    color:
                        context.isLightTheme
                            ? context.colors.textSecondary
                            : context.textInk(0.4),
                    decoration: TextDecoration.underline,
                    decorationColor:
                        context.isLightTheme
                            ? context.colors.textSecondary
                            : context.textInk(0.4),
                  ),
                ),
              ),
              SizedBox(width: 16.w),
              Text(
                '|',
                style: AppTypography.textXsMedium.copyWith(
                  color: context.textInk(0.3),
                ),
              ),
              SizedBox(width: 16.w),
              GestureDetector(
                onTap: () => _launchUrl('https://chessever.com/terms-of-use'),
                child: Text(
                  'Terms of Use',
                  style: AppTypography.textXsMedium.copyWith(
                    color:
                        context.isLightTheme
                            ? context.colors.textSecondary
                            : context.textInk(0.4),
                    decoration: TextDecoration.underline,
                    decorationColor:
                        context.isLightTheme
                            ? context.colors.textSecondary
                            : context.textInk(0.4),
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
          );
        },
      ),
    );
  }
}

class _FeaturesList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final features = [
      (Icons.people_rounded, 'Countrymen & Favorites'),
      (Icons.person_search_rounded, 'Opponent Prep Tools'),
      (Icons.auto_stories_rounded, 'Database Storage'),
      (Icons.desktop_windows_rounded, 'ChessEver Desktop Beta'),
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
          Icon(icon, size: 20.ic, color: context.colors.accentText),
          SizedBox(width: 12.w),
          Text(
            text,
            style: AppTypography.textMdMedium.copyWith(
              color: context.colors.textPrimary.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

// Old feature list removed

enum PlanType { monthly, annual }

/// The two plan cards on their own, for layout and contrast tests.
@visibleForTesting
Widget paywallPricingForTest({
  required ValueNotifier<PlanType> selectedPlan,
  required Package? monthlyPackage,
  required Package? annualPackage,
}) => _PricingSection(
  selectedPlan: selectedPlan,
  monthlyPackage: monthlyPackage,
  annualPackage: annualPackage,
  productsError: null,
  isRetrying: false,
  onRetry: () {},
);

class _PricingSection extends HookWidget {
  const _PricingSection({
    required this.selectedPlan,
    required this.monthlyPackage,
    required this.annualPackage,
    required this.productsError,
    required this.isRetrying,
    required this.onRetry,
  });

  final ValueNotifier<PlanType> selectedPlan;
  final Package? monthlyPackage;
  final Package? annualPackage;
  final String? productsError;
  final bool isRetrying;
  final VoidCallback onRetry;

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

    // Only surface the failure once retries are exhausted. While a fetch is
    // still in flight the skeleton is honest — it really is loading.
    final showError = !hasPackages && productsError != null && !isRetrying;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showError) ...[
          _ProductsErrorRow(message: productsError!, onRetry: onRetry),
          SizedBox(height: 12.h),
        ],
        // One grid for both plans: equal heights, and every row (title,
        // note, price, per-month line) on a shared line, whatever the copy.
        IntrinsicHeight(
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            title: 'Annual',
            // BILLED AMOUNT is the main price (Apple requirement)
            price: annualPackage?.storeProduct.priceString,
            period: '/yr',
            // Monthly equivalent shown as subordinate subtitle
            subtitle: monthlyEquivalentFromAnnual,
            note: savingsPercent > 0 ? 'Save $savingsPercent%' : 'Best value',
            isLoading: !hasPackages,
            onTap:
                hasPackages ? () => selectedPlan.value = PlanType.annual : null,
          ),
        ),
          ],
        ),
        ),
      ],
    );
  }
}

/// Shown when offerings could not be loaded after retries. Replaces an
/// otherwise-permanent shimmer with something the user can act on.
class _ProductsErrorRow extends StatelessWidget {
  const _ProductsErrorRow({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            message,
            style: AppTypography.textSmMedium.copyWith(
              color: context.textInk(0.6),
            ),
          ),
        ),
        SizedBox(width: 12.w),
        GestureDetector(
          onTap: onRetry,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            // 44dp minimum tap target.
            padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 4.w),
            child: Text(
              'Try again',
              style: AppTypography.textSmBold.copyWith(color: context.colors.accentText),
            ),
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
    this.note,
    this.subtitle,
    this.isLoading = false,
  });

  final bool isSelected;
  final String title;
  final String? price;
  final String period;
  final VoidCallback? onTap;

  /// One quiet line under the title ("Save 33%"). Plain type, no pill: a
  /// plan without one still holds the slot so both cards keep their rows on
  /// the same lines.
  final String? note;

  /// Subordinate per-month line under the price; the slot is held when null.
  final String? subtitle;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isPressed = useState(false);
    final showLoading = isLoading || price == null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final light = context.isLightTheme;
    // The selected ring carries the state (cyan is ~2.2:1 on paper, so light
    // rings in the accent-text teal). A tonal fill, no bloom.
    final borderColor =
        isSelected
            ? (light ? context.colors.accentText : kPrimaryColor)
            : context.colors.textPrimary.withValues(alpha: 0.1);

    final backgroundColor =
        isSelected
            ? kPrimaryColor.withValues(alpha: 0.15)
            : context.colors.textPrimary.withValues(alpha: 0.05);

    final noteStyle = AppTypography.textXsBold.copyWith(
      color: context.colors.accentText,
    );
    final subtitleStyle = AppTypography.textXxsRegular.copyWith(
      // 0.72 keeps the per-month line at AA on the selected tint in dark.
      color: context.textInk(0.72),
    );

    // Holds a one-line slot at [style]'s height without drawing anything
    // (a no-break space). Real copy may take a second line at large text
    // sizes rather than clip.
    Widget line(String? text, TextStyle style) => ExcludeSemantics(
      excluding: text == null,
      child: Text(
        text ?? '\u00a0',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: showLoading ? null : (_) => isPressed.value = true,
      onTapUp:
          showLoading
              ? null
              : (_) {
                isPressed.value = false;
                onTap?.call();
              },
      onTapCancel: showLoading ? null : () => isPressed.value = false,
      child: _SpringPress(
        pressed: isPressed.value,
        reduceMotion: reduceMotion,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          // The border insets the content, so the thinner unselected ring
          // gives its half pixel back as padding: both cards' rows stay on
          // the same lines whichever one is selected.
          padding: EdgeInsets.all(12.sp + (isSelected ? 0 : 0.5)),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(16.br),
            border: Border.all(color: borderColor, width: isSelected ? 2 : 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.textMdBold.copyWith(
                        color:
                            isSelected
                                ? context.colors.textPrimary
                                : context.textInk(0.7),
                      ),
                    ),
                  ),
                  // The check keeps its slot so the title never shifts.
                  Opacity(
                    opacity: isSelected ? 1 : 0,
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: context.colors.accentText,
                      size: 18.ic,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 2.h),
              line(note, noteStyle),
              // Price block pinned to the bottom, so both prices share a
              // baseline even when one card's copy runs longer.
              const Spacer(),
              SizedBox(height: 10.h),
              if (showLoading)
                Container(
                  width: 60.w,
                  height: 24.h,
                  decoration: BoxDecoration(
                    color: context.colors.textPrimary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4.br),
                  ),
                )
              else
                // Main Price (BILLED AMOUNT - most prominent, Apple
                // Guideline 3.1.2)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        price!,
                        style: AppTypography.displaySmBold.copyWith(
                          color: context.colors.textPrimary,
                          fontSize: 20.sp,
                        ),
                      ),
                      SizedBox(width: 2.w),
                      Text(
                        period,
                        style: AppTypography.textSmMedium.copyWith(
                          color: context.textInk(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(height: 2.h),
              line(showLoading ? null : subtitle, subtitleStyle),
            ],
          ),
        ),
      ),
    );
  }
}

/// The 0.97 press on the paywall's cards and buttons, on a snappy spring so
/// it stays interruptible; still under reduced motion.
class _SpringPress extends StatelessWidget {
  const _SpringPress({
    required this.pressed,
    required this.reduceMotion,
    required this.child,
  });

  final bool pressed;
  final bool reduceMotion;
  final Widget child;

  static const _motion = CupertinoMotion.snappy(
    duration: Duration(milliseconds: 240),
    snapToEnd: true,
  );

  @override
  Widget build(BuildContext context) {
    return SingleMotionBuilder(
      motion: reduceMotion ? const Motion.none() : _motion,
      value: pressed ? 0.97 : 1.0,
      builder:
          (context, scale, child) => Transform.scale(
            // Springs settle a hair short of 1.0; snap so text rasterises
            // crisp at rest.
            scale: (scale - 1).abs() < 0.002 ? 1.0 : scale,
            child: child,
          ),
      child: child,
    );
  }
}

class _PurchaseButton extends HookWidget {
  const _PurchaseButton({
    required this.selectedPlan,
    required this.monthlyPackage,
    required this.annualPackage,
    required this.isLoading,
    required this.isEnabled,
    required this.onTap,
  });

  final PlanType selectedPlan;
  final Package? monthlyPackage;
  final Package? annualPackage;
  final bool isLoading;
  final bool isEnabled;
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
        buttonText = 'Try 3 Days Free, then $priceString/$periodSuffix';
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
          buttonText = 'Try 3 Days Free, then $priceString/$periodSuffix';
        }
      } else {
        buttonText = 'Try 3 Days Free, then $priceString/$periodSuffix';
      }
    } else {
      buttonText = 'Continue';
    }

    final isTappable = isEnabled && !isLoading;

    return GestureDetector(
      onTapDown: isTappable ? (_) => isPressed.value = true : null,
      onTapUp:
          isTappable
              ? (_) {
                isPressed.value = false;
                onTap();
              }
              : null,
      onTapCancel: isTappable ? () => isPressed.value = false : null,
      child: _SpringPress(
        pressed: isPressed.value,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
        child: Opacity(
          // Reads as "not ready yet" instead of inviting a tap that no-ops.
          opacity: isEnabled ? 1.0 : 0.4,
          child: Container(
          width: double.infinity,
          height: 54.h,
          // One solid brand fill with a near-black label (~8:1) in both
          // themes: no cyan-to-blue gradient, no bloom under it.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16.br),
            color: context.colors.brand,
          ),
          child: Center(
            child:
                isLoading
                    ? SizedBox(
                      width: 24.w,
                      height: 24.h,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          context.colors.inkOnAccent,
                        ),
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
                            color: context.colors.inkOnAccent,
                            letterSpacing: 0.2,
                          ),
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

/// Android-only redemption flow. Code-gated percentage offers must be
/// purchased via Google Play Billing with a specific offer token; the
/// /redeem deep link only handles 100%-off promo codes. We validate the
/// code locally, find the matching SubscriptionOption, and launch billing.
Future<void> _showAndroidCodeRedeemSheet(
  BuildContext context,
  WidgetRef ref, {
  required Package? monthlyPackage,
  required Package? annualPackage,
  required PlanType selectedPlan,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    constraints: ResponsiveHelper.bottomSheetConstraints,
    builder:
        (_) => _AndroidCodeRedeemSheet(
          parentRef: ref,
          monthlyPackage: monthlyPackage,
          annualPackage: annualPackage,
          selectedPlan: selectedPlan,
        ),
  );
}

class _AndroidCodeRedeemSheet extends HookConsumerWidget {
  const _AndroidCodeRedeemSheet({
    required this.parentRef,
    required this.monthlyPackage,
    required this.annualPackage,
    required this.selectedPlan,
  });

  final WidgetRef parentRef;
  final Package? monthlyPackage;
  final Package? annualPackage;

  /// Plan the user picked on the paywall. When a single code is tagged on
  /// both offers (so one code works for monthly and annual), this drives
  /// which one gets applied — the selected plan's offer is checked first.
  /// If the code is plan-specific (only one offer carries the tag), the
  /// fallback search picks up the other plan's offer, mirroring iOS.
  final PlanType selectedPlan;

  @override
  Widget build(BuildContext context, WidgetRef _) {
    final controller = useTextEditingController();
    final code = useState('');
    final isSubmitting = useState(false);
    final errorMessage = useState<String?>(null);

    Future<void> submit() async {
      if (isSubmitting.value) return;
      errorMessage.value = null;

      final canonical = code.value.trim();
      if (canonical.isEmpty) return;

      // Codes are managed entirely in Play Console: each subscription offer
      // is tagged with its lowercase code (e.g. `goatotb`). We look up the
      // offer by tag against the live store data, so adding, expiring, or
      // rotating codes is a Play Console operation — no app release.
      //
      // When a single code is tagged on both offers (one code → both plans),
      // the user's currently-selected plan wins; if no offer in that plan
      // carries the tag, we fall back to the other plan so a plan-specific
      // code can still override the selection (matches iOS, where ASC custom
      // codes auto-route to whichever subscription they're tied to).
      final preferred =
          selectedPlan == PlanType.annual ? annualPackage : monthlyPackage;
      final fallback =
          selectedPlan == PlanType.annual ? monthlyPackage : annualPackage;
      final match = RevenueCatService().findOfferByCode([
        if (preferred != null) preferred,
        if (fallback != null) fallback,
      ], canonical);
      if (match == null) {
        errorMessage.value = 'Invalid or expired code.';
        return;
      }

      isSubmitting.value = true;
      try {
        // Stamp attribution before handing off to Play Billing so partner
        // dashboards can see this conversion as a code redemption.
        const source = 'android_offer_token';
        final reportedCode = canonical.toUpperCase();
        final affiliate =
            await AppsflyerService.instance.getCachedAttributionContext();
        parentRef
            .read(subscriptionProvider.notifier)
            .markRedemptionPending(source: source, code: reportedCode);
        await RevenueCatService().tagRedemptionAttempt(
          source: source,
          code: reportedCode,
          affiliateContext: affiliate,
        );
        unawaited(
          AppsflyerService.instance.logRedemptionInitiated(
            source: source,
            code: reportedCode,
          ),
        );

        final result = await parentRef
            .read(subscriptionProvider.notifier)
            .purchaseSubscriptionOption(match.package, match.option);

        if (result.success) {
          // Subscription state listener on the paywall closes the sheet and
          // shows the celebration overlay; we just dismiss our own sheet.
          if (context.mounted) Navigator.of(context).pop();
        } else if (result.wasCancelled) {
          // User backed out of the Play sheet — leave them on our sheet so
          // they can retry without re-typing the code.
          if (context.mounted) errorMessage.value = null;
        } else {
          if (context.mounted) {
            errorMessage.value =
                result.errorMessage ?? 'Could not apply the discount.';
          }
        }
      } finally {
        if (context.mounted) isSubmitting.value = false;
      }
    }

    return Padding(
      // Lift the sheet above the keyboard so the CTA stays tappable.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: context.colors.surface,
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
                  color: context.colors.textPrimary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2.br),
                ),
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'Redeem a code',
              style: AppTypography.textLgBold.copyWith(color: context.colors.textPrimary),
            ),
            SizedBox(height: 6.h),
            Text(
              'Enter your code to apply your discount. The Play Store purchase sheet will open with the discounted price.',
              style: AppTypography.textSmRegular.copyWith(
                color: context.textInk(0.6),
              ),
            ),
            SizedBox(height: 16.h),
            TextField(
              controller: controller,
              autofocus: true,
              enabled: !isSubmitting.value,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.go,
              onChanged: (val) {
                code.value = val;
                if (errorMessage.value != null) errorMessage.value = null;
              },
              onSubmitted: (_) => submit(),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(40),
              ],
              style: AppTypography.textMdMedium.copyWith(
                color: context.colors.textPrimary,
                letterSpacing: 1.2,
              ),
              decoration: InputDecoration(
                hintText: 'XXXXXXXXXX',
                hintStyle: AppTypography.textMdMedium.copyWith(
                  color: context.textInk(0.25),
                  letterSpacing: 1.2,
                ),
                filled: true,
                fillColor: context.colors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.br),
                  borderSide: BorderSide(
                    color: context.colors.textPrimary.withValues(alpha: 0.08),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.br),
                  borderSide: BorderSide(
                    color: context.colors.textPrimary.withValues(alpha: 0.08),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.br),
                  borderSide: BorderSide(
                    color:
                        context.isLightTheme
                            ? context.colors.accentText
                            : kPrimaryColor,
                  ),
                ),
              ),
            ),
            if (errorMessage.value != null) ...[
              SizedBox(height: 8.h),
              Text(
                errorMessage.value!,
                style: AppTypography.textSmMedium.copyWith(
                  color:
                      context.isLightTheme
                          ? context.colors.danger
                          : const Color(0xFFFF6B6B),
                ),
              ),
            ],
            SizedBox(height: 16.h),
            _RedeemButton(
              isEnabled: code.value.trim().isNotEmpty,
              isLoading: isSubmitting.value,
              onTap: submit,
            ),
            SizedBox(height: 8.h),
            TextButton(
              onPressed:
                  isSubmitting.value ? null : () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: AppTypography.textSmMedium.copyWith(
                  color: context.textInk(0.5),
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
      child: _SpringPress(
        pressed: isPressed.value,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
        child: AnimatedOpacity(
          opacity: tappable ? 1.0 : 0.5,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: double.infinity,
            height: 54.h,
            // Solid brand fill, near-black label, no gradient or bloom.
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16.br),
              color: context.colors.brand,
            ),
            child: Center(
              child:
                  isLoading
                      ? SizedBox(
                        width: 24.w,
                        height: 24.h,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            context.colors.inkOnAccent,
                          ),
                        ),
                      )
                      : Text(
                        'Apply discount',
                        style: AppTypography.textLgBold.copyWith(
                          color: context.colors.inkOnAccent,
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
