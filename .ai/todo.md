# Library UI Overhaul — todo

Spec: 3-tab Library (Studies / My Database / Discovery), board tag flow, My Likes tags, Miniatures.

## Scope split
- **Pure UI (no migration)** — doing now.
- **Backend-blocked (needs additive migration, awaiting permission)** — Studies data, Miniatures RPC + community like-count.

## Phase 1 — Board save/edit tag flow (explicit gap)  [in progress]
- [ ] `lib/constants/game_tags.dart` — 10 official tags constant
- [ ] save_analysis_sheet.dart: preload existing tags (liked path + getSavedAnalysis fetch)
- [ ] save_analysis_sheet.dart: tag chips row (always visible), toggle select
- [ ] save_analysis_sheet.dart: persist `tags` on insert + update (replace `const []`)
- [ ] flutter analyze clean

## Phase 2 — Library 3 tabs
- [ ] SegmentedSwitcher at top (Studies / My Database / Discovery), default My Database
- [ ] My Database tab = current library content MINUS TWIC
- [ ] Move TWIC card into Discovery tab
- [ ] Per-tab scroll position + search input preserved
- [ ] Studies tab scaffold (coming-soon state — backend absent)
- [ ] Discovery tab = Miniatures scaffold (coming-soon — backend absent)

## Phase 3 — My Likes tag chips
- [ ] Tag chips row at top of My Likes
- [ ] Free: attach tags. Tap-to-FILTER opens paywall (premium)

## Backend (awaiting permission — additive only)
- [ ] Studies: store table + Lichess sync (substantial, recommend defer)
- [ ] Miniatures: RPC/view over games (decisive + <20 moves, sort avg rating)
- [ ] community game like-count table + increment on like

## Test notes
- Append per phase.
