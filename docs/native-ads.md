# Today native ad

The Today feed placement is currently removed for performance comparison.
No native ad widget is mounted or native ad request initiated by the feed,
regardless of build flags. The integration and IDs below are retained for
possible reintroduction.

The production Android/iOS Today feed displays one Native Advanced ad between
its first and second regular events. Pinned smart events stay above them.
There is no placement with fewer than two regular events, while subscription
status is loading, or with paid/active rewarded Premium access. Other tabs and
ChessEver Test do not request native ads.

The SDK's medium native template provides ad attribution, AdChoices, and a
video media area above the 120×120 minimum. The card reserves 400 logical pixels
of height to fit the media and text assets. ATT,
UMP consent, test-device configuration and SDK initialization share the rewarded
ad setup. Unavailable inventory and loading failures collapse the placement.

## Configuration

Debug uses Google's native test units. Run your usual command on a simulator
or device to check the placement:

```sh
flutter run --dart-define-from-file=.env
```

Production native IDs are configured as defaults. Optional build defines, or
corresponding keys in your local define file, can override them:

```text
ADMOB_ANDROID_NATIVE_ID=ca-app-pub-3681310687796023/2917470581
ADMOB_IOS_NATIVE_ID=ca-app-pub-3681310687796023/4370153050
```

`NATIVE_ADS_ENABLED=false` disables this placement. It defaults to true and is
independent of `REWARDED_PREMIUM_ENABLED`. Profile/release uses these native IDs;
use a registered test device for development with those builds. An empty or
invalid ID override disables the placement on that platform in profile/release.

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
