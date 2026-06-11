# Contributor Onboarding & Abuse-Proof API Key System — Design

**Date:** 2026-06-08
**Status:** Proposed (awaiting review)
**Author:** Security/architecture proposal
**Scope:** `chessever-frontend`, `chessever_frontend_desktop` (consumers), `chessever_web_frontend` (key portal), `chessever_gamebase` (key enforcement), `chessever-main` Supabase (RLS hardening)

---

## 1. Problem

`chessever-frontend` and `chessever_frontend_desktop` are open source, but contributors cannot run them: the apps need a production `.env` we cannot share. We want:

1. A **freely distributable, degraded `.env`** that lets a contributor build and run both apps for UI/feature work, containing **no secret that can harm us**.
2. A **self-service portal** in `chessever_web_frontend` where a contributor signs in and generates a personal API key that is **ecosystem-wide rate-limited and scope-restricted**, such that contributor traffic **cannot abuse our database resources** — bounded worst-case by construction, not by trust.

## 2. Current-state findings (verified)

### 2.1 The `.env` splits into three risk classes

| Class | Keys | Status today |
|---|---|---|
| **P — public-by-design** | `GOOGLE_WEB_CLIENT_ID`, `GOOGLE_IOS_CLIENT_ID`, `RevenueCatAPIKey` (`goog_…` public SDK key), `SENTRY_FLUTTER` (DSN), `ONESIGNAL_APP_ID`, `AMPLITUDE`, `CLARITY_PROJECT_ID`, `APPSFLYER_DEV_KEY` | Already ship inside every App Store / Play Store binary. Not secret. Only risk: contributor activity polluting **our** prod analytics/crash telemetry. |
| **A — Supabase anon** | `SUPABASE_URL` (`oelbsuggrzyqwzmvidju.supabase.co`), `SUPABASE_ANON_KEY` | **Already public.** The anon JWT ships in every mobile binary *and* in the public `chessever-web-frontend` JS bundle (`src/lib/supabase-browser.ts`). Distributing it to contributors adds **no** new exposure. RLS is the control surface. |
| **G — Gamebase** | `GAMEBASE_API_KEY` | **The genuine secret and the genuine abuse vector.** |

### 2.2 Gamebase API (`chessever_gamebase`) — the real heavy DB

- **Stack:** Node 20 + Hono, entry `src/server.ts` (port 3232), router `src/api.ts`. Deployed on Coolify/DigitalOcean. Prisma → TWIC Postgres (`game`, `game_position`, `game_position_deep` = 100M+ rows).
- **Auth today:** `src/api.ts:16-29` — a single static key compared by string equality: `apiKey !== envVars.clientApiKey` (`CLIENT_API_KEY` env). **No per-key lookup, rate limit, quota, scope, or expiry.** Every holder has identical, unlimited access.
- **Existing partial protections:** pagination caps (game-position max 50/page, search max 100/page); `statement_timeout` per service (8s–120s); Prisma pool limit 35; Redis cache (60s TTL) but only for `pageNumber ≤ 4 && pageSize ≤ 100` (aggregates/games) and `pageNumber ≤ 3 && pageSize ≤ 50 && query.length ≤ 64` (search). **No request-rate limiting of any kind.** No reverse-proxy rate limit in repo.
- **Endpoint risk classes:**
  - *Safe read (contributor-allowed):* `GET /api/player/:id`, `/api/player/:id/games|events|stats`, `GET /api/game/:id`, `/api/search*` (small caps), `/api/studies*`, `/api/miniatures`.
  - *Heavy (contributor cache-only):* `/api/game-position/aggregates*`, `/api/game-position/games*`, `/api/game-position/fen/games*`.
  - *Forbidden to contributor tier:* `/api/admin/*` (Basic-auth, ingestion/queue control), `/api/ingest/*`, `/api/eval/*`.

### 2.3 Cloud Supabase (`oelbsuggrzyqwzmvidju`) — RLS posture

- Every `public` table has **RLS enabled**, but the **`anon` role holds table-level INSERT/UPDATE/DELETE grants on all tables** — RLS policies are the *only* write barrier.
- Content tables (`games`, `tours`, `rounds`, `settings`, `chess_players`, `calendar_events`, `group_broadcasts`) → read policy + admin-only delete, no anon write policy ⇒ **read-only to anon (correct).**
- Tables with RLS enabled and **zero policies** (`broadcast_*`, `community_*`, `notification_outbox`, `kv_store_*`, `omitted_events`, `notification_user_windows`, `user_notification_sends`, `fide_photo_fetch_cache`) ⇒ default-deny (safe).
- **Cache/telemetry tables written by the app as anon** (`evals`, `positions`, `pvs`, `lichess_move_annotations_cache`, `app_feedback`) ⇒ likely carry **permissive anon-INSERT/UPDATE** policies ⇒ spam-insert vector (bounded, but real).
- `SECURITY DEFINER` RPCs executable by anon/authenticated: `get_shared_book`, `ensure_saved_analysis_database_folder`, `delete_user_account`, `is_admin_user`.

