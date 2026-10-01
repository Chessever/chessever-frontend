-- Optional bounded backfill transport. Every item uses the existing exact-PGN
-- writer, including its result binding and trigger rollback guard.
create or replace function public.store_report_game_classifications(p_items jsonb)
returns jsonb
language plpgsql security invoker
set search_path = ''
set lock_timeout = '2s'
as $$
declare
  item jsonb;
  outcomes jsonb := '[]'::jsonb;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'classification batch must be an array';
  end if;
  if jsonb_array_length(p_items) > 100 or octet_length(p_items::text) > 16777216 then
    raise exception 'classification batch is too large';
  end if;
  -- Consistent row-lock order when separate backfills overlap.
  for item in select value from jsonb_array_elements(p_items)
    order by value->>'p_game_id' loop
    outcomes := outcomes || jsonb_build_array(public.store_report_game_classification(
      item->>'p_game_id', item->>'p_expected_pgn', item->'p_classification'));
  end loop;
  return outcomes;
end;
$$;
revoke all on function public.store_report_game_classifications(jsonb)
  from public, anon, authenticated;
grant execute on function public.store_report_game_classifications(jsonb) to service_role;
notify pgrst, 'reload schema';
