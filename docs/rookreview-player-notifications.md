# RookReview favorite-player notifications

Implementation branch: `feat/rookreview-players-notification`, in the mobile and
admin repositories. The mobile branch starts at `origin/stable` (`16b709b4`);
the admin branch starts at `origin/main` (`16fa0cc`). No website code changes.

## Processing

The existing ten-minute `partner-news-sync` still imports readable articles even
when AI is disabled or unavailable. Its optional background worker calls OpenAI's
Responses API with strict structured output and `store: false`. It sends only
headline, summary and body text. Image markup, alt text and URL destinations are
removed; no image folders are used. There are no model tools or external lookups.

The model selects up to five main subjects/directly quoted chess players and
returns complete names, exact mentions and verbatim evidence. Passing mentions,
results-only participants, photographers, relatives and non-chess athletes are
excluded. Uncertain identities are omitted. A unique exact normalized full-name
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

This change is local source only: no hosted SQL, deployed functions, real model
requests or real pushes were executed. The feature remains disabled.

1. Apply mobile migration `20261103213329_rookreview_player_notifications.sql`,
   then admin migration `20261103213332_rookreview_notification_transport.sql`.
   Review the full-directory name-expression index and schema locks in the
   production migration window. Installing either migration does not enable it.
2. Deploy the admin service and updated `partner-news-sync`. Preserve its existing
   `verify_jwt = false` configuration and stream-token authentication. Use the
   production project `oelbsuggrzyqwzmvidju` when deployment is authorized.
3. Configure the Edge Function secrets `OPENAI_API_KEY`, `ROOKREVIEW_AI_MODEL`
   (a Responses/strict-JSON-schema capable model), and `ROOKREVIEW_AI_ENABLED=true`.
   These are server secrets, never public/mobile build configuration. There is no
   hardcoded model or key. The session had neither configured, so live extraction
   quality and account/model availability still need validation before activation.
4. Release mobile **37.8.3+3787**, and verify an actual warm/cold partner tap on
   device. Do not bypass the version gate to target older app builds.
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

API references: [Structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs)
and [Supabase background tasks](https://supabase.com/docs/guides/functions/background-tasks).
