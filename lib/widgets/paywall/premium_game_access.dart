import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Browse freely, but require paid/rewarded access before opening the game.
Future<bool> ensurePremiumGameAccess(
  BuildContext context, {
  required String featureId,
  required String returnTo,
}) async {
  if (!context.mounted) return false;
  if (ProviderScope.containerOf(
    context,
    listen: false,
  ).read(premiumAccessProvider)) {
    return true;
  }
  return showPremiumPaywallSheet(
    context: context,
    featureId: featureId,
    returnTo: returnTo,
  );
}
