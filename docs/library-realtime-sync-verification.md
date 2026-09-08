# Library Realtime repair and mobile/desktop sync

Verified on 2026-09-08.

## Root cause and deployed repair

[Trello 1130](https://trello.com/c/uqJ2vxpu/1130-fix-phone-pgn-import-destination-loading-hermesvasif)
reported a phone PGN import destination failure. [Sentry CHESSEVER-1WJ](https://algorithm-squad-fze.sentry.io/issues/142847698/)
contained the server's rejected `public.user_folders` subscription message.
The Supabase Realtime server emits that message when the requested table has no
matching entry in its publication. Both live environments were missing it.

The additional cross-device audit found the same omission for
`public.user_saved_analyses`, the shared cloud PGN storage used by both apps.

| Environment | Project | Folder migration | Saved-PGN migration |
| --- | --- | --- | --- |
| Production | `oelbsuggrzyqwzmvidju` | `20260908100908` | `20260908101932` |
| Test | `odmekzlfunfocvedqusl` | `20260908100810` | `20260908101336` |

Each deployed migration only adds its existing table to `supabase_realtime` if
missing. A three-second lock timeout aborts rather than waiting behind another
transaction. Local files in `supabase/migrations` use the production history
versions; the Management API generated the test history versions independently.
Do not replay unrelated migrations or rewrite either environment's history to
make those generated timestamps match.

Before: `public.games`, `public.rounds`, `public.settings`.
After: those same entries plus `public.user_folders` and
`public.user_saved_analyses`.

Before/after catalog snapshots verified that all existing publication entries,
publication options, public-table RLS flags, privileges, policies, columns,
constraints, triggers and replica identities remained unchanged. No customer
rows were inserted, updated or deleted by deployment or live verification.

## Client changes

Both frontends use the same account-bound change notification and catch-up
logic. Cloud saves and updates trigger coalesced refreshes of visible Library
data. A 30-second catch-up interval covers missed notifications and deletions;
account changes and disposal cancel the old subscription and timers. Existing
repository reads continue to enforce ownership, pagination and filters.

- Phone: folder loading retains usable data during Realtime errors, falls back
  to one bounded HTTP read, and offers Retry after a genuine loading failure.
  Open book pages, tags and counts refresh after changes from another device.
  Refresh preserves loaded pages, handles server response caps, and rejects
  stale in-flight pagination results.
- Desktop (`chessever_frontend_desktop`): matching folder recovery and Retry;
  cloud database counts, preview, content view and open database workspace
  refresh from the shared account signal. Local-file save behavior is unchanged.

The client source changes are included in mobile `34.11.0+3422` and desktop
`20.29.0+343`. The database repair is already live and applies to existing clients'
relevant subscriptions. The additional client recovery/refresh behavior requires
distribution of these versions; committing and pushing source does not confirm
an app-store release or desktop binary publication.

## Verification

- Isolated PostgreSQL tests for both migrations: missing-table regression,
  idempotence, preservation of existing publication members/access controls,
  owner-only row visibility, and actual logical-replication INSERT output.
- Live read-only subscription probes: test failed with the matching server
  error before the folder repair, then received `postgres_changes` replication
  readiness afterward. Both tables now acknowledge readiness on test and
  production. Production probes also passed using desktop's older pinned SDK.
  A nonexistent account filter was used; no customer data was read or logged.
- Phone: 17 focused tests passed, covering PGN saving and Retry, HTTP/Realtime
  races, two clients receiving coalesced changes, account isolation, catch-up,
  disposal, pagination, filters and stale-response protection.
- Desktop: 29 focused tests passed, including matching sync/recovery tests and
  the existing cloud/local destination and saved-game metadata tests.
- Scoped `flutter analyze --no-pub` passed for every changed Dart file in both
  repositories. No app was launched, attached to, or built for runtime verification.

## Device check after client release

Use the same account and **the same Supabase environment** on phone and desktop.
Both repositories' `.env` files currently identify production; phone `.env.test`
identifies the separate test project. Matching email addresses across those two
projects do not create shared accounts or shared Library data.

1. Keep the cloud Library open on both devices. Create or rename a database on
   one device and check that the other device's destination list updates.
2. Import a small PGN on phone and save it to that cloud database. Check that
   desktop's open preview/workspace and count refresh. Repeat in reverse.
3. Save an edit from one device, then reopen that saved game on the other. Check
   the PGN and annotations. Live refresh does not overwrite an unsaved editor.
4. Disconnect and reconnect one device. Verify folder loading remains usable,
   Retry works when HTTP loading also fails, and saved changes catch up.
5. Delete a disposable saved game and allow the 30-second catch-up interval.
   Check both lists. Sign out or switch accounts and confirm the old account's
   pending folder load cannot populate the new account.
6. Confirm desktop's explicitly local-file destination still saves locally.
