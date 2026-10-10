# Phone: one-way editorial Inbox

## Scope and audience

- Editorial plain-text messages from the ChessEver team to **everyone**, including
  existing Supabase `signInAnonymously` guests. This is not an account-sign-in gate,
  a reply/chat system, a recipient list, Premium targeting or a push subscription.
- Publication makes one shared message visible in Inbox; **no push, email,
  OneSignal call, send queue or per-recipient fan-out** is implemented.
- A read means that this exact message was opened and the server successfully
  recorded that session's read. Listing/refreshing Inbox does not mark anything.
- The backend change is additive. Existing push/live-event notification behavior,
  configuration and credentials are unchanged. The phone code shipped as
  `36.0.2+3580`. Local implementation/testing grants no remote authority.

## Data and access contract

Migration: `supabase/migrations/20261010120000_editorial_inbox.sql`.

| Table | Columns and meaning |
| --- | --- |
| `public.editorial_inbox_messages` | `id uuid` explicit primary key; `title text`; `body text` plain text; `published_at timestamptz` (`NULL` = draft); `created_at timestamptz` server default |
| `public.editorial_inbox_reads` | `user_id uuid` FK to `auth.users`; `message_id uuid` FK to messages; `read_at timestamptz` server default; primary key `(user_id,message_id)` |

- Title: 1–200 Unicode characters, nonblank, single line. Body: 1–20,000
  characters, nonblank; newlines allowed. Store/render literally, not as HTML or
  Markdown. The tool rejects NUL; PostgreSQL text cannot contain NUL either.
- `anon` and `authenticated` have SELECT access only to messages where
  `published_at IS NOT NULL AND published_at <= now()`. Both drafts and synthetic
  future publications are hidden. All other message privileges are revoked.
- `authenticated` can SELECT **only its own** reads through RLS. `anon` cannot
  SELECT reads. Neither client role has raw INSERT/UPDATE/DELETE privileges or
  write policies on either table.
- An anonymous-auth guest has an auth UUID and the `authenticated` database
  role. Guests use exactly the same session RPCs as registered accounts.
  A truly unauthenticated `anon` reader may SELECT public content, but cannot
  record reads or execute the session RPCs.
- Explicit function grants replace broad default grants. Every RPC pins
  `search_path = ''` and uses schema-qualified references. The listing RPC is
  SECURITY INVOKER with table RLS; marking and administrative RPCs are narrowly
  SECURITY DEFINER. No RPC accepts an arbitrary user UUID.
- Published content, IDs and publication timestamps cannot be edited or
  unpublished through the workflow. Publication takes server `now()`, not a
  client-supplied timestamp. A trigger also rejects privileged accidental
  published updates and changes to draft IDs/creation times.
- Both FKs use `ON DELETE CASCADE`. There is **no delete RPC or client/service
  table DELETE grant**. A future explicitly authorized owner-level erasure can
  delete messages/users and remove their read markers without orphans.

### Frontend RPCs (execute: `authenticated` only)

```text
list_editorial_inbox(
  p_before_published_at timestamptz DEFAULT NULL,
  p_before_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 100
) -> rows {id, title, body, published_at, read_at}

mark_editorial_inbox_read(p_message_id uuid) -> timestamptz
```

- Listing requires `auth.uid()`. Order is `published_at DESC, id DESC`. Pass both
  cursor fields from the last item, or neither; partial cursors are rejected.
  Positive page limits are clamped to 100; NULL/nonpositive limits are rejected.
  The join includes only the caller's reads. **Continue paging until exhaustion**,
  including old messages and timestamp ties; 100 is a page size, not a total cap.
- Marking requires `auth.uid()` and an exact currently visible published ID.
  Missing/draft/future IDs fail with the same not-found error. It inserts only
  the caller's row and returns the original timestamp on conflict/retry. It does
  not update an existing timestamp, mark other messages or expose other users.
- Fetch/mark failures are not empty/unread-zero/success results. Keep a
  recoverable error state, do not optimistically commit a read on failure, and
  provide retry. Only use the returned timestamp after a successful mark.
- Local cached content/read state must be keyed by the current **auth UUID**,
  including the guest UUID. Clear/switch account-scoped state on auth changes;
  do not carry read flags across users. Cached state is not server confirmation.
  These are client integration requirements, not a claim of device validation.

### Administrative RPCs (execute: `service_role` only)

```text
save_editorial_inbox_draft(p_id uuid, p_title text, p_body text)
  -> one message row (PostgREST composite representation)
publish_editorial_inbox(p_id uuid, p_expected_title text, p_expected_body text)
  -> one message row (PostgREST composite representation)
```

- Saving inserts/updates only an unpublished draft with the explicit UUID.
  Reusing the same UUID does not create another message. Saving published
  messages fails, even if the new content is identical.
- Publishing is a **separate action**. It locks the draft and compares the
  expected title/body snapshot atomically. A stale preview/concurrent edit
  fails rather than publishing different text. A retry with the same UUID and
  content returns the original published row/time. Missing IDs are not created.
