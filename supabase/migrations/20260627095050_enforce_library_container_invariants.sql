-- Enforce the split library node model:
--   * folder   nodes can contain child folders and databases, but no games
--   * database nodes can contain games, but no child nodes
--
-- This is additive/non-destructive. Existing mixed database nodes are promoted
-- to folders and their direct games are moved into a newly-created child
-- database, preserving all saved games and child nodes.

begin;

do $$
declare
  mixed record;
  new_database_id uuid;
  candidate text;
  n int;
begin
  for mixed in
    select f.*
    from public.user_folders f
    where f.node_type = 'database'
      and exists (
        select 1 from public.user_folders child where child.parent_id = f.id
      )
      and exists (
        select 1 from public.user_saved_analyses a where a.folder_id = f.id
      )
  loop
    candidate := mixed.name || ' Games';
    n := 0;

    while exists (
      select 1
      from public.user_folders
      where user_id = mixed.user_id and name = candidate
    ) loop
      n := n + 1;
      candidate := mixed.name || ' Games ' || n;
    end loop;

    insert into public.user_folders (
      user_id,
      name,
      color,
      icon,
      order_index,
      parent_id,
      node_type
    ) values (
      mixed.user_id,
      candidate,
      mixed.color,
      'database',
      mixed.order_index,
      mixed.id,
      'database'
    )
    returning id into new_database_id;

    update public.user_saved_analyses
    set folder_id = new_database_id
    where folder_id = mixed.id;

    update public.user_folders
    set node_type = 'folder',
        icon = case
          when coalesce(icon, '') = '' or icon = 'database' then 'folder'
          else icon
        end,
        updated_at = now()
    where id = mixed.id;
  end loop;
end $$;

-- Keep the previous backwards-compatible auto-heal for empty legacy database
-- parents: if a node has children and no direct games, it is a folder.
update public.user_folders p
set node_type = 'folder',
    icon = case
      when coalesce(icon, '') = '' or icon = 'database' then 'folder'
      else icon
    end,
    updated_at = now()
where p.node_type = 'database'
  and exists (select 1 from public.user_folders c where c.parent_id = p.id)
  and not exists (
    select 1 from public.user_saved_analyses g where g.folder_id = p.id
  );

create or replace function public.ensure_parent_node_is_folder()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  parent record;
begin
  if new.parent_id is null then
    return new;
  end if;

  if new.parent_id = new.id then
    raise exception 'A library node cannot be its own parent'
      using errcode = '23514';
  end if;

  select id, node_type
    into parent
  from public.user_folders
  where id = new.parent_id;

  if parent.id is null or parent.node_type = 'folder' then
    return new;
  end if;

  -- Old app builds can still create database -> child database. If the parent
  -- is empty, promote it to a folder so the child stays reachable.
  if not exists (
    select 1 from public.user_saved_analyses g where g.folder_id = parent.id
  ) then
    update public.user_folders
    set node_type = 'folder',
        icon = case
          when coalesce(icon, '') = '' or icon = 'database' then 'folder'
          else icon
        end,
        updated_at = now()
    where id = parent.id;

    return new;
  end if;

  raise exception 'Databases can only contain games; create child nodes under a folder'
    using errcode = '23514';
end;
$function$;

drop trigger if exists ensure_parent_node_is_folder_trigger
  on public.user_folders;

create trigger ensure_parent_node_is_folder_trigger
before insert or update of parent_id on public.user_folders
for each row
execute function public.ensure_parent_node_is_folder();

commit;
