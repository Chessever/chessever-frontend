# Library UI Overhaul + Discovery — todo

## DONE — pushed to dev
- [x] Board save/edit tag flow — `425b612f`
- [x] Three-tab Library (Studies / My Database / Discovery) — `a1297401`
- [x] My Likes tag filter chips — `8b80be0c`
- [x] Liked card tag display — `90642472`
- [x] **Roulette tag picker** (spring physics wheel) for liked games — `115655fe`
  - detented wheel, countdown ring, reduced-motion fallback
  - fires after a like; liked-game save sheet shows roulette trigger
  - additive Supabase: GIN index on tags + generated `primary_tag` (+btree)
- [x] **Studies + Miniatures** wired from gamebase_openapi.yaml — `42cf29b6`
  - models + repo methods + providers (discovery/*)
  - Studies tab (sort/search/pull-to-refresh) + chapter screen (open PGN on board)
  - Discovery = ChessEver master DB pinned + Miniatures (Today/Week/All, sort)

## PENDING — backend production deploy
- [ ] `/api/studies` + `/api/miniatures` return **404 in production** (contract in
      yaml shipped, deploy lagging). Base URL + X-API-Key verified against an
      existing endpoint (search/metadata → 200). Once live:
      - smoke-test real JSON, confirm `discovery_models.dart` field names match
      - verify study chapter PGN opens on board; miniature opens on board

## Test (device)
- Library segmented control: My Database default; Discovery shows master DB +
  Miniatures; Studies lists studies.
- Like a game → roulette appears → spin/stop → tag attaches; reopen save sheet →
  roulette trigger shows current tag.
- My Likes tag chips filter (premium); liked cards show tag pills.
- Studies: sort menu, search (debounced backend q), pull-to-refresh; tap study →
  chapters → tap chapter opens on board.
- Miniatures: window tabs + sort; tap row opens master game on board.
