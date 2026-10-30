# Feed ads

Discovery › Feed shows a non-rewarded ad on a page of its own at positions
3, 8, 13, 18… (`kFeedAdEvery` counts pages, including ads), swiped past like
any post. Only viewers without a paid subscription see it, on Android and iOS,
once the subscription has first been checked. Nothing gates scrolling: the old Watch ad / Upgrade prompt
between posts is gone.

Each ad page carries the ad surfaces' shared frame (`ad_disclosure.dart`):
"We use ads to keep ChessEver available for all" above the ad and "Remove Ads"
under it, which opens the subscription paywall (`featureId: remove_ads`,
`returnTo: feed`, no rewarded option).

## News reader

Discovery › News keeps ads out of the grid and reuses these same ad pages,
placement cadence, consent setup and paid-subscription eligibility inside the
horizontal article reader. Temporary rewarded Premium does not remove ads.
Articles have no reading allowance or Watch ad / Subscribe interruption.
Remove Ads remains an explicit action on an ad page (`returnTo: news/reader`).
Unavailable ad slots are withdrawn only from that reader route, preserving its
current article and vertical reading position without affecting Feed's slots.

At an article's bottom, a deliberate upward pull fills a progress indicator.
Release past the threshold to advance one page, or tap the same footer action.
A scheduled ad remains in the sequence. Short pulls, canceled gestures and
ballistic scrolling never advance. Next batches share the reader's in-flight
request, and failed loads keep the article available for retry. Reduced motion
uses an immediate page change and a static loading indicator.

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

- Guest or free account: ad pages at positions 3, 8, 13…, with both lines; swiping on
  and back works over the ad; tapping the ad opens it; Remove Ads opens the
  paywall without a Watch ad option.
- Subscribe from Remove Ads: the ad pages leave, the post on screen stays.
- Rewarded access active without a paid subscription: ad pages still appear.
- Airplane mode or declined consent: no ad pages, no blank pages.
- Phone and tablet, light and dark, portrait and landscape.

- News: open a card beyond the first ad slot directly, then swipe both ways;
  only reader pages contain ads, and no reading-access prompt appears.
- News: at the article end, compare a short pull, a long pull and a fast fling;
  only a long pull released past the threshold advances. Tap the footer too.
- News: subscribe or lose ad fill while reading; retain the current article and
  scroll position. Verify the last article has no next action once all news loads.
- News: check large text and Reduce Motion in both themes.

Pulling up at the end of a News article or tapping its footer brings the next
article or ad in from below. Horizontal browsing and each article's independent
reading position remain available. Reduced motion advances immediately.
