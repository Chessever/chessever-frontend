# Today native ad

The production Android/iOS Today feed displays one Native Advanced ad between
its first and second regular events. Pinned smart events stay above them.
There is no placement with fewer than two regular events, while subscription
status is loading, or with paid/active rewarded Premium access. Other tabs and
ChessEver Test do not request native ads.

The SDK's small native template provides ad attribution and AdChoices. ATT,
UMP consent, test-device configuration and SDK initialization share the rewarded
ad setup. Unavailable inventory and loading failures collapse the placement.

## Configuration

Debug uses Google's native test units. Run your usual command on a simulator
or device to check the placement:

```sh
flutter run --dart-define-from-file=.env
```

Live native ads remain disabled until the platform's separate Native Advanced
ad-unit ID is configured. Create it in AdMob under Apps → the production app →
Ad units → Add ad unit → Native Advanced. Rewarded IDs cannot be reused.

Add these build defines, or the corresponding keys in your local define file:

```text
ADMOB_ANDROID_NATIVE_ID=ca-app-pub-.../...
ADMOB_IOS_NATIVE_ID=ca-app-pub-.../...
```

`NATIVE_ADS_ENABLED=false` disables this placement. It defaults to true and is
independent of `REWARDED_PREMIUM_ENABLED`. Profile/release requires a configured
native ID; use a registered test device for development with those builds.

## Device checks

- Free user, Today, two or more events: one labeled ad after the first regular
  event; event navigation, pagination and refresh still work.
- Check phone and tablet, light and dark themes, and scrolling away and back.
- Other tabs, fewer than two events, and ChessEver Test: no placement.
- Paid subscription or active rewarded access: no native ad. Subscription
  purchase hides it immediately.
- Decline consent or disconnect before loading: event feed stays usable and no
  blank ad panel remains. Privacy choices stay available under About when UMP
  requires them.

Reference: https://developers.google.com/admob/flutter/native/templates
