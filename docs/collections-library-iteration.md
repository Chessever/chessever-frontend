# Collections and Library iteration

The initial iteration was prepared for the test app without a deployment or
remote migration. The separately authorized production catalog fix is recorded
at the end of this document. No app was launched for agent validation.

## Product behavior

| Before | After | Why |
| --- | --- | --- |
| Icon-only navigation kept the former label space. | A 48dp navigation surface plus the device safe area; every icon retains a 44dp target, tooltip, and accessible name. | Compact navigation without reducing the tap target. |
| Library occupied a primary tab. | Collections occupies that tab; Library opens from My Space. | Public exploration and private study have distinct destinations. |
| My Space used the chat action. | Its original plus action and add sources are restored. | Saved events, players, games, openings, Library items and smart events remain reachable. |
| Discovery used one row of mixed illustrations. | Feed / Most Liked and Miniatures / Reports use full artwork in the existing hub frame. | A consistent visual language based on chess positions, real opponent portraits and analysis. |
| Opening cards used large board tiles. | Compact event-style rows show a canonical position, name, ECO and available counts. | Faster scanning; a global opening opens relevant books, while a book opening opens its own games. |
| Library folders only had private/link-sharing behavior. | Owned folders can save private book metadata, explicitly publish, update their snapshot, or unpublish. | A public book is the published edition of an owned private source. |
| Some form fields could leave a lazy list before validation. | All eight fields remain mounted in a scrollable form. | Required fields remain validated when actions are below the fold. |
| Preview art could show a hidden broadcast position. | Feed and Reports previews respect the event no-spoiler preference, including its loading state. | Discovery must not reveal a protected position or evaluation curve. |

Collections has **Openings / Games / Books**. A book has **About / Games /
Openings**, with its title, cover, author, subtitle, description, foreword,
publisher/year and other supported collection credits. Counts come from the API.

The new Collections mark follows the supplied stacked-page reference. Library
uses the local `assets/pngs/library_study.png` study image. Heart halves use the
two actual opponents from each game; absent photos use plain initials. No
fictional games, player identities, counts, testimonials or social proof appear.

## Publishing contract

Owned folders and databases expose **Publish / edit book** in their context menu
and an upload action in their header. Likes, subscriptions and permanent system
databases are excluded. Server-side ownership checks remain authoritative.

- Save private draft never publishes. Sharing a link never publishes.
- Publish book is explicit and snapshots the folder's current owned descendants,
  including when republishing a previously withdrawn book.
- Save changes updates metadata. Replacing the game snapshot is a separate
  checkbox, off by default, on already published books.
- Unpublish asks for confirmation and keeps the private source and metadata.
- A failed request preserves entered text. In-flight requests disable repeat
  submission and navigation; dirty forms ask before discarding edits.
- Source deletion first withdraws its public books when publishing is configured.
  Failed withdrawal blocks source deletion. A deletion fence blocks concurrent
  republishing; retry **Delete** to finish if the operation fails midway.
- An invalid but present publishing configuration blocks deletion rather than
  silently skipping withdrawal. In the test rollout, missing configuration also
  blocks deletion until withdrawal can be checked. Legacy deletion outside the
  test rollout remains unchanged.

The current server limit is 1,000 games / 10 MiB per snapshot. Oversized snapshots
are rejected, not truncated. Saved variations, annotations, NAGs, clocks,
evaluations and custom starting positions are serialized by the server.

Metadata limits match the API: title/subtitle/author 300 characters, publisher
200, description 20,000, foreword 50,000, cover URL 2,000, year 0–9999. Cover URLs
must use HTTPS.

## Test configuration and companion changes

The mobile test app requires explicit `GAMEBASE_TEST_BASE_URL` and
`GAMEBASE_TEST_API_KEY` compile-time configuration for catalog reads. Publishing
uses the separate `LIBRARY_BOOK_PUBLISHING_BASE` setting, pointing to
`https://<verified-test-web-host>/library-publication-test`, with only the user's
session token. The Gamebase publication key stays on the proxy server; it is not
bundled in the app. Neither client setting inherits a production URL or key.
Missing configuration produces a retryable
unavailable state. Known production hosts, credentials in URLs, query strings,
fragments and non-HTTPS remote targets are rejected. HTTP is allowed for loopback
development. Publication requests never follow redirects.

The existing app bootstrap validates the test Supabase URL against
`https://odmekzlfunfocvedqusl.supabase.co` before initializing its client. Configure
only the separately verified test Gamebase service. Do not copy production
credentials to make this screen work.

Companion local work:

- Gamebase: `/Users/berkay/projects/chessever_gamebase-collections`, branch
  `feat/collections`. See `docs/collections.md` and
  `sql/collections-library-publication.sql` there. Publication is disabled until
  `LIBRARY_PUBLICATION_ENVIRONMENT=test` and the verified non-primary
  `LIBRARY_PUBLICATION_AUTH_PROJECT` are explicitly configured.
