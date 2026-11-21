import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/glass_dialog_route.dart';
import 'package:flutter/material.dart';

/// Required intro for rewarded interstitials: reward disclosure and a skip
/// action before loading/showing the alternative ad. Dismissal also skips.
Future<bool> showRewardedInterstitialIntro(BuildContext context) async {
  if (!context.mounted) return false;
  // Material's alert dialog on the popups' glass (its old dialog-theme
  // surface and corner), opened without a fade so the frost is there from
  // the first frame.
  return await showGlassDialog<bool>(
        context: context,
        builder: (dialogContext) => GlassAlertFrame(
          tone:
              DialogTheme.of(dialogContext).backgroundColor ??
              dialogContext.colors.popup,
          borderRadius: BorderRadius.circular(28),
          child: AlertDialog(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            shadowColor: Colors.transparent,
            elevation: 0,
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
        ),
      ) ??
      false;
}
