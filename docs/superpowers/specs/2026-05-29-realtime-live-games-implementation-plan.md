# Realtime Live-Games — Minimum-Viable Fix for Trello #654

> Status: ready-to-ship · Date: 2026-05-29 · Trello card #654 "Phone event refresh should fetch later live rounds — HermesVasif"
>
> Decision recorded: ship the **minimum-viable fix** that solves Vasif's bug. The full architectural refactor described in `2026-05-28-realtime-live-rounds-design.md` is **deferred**; the deferred-work table at the end of this doc preserves the rationale for future revisits.

---

## 1. The bug (one paragraph)

Vasif: Titled Tuesday 2026-05-26, phone app did not show Round 2 even after manual refresh and after closing and reopening the event. Desktop showed Round 2 live.

Root cause is **not** the 1000-row PostgREST cap. The pagination loop fix from PR #189 is already on `dev` (commit `4325eef8`); if the cap were the cause, close-reopen would have worked for Vasif. It didn't. The actual cause: `public.settings` (carrying `live_round_ids`) is **not** in the `supabase_realtime` publication, so `.stream()` on `settings` delivers exactly one snapshot at subscribe time and goes silent. Round status is computed off that frozen snapshot, so a round that goes live after open is never promoted client-side.

## 2. The fix (four changes, ~3 files + 1 SQL line)

| # | Change | File | Risk |
|---|---|---|---|
| 1 | `ALTER PUBLICATION supabase_realtime ADD TABLE public.settings;` | migration | reversible one-liner |
| 2 | `listEquals` guards before `bumpForYouEventsRefreshSignal` at lines 168 + 171 | `lib/providers/for_you_games_provider.dart` | **mandatory** safety pairing with #1 — without these, the revived stream fires a refetch storm on every WAL write |
| 3 | Promote-only + transient-empty guard in `_onLiveRoundsChanged` | `lib/screens/tour_detail/games_tour/providers/games_app_bar_provider.dart` (~:1262) | prevents reconnect snapshots from demoting a live round |
| 4 | Day-boundary fix in `status()` | `lib/screens/tour_detail/games_tour/models/games_app_bar_view_model.dart:62` | independent latent bug; round started 23:50 must not flip to `completed` at local midnight |

Total: one SQL line + three small Dart edits. Solves Vasif's bug. Zero new channels. Zero new providers. Zero new disposal-contract surface.

## 3. Verification (manual, post-merge)

Pre-merge: `flutter analyze` on the three touched Dart files clean.

Post-merge on a live broadcast:
- [ ] Open Titled Tuesday during Round 1.
- [ ] Wait for Round 2 start time.
- [ ] Without restarting the app and without pull-to-refresh, Round 2 appears as live within seconds.
- [ ] App background → foreground does not flip Round N out of `live` momentarily.
- [ ] Round started 23:50 local stays `ongoing`/`live` past midnight.

## 4. Revert procedure

### Full revert (everything in this fix)

```bash
git revert <pr-sha> --no-edit
git push origin dev
```

```sql
ALTER PUBLICATION supabase_realtime DROP TABLE public.settings;
```

Verify:
```sql
SELECT tablename FROM pg_publication_tables
WHERE pubname = 'supabase_realtime' ORDER BY tablename;
-- expect: games   (only)
```

Total elapsed: ~60 seconds. No data migration. No cache invalidation. The SQLite `games_$tourId` cache is unchanged in shape.

### Hotfix revert (live incident)

If For-You shows symptoms of a refetch storm, drop the publication FIRST, then revert the client:

```sql
ALTER PUBLICATION supabase_realtime DROP TABLE public.settings;
```

…then `git revert` the client PR. Order matters: dropping the publication immediately suspends the WAL stream, which collapses any cascade even before client code returns.

### Revert ordering hazard

If the fix is split into multiple PRs and partial-reverted:

- **Never** revert the For-You `listEquals` guards (change #2) while the publication ADD (change #1) is still deployed. Doing so causes the refetch storm. Either revert both together, or revert #1 first.
- All four changes can be reverted together safely in any order.

---

## 5. Deferred work (recorded for future revisits)

The 2026-05-28 design spec proposed a broader architectural shift. After auditing the bug, we concluded only the publication ADD + three guards are required to solve Trello #654. The full plan is deferred. The table below captures what each deferred piece would buy, what risk it carries, and whether it would solve the ticket (most do not). Revisit when there is a concrete user signal pointing to one of these surfaces.

### What the big plan adds beyond the minimum

| Piece | Solves Trello #654? | Independent value | Risk |
|---|---|---|---|
| Per-tour realtime channel + drop 10s poll (event Games tab) | No (status was the cause, not poll latency) | Lower battery on Games tab. Push-driven UX nicety. | Socket budget, race buffer, dispose contracts |
| Drop pagination loop in `getGamesByTourId` | No (loop already works) | Cleanup. ~50 LOC delete. | None |
| Anchored scroll prepend on new-round INSERT | No (no top-prepend without per-tour channel being live) | UX polish for new rounds | Small |
| 5-surface intersect-debounced control plane (For You / favorites / countrymen / player profile / event tab) | No (Vasif's bug is the event tab only) | All surfaces stay fresher on live-set change | New surface area |
| Clock tick promote-only liveness | Indirectly — only needed because we ship the publication ADD; **already covered by change #3 in this minimum fix** | Backup signal if push lags | Demote bugs if rules wrong |
| Multi-binding / channel registry (single user-scoped channel) | No | Pro-tier cost cap at scale | Premature for current load |
| RPC `get_tour_games_minimal` (server-aggregate JSONB) | No | 5× faster cold open | Minor |

Everything in this table is "nice to have", not "required for the ticket". The big plan's ~14 unit tests + 5 surface refactors + new providers are real engineering cost. ChessEver is at "close to perfect" because the per-card streams cover the 99% case.

### Verified pre-flight facts (preserved for the deferred work)

| Fact | Value |
|---|---|
| Project tier | Cloud Pro, Small compute (`max_connections=120`) |
| `games` in publication | ✅ yes |
| `settings` in publication | ❌ no — this minimum fix adds it |
| `rounds` in publication | ❌ no — intentionally not added |
| `games` replica identity | `default (pk)` — sufficient |
| `rounds.nr` column | ❌ missing — order key would need `starts_at` + regex(slug) if per-tour channel ever ships |
| Biggest tour | `tour_id='KzJtN57S'`, 4068 games |
| Cold payload (no pgn) | 3.3 MB raw / ~700 KB gzipped wire |
| Cold payload (with pgn) | 24 MB raw / ~5 MB wire |
| PGN p50 / p95 / max | 4.7 KB / 7.8 KB / 14 KB |
| `players[].clock` populated for fresh-paired rows | 1.4% (effectively absent → fresh-paired card shows `--:--` until first move, acceptable) |
| Realtime concurrent connections quota | 500 included; $10 per 1000 overage |
| Realtime messages/month | 5M included; $2.50 per 1M overage |
| Max realtime message size | 3 MB |

### Triggers for revisiting the deferred work

Ship the per-tour channel + drop the poll **only if** one of these signals appears:

- Real user reports of battery drain attributable to the 10s tour-games poll on long event sessions.
- Real user reports of "I refreshed the event games list and new live games still didn't appear" (i.e. the post-fix Trello card would say "phone game list doesn't push", not "live round doesn't show").
- Telemetry showing the 10s poll fires >500 times per session for a meaningful slice of users.

Ship the 5-surface intersect-debounced control plane refetch **only if** one of these signals appears:

- Real user reports that today's live games on Countrymen / Favorites / Player profile remain stale.
- Telemetry showing live-set changes are happening but those tabs don't reflect them within ~30s.

Ship the per-tour channel only if the cost-cap math (PR-tier 500 sockets, current ~3 sockets/user steady-state) is broken by user growth such that a meaningful user cohort would benefit.

---

## 6. References

- Trello card #654 — short link `CPW00mGJ`.
- 2026-05-28 design spec — `docs/superpowers/specs/2026-05-28-realtime-live-rounds-design.md` (architectural target if the minimum fix ever proves insufficient).
- Closed PR #189 — `fix/phone-event-rounds-fetch-all` (the pagination-loop fix, already merged to `dev` via commit `4325eef8`).
- Memory note: `realtime_publication_only_games.md`.
- Memory note: `games_date_start_corruption.md` (day-bucketing rules — informs the day-boundary fix in change #4).
- Supabase pricing: https://supabase.com/pricing (verified 2026-05-29).