- Web: `/Users/berkay/projects/chessever_web_frontend`, branch
  `perf/explorer-instant`. Existing superadmin publishing remains the metadata
  console. Compression failures, duplicate submission and repeated compression
  during preview/apply are handled. The dedicated, disabled-by-default
  `/library-publication-test/api/library/folders/{id}/book` adapter supplies the
  server API key after verifying the test user's session. See that repository's
  `docs/library-publication-test-proxy.md` for the `PUBLICATION_TEST_*` settings,
  exact upstream hostname binding and deployment checks.
- Desktop: draft [PR #267](https://github.com/Chessever/chessever_frontend_desktop/pull/267),
  based on `perf/explorer-instant`. Its opt-in `LIBRARY_BOOK_PUBLISHING_BASE`
  is `https://<verified-test-web-host>/library-publication-test`. The adapter
  forwards the session and supplies its server key.
  See that repository's `docs/library_book_publishing.md`.

Gamebase adds an owner/project/folder identity mapping, recursive source ancestry,
publication serialization and indexes for ECO, book membership and public access.
Existing full-text metadata and tag indexes remain in use. Public opening counts
include only published books. Game payloads still enforce collection access.
Draft metadata, private folder identities and unshared games are not indexed
publicly. API writes are transactional; a failed snapshot preserves its previous
edition. No remote migration has been applied.

The Gamebase publication transaction and Supabase source hierarchy are separate.
Normal concurrent publication/deletion and folders moved before deletion are
covered; a simultaneous folder move from another client is not atomic with
source deletion. The backend runbook records this boundary.

## Design re-check

The supplied design law was reviewed against the touched native surfaces. Its
landing-page hero, pricing, testimonials, footer, logo wall, theme-switch and
newsletter patterns do not apply here and were not introduced. Existing product
type, native controls and event-card conventions are retained deliberately.

- No new gradient text, glow, floating card, icon tile, generic illustration,
  boxed shadow, decorative rule, grain overlay, background grid or font family.
- New artwork fills the established hub frame; labels remain outside decorative
  clipping. Book covers preserve their complete image. The page geometry does
  not rely on text length to place navigation or editor actions.
- Content is visible by default. The heart drift changes only transforms, caches
  its portrait subtree, stops offscreen, honors reduced motion and disposes its
  controller. Existing press feedback remains short and never moves on hover.
- New action buttons have no default filled/outlined pairing. App messages use
  `showAppSnack`; failures retain the form and explain the next step.
- Touch targets, semantic labels, narrow layouts and larger text are covered by
  widget tests. Large illustrations are decorative and excluded from semantics.
- The plus menu, four Discovery routes, Collections tabs, scoped opening routes,
  publishing actions and error recovery are wired to real behavior.

This is a source and automated-widget review. Pixel inspection, visual centering,
photo cropping on actual devices, screen-reader behavior and live interaction
remain device checks, because this repository explicitly delegates runtime/UI
verification to the user.

## Device verification

After the companion changes are installed in the verified test environment:

1. Check the compact bar and all three destinations on a small phone and tablet,
   both themes, enlarged text, and with a bottom safe area. Re-tap Collections
   to return the active tab to the top.
2. Open My Space, use every plus-menu source, then open Library and navigate
   back. Confirm the floating action does not cover the last saved item.
3. Open all four Discovery destinations. Enable no spoilers for a broadcast and
   confirm Feed/Reports art cannot reveal its position or curve. Check reduced
   motion stops the heart drift.
4. In Collections, open an opening, choose a matching book, and verify its count.
   In that book's Openings tab, confirm only that book's matching games appear.
   Compare About metadata with the test superadmin editor.
5. Save a folder draft, reopen it, then publish. Verify it appears publicly only
   after Publish. Change a private game; confirm the public edition changes only
   after explicitly updating games. Test nested folders and annotations.
6. Disconnect during saving and retry. Confirm text survives, duplicate submit is
   blocked, and no failed request reports success. Unpublish, then confirm the
   private source remains. Publish again and delete its parent; verify all its
   public descendants are withdrawn before the private subtree is removed.

Do not use `flutter run` or `flutter build` for agent validation. Use scoped
`flutter analyze --no-pub` and the relevant unit/widget tests.

## Automated validation completed

- Mobile navigation, Discovery, configuration and publication: 47 tests passed.
  The final publication/configuration follow-up passed all 14 tests.
- Collections/API/access coverage passed 89 tests; the added publication-refresh
  race regression passed with the full 17-test Collections screen file.
- My Space add policy, saved players/games and layout tests passed. An obsolete
  full-board scroll-distance assertion now checks the actual compact-list extent.
  The original add-sheet suite passed 10 tests; FAB coverage passed 4 tests,
  including all six choices on a 320×568 phone at 1.3× text size.
- All touched mobile source/test paths passed scoped `flutter analyze --no-pub`;
  `git diff --check` is clean.
- Backend: 234 unit tests and 8 isolated source/integration tests passed;
  TypeScript and Prisma validation passed. The additive SQL was applied twice
  only to a disposable local cluster, which was stopped afterward.
- Desktop changes are reviewed in draft PR #267. No mobile, web or backend
  release was created. Existing unrelated working-tree edits were preserved.
- Web: 116 tests passed, with TypeScript and lint clean. Desktop: 12 service
  tests and 4 form tests passed, with scoped analysis clean (`21.7.5+411`).

## My Space edit follow-up

The plus menu now opens the existing circle-selection and hold-to-drag editor
directly on My Space. The behavior and controls were traced through commits
`fa18863c`, `b0b47e76` and `c6ad3762` on the feature branch's ancestry.

| Before | After | Why |
| --- | --- | --- |
| Edit required an individual See all screen | Plus menu offers Edit; the existing Remove and Done actions appear together | Reuse the established interaction and visual treatment |
| Home regrouped saved items by type | Adjacent items share their usual rail while the whole page follows saved order | A drop between different types stays there after Done |
| Selection removal belonged to one type | One selection can remove several kinds, with one Undo | Arrange saved shortcuts without deleting their source content |
| Fixed-height menu content could exceed a short screen | Menu height follows available space and its contents scroll | Keep Edit and every add source reachable with large text |
| Hub tiles clipped their labels at 1.8× text on a narrow phone | Tile height grows with the title and caption metrics | Keep live text clear of the rounded clip |
| Responsive scaling reduced action touch targets below 44 points | Discovery actions keep a physical 44-point minimum in both dimensions | Keep Remove and Done easy to tap on small phones |

The follow-up design re-check covers the supplied law against these native
surfaces: no new typeface, palette, decorative icon container, marketing layout,
glow, border system, shadow, gradient, background, hover effect or fabricated
content was introduced. Existing event/opening/game cards and player portraits
remain the actual product content. Existing edit motion carries selection and
drag feedback, supports reduced motion, and does not gate card content on an
entrance animation. Circle semantics, disabled removal before selection,
consistent gutters and toolbar reachability are retained. The menu is bounded
above its pointer and scrolls rather than clipping live controls.

The static review does not replace on-device optical inspection. Check My Space
→ plus → Edit; select several kinds and Remove, then Undo; hold an item and move
it between other kinds; tap Done and reopen My Space to confirm order. Also
check the same sequence with enlarged text and reduced motion. Fixed My Likes,
Library and Build a smart event navigation tiles are outside the saved-item
editor.

Follow-up validation: 159 tests passed (54 My Space/FAB widget tests, 46 order,
pending-write and provider tests, and 59 shared Discovery/hub/For You tests).
Scoped `flutter analyze --no-pub` reports no issues across the eight touched
source files and three test files. Scoped `git diff --check` is clean. No app
was launched or built; the remaining on-device checks above belong to the user.

## Production Collections 404 follow-up (2026-09-28)

The user explicitly authorized the production Gamebase target for diagnosis and
deployment. The deployed server lacked the new static `/api/collections/openings`
and `/api/collections/games` routes, so its generic slug route returned 404.

A focused patch was prepared on the current production revision, preserving its
explorer performance changes. It adds catalog openings, matching books, catalog
games, book-scoped openings and exact ECO filtering for book games. Existing
premium entitlement checks remain in force. This patch requires no migration
and does not enable private-folder publishing.

- Backend commit: `d059b28571dc3409cef38d17fb14c5b131159d4b`, deployed through
  Coolify to `https://service.chessever.com`.
- Deployment: `j3ahuaqjauy3reif3h4pcfhg`, finished; the replacement API container
  is healthy and its companion workers are running.
- Validation: TypeScript build plus 282 tests passed (227 collection unit tests,
  22 HTTP/database integration tests, 6 opening-classification tests, 27 explorer
  regression tests). The new HTTP regression reproduced the 404 before the fix.
- Live read-only checks returned 200 for Books, Openings, Games, books for an
  opening, and the published book's Openings route. The anonymous Games result
  correctly excludes premium content.
- The previous production image is retained as
  `gamebase:rollback-collections-43b9e43`. Temporary local test services were stopped.

Device check: reopen Collections, switch through Openings / Games / Books, then
open a book and its Openings tab. This server fix does not require a new app build.

## Hub artwork revision

The repeated board backdrops and bobbing hearts described in the initial
iteration were replaced following user feedback. Feed, Miniatures and Reports
now use distinct bundled photographic scenes. Most Liked and My Likes display
red-edged hearts immediately and scroll them horizontally in a seamless loop;
actual opponent portraits fill the two cheek circles as they become available.
See [the artwork, prompts and validation](hub-background-refinement.md).