**Conclusion:** Supabase exposure already exists for any app user and is **not increased** by giving contributors the anon key. It deserves a hardening pass *because* we are about to publicize the key more prominently. The novel work is the **Gamebase** tiered key system.

### 2.4 Web frontend (`chessever_web_frontend`) — portal host

- Next.js 16 App Router (React 19, TS), Supabase Auth already wired with **Google + Apple OAuth** (`src/app/account/AccountClient.tsx`), PKCE, role-based admin gate, service-role server client (`src/lib/supabase-admin.ts`), Next API routes + Supabase Edge Functions. Deployed on Vercel. **A `/developers` portal slots in directly using the existing auth session.**

### 2.5 Data-hub (`chessever_data_hub_monorepo`)

Pure write-side ETL (Lichess → Supabase). Exposes no frontend-facing API. Holds `SUPABASE_SERVICE_ROLE_KEY` and `DO_API_TOKEN` (never to be shared). **Out of scope for contributor onboarding.**

## 3. Goals & non-goals

**Goals**
- Contributors run both Flutter apps with a committed, secret-free env.
- Contributors optionally obtain a personal Gamebase key for real-data testing.
- Contributor traffic against Gamebase has a **provable, attacker-independent resource ceiling.**
- Tighten the Supabase anon surface before publicizing the key.

**Non-goals**
- Not building a public/commercial API product (separate future effort; this design is forward-compatible with it).
- Not changing how first-party production apps authenticate (backwards compatible).
- Not exposing the deep position explorer, engine eval, ingestion, or admin to contributors.

## 4. Approaches considered

- **A — Self-service portal + tiered Gamebase auth (chosen for Phase 1).** Per-user hashed keys, scope allow-list, per-key + global rate limits, cache-only heavy endpoints, expiry/rotation, anomaly auto-suspend. Only option with a provable bound.
- **B — Mock-data-first, no live key (chosen for Phase 0).** Ship fixtures; blank `GAMEBASE_API_KEY` → app degrades to sample data. Zero new infra, ships immediately. Complements A.
- **C — Shared low-priv proxy key + edge rate-limit (rejected).** No per-abuser identity/revocation/attribution; re-creates the shared-secret problem behind a proxy.

**Decision: ship B now, build A next. A supersedes the need for any shared contributor key.**

## 5. Design — Phase 0: distributable degraded env + mock mode

### 5.1 `.env.example` (committed) + `make dev-env`
- Commit `.env.example` with all keys documented and grouped by risk class.
- A setup script (`make dev-env` / `scripts/dev_env.sh`) writes `.env` from `.env.example`, filling:
  - **Class P:** dedicated **dev/sandbox** project values where one exists (Amplitude/Clarity/OneSignal dev app, Sentry dev DSN) so contributor noise never reaches prod dashboards; harmless real values otherwise (Google client IDs are bundle-id-scoped). Where no sandbox exists, leave blank — the app must tolerate missing analytics keys.
  - **Class A:** the public anon key + URL (read-only content path; see §7 hardening). Acceptable because already public.
  - **Class G:** `GAMEBASE_API_KEY=` **blank**.

### 5.2 Graceful degradation when `GAMEBASE_API_KEY` is blank
- Both apps must detect a missing/empty Gamebase key and switch the historical-DB features (position explorer, player game search, miniatures, studies) to a **bundled fixture dataset** (a few serialized sample responses) with a visible "sample data — add a developer key to enable live search" banner.
- This makes the apps fully runnable for UI/feature work with **zero backend calls** to the heavy DB. (Contributor onboarding requires this even after Phase 1, as the no-key default.)

### 5.3 Secret hygiene
- Pre-commit hook (`gitleaks`/`detect-secrets`) in both Flutter repos to block accidental real-secret commits.
- Rotate the existing static `GAMEBASE_API_KEY` once Phase 1 lands (it has been in shared local envs); the new first-party key is injected only via CI build secrets, never committed.

## 6. Design — Phase 1: Gamebase key portal + tiered enforcement

