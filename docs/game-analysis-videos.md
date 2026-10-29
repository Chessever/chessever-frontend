# Game analysis videos

This feature is additive across the production mobile app, desktop/shared browser app, chessever.com, Gamebase and admin.chessever.com. No live service or migration is changed by these commits.

## Behavior

- Collection publishing has an optional game-video editor. Each saved source game has its own YouTube URL and optional spoken-language code. Links use the existing `LibraryGameId` snapshot tag, so a refreshed snapshot retains the assignment.
- Any signed-in author with a verified email can submit a video from a board's **Attach analysis video** menu, without making a collection. Authors can view and edit their submissions. An edit returns the video to pending and removes its former approval.
- Only superadmins approve public submissions and collection publication. Existing collection submission, ownership, takedown and premium-access rules remain authoritative.
- Paste a watch, share, live, shorts or embed URL to fill start/end times and playback options. Start/end accept seconds, `mm:ss`, `hh:mm:ss`, or `1h2m3s`. End must be after start.
- Supported URL settings: `start`/`t`/`#t`, `end`, `autoplay`, `mute`, `loop`, `cc_load_policy`, `cc_lang_pref`, `hl`. Tracking and unrelated playlist parameters are removed. Player/caption language is separate from spoken language. Provider and browser policies may prevent autoplay or captions.
- Author photos use the existing account/collection author-photo system. Missing photos use the existing initials avatar. Broadcasts keep their country circles.
- Completed games list analysis before old broadcasts; live games list broadcasts first. Analyses sort by followed authors, preferred spoken language, newest publication, then author name and ID. Use the source menu/long press to follow an author.
- Choosing an analysis does not replace the viewer's saved broadcast language. A failed lookup or follow action cannot stop an existing broadcast. Source lookups do not gate board rendering.

## Compatibility

Old clients send no new fields. The server preserves video metadata when those fields are absent. New clients omit untouched optional fields; no existing user needs to enter anything. Existing stream APIs, country preferences, visibility, fullscreen and player-retention behavior remain in place.

`gameVideos` remains a map of stable game IDs to URL strings. `gameVideoLanguages` is a parallel optional map. Empty maps intentionally clear assignments. Standalone submissions and follows use separate tables with RLS and authenticated API access. Public discovery returns only published, entitled sources. Games match played moves and players, ignoring comments and round labels.

## Rollout order (not executed)

1. Verify the production Gamebase database target from that service's configuration. Apply `chessever_gamebase/sql/game-analysis-videos.sql` to that database. The collection-match index uses `CREATE INDEX CONCURRENTLY` outside the transaction; use a SQL client that supports this. Do not wrap the entire file in another transaction.
2. Deploy the Gamebase API, then the desktop repository's `gamebase-proxy` allowlist. Any Edge Function deployment must retain `verify_jwt=false` and follow the repository's post-deploy auth checks.
3. Deploy chessever.com, including the `/embed/analysis-video` player document and the authenticated submission/follow proxies. Existing Gamebase API-key configuration is reused.
4. Configure the admin worker's server-only `GAMEBASE_API_KEY` secret with the production first-party Gamebase key. Deploy the portal/worker. Cloudflare Access, current-account admin checks and upstream superadmin/scope checks all remain required. No key is shipped to the browser.
5. Release the mobile and desktop apps after on-device checks. Existing releases continue working through the unchanged APIs.

The standalone-table discovery fallback tolerates an API rollout before SQL. Submissions need the schema; a failed submission retains the form. Rolling back clients/API does not require deleting data or reverting the additive schema.

## Admin controls

**Videos → Analysis reviews** filters pending/published/rejected/archived videos and edits URL, timing, playback, credit, spoken language and review note. Approve, reject and archive operate on the edited values. Rejection requires a note.

**Collection videos** loads a collection by list or ID, pages its games, edits their videos, and uses the existing superadmin publication endpoint.

**Broadcast streams** loads a group/tour/round by ID, edits stream URLs and labels/language/country, and supports custom/inherit/disabled modes. Save preserves existing publication/audience/platform metadata and sends the revision for concurrency protection.

## On-device review before release

Runtime app testing belongs to the user under this repository's rules. No Flutter app was launched or attached for validation.

1. Open an existing live game with streams. Switch flags, hide/show, enter/exit fullscreen, change games/rounds and desktop tabs. Confirm the old playback and remembered preferences still behave as before.
2. Save/submit an old collection without touching Game videos. Confirm its existing publication/review state and contents stay intact.
3. Add `https://youtu.be/abcdefghijk?t=12m30s&end=1200&loop=1&cc_load_policy=1&cc_lang_pref=en`, inspect the populated fields, then change start to `13:00`. Save, reopen and verify the URL/fields. Use a real embeddable video for playback.
4. Submit a video from a game outside a collection. Confirm it is private until superadmin approval; reject with a note, edit/resubmit, approve, then edit the published submission and confirm it returns to pending.
5. Open the same completed game from a collection, search/library and broadcast entry point. Confirm approved author circles, photo/initials fallback, exact segment start/end and analysis-before-broadcast order.
6. Follow two authors, set a preferred language, and verify followed/language/newest order. Select a broadcast explicitly and refresh metadata; confirm that selection is respected.
7. Check signed-out, free and premium accounts; another author's draft must never be a public source. Hide an attachment by archiving/rejecting and refresh the board.
8. Disable networking or point a local development client at an older API. Confirm games, old streams and untouched collection saves remain usable, while new submission errors retain edits.
9. Repeat the publishing and standalone flows on mobile, desktop, app.chessever.com and chessever.com; review URLs from admin.chessever.com. Check keyboard focus, large text and screen-reader labels on device.
