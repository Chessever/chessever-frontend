# Library UI Overhaul — todo

Spec: 3-tab Library (Studies / My Database / Discovery), board tag flow, My Likes tags, Miniatures.

## DONE (pure UI, no migration) — committed to dev
- [x] **Phase 1** board save/edit tag flow — `425b612f`
  - `lib/constants/game_tags.dart` (10 official tags + icons)
  - save sheet: always-visible tag chips, preload existing tags, persist on insert/update
  - threaded tags through SavedAnalysisData → auto-save/manual-update no longer wipe tags
- [x] **Phase 2** three-tab Library — `a1297401`
  - SegmentedSwitcher (Studies / My Database / Discovery), default My Database
  - per-tab search text + scroll preserved (IndexedStack + _tabQueries)
  - TWIC moved My Database → Discovery, relabeled "ChessEver Master Database" (FolderCard.titleOverride)
  - Studies + Miniatures = honest "Soon" panels
- [x] **Phase 3** My Likes tag chips — `8b80be0c`
  - tag chip row, tap-to-filter = premium (requirePremiumGuard), union semantics
  - MyLikesFilterState.selectedTags + provider apply
- [x] liked card tag display — `90642472`

## BLOCKED — needs backend (additive migration), awaiting permission
- [ ] **Studies real data**: `lichess_studies` + `_chapters` tables + sync edge fn (company Lichess token, filter junk, quality rank). Bigger than a migration.
- [ ] **Miniatures real list**: indexed derived columns on `games` (move_count / is_decisive / is_miniature) OR RPC/matview (decisive + <20 moves, sort avg rating). 990k rows → needs index, not client-side.
- [ ] **Community like-count**: additive table/counter aggregating likes per game; increment on like; feeds Miniatures like-sort.

## Test notes
- `flutter analyze` clean on all 9 touched files.
- Manual (device):
  1. Board → double-tap like, open save sheet → tag chips visible, toggle, save. Reopen game → tags still selected. Move a piece (auto-save) → reopen → tags still there.
  2. Library → segmented control: lands on My Database; TWIC gone from My Database, now in Discovery as "ChessEver Master Database"; Studies/Discovery show Soon panels; switch tabs → search text + scroll preserved.
  3. My Likes → tag chip row; free user taps chip → paywall; premium taps → list filters by tag (union); liked cards show tag pills.
