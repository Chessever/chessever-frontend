# Tasks

Goal: full parity of collection publishing across web, mobile and desktop, with a
real cover-photo upload that is separate from the profile avatar.

Facts (investigation, 2026-10-01 19:00):
- Apps → web proxy `/api/library/folders/:id/book` (adds server-only GAMEBASE_API_KEY) → gamebase `/library/folders/:id/book`.
  The proxy is hard-wired to `service.chessever.com` + Supabase `oelbsuggrzyqwzmvidju`.
- No owner-scoped cover upload exists anywhere. Only `POST/DELETE /api/superadmin/collections/:id/cover`
  (JSON {image: base64}, JPEG/PNG/WebP, 2:3 ±1%, ≥600×900, ≤8 MB → 800×1200 WebP, stored by coverStore).
- Library books use authoringRequirementsVersion 1, so a cover is NOT required to submit.
- "advanced" collection: no trace in gamebase or web code; most likely made in the web superadmin console (NewBook + CoverEditor).
- Desktop already has an editor (`lib/desktop/widgets/library/library_book_dialog.dart`) but without the mobile improvements.

- [x] IN PROGRESS (subagent ad48bbb0): desktop editor parity, no cover upload. Repo chessever_frontend_desktop, main, will bump 21.7.7.
- [x] Gamebase owner route `POST/DELETE /library/folders/:folderId/book/cover`: committed `4c318d0` on `feat/library-owner-cover` (local, not pushed).
      Follow-up: a cover change on a live book now resubmits it for review instead of leaving an unsubmitted draft (238/238 tests).
      Worktree `/Users/berkay/projects/chessever_gamebase-owner-cover`. tsc clean, test:collections 235/235, plus 3 new router tests.
      Body `{image: base64, fileName?}` → returns the same `describe()` payload as GET book. Returns 409 if the book was never saved. A new cover on a published book sends it back to review.
- [x] Web proxy cover routes: committed `724c0e9e` on `feat/library-owner-cover` off **origin/main** (worktree `/Users/berkay/projects/chessever-web-owner-cover`, local, not pushed).
      Production `/api/library/folders/:id/book/cover` and test `/library-publication-test/api/library/folders/:id/book/cover`, POST + DELETE, 12 MB cap. 20/20 proxy tests pass, tsc and eslint clean.
      Note: remote `codex/collection-author-hydration` was rewritten and dropped the production proxy, so I used main as the base.
- [x] Mobile gallery cover: committed `56914e0c` (35.34.1) on stable, local, not pushed. `prepareCollectionCover` centre-crops to 2:3 at 800×1200 PNG and refuses photos below 600×900.
      Upload starts as soon as a photo is picked; a book that was never saved gets saved as a private draft first. The link field is gone. 11/11 tests pass, including 3 random orders.
      DEPENDS ON DEPLOY: until gamebase `4c318d0` and web `724c0e9e` are live, the upload shows "Cover uploads are not available here yet."
- [x] Order-dependent test failure: the root cause was the caret's show-on-screen scroll pulling the button off-screen after `_tap` had scrolled to it. `_tap` now unfocuses first.
- [x] Desktop editor parity (worker ad48bbb0): `61713a13` (21.7.7), verified myself: analyze clean, 23/23 tests.
- [x] Desktop cover upload: `5cc20acd` (21.7.8) on desktop main, local, not pushed. File picker → same 2:3 prep → test bridge `/book/cover`. 24/24 tests.
- [ ] Parity gaps still open:
      - [x] Desktop publish copy and live-book saves: `601c272f` (21.7.9). Published books now always resubmit ("Submit changes" / "Submit with latest games"), the way mobile does. Before this, "Save details" and "Update games" sent publish:false, and Gamebase's lease guard quietly turned the live book back into an unsubmitted draft. 13/13 tests pass.
      - [x] Mobile crop control: `ae3a6fa9` (35.34.2). Full-screen `CoverCropper` (`lib/screens/library/cover_cropper.dart`): drag to move, pinch to zoom, zoom capped so the window stays ≥600×900. Too-small photos are refused before the cropper opens. 15/15 tests.
      - [x] Desktop crop control: `c1d89a03` (21.7.10). `cover_crop_dialog.dart` gives a desktop card with drag, scroll/trackpad zoom and a zoom slider; Enter uses the image, Esc cancels. Same 600×900 cap. 17/17 tests.
      - NOTE: another process is editing chessever-frontend's working tree (feed_board.dart, feed_clip.dart, feed tests, plus git index.lock contention). Don't touch those files.
      - Web has no screen for publishing a library folder; web authors use the superadmin console from a PGN. Needs a product decision.
