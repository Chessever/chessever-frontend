-- Force Engine Experience "Thinking Time" to 5 seconds for every user.
-- The Flutter client maps search_time_index = 0 to the "5s" option.

alter table public.user_engine_settings
  alter column search_time_index set default 0;

update public.user_engine_settings
set search_time_index = 0
where search_time_index is distinct from 0;

create or replace function public.force_engine_thinking_time_5s()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.search_time_index := 0;
  return new;
end;
$$;

drop trigger if exists force_engine_thinking_time_5s
  on public.user_engine_settings;

create trigger force_engine_thinking_time_5s
before insert or update on public.user_engine_settings
for each row
execute function public.force_engine_thinking_time_5s();

comment on function public.force_engine_thinking_time_5s()
  is 'Forces user_engine_settings.search_time_index to 0, the 5 second Thinking Time option.';
