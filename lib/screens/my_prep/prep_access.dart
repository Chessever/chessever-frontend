import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

bool _promptOpen = false;

/// Whether the reader may download Prep games right now, without asking.
bool hasPrepAccess(WidgetRef ref) => ref.read(premiumAccessProvider);

/// Adding players and downloading or refreshing their games is Premium, as
/// it is in desktop Prep. Games already downloaded stay readable.
Future<bool> ensurePrepAccess(BuildContext context) async {
  if (!context.mounted) return false;
  final container = ProviderScope.containerOf(context, listen: false);
  if (container.read(premiumAccessProvider)) return true;
  if (_promptOpen) return false;
  _promptOpen = true;
  try {
    return await showPremiumPaywallSheet(
      context: context,
      featureId: 'my_prep',
      returnTo: 'my_space/my_prep',
    );
  } finally {
    _promptOpen = false;
  }
}
