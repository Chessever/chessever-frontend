-- Per-tour corrections to tours.info that survive every feed sync.
--
-- The data hub rewrites tours.info from Lichess on each tour sync, so a manual
-- UPDATE lasts only until the next one. A row here is merged over whatever any
-- writer sends, on insert and on update, by a BEFORE trigger that runs after
-- tours_normalize_info_text (BEFORE triggers fire in name order).
--
-- First use (2026-11-11): Total Chess World Championship Tour Pilot 2026,
-- "Group Stage | Combined" (wLrwkC0C). The organizer publishes it on Lichess
-- with teamTable=true and tags every player with their own group as a "team",
-- so each board reads "Group A vs Group A". Both apps trust teamTable first:
-- the web wall grouped zero team matches and showed an empty live round, and
-- the phone opened the team layout. The data hub also appends "(team)" to the
-- format, so the format must be restored too, not only the flag.

create table if not exists broadcasting_private.tour_info_overrides (
  tour_id text primary key references public.tours(id) on delete cascade,
  info_patch jsonb not null check (jsonb_typeof(info_patch) = 'object'),
  reason text not null,
  created_at timestamptz not null default now()
);

revoke all on broadcasting_private.tour_info_overrides from public, anon, authenticated;

create or replace function public.tours_apply_info_override()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
declare
  patch jsonb;
begin
  select o.info_patch into patch
  from broadcasting_private.tour_info_overrides o
  where o.tour_id = new.id;

  if patch is not null then
    new.info := coalesce(new.info, '{}'::jsonb) || patch;
  end if;
  return new;
end;
$$;

revoke execute on function public.tours_apply_info_override() from public, anon, authenticated;

drop trigger if exists tours_zz_apply_info_override on public.tours;
create trigger tours_zz_apply_info_override
before insert or update on public.tours
for each row execute function public.tours_apply_info_override();

-- Later the same day the Combined tour was omitted from the data hub
-- (omitted_events id 180) and deleted, which cascades this row away; the
-- guard keeps a replay from failing on the foreign key.
insert into broadcasting_private.tour_info_overrides (tour_id, info_patch, reason)
select
  'wLrwkC0C',
  '{"teamTable": false, "format": "6-player double round-robin"}'::jsonb,
  'Total Chess Combined mirrors Group Stage A-D; the Lichess team flag and group-as-team tags are not a team event.'
where exists (select 1 from public.tours where id = 'wLrwkC0C')
on conflict (tour_id) do update
  set info_patch = excluded.info_patch, reason = excluded.reason;

-- Apply it now; the trigger rewrites info on this touch.
update public.tours set info = info where id = 'wLrwkC0C';
