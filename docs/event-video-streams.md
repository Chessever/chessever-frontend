# Event video in the app

YouTube, Twitch and Kick appear directly under the board, with the engine lines
below the stream (the reader's own engine settings, identical to watch mode off).
Phones and tablets keep the notation/explorer panel below the engine lines
at a bounded, scrollable height. The camera
button replaces board swap when the event has valid streams; **Flip board** moves
to the phone/tablet three-dot menu, keeping the circular refresh mark from the
bottom bar. Hiding video restores the user's engine layout. Turning watch mode
on or off animates the layout. Swiping games keeps adjacent watch layouts
consistent and transfers the single player without an entrance fade.
Vertical drags starting on the player scroll the game screen; taps and horizontal
seeking remain with the video controls. The preferred stream loads paused, with
horizontal flags above it. Flags appear on first entry and deliberate video taps,
then dismiss after three seconds of inactivity. Scrolling holds dismissal;
selecting a flag restarts the timer. Game switches do not reveal flags.
Each stream has its own flag, provider label and selected styling. Switching
streams continues only confirmed playback; a paused stream stays paused.
Provider controls remain enabled without reloading the embed on taps.

Stream selection uses the locally saved country from a manually selected flag
(`ce-video-country.v1`), falling back to the current Countrymen selection when no
valid local preference exists. Saved-country streams come first, then exact Countrymen-country streams, then
related-language streams for those preferences, then the event's normal order.
This ordering is frozen during the event when a stream is selected; the newly
saved preference applies when opening another event.
The first stream in that order is selected initially. An existing event selection stays selected.
If neither country nor language group matches,
the event default wins. The language groups are maintained in
`video_country_preference.dart`; multilingual countries may belong to multiple
groups, and explicit stream language controls group matching.

The camera action is always white: crossed out to hide a visible video, and
uncrossed to show a hidden video.

Streams honor the web contract's `platforms` list: omitted allows all clients;
only streams allowing `mobile` enter mobile flags, ranking, and playback. An
empty list allows none. Metadata refresh removes a stream if mobile access is
removed. Top-level `language` takes precedence over legacy publication language.

Show/Hide Video is saved locally (`ce-video-visible.v1`) across events and app
restarts. First-time users see video; restoring or showing it loads the selected stream paused.

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
changing games in the same tour preserves selection, visibility, and playback,
including moving to another round of the same event, so swiping games or using
the game dropdown never interrupts the broadcast. If the chosen stream no longer
exists in the new round, the existing selection is retained during the game change.
The game model has no parent-event ID, so the tour ID is the event/session key.
Language preference persists locally across events; exact stream/visibility
choices last for the board route. The existing web language mapping and
English/preferred/audience ordering are mirrored in the Dart model. Audience
snapshots freeze per viewed round, and duplicate channel totals are counted once.

YouTube/Twitch report actual playing/paused state; Kick documents no supported
playback-state API, so its own playback cannot be confirmed. Choosing a stream
always requests playback, and once the embed is ready the app calls the
provider's play explicitly (YouTube/Twitch), so autoplay params alone can never
leave the stream waiting behind a second tap. Kick relies on its embed's
autoplay parameter.
Hide, background, covering the board with another route, and leaving the event
stop playback. Show/return and route returns are paused. Returning from app
background continues a stream that was live when the app was backgrounded: it
reloads at the provider's live edge and keeps playing (a stream that was paused
stays paused). Provider offline/restriction notices remain inside the player,
with a retry action for wrapper failures.

YouTube/Twitch also report mute flips from the provider's own controls, and the
session carries the last mute state into every later embed document, so switching
streams never resets mute. Kick exposes no readable mute state; its embed
inherits whatever mute state another provider last reported.

Twitch needs a 400×300 view. Narrow phones offer **Watch Twitch in landscape**,
which opens a rotated in-app viewer without changing the device orientation
policy. Closing it returns to the selected stream paused. No offscreen Twitch
player starts behind the expansion button.

On iOS, the bottom-right fullscreen button opens the same player in a landscape
in-app viewer. It dismisses after three seconds and reappears when the video is
tapped. YouTube's native fullscreen button is disabled there. On Android, the
provider's fullscreen button opens its WebView custom view above the route.
Both viewers rotate their content to landscape on portrait phones. Back exits fullscreen first, then the expanded viewer, then the route.
Entering or leaving never reloads the document, and a stream that was live is
nudged back once if the embed paused while the custom view attached. Rotating
during fullscreen never stops playback; only a real surface resize is treated as
rotation (inset-only metrics churn is ignored), and leaving fullscreen onto a
narrow inline Twitch view stops the now-invisible player.

## Validation and device checklist

Fixtures live in `test/fixtures/event_video_streams.json`; tests use a fake player
and never contact providers. Run scoped `flutter analyze --no-pub` and the
`event_video*_test.dart` tests. No app build/run is needed for static validation.

Using the production flavor, or the test flavor with verified test origins and
streams, the user checks on Android and iOS:

1. Open a streamed game: the selected video is paused with flags above it and
   engine lines below. Verify flags dismiss after three seconds, return on a
   video tap, and stay visible while scrolling the horizontal list.
2. Select another flag while paused and while playing. Check playback state and
   mute carry over, repeated flags have distinct labels, and order stays fixed.
   Verify Android/iOS landscape fullscreen still uses one player.
3. Hide/show video: Show restores the selected stream paused. Flip board remains
   in the top-right menu. Engine lines continue using saved settings.
4. Switch games in the same tour during playback, by swiping and through the
   game dropdown, including games in another round of the same event. Check
   there is one player, no audio duplication, no restart, and the stream keeps
   running. Switch to an event without streams.
5. On a narrow phone, expand Twitch, play, select streams, and close/back to the
   board. Check board/engine scrolling (including drags starting on the video),
   portrait/tablet landscape, and rotation.
6. Background the app, cover the board with another screen, and leave the event.
   Verify audio stops; returning from app background resumes a stream that was
   playing (reloaded at the live edge), while covering the board returns paused.

The Stockfish debug kill switch is unchanged; empty debug PVs remain expected.
