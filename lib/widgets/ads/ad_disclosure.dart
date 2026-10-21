import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';

/// The line every ad placement opens with, above the ad.
class AdDisclosureLine extends StatelessWidget {
  const AdDisclosureLine({super.key});

  static const String text = 'We use ads to keep ChessEver available for all';

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
    );
  }
}

/// The action every ad placement closes with, under the ad: straight to the
/// subscription paywall. A rewarded unlock is temporary, which is not what
/// "Remove Ads" promises.
class RemoveAdsButton extends StatelessWidget {
  const RemoveAdsButton({this.returnTo, super.key});

  /// The surface the viewer resumes on once subscribed (paywall analytics).
  final String? returnTo;

  static const String label = 'Remove Ads';

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => showPremiumPaywallSheet(
        context: context,
        featureId: 'remove_ads',
        returnTo: returnTo,
        allowRewarded: false,
      ),
      style: TextButton.styleFrom(
        foregroundColor: context.colors.accentText,
        minimumSize: const Size(0, 44),
      ),
      child: const Text(
        label,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}
