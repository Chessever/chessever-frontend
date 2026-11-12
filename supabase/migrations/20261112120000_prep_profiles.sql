-- Prep profiles, synced between the reader's devices and apps.
--
-- A Prep profile (the mobile app's My Prep, the desktop app's Players
-- workspace) is kept on the device with its downloaded games. This table
-- holds what makes a profile, never its games: its name, whether it is the
-- reader's own, and the sources its games come from (Lichess, Chess.com and
-- ChessEver database players, with their download options). Each app
-- writes its profiles here and rebuilds the ones it lacks, then downloads
-- the games itself. Imported PGN files stay on the device that read them.
--
-- `profile` is one shared JSON shape (see `prep_cloud_sync.dart` in both
-- apps). A deleted profile keeps its row with `deleted_at` set, so the
-- other devices remove it instead of writing it back.
--
-- Additive: older apps never read or write this table.

create table if not exists public.prep_profiles (
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_id text not null
    check (char_length(profile_id) between 1 and 200),
  profile jsonb not null default '{}'::jsonb
    check (octet_length(profile::text) <= 65536),
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, profile_id)
);

alter table public.prep_profiles enable row level security;

drop policy if exists prep_profiles_owner_read on public.prep_profiles;
create policy prep_profiles_owner_read on public.prep_profiles
  for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists prep_profiles_owner_insert on public.prep_profiles;
create policy prep_profiles_owner_insert on public.prep_profiles
  for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists prep_profiles_owner_update on public.prep_profiles;
create policy prep_profiles_owner_update on public.prep_profiles
  for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists prep_profiles_owner_delete on public.prep_profiles;
create policy prep_profiles_owner_delete on public.prep_profiles
  for delete to authenticated
  using (auth.uid() = user_id);

revoke all on public.prep_profiles from anon;
grant select, insert, update, delete on public.prep_profiles to authenticated;
grant select, insert, update, delete on public.prep_profiles to service_role;

create or replace function public.prep_profiles_touch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists prep_profiles_touch on public.prep_profiles;
create trigger prep_profiles_touch
  before update on public.prep_profiles
  for each row execute function public.prep_profiles_touch();
