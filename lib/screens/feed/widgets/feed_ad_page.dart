import 'dart:async';
import 'dart:math' as math;

import 'package:chessever2/revenue_cat_service/subscribe_state.dart';
import 'package:chessever2/screens/feed/models/feed_entry.dart';
import 'package:chessever2/screens/feed/providers/feed_entries_provider.dart';
import 'package:chessever2/screens/feed/widgets/feed_layout.dart';
import 'package:chessever2/services/feed_ads_config.dart';
import 'package:chessever2/services/rewarded_premium/rewarded_access_provider.dart';
import 'package:chessever2/theme/app_colors.dart';
import 'package:chessever2/widgets/ads/ad_disclosure.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// An ad on a Feed page of its own ([FeedAdEntry]), swiped past like any
/// post: the disclosure line at the top, an inline adaptive banner as large
/// as the page leaves room for, and Remove Ads at the foot.
///
/// The ad is asked for when the page is first built, which Feed does while
/// the post before it is still on screen, so it has usually landed by the
/// time the viewer swipes on. An ad that does not come (no fill, no consent,
/// offline) withdraws its page ([feedAdWithdrawnProvider]): Feed never keeps
/// an empty page in the viewer's way.
class FeedAdPage extends ConsumerStatefulWidget {
  const FeedAdPage({required this.entry, super.key});

  final FeedAdEntry entry;

  @override
  ConsumerState<FeedAdPage> createState() => _FeedAdPageState();
}

typedef _Slot = ({int width, int height});

class _FeedAdPageState extends ConsumerState<FeedAdPage> {
  BannerAd? _ad;

  /// The size the ad actually came in; null until it has.
  AdSize? _size;

  /// The room the ad was asked for, in whole logical pixels.
  _Slot? _slot;

  /// Less room than this fits no banner worth a page.
  static const double _minHeight = 50;

  /// Wider than this (a tablet), the banner keeps a reading width.
  static const double _maxWidth = 600;

  /// The placeholder holds the medium rectangle's shape (300×250), the size
  /// most often served, so a landing ad moves little.
  static const double _placeholderRatio = 250 / 300;

  @override
  void dispose() {
    _drop();
    super.dispose();
  }

  void _drop() {
    final ad = _ad;
    _ad = null;
    _size = null;
    if (ad != null) unawaited(ad.dispose());
  }

  /// Asks for an ad once the page is laid out, and again only when its width
  /// changes (a rotation, a resized window): the height is only a ceiling.
  void _request(BoxConstraints constraints) {
    final width = math.min(constraints.maxWidth, _maxWidth).floor();
    final height = constraints.maxHeight.floor();
    if (width <= 0 || height <= 0 || _slot?.width == width) return;
    if (height < _minHeight) {
      // No banner fits: the page would only ever hold its placeholder.
      if (_ad == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _withdraw());
      }
      return;
    }
    final slot = (width: width, height: height);
    _slot = slot;
    // Consent prompts must not open during a build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _slot == slot) unawaited(_load(slot));
    });
  }

  Future<void> _load(_Slot slot) async {
    if (!FeedAdsConfig.available ||
        ref.read(subscriptionProvider).isSubscribed) {
      return;
    }
    final shown = _ad;
    if (shown != null) {
      // Out of the tree first: an ad is never disposed under its AdWidget.
      setState(() {
        _ad = null;
        _size = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(shown.dispose());
      });
    }
    try {
      await ref
          .read(rewardedAccessProvider.notifier)
          .ads
          .prepareConsent(context);
      if (!mounted ||
          _slot != slot ||
          ref.read(subscriptionProvider).isSubscribed) {
        return;
      }
      final ad = BannerAd(
        adUnitId: FeedAdsConfig.unitId,
        size: AdSize.getInlineAdaptiveBannerAdSize(slot.width, slot.height),
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) => unawaited(_show(ad as BannerAd)),
          onAdFailedToLoad: (ad, error) {
            debugPrint('[FeedAd] no ad: ${error.code} ${error.message}');
            unawaited(ad.dispose());
            if (!identical(ad, _ad)) return;
            _ad = null;
            _withdraw();
          },
        ),
      );
      _ad = ad;
      await ad.load();
    } catch (error) {
      // Closed on the way (the page scrolled out of the cache) is not a
      // failure: built again, it asks again.
      if (!mounted || _slot != slot) return;
      debugPrint('[FeedAd] unavailable: $error');
      _drop();
      _withdraw();
    }
  }

  /// The ad landed: its box takes the size it actually came in, which an
  /// inline adaptive banner only knows once it has.
  Future<void> _show(BannerAd ad) async {
    AdSize? size;
    try {
      size = await ad.getPlatformAdSize();
    } catch (_) {}
    if (!mounted || !identical(ad, _ad)) return;
    if (size == null) {
      _drop();
      _withdraw();
      return;
    }
    setState(() => _size = size);
  }

  void _withdraw() {
    if (!mounted) return;
    final withdrawn = ref.read(feedAdWithdrawnProvider.notifier);
    withdrawn.state = {...withdrawn.state, widget.entry.key};
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    final size = _size;
    return Semantics(
      key: ValueKey('feed_ad_${widget.entry.after}'),
      container: true,
      label: 'Advertisement',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          FeedLayout.sidePadding,
          14,
          FeedLayout.sidePadding,
          6,
        ),
        child: Column(
          children: [
            const AdDisclosureLine(),
            const SizedBox(height: 10),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _request(constraints);
                  final width = math.min(constraints.maxWidth, _maxWidth);
                  final Widget slot;
                  if (ad != null && size != null) {
                    slot = SizedBox(
                      width: math.min(size.width.toDouble(), width),
                      height: math.min(
                        size.height.toDouble(),
                        constraints.maxHeight,
                      ),
                      child: AdWidget(key: ObjectKey(ad), ad: ad),
                    );
                  } else {
                    slot = ExcludeSemantics(
                      child: Container(
                        key: const ValueKey('feed_ad_placeholder'),
                        width: width,
                        height: math.min(
                          constraints.maxHeight,
                          width * _placeholderRatio,
                        ),
                        decoration: BoxDecoration(
                          color: context.colors.skeleton,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    );
                  }
                  return Center(child: slot);
                },
              ),
            ),
            // Clear of the ad, so a tap meant for one never lands on the
            // other.
            const SizedBox(height: 16),
            const RemoveAdsButton(returnTo: 'feed'),
          ],
        ),
      ),
    );
  }
}
