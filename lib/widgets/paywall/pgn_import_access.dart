import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

bool _promptOpen = false;

/// PGN imports require paid or active rewarded access, including in debug.
Future<bool> ensurePgnImportAccess(BuildContext context) async {
  if (!context.mounted) return false;
  if (ProviderScope.containerOf(
    context,
    listen: false,
  ).read(premiumAccessProvider)) {
    return true;
  }
  if (_promptOpen) return false;
  _promptOpen = true;
  try {
    return await showPremiumPaywallSheet(
      context: context,
      featureId: 'pgn_import',
      returnTo: 'library/pgn_import',
    );
  } finally {
    _promptOpen = false;
  }
}
