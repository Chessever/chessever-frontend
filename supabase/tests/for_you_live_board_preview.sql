-- Exercise the deployed RPC against isolated fixtures. Every table and the
-- function clone lives in pg_temp; no production rows or definitions change.
begin;
create temp table group_broadcasts on commit drop as select * from public.group_broadcasts where false;
create temp table tours on commit drop as select * from public.tours where false;
create temp table rounds on commit drop as select * from public.rounds where false;
create temp table games on commit drop as select * from public.games where false;

do $clone$
begin
  execute replace(pg_get_functiondef('public.get_for_you_top_games(text[],integer)'::regprocedure), 'public.', 'pg_temp.');
end;
$clone$;

insert into pg_temp.group_broadcasts(id, name) values
  ('preview-match', 'Match play'), ('preview-ordinary', 'Ordinary'),
  ('preview-ended', 'Finished'), ('preview-categories', 'Categories');
insert into pg_temp.tours(id, group_broadcast_id, name, avg_elo) values
  ('match', 'preview-match', 'Knockout', 2700),
  ('ordinary', 'preview-ordinary', 'Swiss', 2600),
  ('ended', 'preview-ended', 'Finished', 2500),
  ('strong', 'preview-categories', 'Open', 2800),
  ('weak', 'preview-categories', 'Challengers', 2400);
insert into pg_temp.rounds(id, tour_id, name, starts_at) select
  'round-' || id, id, 'Round 1', now() - interval '2 hours' from pg_temp.tours;

-- A match whose active game is beyond every possible home-preview limit.
insert into pg_temp.games(id, tour_id, round_id, board_nr, status, last_move, last_move_time, game_day, fen, players, is_mirror)
select 'finished-' || n, 'match', 'round-match', n, '1/2-1/2', 'e2e4',
  now() - interval '30 minutes', current_date, 'played',
  '[{"name":"Nakamura"},{"name":"Erdogmus"}]'::jsonb, false
from generate_series(1,20) as n;
insert into pg_temp.games(id, tour_id, round_id, board_nr, status, last_move, last_move_time, game_day, fen, players, is_mirror) values
  ('live-late', 'match', 'round-match', 27, '*', 'e2e4', now(), current_date, 'played', '[{"name":"Nakamura"},{"name":"Erdogmus"}]', false),
  ('live-earlier', 'match', 'round-match', 26, '*', 'e7e5', now() - interval '1 minute', current_date, 'played', '[{"name":"Nakamura"},{"name":"Erdogmus"}]', false),
  ('shell', 'match', 'round-match', 0, '*', null, null, current_date, 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', '[{"name":"Carlsen"},{"name":"Movahed"}]', false),
  ('mirror', 'match', 'round-match', 0, '*', 'e2e4', now(), current_date, 'played', '[{"name":"Nakamura"},{"name":"Erdogmus"}]', true),
  ('unknown', 'match', 'round-match', 0, '*', 'e2e4', now(), current_date, 'played', '[{"name":"TBD"},{"name":"Opponent"}]', false),
  ('ordinary-finished', 'ordinary', 'round-ordinary', 1, '1-0', 'e2e4', now(), current_date, 'played', '[{"name":"A"},{"name":"B"}]', false),
  ('ordinary-live', 'ordinary', 'round-ordinary', 10, 'ongoing', 'e2e4', now(), current_date, 'played', '[{"name":"C"},{"name":"D"}]', false),
  ('stale', 'ordinary', 'round-ordinary', 2, '*', 'e2e4', now() - interval '3 hours', current_date, 'played', '[{"name":"E"},{"name":"F"}]', false),
  ('future-time', 'ordinary', 'round-ordinary', 3, '*', 'e2e4', now() + interval '10 minutes', current_date, 'played', '[{"name":"G"},{"name":"H"}]', false),
  ('ended-first', 'ended', 'round-ended', 1, '1-0', 'e2e4', now() - interval '1 hour', current_date, 'played', '[{"name":"A"},{"name":"B"}]', false),
  ('ended-second', 'ended', 'round-ended', 2, '0-1', 'e2e4', now(), current_date, 'played', '[{"name":"C"},{"name":"D"}]', false),
  ('strong-finished', 'strong', 'round-strong', 1, '1-0', 'e2e4', now(), current_date, 'played', '[{"name":"A"},{"name":"B"}]', false),
  ('weak-live', 'weak', 'round-weak', 1, '*', 'e2e4', now(), current_date, 'played', '[{"name":"C"},{"name":"D"}]', false);

do $checks$
declare chosen text[]; preview_limit integer;
begin
  foreach preview_limit in array array[1,4,5,12] loop
    select array_agg(id order by ordinality) into chosen
    from pg_temp.get_for_you_top_games(array['preview-match'], preview_limit) with ordinality as g;
    if chosen[1] is distinct from 'live-earlier' then
      raise exception 'Live game outside the first boards is absent from limit %: %', preview_limit, chosen;
    end if;
    if preview_limit > 1 and chosen[2] is distinct from 'live-late' then
      raise exception 'Live boards must keep board order: %', chosen;
    end if;
    if chosen && array['shell','mirror','unknown'] then
      raise exception 'Shell, mirror or unnamed board leaked into preview: %', chosen;
    end if;
  end loop;

  select array_agg(id order by ordinality) into chosen
  from pg_temp.get_for_you_top_games(array['preview-ordinary'], 4) with ordinality as g;
  if chosen is distinct from array['ordinary-live','ordinary-finished','stale','future-time'] then
    raise exception 'Ordinary live game or stale/future activity order changed: %', chosen;
  end if;
  select array_agg(id order by ordinality) into chosen
  from pg_temp.get_for_you_top_games(array['preview-ended'], 4) with ordinality as g;
  if chosen is distinct from array['ended-first','ended-second'] then
    raise exception 'Finished-event board order changed: %', chosen;
  end if;
  select array_agg(id order by ordinality) into chosen
  from pg_temp.get_for_you_top_games(array['preview-categories'], 4) with ordinality as g;
  if chosen is distinct from array['strong-finished'] then
    raise exception 'Preview mixed categories or changed category priority: %', chosen;
  end if;
end;
$checks$;
rollback;
