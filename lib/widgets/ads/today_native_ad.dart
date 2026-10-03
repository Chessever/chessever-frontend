import 'dart:async';

import 'package:chessever2/services/native_ads_config.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/paywall/premium_paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// One SDK-rendered native ad, including attribution and AdChoices controls.
/// Loading and failed requests occupy no space in the event feed.
class TodayNativeAd extends ConsumerStatefulWidget {
  const TodayNativeAd({super.key});

  @override
  ConsumerState<TodayNativeAd> createState() => _TodayNativeAdState();
}

class _TodayNativeAdState extends ConsumerState<TodayNativeAd>
    with AutomaticKeepAliveClientMixin {
  NativeAd? _ad;
  bool _loaded = false;
  bool _started = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Consent UI must not be presented during the feed's build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load() async {
    if (!NativeAdsConfig.available || ref.read(premiumAccessProvider)) return;
    try {
      await ref
          .read(rewardedAccessProvider.notifier)
          .ads
          .prepareConsent(context);
      if (!mounted || ref.read(premiumAccessProvider)) return;
      final colors = Theme.of(context).colorScheme;
      final ad = NativeAd(
        adUnitId: NativeAdsConfig.unitId,
        request: const AdRequest(),
        nativeTemplateStyle: NativeTemplateStyle(
          // The compact template's media area is below the 120x120 video
          // minimum. Medium provides a full-width video region on both OSes.
          templateType: TemplateType.medium,
          mainBackgroundColor: colors.surfaceContainerHigh,
          primaryTextStyle: NativeTemplateTextStyle(
            textColor: colors.onSurface,
          ),
          secondaryTextStyle: NativeTemplateTextStyle(
            textColor: colors.onSurfaceVariant,
          ),
          tertiaryTextStyle: NativeTemplateTextStyle(
            textColor: colors.onSurfaceVariant,
          ),
          callToActionTextStyle: NativeTemplateTextStyle(
            textColor: colors.onPrimary,
            backgroundColor: colors.primary,
          ),
        ),
        listener: NativeAdListener(
          onAdLoaded: (ad) {
            if (mounted && identical(ad, _ad)) {
              setState(() => _loaded = true);
            }
          },
          onAdFailedToLoad: (ad, _) {
            if (identical(ad, _ad)) _ad = null;
            unawaited(ad.dispose());
          },
        ),
      );
      _ad = ad;
      await ad.load();
    } catch (_) {
      // An optional feed placement should not interrupt reading events.
      final ad = _ad;
      _ad = null;
      if (ad != null) unawaited(ad.dispose());
    }
  }

  @override
  void dispose() {
    final ad = _ad;
    _ad = null;
    if (ad != null) unawaited(ad.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (!_loaded || _ad == null) return const SizedBox.shrink();
    return Padding(
      // The next event already supplies its own top spacing. Avoid doubling
      // that gap, and leave a small gap after the preceding game cards.
      padding: const EdgeInsets.only(top: 8),
      child: Center(
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'We use ads to keep ChessEver available for all',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              SizedBox(height: 350, child: AdWidget(ad: _ad!)),
              TextButton(
                // Straight to the paywall: a rewarded unlock is temporary,
                // which is not what "Remove Ads" promises.
                onPressed:
                    () => showPremiumPaywallSheet(
                      context: context,
                      featureId: 'remove_ads',
                      allowRewarded: false,
                    ),
                style: TextButton.styleFrom(
                  foregroundColor: context.colors.accentText,
                  minimumSize: const Size(0, 44),
                ),
                child: const Text(
                  'Remove Ads',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