### 6.1 Key store (Gamebase DB or Supabase — see open decision §9)
Table `api_key`:
```
id            uuid pk
key_hash      text         -- SHA-256 of the raw key; raw shown once, never stored
key_prefix    text         -- e.g. "cevg_live_AB12" for display/identification
owner_user_id uuid         -- Supabase auth user
tier          text         -- 'first_party' | 'contributor'
scopes        text[]       -- allow-listed endpoint groups
created_at    timestamptz
expires_at    timestamptz  -- contributor default now()+90d
last_used_at  timestamptz
revoked_at    timestamptz
```
Index on `key_hash`. Optional `api_key_usage` rollup table (per-key daily counters) for the dashboard + anomaly detection.

### 6.2 Gamebase auth middleware upgrade (`src/api.ts`)
Replace the static compare with:
1. If header equals the **first-party** key (CI-injected) → `tier=first_party`, full access. *Backwards compatible — production apps unaffected.*
2. Else hash the presented key, look up `api_key` (cached in Redis ~60s). Reject if missing / `revoked_at` / `expires_at < now()`.
3. Attach `{tier, scopes, owner_user_id}` to the request context. Update `last_used_at` async.

### 6.3 Contributor-tier enforcement (all bounds are hard ceilings)
1. **Scope allow-list** — only the §2.2 "safe read" group. `/admin/*`, `/ingest/*`, `/eval/*` and deep-explorer routes return 403 for `tier=contributor`. Enforced as middleware *before* any handler.
2. **Cache-only heavy endpoints** — for `tier=contributor`, position-aggregates/games/search handlers read **only** from Redis. On cache miss: return a small precomputed sample (or `204`/`{cached:false}`), **never** issue a cold uncached query. Contributors structurally **cannot trigger an expensive scan.**
3. **Per-key token bucket** — Redis sliding window, e.g. **30 req/min, burst 10** → `429` + `Retry-After`.
4. **Per-key daily quota** — e.g. **5,000 req/day** → `429` until reset.
5. **Global contributor-tier token bucket** — one shared Redis bucket across *all* contributor keys, e.g. **100 req/s tier-wide**. Independent of key count ⇒ mass key-minting yields nothing.
6. **Forced pagination floor** — contributor `pageSize` clamped to ≤ 20 regardless of request.
7. **Short statement timeout + isolated pool** — contributor queries run with `SET LOCAL statement_timeout='3s'` and a small dedicated Prisma pool (e.g. 5 connections) or, preferably, a **read replica** DSN, so contributor load cannot starve the production pool.
8. **Anomaly auto-suspend** — sustained 429s / scope-violation attempts / error spikes flip `revoked_at` and alert.

### 6.4 Portal (`chessever_web_frontend`, `/developers`)
- New authenticated page reusing the existing Supabase session (Google/Apple). Unauthenticated → sign-in.
- **Mint:** server route / Edge Function (service role) generates a random key, stores its SHA-256 in `api_key`, returns the raw key **once**. UI shows copy-once modal + the `.env` line to paste.
- **Manage:** list active keys (prefix, created, last-used, expiry), per-key usage vs quota, **revoke** and **rotate**.
- **Anti-mass-minting:** require verified email (Supabase Auth already verifies OAuth identities) + **max 3 active contributor keys per user**; optional GitHub-account link / Turnstile CAPTCHA on mint. Combined with the §6.3.5 global ceiling, abuse via many accounts is still bounded by the tier-wide bucket.

### 6.5 Why the bound holds (threat model summary)
| Attacker move | Bounding control |
|---|---|
| Hammer one key | per-key token bucket + daily quota (§6.3.3–4) |
| Mint many keys / many accounts | global tier bucket (§6.3.5) + max-keys-per-user (§6.4) |
| Hit expensive explorer/search | cache-only + scope allow-list (§6.3.1–2) |
| Long/heavy single query | 3s statement_timeout + isolated pool/replica (§6.3.7) |
| Reach write/admin/ingest/eval | scope allow-list 403 (§6.3.1) |
| Leak/share a key | hashing + revoke + 90d expiry + anomaly auto-suspend (§6.1, §6.3.8) |
| Abuse Supabase via anon key | §7 hardening; exposure unchanged from status quo |

Worst-case Gamebase consumption is **fixed by the global bucket + cache-only policy**, independent of how hard anyone tries.

