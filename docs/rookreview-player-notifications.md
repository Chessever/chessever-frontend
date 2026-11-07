> Function ownership moved on November 6, 2026: canonical runtime source, parser/extractor tests and deployment config are now in `Chessever/chessever-web-frontend/supabase/functions/partner-news-sync/`, beside `create-news`. This repository retains the historical SQL migrations, database tests and mobile client. Production behavior and deployed version 12 are unchanged by the move.

# RookReview favorite-player notifications

Implementation branch: `feat/rookreview-players-notification`, in the mobile and
admin repositories. The mobile branch starts at `origin/stable` (`16b709b4`);
the admin branch starts at `origin/main` (`16fa0cc`). No website code changes.

## Processing

The existing ten-minute `partner-news-sync` still imports readable articles even
when AI is disabled or unavailable. Its optional background worker calls
Cloudflare Workers AI with the same `@cf/zai-org/glm-5.3-flash` model and low
reasoning effort as the chatbot (`chessever_cloudflare/apps/chat/wrangler.jsonc`).
It uses the account-scoped Chat Completions REST endpoint with a JSON schema and
`store: false`, because Supabase has no Cloudflare AI binding. It sends only
headline, summary and body text. Image markup, alt text and URL destinations are
removed; no image folders are used. There are no model tools or external lookups.

The model selects up to five chess players explicitly named in the title, summary
or written prose, including passing mentions, briefly named opponents and short
result sentences. Main subjects and directly quoted speakers take priority, then
other prose mentions in article order. The existing `subject` role includes these
prose mentions; `quotation` identifies directly attributed speakers. It returns
complete names, exact mentions and unchanged contiguous evidence excerpts selected
from the schema enum. Combining or paraphrasing evidence is rejected locally and
by the database. Names appearing only in standings tables, result/score lists or
pairing lists remain excluded; appearing in written prose can qualify them.
Images, captions, URLs and non-chess people remain excluded.
Uncertain identities are omitted. A unique exact normalized full-name
match in `chess_players` supplies the FIDE ID and display name. No model-supplied
FIDE IDs, rating-ranked guesses or ambiguous name matches are accepted. Names
that need unsupported aliases/transliteration remain unresolved.

The database checks identities and evidence again and writes a private immutable
partner publication. The admin service consumes native and partner publications
through its existing favorite-player scheduler, account preferences, canonical
device view, immutable personalized copy, queue, claim and pre-submission checks.
Multiple matched favorites still yield one delivery per article/installation.
Native payloads, campaign keys and lock names remain unchanged. Partner campaign
keys include `rookreview`, avoiding collisions with native numeric article IDs.

## Prospective admission and dedupe

The database policy starts **disabled**. Enabling it stamps an activation instant
under READ COMMITTED; admission and policy updates serialize on the same row.
An existing article is never enrolled by an edit or later sync. Even a new GUID
for an already imported URL cannot enroll that original article.

Only first inserts after activation with a source publication date between the
activation instant and now, and no older than 30 minutes, can create a job.
Live RSS imports skip future-dated items until due, rather than clamping them
into a fresh alert. Original GUID/URL admissions are unique. Each job has one processing lease and at
most three attempts. Work expires 30 minutes after the source publication, not
30 minutes after extraction or a retry. A failed/refused/incomplete AI result
creates no publication and never blocks the RSS import. Expired or ambiguous
articles remain readable without a notification.

Material/source-date edits, hiding, disabled sources and a changed activation
instant invalidate eligibility. Republishing or re-enabling cannot reset the
admission/publication/fanout history. Existing queue dedupe remains authoritative;
uncertain FCM outcomes are not replayed as fresh sends.

A partner payload is:

```json
{"type":"favorite_player_news","news_id":"10760","news_source":"rookreview"}
```

The updated mobile handler opens `/app/news/partners/rookreview/10760`, ignoring
competing route/URL hints. Native payloads omit `news_source`. Older handlers
would treat the partner numeric ID as native, so both fanout and send-time checks
require app version **37.8.3+3787 or later** for partner pushes. Malformed/unknown
versions are excluded. Native alerts retain their existing version contract.

## Rollout

Production rollout completed **November 3, 2026 at 8:04:29 PM EST**. Credentials,
schemas and both services are deployed; the prospective policy is enabled.
See [the production rollout record](rookreview-rollout-2026-11-03.md) for exact
versions, readiness and repeated-sync checks. All 77 existing articles remained
unenrolled. No opted-in device had a compatible app version at activation, so
device delivery still requires the app update; no mobile release was performed.

An authenticated `POST {"check_ai":true}` uses the same stream-token gate and
verifies the installed GLM credential with fixed synthetic text. It never reads
or imports articles and never claims or publishes notification jobs. The deployed
probe returned HTTP 200 and the exact configured model.

