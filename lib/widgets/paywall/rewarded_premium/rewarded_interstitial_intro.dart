import 'package:flutter/material.dart';

/// Required intro for rewarded interstitials: reward disclosure and a skip
/// action before loading/showing the alternative ad. Dismissal also skips.
Future<bool> showRewardedInterstitialIntro(BuildContext context) async {
  if (!context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Try another ad?'),
          content: const Text(
            'The first ad could not load. Watch an alternative ad '
            'to unlock 10 minutes of Premium, or skip for now.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Watch ad'),
            ),
          ],
        ),
      ) ??
      false;
}
