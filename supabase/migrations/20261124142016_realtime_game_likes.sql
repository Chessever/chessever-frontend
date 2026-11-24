-- The saved analysis in My Likes remains the source of truth. Existing
-- builds can still read/write it directly and use game_like_count unchanged.
create function public.game_like_summary(p_source_game_id text)
returns jsonb
language sql stable security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'count', count(distinct l.user_id),
    'liked', coalesce(bool_or(l.user_id = (select auth.uid())), false)
  )
  from rewarded_private.game_likes l
  where l.source_game_id = btrim(p_source_game_id);
$$;

revoke all on function public.game_like_summary(text) from public;
grant execute on function public.game_like_summary(text) to anon, authenticated;

-- A desired state, so retrying a like cannot undo it. Serialize updated
-- clients' writes for this account/game, retaining an existing analysis and
-- its tags, date and notes. An explicit unlike removes every copy of that
-- source in My Likes only, including pre-existing duplicate likes.
create function public.write_game_like(p_source_game_id text, p_folder_id uuid, p_like jsonb default null)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_id text := btrim(p_source_game_id);
  v_folder uuid;
  v_row public.user_saved_analyses;
begin
  if v_user is null or v_id is null or v_id = '' then
    raise exception 'A signed-in account and source game are required' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('game-like:' || v_user || ':' || v_id, 0));
  select id into v_folder from public.user_folders
    where user_id = v_user and is_liked_games;

  if v_folder is not null and p_folder_id is distinct from v_folder then
    raise exception 'My Likes folder does not belong to this account' using errcode = '42501';
  end if;

  if p_like is null then
    delete from public.user_saved_analyses
      where user_id = v_user and folder_id = v_folder and source_game_id = v_id;
    return null;
  end if;

  if v_folder is null then
    raise exception 'My Likes folder does not belong to this account' using errcode = '42501';
  end if;

  select * into v_row from public.user_saved_analyses
    where user_id = v_user and folder_id = v_folder and source_game_id = v_id
    order by created_at desc, id desc limit 1;
  if found then return to_jsonb(v_row); end if;

  insert into public.user_saved_analyses (
    user_id, folder_id, source_game_id, source_tournament_id, title, chess_game
  ) values (
    v_user, v_folder, v_id, p_like->>'source_tournament_id', p_like->>'title', p_like->'chess_game'
  ) returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

revoke all on function public.write_game_like(text, uuid, jsonb) from public, anon;
grant execute on function public.write_game_like(text, uuid, jsonb) to authenticated;

create policy "Receive own account like changes"
on realtime.messages for select to authenticated
using (
  extension = 'broadcast'
  and topic = (select realtime.topic())
  and topic = 'account-likes:' || (select auth.uid())::text
);

-- Messages only invalidate a read. No row, PGN or believing a client-supplied
-- count, and no account identity in the public per-game message.
create function rewarded_private.notify_game_like_change(p_id text, p_user uuid)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if p_id is null or btrim(p_id) = '' then return; end if;
  perform realtime.send('{}'::jsonb, 'changed', 'game-likes:' || p_id, false);
  perform realtime.send('{}'::jsonb, 'changed', 'account-likes:' || p_user, true);
end;
$$;

create function rewarded_private.notify_saved_like_change()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and
     (old.user_id, old.folder_id, old.source_game_id) is not distinct from
     (new.user_id, new.folder_id, new.source_game_id) then
    return null;
  end if;

  if tg_op <> 'INSERT' and old.source_game_id is not null and exists (
    select 1 from public.user_folders f
    where f.id = old.folder_id and f.user_id = old.user_id and f.is_liked_games
  ) then
    perform rewarded_private.notify_game_like_change(old.source_game_id, old.user_id);
  end if;
  if tg_op <> 'DELETE' and new.source_game_id is not null and exists (
    select 1 from public.user_folders f
    where f.id = new.folder_id and f.user_id = new.user_id and f.is_liked_games
  ) then
    perform rewarded_private.notify_game_like_change(new.source_game_id, new.user_id);
  end if;
  return null;
end;
$$;

create trigger notify_saved_like_change
after insert or delete or update of user_id, folder_id, source_game_id
on public.user_saved_analyses
for each row execute function rewarded_private.notify_saved_like_change();

-- The folder must still be visible for a cascading delete to be signalled.
create function rewarded_private.notify_likes_folder_change()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
declare v_id text;
begin
  if (tg_op = 'DELETE' and old.is_liked_games)
    or (tg_op = 'UPDATE' and old.is_liked_games is distinct from new.is_liked_games) then
    for v_id in select distinct a.source_game_id from public.user_saved_analyses a
      where a.folder_id = old.id and a.user_id = old.user_id and a.source_game_id is not null
    loop
      perform realtime.send('{}'::jsonb, 'changed', 'game-likes:' || v_id, false);
    end loop;
    perform realtime.send('{}'::jsonb, 'changed', 'account-likes:' || old.user_id, true);
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create trigger notify_likes_folder_change
before delete or update of is_liked_games on public.user_folders
for each row execute function rewarded_private.notify_likes_folder_change();

revoke all on function rewarded_private.notify_game_like_change(text, uuid) from public, anon, authenticated;
revoke all on function rewarded_private.notify_saved_like_change() from public, anon, authenticated;
revoke all on function rewarded_private.notify_likes_folder_change() from public, anon, authenticated;
