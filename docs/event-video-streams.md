# Event video in the app

YouTube, Twitch and Kick appear between the engine row and notation. The camera
button replaces board swap when the event has valid streams; **Flip board** moves
to the phone/tablet three-dot menu. Hiding video restores the user's engine layout.
Vertical drags starting on the player scroll the game screen; taps and horizontal
seeking remain with the video controls. The initial player is paused. Flags appear initially and on player touch, dismiss
three seconds after interaction, and hold open during scrolling. Each stream has
its own flag and provider label, including streams sharing the same language.

Stream selection uses the locally saved country from a manually selected flag
(`ce-video-country.v1`), falling back to the current Countrymen selection when no
valid local preference exists. Exact-country streams come first, then streams
in the configured commentary-language group, then the event's normal order.
The first stream in that order is selected paused; an existing event selection
or playing stream stays selected. If neither country nor language group matches,
the event default wins. The language groups are maintained in
`video_country_preference.dart`; multilingual countries may belong to multiple
groups, and explicit stream language controls group matching.

The camera action is always white: crossed out to hide a visible video, and
uncrossed to show a hidden video.

## Flavor configuration

The production flavor (`lib/main.dart`) enables video by default using the approved
read-only spectator API at `https://api.broadcast.chessever.com`. Its embedded
player uses `https://chessever.com` for the base URL, Twitch parent, and YouTube
origin/referrer. No video Dart defines are needed for that flavor.

The test flavor (`lib/main_test.dart`) remains isolated and has no default video
origins. Supply both Dart defines in its existing development/release configuration:

- `CHESSEVER_TEST_VIDEO_API_ORIGIN`: verified test broadcasting API HTTPS origin.
- `CHESSEVER_TEST_VIDEO_EMBED_ORIGIN`: verified test HTTPS origin for the embedded
  document's base URL, Twitch parent, and YouTube origin/referrer.

Neither test define has a default or production fallback. The production flavor ignores both.
Origins must be HTTPS without credentials, a port, a path, query, or fragment,
and contain a dedicated `test`/`staging` hostname label (also accepted:
`test-*`, `staging-*`, `*-test`). Naming is a guard, **not proof of isolation**:
verify the backing environment before configuring either address. The actual
embed origin/referrer must be accepted by the providers on Android and iOS.
Missing/invalid configuration leaves normal game controls and analysis available.
Do not substitute the production broadcasting origin in the test flavor.

Reads use `/api/broadcast/round/:roundId/video-streams`, or
`/api/broadcast/:tourId/video-streams` only when no round is present. The server
resolves round/tour/group inheritance and visibility; the app does not query
private video tables. HTTP redirects are not followed. Reads refresh every 30
seconds in foreground. Temporary failures retain the player; 401/403/404/410
clear it. No migrations, server edits, or deployments are included.

## Playback and ownership

The route owns one player controller. Only the active game attaches its view;
changing games in the same tour preserves selection, visibility, and playback.
The game model has no parent-event ID, so the tour ID is the event/session key.
Language preference persists locally across events; exact stream/visibility
choices last for the board route. The existing web language mapping and
English/preferred/audience ordering are mirrored in the Dart model. Audience
snapshots freeze per viewed round, and duplicate channel totals are counted once.

YouTube/Twitch report actual playing/paused state. Kick documents no supported
playback-state API, so switching **away from Kick** conservatively leaves the next
stream paused. Switching from a confirmed playing YouTube/Twitch stream requests
playback on the selected provider; platform gesture policy may still require Play.
Hide, background, covering the board with another route, and leaving the event
stop playback. Show/return is paused. Provider offline/restriction notices remain
inside the player, with a retry action for wrapper failures.

Twitch needs a 400×300 view. Narrow phones offer **Watch Twitch in landscape**,
which opens a rotated in-app viewer without changing the device orientation
policy. Closing it returns to the selected stream paused. No offscreen Twitch
player starts behind the expansion button.

## Validation and device checklist

Fixtures live in `test/fixtures/event_video_streams.json`; tests use a fake player
and never contact providers. Run scoped `flutter analyze --no-pub` and the
`event_video*_test.dart` tests. No app build/run is needed for static validation.

Using the production flavor, or the test flavor with verified test origins and
streams, the user checks on Android and iOS:

1. Open a streamed game: flags show; video is below the engine slot, above notation,
   and paused. Flags disappear after three seconds; touch video to reveal them.
2. Scroll/select repeated-language flags. The timer restarts; a paused stream stays
   paused, and switching from confirmed playback requests continued playback.
3. Hide/show video. Normal engine lines return when hidden; Show stays paused.
   Swap board works in the top-right menu. Events without video keep bottom swap.
4. Switch games in the same tour during playback. Check there is one player, no
   audio duplication, and no restart. Switch to an event without streams.
5. On a narrow phone, expand Twitch, play, select streams, and close/back to the
   board. Check notation scrolling (including drags starting on the video), portrait/tablet
   landscape, and rotation.
6. Background the app, cover the board with another screen, and leave the event.
   Verify audio stops and returning never auto-starts playback.

The Stockfish debug kill switch is unchanged; empty debug PVs remain expected.
