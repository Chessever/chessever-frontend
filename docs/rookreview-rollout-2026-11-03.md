# RookReview production rollout — November 3, 2026

Enabled at **8:04:29 PM EST** (`2026-11-04T01:04:29.555714Z`).
Production Supabase project: `oelbsuggrzyqwzmvidju` (Chessever).
Cloudflare account: `091ffffd15ccb45cae080adb653b17db`.

## Deployment

- Cloudflare model: `@cf/zai-org/glm-5.3-flash`, low reasoning effort, matching the deployed chatbot.
- Dedicated token: `RookReview player news production`; Workers AI Read/Edit on the ChessEver account only; expires November 3, 2027. Its value was transferred directly into production Supabase and never written to repository files or deployment output.
- Supabase secrets saved: `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_AI_API_TOKEN`, `ROOKREVIEW_AI_ENABLED=true`.
- Hosted migrations: `20261104005515_rookreview_player_notifications.sql`, followed by `20261104005636_rookreview_notification_transport.sql`. Local migration files and references match the hosted versions assigned by the API. The large player-name index completed and is valid. Migration execution used short lock timeouts.
- Edge Function `partner-news-sync`: active version **11**, bundle SHA-256 `7464857c1765ec05153a54761eb68b303b3f1312f4faac339d489caebd9a0c13`; own stream-token authentication retained; `verify_jwt=false` retained.
- Cloudflare delivery Worker `chessever-notifications`: active version `803d43f4-1477-4180-b046-6403b62fdc56`. Existing queue, cron schedules, runtime variables and secrets preserved. Deployment gate: production build, type check and all **556 tests passed**.

## Verification without old-article sends

The authenticated `check_ai` request ran inside the deployed Edge Function using
its installed scoped token. It returned HTTP 200 with
`{"check_ai":true,"ok":true,"model":"@cf/zai-org/glm-5.3-flash"}`.
The check uses fixed synthetic text and never imports an article, claims a job,
writes a publication, selects recipients or submits a push. Request ID: `255140`.

Before activation, all **77** stored RookReview articles remained unenrolled.
After activation, two authenticated syncs (`255147`, `255153`) each returned
HTTP 200, `received=30`, `inserted=0`, `updated=0`, with no timeout or error.
The stored article count remained 77 and the ordered article-ID fingerprint
remained `dffbe9f430065bad9c227bc8088d0ffe`.

Post-check counts: **0 notification jobs, 0 partner publications, 0 RookReview
campaigns, 0 RookReview deliveries**. No historical or repeated-sync push was
queued or sent. No timestamps were rewritten and no fixture articles or jobs
were inserted in production. The source reported zero consecutive failures.

The admission trigger remains INSERT-only, checks the activation instant and
30-minute source-publication freshness, rejects previously imported URLs, and
keeps unique GUID/URL admissions. Existing rows cannot become eligible through
edits or repeat imports. Reactivation changes the epoch; it does not replay old
jobs. The model and delivery checks retain the original publication deadline.

All new tables have RLS and no anon/authenticated SELECT/INSERT/UPDATE/DELETE
grants. The security advisor's no-policy notices describe the intentional private,
service-only tables; no permissive public policies were added. The Edge Function
returns its own HTTP 401 for unauthenticated POSTs. Critical existing gateway-auth
flags were checked and remained false. The desktop auth-check script referenced
by AGENTS.md was not present in the available checkouts, so metadata and actual
endpoint responses were checked directly instead.

## Mobile compatibility

At activation, **0 opted-in installations** reported version 37.8.3 or later.
The version gate remains enforced, because older clients would interpret the
partner numeric ID as native News. The backend is enabled, but device delivery
requires a compatible app update. No mobile/store release or physical-device
push test was performed. This source branch is version **37.8.5+3789**.

## Backout

Set `partner_news_notification_policy.enabled=false` for `rookreview`, and/or
set `ROOKREVIEW_AI_ENABLED=false`. Preserve jobs, publications, fanout and delivery
history. Never delete history, backdate publication times or lower the version
gate to force delivery. A later reactivation establishes a fresh cutoff.
