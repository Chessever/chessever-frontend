-- Collection stories (Settings › Customization › Collection stories, and the
-- pull past either end of Today's story row, which turns it Off) kept on the
-- server with the reader's other settings, so every device shows or hides
-- the row the same way.
--
-- Why user_engine_settings: it is the app's one per-user settings row (the
-- board, engine, PiP and Countrymen settings), unique per user_id, owner-only
-- RLS for select/insert/update/delete, created by the first settings upsert
-- on user_id. The column rides on that row, its policies and its grants. The
-- table is not in the realtime publication and no setting listens live; a
-- change made on another device applies at the next launch, sign-in or
-- account switch, as the other settings do.
--
-- 'on' or 'off'; null means the reader never chose on the server. The app
-- reads null as On. The first time it finds null for a signed-in reader it
-- writes the choice the reader already had (the auth user_metadata key
-- `today_stories_v1` that 39.1-39.2 wrote, or the device's copy, the newer of
-- the two), and from then on it never writes user_metadata. Guests
-- (anonymous sessions) keep the choice on the device.
--
-- Additive: one nullable column, no default, no backfill. Older builds never
-- read or write it (they keep the device copy and user_metadata), and the
-- board, engine and Countrymen upserts name their own columns, so they never
-- touch it. A build that ships before this migration finds the column
-- missing (PostgREST 42703 / PGRST204) and keeps the device copy and
-- user_metadata, with nothing shown to the reader.
--
-- Revert: no app needs the column to exist, so stop reading it in the app
-- and leave it in place (additive changes only; dropping it would lose the
-- readers' choices).

begin;

alter table public.user_engine_settings
  add column if not exists collection_stories text
    constraint user_engine_settings_collection_stories_check
    check (collection_stories in ('on', 'off'));

comment on column public.user_engine_settings.collection_stories is
  'Collection stories row on Today: on or off; null = never chosen (read as on). Written by the app on every change (Settings › Customization › Collection stories, and the row''s pull-away).';

commit;
