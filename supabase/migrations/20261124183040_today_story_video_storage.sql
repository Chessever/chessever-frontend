begin;

-- Uploads use signed, single-object URLs issued by the admin worker. The
-- generated object path can be read by the native players and browser CDNs.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('today-story-video', 'today-story-video', true, 31457280, array['video/mp4'])
on conflict (id) do nothing;

commit;
