# Watch release audit - 26 October 2026

Version: **37.3.3+3732**. Release source: mobile `stable`. The local watch checkout is on the watch repository's `main` mirror.

## Release verdict

The repaired watch app runs in the Mac's native Device Hub with production data. The event-to-board route, refresh, standings, player scorecards, board flip, account transport and acknowledged game handoff were exercised in the real watchOS Simulator. The iPhone opened the matching **Rapport vs Dai** game. This is ready for paired physical-device/TestFlight validation, rather than an unconditional App Store sign-off.

Before store release, verify forwarded notifications (foreground and cold launch), Always On privacy/resume, physical Crown feel and refresh, haptics, VoiceOver and large text on a supported watch. The full mobile suite also has the 22 non-watch failures listed below. No store submission, backend deployment or Git push was performed.

## Fixed findings

| Priority | Finding | Result |
| --- | --- | --- |
| P0 | Watch launch failed with `chessever_watch_free` missing | Restored the plugin's `watchos/Package.swift`, added a startup fallback and a native-symbol CI gate. Actual repaired binary passes; a binary without the bridge is rejected. |
| P1 | Boards required event, section, round and pairing navigation | An event now opens the latest started round with published boards, in a single-column board feed. Round controls and standings sit between boards. Each board opens its game tools. |
| P1 | Simultaneous offline sync requests could queue duplicates | Coalesced in-flight requests; background queue remains bounded. |
| P1 | Malformed account snapshots could throw from the stream listener | Ignore malformed snapshots and retain the last valid account; later valid snapshots still apply. |
| P2 | Installed-app metadata temporarily disagreed with reachability | Reachable, activated sessions may request sync while installation metadata catches up. Account instructions no longer simultaneously say connected and ask to install. |
| P2 | Missing played counts appeared as a misleading score divided by zero | Preserve an absent count; display the published score alone. A reported zero remains zero. Invalid FIDE ID zero falls back to the player's name. |
| P2 | Headings, notes, card text and player strips used different axes | Shared text inset, centered row accessories, player strips matching board width, long-word fitting, consistent card spacing. |
| P2 | Automatic refresh inserted a loader and moved loaded rows | Retain the existing geometry; the Refresh row keeps its label and uses a small busy indicator. Initial loading still has feedback. |
| P2 | Scrolled content collided with the system clock | Added a scroll-dependent clock fade. Coalesced its updates after layout so refresh extent corrections cannot rebuild during a frame. |
| P2 | Text-heavy browsing | Real 24pt event thumbnails, federation flags and functional native icons; no invented photos or decorative badges. Missing photos have an immediate bare flag fallback. |

Crown/finger refresh uses the native scroll position and `CupertinoSliverRefreshControl`, with a 52pt threshold and one request until completion. It works on short pages. The Refresh button remains available. The game handoff passes its eight-second timeout into the transport itself.

## Validation and evidence

- Changed-file `flutter analyze --no-pub`: clean in both checkouts.
- **24 focused watch tests pass**, including native-style non-drag overscroll, short-page pull refresh, one request while busy, one-tap boards, round selection, offline retention, all three watch sizes, doubled text, shared text alignment, centered accessories and stable refresh layout.
- Rendered the watch tests with the Mac's actual SF Compact font at **162×197, 184×224 and 211×257**. Inspected Current, boards, game tools, account and scorecard screens. These small-size review images contain labeled test fixtures; the walkthrough videos contain real production events.
- Real native watch launch: bridge symbols present; no startup red screen. Simulator first frame was approximately one second in the audit harness (debug, not a release performance measurement).
- Native pointer tour completed through Current, pull refresh, phone sync, event boards, standings, game tools, flip, handoff, scorecard and back navigation.
- WatchConnectivity initially returned `Companion app is not installed` despite correct installed bundles. Rebuilding the phone with its embedded watch and restarting the watch simulator cleared its stale registration. The subsequent tour reported `counterpart installed=true, reachable=true` and `handoff accepted=true`; the iPhone UI independently showed Rapport vs Dai.
- Installed phone and embedded watch: `com.chessever.app` / `com.chessever.app.watchkitapp`, matching version/build **37.3.3+3732**. Companion key matches production. No `WKWatchOnly` key.
- Production public feed responded HTTP 200 in 0.34 seconds after transient startup timeouts cleared. Public read configuration and key role were verified without printing credentials.
- Plists/project syntax and shell scripts checked. Native-symbol gate exercised against a real passing binary and a missing-bridge negative case.
- Full mobile suite: **5,862 passed, 4 skipped, 22 failed**. Failing test files were not modified by this audit; their causes have not been established by a baseline rerun.

