-- Prevent regular Supabase API roles from deleting/truncating exposed cache and
-- support tables. RLS is enabled and intentionally has no DELETE policies.

do $$
declare
  tbl text;
  pol record;
begin
  foreach tbl in array array[
    'positions',
    'evals',
    'pvs',
    'lichess_move_annotations_cache',
    'round_name_overrides',
    'user_notification_sends'
  ] loop
    execute format('alter table public.%I enable row level security', tbl);

    for pol in
      select policyname
      from pg_policies
      where schemaname = 'public'
        and tablename = tbl
        and cmd in ('DELETE', 'ALL')
    loop
      execute format('drop policy %I on public.%I', pol.policyname, tbl);
    end loop;
  end loop;

  foreach tbl in array array[
    'positions',
    'evals',
    'pvs',
    'lichess_move_annotations_cache'
  ] loop
    execute format(
      'drop policy if exists %I on public.%I',
      'regular_users_read_' || tbl,
      tbl
    );
    execute format(
      'create policy %I on public.%I for select to anon, authenticated using (true)',
      'regular_users_read_' || tbl,
      tbl
    );

    execute format(
      'drop policy if exists %I on public.%I',
      'regular_users_insert_' || tbl,
      tbl
    );
    execute format(
      'create policy %I on public.%I for insert to anon, authenticated with check (true)',
      'regular_users_insert_' || tbl,
      tbl
    );

    execute format(
      'drop policy if exists %I on public.%I',
      'regular_users_update_' || tbl,
      tbl
    );
    execute format(
      'create policy %I on public.%I for update to anon, authenticated using (true) with check (true)',
      'regular_users_update_' || tbl,
      tbl
    );
  end loop;

  execute 'drop policy if exists regular_users_read_round_name_overrides on public.round_name_overrides';
  execute 'create policy regular_users_read_round_name_overrides on public.round_name_overrides for select to anon, authenticated using (true)';
end $$;

revoke delete, truncate on table
  public.positions,
  public.evals,
  public.pvs,
  public.lichess_move_annotations_cache,
  public.round_name_overrides,
  public.user_notification_sends
from anon, authenticated;

revoke delete, truncate on table
  public.positions,
  public.evals,
  public.pvs,
  public.lichess_move_annotations_cache,
  public.round_name_overrides,
  public.user_notification_sends
from public;