- [x] PUSHED 2026-10-01 19:50: mobile stable → origin (`6e2ec74d`, includes the other session's feed fix). PRs: desktop #269, gamebase #98, web #684.
- [x] MERGED 2026-10-01 20:15: gamebase #98 → codex/collection-identity-hydration (`a2525c7c`); web #684 → main (`bd582e67`); desktop #269 → main (`56e66829`, admin merge, since review was required). Gamebase still needs a deploy.

## Author credit: publishing in someone else's name (started 2026-10-01 23:40)

Goal: on web, mobile and desktop an author picks "Me" or "Someone else". Someone else = typed name
(suggested from existing ChessEver authors so spellings match) + an optional square author photo, separate
from the profile photo and the cover. Credited names group into one author across the catalog.

Facts: today the author picture is always the OWNER's profile photo (catalogAuthors → publishedAuthorAvatar),
and catalog identity is `account:` for every owned book, so on-behalf credits would merge under the publisher.

Contract (gamebase, no SQL migration, everything in collection.metadata jsonb):
- `authorCredit: "self" | "other"` on PUT /library/folders/:id/book and console PATCH/POST collections. Detail returns
  `authorCredit` (default "self") and `authorPhotoUrl` (string|null). Saving "self" removes the credited photo.
- POST/DELETE /library/folders/:id/book/author-photo and /superadmin/collections/:id/author-photo, body {image: base64}.
  JPEG/PNG/WebP, square ±1%, ≥256×256, ≤8 MB → 512×512 WebP at /media/collection-authors/<id>/<sha32>.webp.
  Upload sets authorCredit=other. Library route: 409 before the first save; a live book goes back to review.
  Codes: author_photo_type, author_photo_animated, author_photo_aspect, author_photo_too_small, author_photo_unavailable, too_large, bad_base64.
- GET /library/authors?name=<1-60>&limit=<1-20, default 8> → {items: [{id, name, bookCount, avatarUrl}]} from published books.
- Catalog: `other` credits group as `credit:md5(lower(trim(author)))` across publishers; avatar = newest credited photo.

- [x] Gamebase (me): `120a983` on `feat/collection-author-credit` (worktree `/Users/berkay/projects/chessever_gamebase-author-credit`), local, not pushed.
      tsc clean; test:collections 246/246 (+8 new). Catalog/suggestion SQL and jsonb updates verified against a throwaway local Postgres (seeded rows, now deleted).
      Grouped authors show their most-used spelling (newest on a tie) instead of min(). Docs: docs/collections.md "Author credits".
- [x] Web proxy (me): `2111505a` on `feat/collection-author-credit` off origin/main (worktree `/Users/berkay/projects/chessever-web-author-credit`), local.
      Prod + test: POST/DELETE .../book/author-photo, GET /api/library/authors?name=&limit=. Console allowlist: collections/:id/author-photo. Proxy tests 26/26, superadmin 35/35, tsc + eslint clean.
- [x] Web console UI: worker `27a9b1c1` + my fix `56b70a55` (same web worktree/branch), local.
      Verified: tsc + eslint clean; 101/101 proxy/console unit tests; mocked publisher browser walk passes (82 calls) after my fix
      (the worker had dropped the "found in the file" Author alternatives and the cover's own too-small wording).
      test/publisher-import.test.ts has 1 failure that ALSO fails on origin/main ca1644ae (pre-existing).
- [x] Mobile (me): `bb297ca3` (35.35.2) pushed to stable. analyze clean on changed files; 29/29 editor + cover tests (also randomized), 10/10 publication tests.
- [x] MERGED 2026-10-02 ~01:00: gamebase #99 → codex/collection-identity-hydration (`459849af`); web #689 → main (`08220f56`);
      desktop #270 → main (`e317caaf`, admin merge: review required). Mobile pushed to stable. Gamebase deploy still needed.
- [ ] Mobile (me).
- [x] Desktop (worker 43fc5ac4): `fca045f0` (21.7.11) on local branch `feat/collection-author-credit` off main 56e66829, not pushed.
      Verified myself: analyze clean on 7 files; 46/46 tests (publication, cover_crop_dialog, library_book_dialog).
      Suggestions call `$base/api/library/authors?name=&limit=6`; photo `book/author-photo`. Client uploads a 512x512 PNG.
- [ ] Web console UI.

## Status check 2026-10-06 15:30 (auto-nudge cycle 1)

- All code for both workstreams is merged: web #684/#689, desktop #269/#270, mobile pushed to stable, gamebase #98/#99. The cover and author-photo routes are on gamebase `origin/main` too; `codex/collection-identity-hydration` is only 1 commit ahead of it.
- The two unchecked lines above ("Mobile (me)", "Web console UI") are leftovers: both are done (`bb297ca3`, `27a9b1c1` + `56b70a55`).
- ~~BLOCKED on the gamebase deploy~~ WRONG, retracted 2026-10-07: production was already serving it. `service.chessever.com/media/collection-covers/...` and `/media/collection-authors/...` answer with the media router's own 404 (`Cache-Control: public, max-age=60`, `nosniff`), which only exists in builds that include the cover and author-photo work. Collection publishing is DONE and live.
- Open product decision (optional, not a blocker): web still has no screen for publishing a library folder.