Recordings and native screenshots are under `output/watch-audit-2026-10-26/` in the watch checkout. `tool/watch_live_audit.dart` is a development-only live pointer tour using real repository reads and native connectivity. It is not the shipped entrypoint. Ship `lib/main_watch.dart` through the existing mobile release workflow with `watch` enabled.

## Native audit score

Source and Simulator review: **15/20**, provisional until physical-device checks.

| Dimension | Score | Evidence / remaining check |
| --- | --- | --- |
| Accessibility | 3/4 | Full semantic game identities, 44pt targets, scaled text tests; physical VoiceOver traversal remains. |
| Performance | 3/4 | Lazy board/list rendering, bounded pagination, visible-route polling and optional cached artwork; release battery/frame profiling remains. |
| Appearance | 3/4 | OLED black, native type, genuine artwork, measured alignment and three-size renders; physical display review remains. |
| Platform conformance | 3/4 | Cupertino navigation, native scroll/Crown integration, clock band and privacy face; wrist/haptics/notification checks remain. |
| Adaptivity | 3/4 | Three sizes plus doubled text; physical system text settings remain. |

## Design-law re-check

The full supplied design law was rechecked against this native watch surface. Website-only compositions are intentionally absent. The identity is the real chess position, real event artwork and native watch navigation.

| Points checked | Outcome |
| --- | --- |
| Lucide defaults, generic redrawn outlines, oversized icon tiles, icons/logos boxed in colored containers, fake/missing logos, gradient logo lockups, zero-icon overcorrection | Functional Cupertino marks, genuine event photos and federation flags. Thumbnails are small circles by the user's explicit direction. No invented brand marks or icon tiles. |
| Em dashes, ornamental quotation marks, filler copy, fake testimonials and metrics | Short task labels and real feed data. No decorative quotations or marketing claims. |
| Fraunces/Work Sans, Space Grotesk, Cormorant, Didones, Sora, JetBrains Mono, Syne, Archivo, the Google-font rotation, safe designer substitutions and repeated house pairings | Native Cupertino/SF system families. No web display font or mono house voice. |
| Eyebrow pills, gradient icon pills, tinted metadata chips, initials avatars, inner glows and pulsing dots | Plain metadata and actual flags/photos. No chips, gradient initials or glow badges. |
| Glowing buttons, paired fill/outline CTAs, hover boops, hover lifts, underline fills, unstable fill animations, default all-around shadows and fake offset shadow boxes | Native touch opacity, genuine activity feedback and no decorative lift/shadows. |
| Floating cards/tags, kitchen-sink cards, pricing tiers, testimonials, pre-footer CTA slabs and oversized footer wordmarks | Not used. Each watch row has one functional role. |
| Faux app windows, fake code panels, crude decorative charts/illustrations and empty product props | Actual FEN positions and the established Cburnett piece assets. |
| Purple gradients, cool blue-charcoal defaults, background glows, centered halos, candy gradients/auroras, cream/beige and UI-kit gray defaults, saturated decorative accents | OLED black and chosen neutral watch surfaces. Chess squares and real federation colors carry their content meaning. |
| Hairline boxes, accent bars, eyebrow ticks, graph-paper backgrounds, numbered rails and decorative unrounded rules | No decorative borders, grids or rails. Tone and spacing provide structure. The chessboard grid is actual game content. |
| Botched glass, blur leaks/pop, box-shaped shadows, bloom silhouettes, grain over text and banded gradients | None present. The clock fade is a functional black viewport mask, not decorative lighting. |
| Invisible entrance content, floating decoration, fixed backgrounds pretending to animate, dead-looking controls and default reveal stacks | Content is visible by default. Motion is functional navigation, touch feedback, scrolling and refresh. |
| Clipped live content, section-overlap cuts, text against edges, uncentered glyphs, cramped display type and off-center strike lines | Deliberate gutters, whole board squares, measured row centers, shared text insets and board/player axes. Normal scrolling exits through the viewport/clock fade. |
| Ragged comparison columns and content flung to the far edges | Single-column watch hierarchy; corresponding player/board edges align. No comparison or footer layouts. |
| Active-nav dots, sun/moon pills, fake countdowns and uniform tiny-label costumes | Native navigation and real reported clocks. Heading/body/caption roles remain distinct. |
| Split heroes, default hero stacks/right panels, dangling accent words, label-over-heading sections, serif statement blocks and repeated section skeletons | Absent. Events open actual boards; scorecards open actual scores. |
| Inset inquiry islands, email-pill forms, image-caption marketing cards, SaaS meta-skeletons, flat post-hero bands, hard image/color seams and recycled house style | Absent. Native product UI is composed for the wrist, with real data and no marketing sections. |
| Dead controls and faked interactivity | Native pointer tour and widget taps cover the primary flow. Physical notification, VoiceOver, wrist and Crown feel checks remain explicitly unclaimed. |
| Premium craft: specificity, authored interaction, coherent type/palette/nav, real imagery and a signature artifact | The user's board-first interaction, genuine board position, event photos and federation marks form the watch's coherent visual language. |