- `service_role` has message SELECT for inspection but no direct table writes.
  Only these two RPCs grant its publishing authority. Never put this role/key in
  a phone app. Bounds and immutable-publication rules are database-enforced.

## Safe local administrative tool

`scripts/inbox/publish_inbox.py` uses the Python standard library. It follows the
service-role-only editorial pattern retained in the discovery migration. The
old `scripts/collections/upload_collection.py` is **absent at this base**;
`docs/collections.md` records its removal/move to Gamebase. It was not recreated
or altered for Inbox.

Safety boundaries:

- An omitted action, `preview`, and `save`/`publish` without `--apply` are fully
  offline previews. They do not retrieve a service credential or contact an API.
- `create` writes a **local draft JSON file only**, validates explicit UUID and
  bounds, and refuses to overwrite an existing file.
- `--apply` can contact **literal loopback only** (`127.0.0.1`, `::1`, or pinned
  `localhost`). Remote URLs, nonloopback IPs, URL credentials, paths, queries and
  fragments are refused. Ambient HTTP(S) proxies are disabled; redirects are
  refused before forwarding credentials. There is no remote bypass flag.
- The applied command reads only dedicated runtime environment variables:
  `EDITORIAL_INBOX_LOCAL_URL` and `EDITORIAL_INBOX_LOCAL_SERVICE_ROLE_KEY`.
  It does not load dotenv or inspect app/production credential files. Supply an
  authorized **local** credential through the runtime secret mechanism; do not
  put keys in a command argument, draft JSON, source, chat or log.
- Applied publication also requires `--confirm-id` matching the exact displayed
  canonical lowercase UUID. It compares saved content before publishing and
  sends the expected snapshot for the locked database comparison.
- Every API write is followed by an exact-ID GET/readback. A failed response,
  mismatched content or failed readback exits nonzero and does not claim success.
  An ambiguous timeout/readback failure may still follow a completed write;
  inspect/retry the **same UUID**, never generate a new one automatically.
- No command sends a notification or email. No production/test rollout or
  editorial publication was performed as part of these local tests.

### Labeled local example

This checked-in example is **synthetic test content, not approved editorial
copy**: `scripts/inbox/example.local-fixture.json`.

```bash
# Default: offline preview; safe without API environment or credentials.
python3 scripts/inbox/publish_inbox.py scripts/inbox/example.local-fixture.json

# Optional local draft creation; this is not an API write or publication.
mkdir -p scripts/inbox/.test-runs
python3 scripts/inbox/publish_inbox.py create \
  --id 50000000-0000-4000-8000-000000000001 \
  --title '[LOCAL TEST FIXTURE] New local draft' \
  --body-file scripts/inbox/example.local-fixture.body.txt \
  --output scripts/inbox/.test-runs/new-local-draft.json

# Dry-run plans: still offline; --apply is deliberately omitted.
python3 scripts/inbox/publish_inbox.py save scripts/inbox/example.local-fixture.json
python3 scripts/inbox/publish_inbox.py publish scripts/inbox/example.local-fixture.json

# Only with an approved disposable local API + local role credential supplied:
python3 scripts/inbox/publish_inbox.py save scripts/inbox/example.local-fixture.json --apply
python3 scripts/inbox/publish_inbox.py publish scripts/inbox/example.local-fixture.json \
  --apply --confirm-id 40000000-0000-4000-8000-000000000001
```

## Executed local validation and reproducibility

**No hosted Supabase, real credential, production database or deployed API was
queried.** There are two distinct fixtures; neither establishes production parity.
The executed local receipt is **41 Python tests passed**, **82 SQL contract
checks passed**, and **4 additional real multi-connection concurrency checks
passed** (eight simultaneous first marks and eight same-UUID publications).

1. **LOCAL API MOCK FIXTURE**: stdlib unittest starts a real loopback HTTP server
   with explicitly synthetic credentials, content and timestamps. It exercises
   CLI subprocess preview/save/publish, draft creation, exact-ID retries,
   separate publication, stale snapshots, readback, malformed/remote endpoints,
   redirect/proxy protection, bounds and failed writes/readbacks.

   ```bash
   python3 -m unittest discover -s scripts/inbox -p 'test_*.py' -v
   ```

2. **LOCAL POSTGRESQL CONTRACT FIXTURE**: `supabase/tests/editorial_inbox.sql`
   bootstraps a minimal labeled `auth.users`/`auth.uid()` and the three database
   roles, then executes the **real migration**. It checks actual grants/RLS,
   guests and registered users, hidden drafts/future items, all cursor pages,
   own-only reads/idempotency, missing sessions, malicious/raw writes, immutable
   publication, service-role bounds/snapshots and both FK cascades. This is not
   full Supabase Auth/JWT or PostgREST/schema-cache integration.

   ```bash
   # Installed PostgreSQL tools on PATH:
   python3 scripts/inbox/run_sql_tests.py

   # Or the locally unpacked PostgreSQL used for this run:
   python3 scripts/inbox/run_sql_tests.py \
     --pg-bin scripts/inbox/.local-postgres/install/usr/lib/postgresql/17/bin \
     --pg-lib scripts/inbox/.local-postgres/install/usr/lib/x86_64-linux-gnu \
     --pg-share scripts/inbox/.local-postgres/install/usr/share/postgresql/17
   ```

   The runner accepts **no database URL or remote host**. It creates its own
   isolated cluster, binds only 127.0.0.1 on a temporary port, clears ambient PG
   connection settings, runs checks, stops the process and removes the cluster.
   Local package/cache artifacts are ignored, not shipped. Docker was not
   available, so PostgreSQL 17 packages were downloaded/unpacked **under
   `scripts/inbox/.local-postgres/` only**; no global installation/config change.

