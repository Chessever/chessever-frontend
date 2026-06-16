-- New user settings should enable Picture-in-Picture for live games by default.
-- Do not update existing pip_mode=0 rows here: existing data cannot distinguish
-- users who explicitly turned PiP off from rows created by the old default.
alter table public.user_engine_settings
  alter column pip_mode set default 1;

update public.user_engine_settings
set pip_mode = 1
where pip_mode is null;
