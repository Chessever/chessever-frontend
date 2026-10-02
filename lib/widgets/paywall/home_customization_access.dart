import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Home customization belongs to paid subscriptions, never rewarded sessions.
Future<bool> ensureHomeCustomizationAccess(
  BuildContext context,
  WidgetRef ref, {
  String? featureId,
  String? returnTo,
  PremiumResume? onEntitled,
}) async {
  if (!context.mounted) return false;
  if (ref.read(subscriptionProvider).isSubscribed) {
    if (onEntitled != null) await onEntitled();
    return true;
  }
  return showPremiumPaywallSheet(
    context: context,
    featureId: featureId,
    returnTo: returnTo,
    onEntitled: onEntitled,
    allowRewarded: false,
  );
}