## Outstanding mobile suite failures

These are outside the watch tests. Resolve or formally triage them before treating the entire mobile release as having a clean test gate.

- test/focus_surfaces_events_test.dart: event card focus menu long-press lifts the card and keeps event actions without unsupported additions
- test/focus_surfaces_events_test.dart: event card focus menu calendar events keep their supported non-broadcast actions
- test/focus_surfaces_events_test.dart: event 3-dot keeps its rows without adding an event to My Space
- test/focus_surfaces_events_test.dart: event 3-dot a gamebase-only event keeps Share without My Space
- test/for_you_scorecard_cold_start_test.dart: cold For You player-name tap carries explicit event games to scorecard
- test/for_you_scorecard_cold_start_test.dart: global player-list player-name tap stays outside event context
- test/library_visual_parity_test.dart: a Likes tap routes the normal board, or asks for Premium first, paid=true
- test/player_profile_preview_data_source_contract_test.dart: Gamebase archive player rows use the TWIC profile backend position sheet and in-board FEN results keep TWIC
- test/widget_test.dart: Counter increments smoke test
- test/most_liked_screen_test.dart: ranked players fit 320px at double text scale, light=false
- test/most_liked_screen_test.dart: ranked players fit 320px at double text scale, light=true
- test/most_liked_screen_test.dart: Likes tabs fit at 320.0 with large text, light=false
- test/most_liked_screen_test.dart: Likes tabs fit at 320.0 with large text, light=true
- test/most_liked_screen_test.dart: Likes tabs fit at 390.0 with large text, light=false
- test/most_liked_screen_test.dart: Likes tabs fit at 390.0 with large text, light=true
- test/home_search_overlay_stability_test.dart: tapping outside the complete search control dismisses focus
- test/discovery_game_list_test.dart: skeleton is as tall as the loaded list: gamesCard, labelled, text x1.3
- test/game_report_reuse_test.dart: leaving a game during restoration does not claim or analyze it
- test/game_report_reuse_test.dart: opening a saved report on a cold device never generates it again
- test/search_source_boundary_test.dart: homepage combined search does not depend on gamebase source data
- test/hub_tile_captions_test.dart: hubCollectionsCaption analysis counts independently from books
- test/hub_tile_captions_test.dart: hubCollectionsCaption events and books, by kind and number