## 7. Supabase anon-surface hardening (do before publicizing the key)
1. **Revoke** anon `INSERT/UPDATE/DELETE` table grants except where the app genuinely writes as anon; for those, replace blanket grants with **column-scoped, rate-bounded** insert policies (or move the writes behind an Edge Function with a service-role + per-IP limit). Target: `evals`, `positions`, `pvs`, `lichess_move_annotations_cache`, `app_feedback`, `fide_photo_fetch_cache`.
2. **Audit the `SECURITY DEFINER` RPCs** (`get_shared_book`, `ensure_saved_analysis_database_folder`, `delete_user_account`, `is_admin_user`): set explicit `search_path`, switch to `SECURITY INVOKER` where possible, and `REVOKE EXECUTE` from `anon` where not needed.
3. Fix the flagged **`function_search_path_mutable`** functions.
4. Optionally add a **PostgREST statement timeout** for the anon role and confirm rounds/games read volume is acceptable (broadcast data, not the 100M TWIC set).

> These are pre-existing issues surfaced by the advisor; folding them in is the responsible move given we're about to point contributors at the key.

## 8. Rollout plan
- **Phase 0 (days):** `.env.example` + `make dev-env` + mock-data degradation + secret-scan hooks + CONTRIBUTING.md "run locally" guide. Unblocks contributors immediately.
- **Phase 0.5 (parallel):** Supabase §7 hardening.
- **Phase 1 (the durable system):** `api_key` store → Gamebase middleware upgrade (first-party + tiered lookup) → contributor-tier enforcement (scope, cache-only, per-key + global limits, timeout/replica) → `/developers` portal → docs. Rotate the legacy static key last.
- **Phase 2 (optional):** usage dashboard, anomaly auto-suspend tuning, read-replica if not done in Phase 1, public-API productization on the same primitives.

## 9. Open decisions (defaults chosen; override as needed)
1. **Key store location** — *default:* the Gamebase Postgres (keeps enforcement-path lookups local/fast). Alternative: cloud Supabase (one auth home, but cross-service lookup on the hot path). 
2. **Class-P sandbox vs blank** — *default:* dedicated dev analytics/crash projects where they already exist, blank otherwise. Need to confirm which sandbox projects exist.
3. **Read replica now or later** — *default:* Phase 1 ships with isolated small pool + 3s timeout; replica is Phase 2 unless one already exists.
4. **CAPTCHA on mint** — *default:* email/OAuth-verified + max-3-keys is enough given the global ceiling; add Turnstile only if minting abuse appears.
5. **Canonical repo for this spec** — currently in `chessever-frontend`; the Gamebase + portal work lands in their own repos referencing this doc.

## 9a. Implementation status (2026-06-08)

Built and opened as PRs (backends auto-deploy on push, so they are **not** pushed to their deploy branches):

- **Registry location decided: Gamebase Postgres** (open decision §9.1), so the `X-API-Key` hot path validates locally. A new discovery shaped this: the **desktop already routes Gamebase calls through a Supabase Edge Function `gamebase-proxy`** that keeps the upstream key server-side, so desktop contributors need no Gamebase key at all. Mobile still sends the key directly to `https://service.chessever.com` as `X-API-Key`, so the contributor key targets mobile + anyone calling the API directly.
- **Gamebase** — PR `Chessever/gamebase#30`: `developer_api_key` table + `npm run db:developer-api-keys`; tiered `X-API-Key` middleware (first-party static key unchanged + `cevg_*` contributor path); `/portal/dev-keys` mint/list/revoke mounted outside `/api` with portal-secret auth; `dev-key.service.ts` doing hash-only storage, Redis-cached validation, and the three layered Redis rate ceilings (per-key/min, per-key/day, global/sec). Gated by `DEV_KEYS_ENABLED`. Cache-only-heavy-endpoints (§6.3.2) and replica isolation (§6.3.7) are deferred; the bound holds via the global ceiling + scope allow-list + existing per-query timeouts.
- **Web portal** — PR `Chessever/chessever-web-frontend#2`: `/developers` page + `/api/developer/keys` thin authenticated proxy to Gamebase + nav link. Degrades to 503 until configured.
- **Flutter apps** — `.env.example` (public keys filled, `GAMEBASE_API_KEY` blank → portal) + README "Contributing" sections in both repos. Mobile `.gitignore` gained an `!.env.example` exception.

**Go-live:** generate one shared secret (`openssl rand -hex 32`); set it as Gamebase `DEV_PORTAL_SECRET` and web `GAMEBASE_PORTAL_SECRET` (must match); run the Gamebase migration; merge both PRs.

## 10. Success criteria
- A fresh contributor clones either app, runs `make dev-env`, and the app launches with sample data and **no production secret on disk**.
- A signed-in contributor mints a key at `/developers` and sees live search/explorer in the app.
- Load test: 10k contributor keys cannot push Gamebase past the configured global QPS, cannot trigger a cold heavy query, and cannot reach any forbidden endpoint.
- Supabase advisor re-run shows the §7 items resolved.