## Rollout status (2026-10-10)

- **Backend is live.** `20261010120000_editorial_inbox.sql` was applied to the
  production project (`oelbsuggrzyqwzmvidju`) on 2026-10-10 and recorded in
  `supabase_migrations.schema_migrations`. Do not re-run it: every statement is
  a plain `create`, so a second run fails and rolls back. Before applying, the
  SQL contract suite passed locally (`python3 scripts/inbox/run_sql_tests.py`:
  82 checks plus 4 concurrency checks).
- **Publishing is done from the admin console**, not the local script:
  `chessever.com/admin/dashboard/inbox` (web repo). It calls the two
  service-role RPCs, shows the message as the app renders it, and requires a
  confirm. The script below still refuses any non-loopback target.
- **Push is optional and off by default.** When the admin ticks it, the console
  queues one `notification_outbox` row (`event_type = 'call_to_action'`,
  `dedupe_key = 'editorial_inbox:<id>'`, `payload.data.inbox_message_id`), which
  the existing dispatcher sends to users with `push_enabled` and
  `call_to_action_alerts`. Tapping it opens the Inbox (app 36.0.2 and later).
- **The app side ships in 36.0.2.** Its drawer row stays hidden until the
  backend answers, so older and newer builds are both safe.
- No message has been published yet. The sections below are kept as the
  original pre-rollout record.

## Approval-gated future rollout (historical; see status above)

### Implemented phone integration

- Inbox is immediately above Board in the shared drawer; Feedback is unchanged.
- Cyan in-app dots appear on the profile/avatar affordance, Inbox and unread rows.
  Drawer/list opening never marks read. The exact detail renders full plain text,
  title/date before requesting its own read receipt. No replies, CTAs or links.
- The existing Riverpod auth identity includes anonymous-auth guests. Changing
  identity recreates the controller; detail routes refuse a different owner.
  Requests pin the originating JWT and reject results after account changes.
- Existing SQLite cache uses auth UUID plus flavor-specific keys and an owner
  envelope. Server-confirmed reads survive restart; failed reads stay unread.
  Failed/partial fetches retain saved rows and dots. Cache failures are visible,
  without blocking server content/read persistence. No shared signed-out cache.
- Startup, the existing app-resume signal, list entry, pull-to-refresh and a
  five-minute foreground timer sync messages/reads. Pagination has no total cap.
  No new push permission prompt, native badge write or notification SDK change.
- A narrow existing SQLite initialization fix observes the shared completer's
  error, preventing an already-handled cache failure from also escaping unhandled.

### User-owned device checklist (not executed)

- On an explicitly approved test backend, create two labeled fixture messages
  using separate draft/save/preview/publish; confirm UUID/full copy/audience first.
- Check guest and registered accounts with OS push enabled and disabled. Expect
  Inbox access in both, no permission nag and unchanged game/event pushes/badges.
- Confirm Inbox above Board, Feedback unchanged, avatar/drawer/row dots present.
  Drawer/list opening must leave both unread. Open one exact full text: only its
  row clears; the other and shared dots remain. Open the last: shared dots clear.
- Restart offline after confirmed reads, switch A→B→A, and switch while a detail,
  fetch or mark is pending. No cross-user rows/read flags/old detail body.
- Simulate fetch/mark/storage failure: saved content/dots remain, errors/retry
  work, successful server sync reconciles unknown-outcome marks. Recheck resume,
  manual refresh and another device's confirmed read.
- Check dark/light, small phone, large text, screen reader labels, back navigation,
  long plain text and strings resembling HTML/links. Nothing executes or navigates.

### Exact activation gates

1. Obtain explicit approval for the exact test Supabase project and migration
   operation. Apply this additive migration there and verify current policies,
   grants, anonymous-auth UUID behavior and actual PostgREST representations.
2. Run session/guest/API integration against that approved test backend and
   device verification through the user. Do not substitute this local bootstrap
   or mock for deployed authentication/permissions or device proof.
3. A separate reviewed tooling change and explicit authorization are required
   before enabling **any remote endpoint**; the current tool refuses even a
   remote test backend. Bind the target/credential deliberately and preserve
   no-send previews, separate publication, snapshot checks and exact-ID readback.
4. Reconfirm the displayed full copy, exact UUID, audience (everyone including
   guests), and **Inbox-only/no push** publication authority before any real
   publish. Production migration/deployment/publication requires its own explicit
   approval and current-target verification; no authorization carries forward.
