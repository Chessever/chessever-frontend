import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/glass_dialog_route.dart';
import 'package:chessever2/widgets/paywall/rewarded_premium/choice_plate.dart';
import 'package:chessever2/widgets/paywall/rewarded_premium/premium_marks.dart';
import 'package:flutter/material.dart';

/// Required intro for rewarded interstitials: reward disclosure and a skip
/// action before loading/showing the alternative ad. Dismissal also skips.
Future<bool> showRewardedInterstitialIntro(BuildContext context) async {
  if (!context.mounted) return false;
  // No fade, so the card's glass is frosted from its first frame. Skip, an
  // outside tap and back all answer false.
  return await showGlassDialog<bool>(
        context: context,
        builder: (_) => const _InterstitialIntro(),
      ) ??
      false;
}

/// The Unlock Premium chooser's language, a step smaller: it opens over the
/// chooser (whose Watch ad led here), so it is a narrower card on the same
/// glass, and its one choice is the chooser's Watch ad plate, play mark and
/// all. The reward is named in the copy, as the ad format requires.
class _InterstitialIntro extends StatelessWidget {
  const _InterstitialIntro();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GlassDialog(
      tone: colors.popup,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      constraints: const BoxConstraints(maxWidth: 320),
      borderRadius: BorderRadius.circular(20),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                namesRoute: true,
                header: true,
                child: Text(
                  'Try another ad?',
                  textAlign: TextAlign.center,
                  style: premiumPopupType(
                    22,
                    1.25,
                    FontWeight.w700,
                    colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'The first ad didn’t load. Watch another for 10 minutes '
                'of Premium.',
                textAlign: TextAlign.center,
                style: premiumPopupType(
                  15,
                  1.4,
                  FontWeight.w400,
                  colors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              ChoicePlate(
                label: 'Watch ad',
                glyph: ChoiceGlyph.play,
                tone: ChoicePlateTone.watch(
                  colors,
                  light: context.isLightTheme,
                ),
                onTap: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: 4),
              ChoiceDismissButton(
                label: 'Skip',
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
