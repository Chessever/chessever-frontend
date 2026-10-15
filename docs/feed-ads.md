# Feed ads

Discovery › Feed shows an ad on a page of its own after every fifth post
(`kFeedAdEvery`), swiped past like any post. Only viewers without paid or
active rewarded access see it, on Android and iOS, once the subscription has
first been checked. Nothing gates scrolling: the old Watch ad / Upgrade prompt
between posts is gone.

Each ad page carries the ad surfaces' shared frame (`ad_disclosure.dart`):
"We use ads to keep ChessEver available for all" above the ad and "Remove Ads"
under it, which opens the subscription paywall (`featureId: remove_ads`,
`returnTo: feed`, no rewarded option).

## Format

An inline adaptive banner (`AdSize.getInlineAdaptiveBannerAdSize`) as wide as
the page (at most 600) and at most as tall as the room between the two lines,
so AdMob can fill the page with a tall creative. The ad is requested when the
page is first built, which Feed does while the post before it is on screen. A
request with no fill, no consent or no network withdraws its page
(`feedAdWithdrawnProvider`); Feed never shows an empty page. Ad pages that join
or leave before the viewer (Premium bought or ended, a withdrawn ad) keep the
viewer on the post they were on.

ATT, UMP consent, test devices and SDK initialization share the rewarded ad
setup (`RewardedAds.prepareConsent`).

## AdMob units

"Feed inline adaptive banner", banner format, automatic refresh disabled (each
ad page requests its own ad), created 2026-10-15:

```text
ADMOB_ANDROID_FEED_BANNER_ID=ca-app-pub-3681310687796023/7169486456
ADMOB_IOS_FEED_BANNER_ID=ca-app-pub-3681310687796023/9843751253
```

These are the defaults in `FeedAdsConfig`; the defines override them. Debug
uses Google's adaptive banner test units. `FEED_ADS_ENABLED=false` turns the
placement off. New units can take up to an hour to start serving.

## Device checks

- Free account: an ad page after the fifth post, with both lines; swiping on
  and back works over the ad; tapping the ad opens it; Remove Ads opens the
  paywall without a Watch ad option.
- Subscribe from Remove Ads: the ad pages leave, the post on screen stays.
- Rewarded access active: no ad pages; when it ends, they return without
  moving the viewer.
- Airplane mode or declined consent: no ad pages, no blank pages.
- Phone and tablet, light and dark, portrait and landscape.
