import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Report access includes cached reports and has no debug or first-report bypass.
Future<bool> ensureGameReportAccess(BuildContext context) async {
  if (ProviderScope.containerOf(
    context,
    listen: false,
  ).read(premiumAccessProvider)) {
    return true;
  }
  return showPremiumPaywallSheet(
    context: context,
    featureId: 'game_reports',
    returnTo: 'game_reports',
  );
}
