import 'package:chessever2/services/analytics/analytics_service.dart';
import 'premium_paywall_view.dart';
export 'premium_paywall_view.dart' show PaywallTrigger, PlanType;
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_ads.dart';
import 'package:chessever2/widgets/paywall/rewarded_premium/rewarded_access_ui.dart';
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
/// [trigger] selects the reference headline; other entry points use settings.
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
  bool allowRewarded = true,
  PaywallTrigger trigger = PaywallTrigger.settings,
}) async {
  if (allowRewarded && RewardedAdsConfig.available) {
    final container = ProviderScope.containerOf(context, listen: false);
    if (container.read(subscriptionProvider).isLoading) {
      await container.read(subscriptionProvider.notifier).refresh();
      if (!context.mounted) return false;
    }
    if (container.read(premiumAccessProvider)) {
      return resumePremiumAction(context, onEntitled: onEntitled);
    }
    final unlocked = await showRewardedAccessChoice(
      context,
      upgrade: (host) => showPremiumPaywallSheet(
        context: host,
        featureId: featureId,
        returnTo: returnTo,
        allowRewarded: false,
        trigger: trigger,
      ),
    );
    if (!unlocked || !context.mounted) return false;
    return resumePremiumAction(context, onEntitled: onEntitled);
  }
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

  AnalyticsService.instance.trackEventDetached(
    "paywall_shown",
    properties: {"trigger": trigger.name},
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
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: ResponsiveHelper.bottomSheetConstraints,
    builder: (_) => _PremiumPaywallSheet(
      hostContext: context,
      handoff: handoff,
      trigger: trigger,
    ),
  );
  if (result != true) {
    AnalyticsService.instance.trackEventDetached(
      "paywall_dismissed",
      properties: {"trigger": trigger.name},
    );
    return false;
  }
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
  if (kDebugMode && !RewardedAdsConfig.available) {
    return resumePremiumAction(context, onEntitled: onEntitled);
  }

  if (RewardedAdsConfig.available) {
    return showPremiumPaywallSheet(
      context: context,
      featureId: featureId,
      returnTo: returnTo,
      onEntitled: onEntitled,
    );
  }
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
  if (kDebugMode && !RewardedAdsConfig.available) {
    return resumePremiumAction(context, onEntitled: onEntitled);
  }

  if (RewardedAdsConfig.available) {
    return showPremiumPaywallSheet(
      context: context,
      featureId: featureId,
      returnTo: returnTo,
      onEntitled: onEntitled,
    );
  }
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

class _PremiumPaywallSheet extends StatelessWidget {
  const _PremiumPaywallSheet({
    required this.hostContext,
    this.handoff,
    required this.trigger,
  });
  final BuildContext hostContext;
  final _PaywallHandoff? handoff;
  final PaywallTrigger trigger;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height,
    child: _PaywallContent(
      hostContext: hostContext,
      handoff: handoff,
      trigger: trigger,
    ),
  );
}

class _PaywallContent extends HookConsumerWidget {
  const _PaywallContent({
    required this.hostContext,
    this.handoff,
    required this.trigger,
  });

  final PaywallTrigger trigger;

  final BuildContext hostContext;
  final _PaywallHandoff? handoff;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      final ctx = hostContext.mounted
          ? hostContext
          : (context.mounted ? context : null);
      if (ctx == null) return;
      Navigator.maybeOf(ctx, rootNavigator: true)?.pop(result);
    }

    Future<void> handlePurchase() async {
      final package = selectedPlan.value == PlanType.annual
          ? annualPackage
          : monthlyPackage;

      if (package == null) return;

      AnalyticsService.instance.trackEventDetached(
        "paywall_purchase_started",
        properties: {"trigger": trigger.name, "plan": selectedPlan.value.name},
      );
      isLoading.value = true;
      final result = await ref
          .read(subscriptionProvider.notifier)
          .purchaseSubscription(package);
      if (result.success) {
        AnalyticsService.instance.trackEventDetached(
          "paywall_purchase_succeeded",
          properties: {
            "trigger": trigger.name,
            "plan": selectedPlan.value.name,
          },
        );
      }
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
        final affiliate = await AppsflyerService.instance
            .getCachedAttributionContext();
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

    return PremiumPaywallView(
      trigger: trigger,
      plan: selectedPlan.value,
      annual: annualPackage,
      monthly: monthlyPackage,
      busy: isLoading.value || subscriptionState.isLoading,
      loadingProducts: subscriptionState.isLoadingProducts,
      error: subscriptionState.error == null
          ? null
          : "Something went wrong. Please try again.",
      productsError: subscriptionState.productsError,
      onSelect: (plan) {
        selectedPlan.value = plan;
        AnalyticsService.instance.trackEventDetached(
          "paywall_plan_selected",
          properties: {"trigger": trigger.name, "plan": plan.name},
        );
      },
      onPurchase: handlePurchase,
      onRestore: handleRestore,
      onRedeem: handleHaveCode,
      onClose: closePaywall,
      onRetry: () => unawaited(
        ref.read(subscriptionProvider.notifier).loadProducts(force: true),
      ),
      onOpenUrl: _launchUrl,
    );
  }
}

@visibleForTesting
Widget paywallPricingForTest({
  required ValueNotifier<PlanType> selectedPlan,
  required Package? monthlyPackage,
  required Package? annualPackage,
}) => ValueListenableBuilder<PlanType>(
  valueListenable: selectedPlan,
  builder: (context, plan, _) => PremiumPaywallView(
    plan: plan,
    annual: annualPackage,
    monthly: monthlyPackage,
    busy: false,
    loadingProducts: false,
    onSelect: (value) => selectedPlan.value = value,
    onPurchase: () {},
    onRestore: () {},
    onRedeem: () {},
    onClose: () {},
    onRetry: () {},
    onOpenUrl: (_) {},
    pricingOnly: true,
  ),
);

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
      builder: (context, scale, child) => Transform.scale(
        // Springs settle a hair short of 1.0; snap so text rasterises
        // crisp at rest.
        scale: (scale - 1).abs() < 0.002 ? 1.0 : scale,
        child: child,
      ),
      child: child,
    );
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
    builder: (_) => _AndroidCodeRedeemSheet(
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
      final preferred = selectedPlan == PlanType.annual
          ? annualPackage
          : monthlyPackage;
      final fallback = selectedPlan == PlanType.annual
          ? monthlyPackage
          : annualPackage;
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
        final affiliate = await AppsflyerService.instance
            .getCachedAttributionContext();
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
              style: AppTypography.textLgBold.copyWith(
                color: context.colors.textPrimary,
              ),
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
                    color: context.isLightTheme
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
                  color: context.isLightTheme
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
              onPressed: isSubmitting.value
                  ? null
                  : () => Navigator.of(context).pop(),
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
      onTapUp: tappable
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
              child: isLoading
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