The rollout procedure for future deployments is:

1. Apply mobile migration `20261104005515_rookreview_player_notifications.sql`,
   then admin migration `20261104005636_rookreview_notification_transport.sql`.
   Review the full-directory name-expression index and schema locks in the
   production migration window. Installing either migration does not enable it.
2. Deploy the admin service and updated `partner-news-sync` from the web repository. Preserve its existing
   `verify_jwt = false` configuration and stream-token authentication. Use the
   production project `oelbsuggrzyqwzmvidju` when deployment is authorized.
3. Configure the Edge Function secrets `CLOUDFLARE_ACCOUNT_ID` (the same account
   as the chatbot: `091ffffd15ccb45cae080adb653b17db`),
   `CLOUDFLARE_AI_API_TOKEN`, and `ROOKREVIEW_AI_ENABLED=true`.
   Use a scoped Workers AI API token from that account; do not reuse a master
   deployment/R2 token. These are server secrets, never public/mobile build
   configuration. The model is pinned to `@cf/zai-org/glm-5.3-flash`; there is no
   alternative-provider fallback or OpenAI key requirement. The account must
   already have access to the paid model, as the chatbot does. Configure the
   server token and validate extraction quality before activation.
4. Release mobile **37.8.5+3789** (partner tap support requires at least
   37.8.3+3787), and verify an actual warm/cold partner tap on device. Do not bypass the version gate to target older app builds.
5. Activate only when ready to admit subsequent articles:

```sql
begin isolation level read committed;
update public.partner_news_notification_policy
set enabled = true where source_id = 'rookreview';
commit;
```

Backout: set `enabled=false` and/or unset `ROOKREVIEW_AI_ENABLED`. Keep job,
publication, fanout and delivery history. Re-enabling establishes a new activation
boundary; existing articles do not replay. Provider requests already submitted
cannot be recalled.

Inspect `partner_news_notification_jobs` for states, attempts and bounded error
codes; `partner_player_news_publications` for verified subjects/evidence; and the
existing admin campaign/delivery tables for downstream outcomes. All new tables
are private with RLS and no anon/authenticated grants. Processing RPCs are
service-role only and security-definer functions pin their search path.

## Validation

Mobile `supabase/tests`: `npm run test:partner-news`, `npm run test:favorite-news`,
and `npm run test:rewarded`. The first command includes the AI request/validation
and new admission/lease/publication regressions. Provider calls in admin tests
are intercepted synthetic transports, including FCM and OneSignal.

Admin: `npm test` and `npx tsc --noEmit`. Flutter: scoped `flutter analyze --no-pub`
and `flutter test --no-pub test/favorite_player_news_test.dart test/direct_push_tap_router_test.dart`.
No Flutter build/run or device automation is used.

Real PostgreSQL locking checks use a disposable network-isolated container:

```sh
docker run --rm -d --name codex-rookreview-local --network none \
  -e POSTGRES_HOST_AUTH_METHOD=trust postgres:17-alpine
python3 supabase/tests/rookreview_notification_concurrency.py \
  --container codex-rookreview-local
docker stop codex-rookreview-local
```

The script creates/drops only a random fixture database in that explicitly named
container. It covers activation versus an in-flight import, SKIP LOCKED claims,
competing completion, unsupported activation isolation and reactivation fences.

API references: [GLM-5.3 Flash](https://developers.cloudflare.com/workers-ai/models/glm-5.3-flash/),
[Cloudflare Chat Completions](https://developers.cloudflare.com/workers-ai/configuration/open-ai-compatibility/)
and [Supabase background tasks](https://supabase.com/docs/guides/functions/background-tasks).

## Passing prose mentions — November 6, 2026

Production `partner-news-sync` version 12 broadens extraction to explicitly named chess players in written prose, including passing mentions, briefly named opponents, praise and short result sentences. Names appearing only in standings/result/pairing lists remain excluded. The five-player bound and main-subject/quoted-speaker priority remain. The existing `subject` role covers eligible prose mentions, so directory, publication and favorite-player delivery contracts need no schema change.

Validation: 43 partner tests and 8 native-news tests passed; extractor and test TypeScript checks passed. The deployed authenticated synthetic `check_ai` request 284820 returned HTTP 200 and required both main player Magnus Carlsen and briefly mentioned Hikaru Nakamura. This probe cannot claim jobs, publish articles or send pushes. The production gateway-auth audit passed for 12 functions and public/authenticated proxy probes. `verify_jwt=false` and the function's own stream-token authentication were preserved.

The change does not backfill, requeue or alter the original article freshness/activation boundaries. Images, captions and URL destinations remain excluded as identity evidence. Source version is 37.9.5+3805; no mobile binary build or store release is required for this server-side change.
