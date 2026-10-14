import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

bool _promptOpen = false;

/// Copying a PGN to the clipboard, one game or a whole event, requires paid
/// or active rewarded access, including in debug: the Watch ad / Upgrade
/// chooser every Premium surface shows. Copy FEN is unchanged.
Future<bool> ensurePgnCopyAccess(
  BuildContext context, {
  String featureId = 'copy_pgn',
  required String returnTo,
}) async {
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
      featureId: featureId,
      returnTo: returnTo,
    );
  } finally {
    _promptOpen = false;
  }
}
