import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

bool _promptOpen = false;

/// Building and exploring an opening tree from a database, a collection or
/// a My Prep player is Premium, as desktop's tree is: the same sheet every
/// Premium surface shows, with its watch-an-ad unlock.
Future<bool> ensureGameTreeAccess(BuildContext context) async {
  if (!context.mounted) return false;
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(premiumAccessProvider)) return true;
  if (_promptOpen) return false;
  _promptOpen = true;
  try {
    return await showPremiumPaywallSheet(
      context: context,
      featureId: 'build_tree',
      returnTo: 'library',
    );
  } finally {
    _promptOpen = false;
  }
}

/// Saving a My Prep player to the cloud library, and keeping that copy in
/// step with new games, is Premium.
Future<bool> ensurePrepCloudAccess(BuildContext context) async {
  if (!context.mounted) return false;
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(premiumAccessProvider)) return true;
  if (_promptOpen) return false;
  _promptOpen = true;
  try {
    return await showPremiumPaywallSheet(
      context: context,
      featureId: 'prep_cloud_sync',
      returnTo: 'library',
    );
  } finally {
    _promptOpen = false;
  }
}
