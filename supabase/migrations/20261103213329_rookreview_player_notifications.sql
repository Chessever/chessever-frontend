-- Prospective only: installation does not enable AI processing or notifications.
begin;
create table public.partner_news_notification_policy (
 source_id text primary key references public.partner_news_sources(id),
 enabled boolean not null default false,
 activated_at timestamptz,
 check (not enabled or activated_at is not null)
);
insert into public.partner_news_notification_policy(source_id) values ('rookreview');
alter table public.partner_news_notification_policy enable row level security;
revoke all on public.partner_news_notification_policy from public,anon,authenticated;
grant select,update on public.partner_news_notification_policy to service_role;

-- Serialize activation and admission, including imports already in flight.
create function public.partner_news_notification_boundary() returns trigger
language plpgsql set search_path='' as $$
begin
 if new.enabled is distinct from old.enabled or new.activated_at is distinct from old.activated_at then
  if current_setting('transaction_isolation') <> 'read committed' then
   raise exception 'Partner activation requires READ COMMITTED' using errcode='25001';
  end if;
  new.activated_at := clock_timestamp();
 end if;
 return new;
end $$;
create trigger partner_news_notification_boundary before update on public.partner_news_notification_policy
 for each row execute function public.partner_news_notification_boundary();

create table public.partner_news_notification_jobs (
 article_id bigint primary key references public.partner_news(id) on delete cascade,
 source_id text not null check(source_id='rookreview'),
 article_url text not null,
 unique(source_id,article_url),
 content_hash text not null,
 published_at timestamptz not null,
 activated_at timestamptz not null,
 expires_at timestamptz not null,
 state text not null default 'pending' check(state in ('pending','processing','done','skipped')),
 attempts int not null default 0,
 lease uuid, leased_until timestamptz,
 subjects jsonb not null default '[]',
 model text,
 last_error text,
 created_at timestamptz not null default now()
);
alter table public.partner_news_notification_jobs enable row level security;
revoke all on public.partner_news_notification_jobs from public,anon,authenticated;
grant select on public.partner_news_notification_jobs to service_role;
create index partner_news_notification_pending on public.partner_news_notification_jobs(created_at)
 where state in ('pending','processing');

create table public.partner_player_news_publications (
 article_id bigint primary key references public.partner_news(id) on delete cascade,
 source_id text not null check(source_id='rookreview'),
 fide_ids text[] not null check(cardinality(fide_ids)>0),
 subjects jsonb not null,
 -- Frozen original import material. Edits revoke queued eligibility, never re-alert.
 content_hash text not null,
 published_at timestamptz not null,
 expires_at timestamptz not null,
 activated_at timestamptz not null,
 created_at timestamptz not null default now()
);
alter table public.partner_player_news_publications enable row level security;
revoke all on public.partner_player_news_publications from public,anon,authenticated;
grant select on public.partner_player_news_publications to service_role;

create index partner_news_notification_source_url on public.partner_news(source_id,url);

create function public.admit_partner_news_notification() returns trigger
language plpgsql security definer set search_path='' as $$
declare policy public.partner_news_notification_policy;
begin
 select * into policy from public.partner_news_notification_policy where source_id=new.source_id for share;
 if found and policy.enabled and new.status='published'
  and new.published_at>=policy.activated_at and new.published_at<=clock_timestamp()
  and new.published_at>=clock_timestamp()-interval '30 minutes'
  and not exists(select 1 from public.partner_news prior where prior.source_id=new.source_id
   and prior.url=new.url and prior.id<>new.id)
  and exists(select 1 from public.partner_news_sources s where s.id=new.source_id and s.enabled) then
  insert into public.partner_news_notification_jobs(article_id,source_id,article_url,content_hash,published_at,activated_at,expires_at)
   values(new.id,new.source_id,new.url,new.content_hash,new.published_at,policy.activated_at,new.published_at+interval '30 minutes')
   on conflict do nothing;
 end if;
 return new;
end $$;
create trigger admit_partner_news_notification after insert on public.partner_news
 for each row execute function public.admit_partner_news_notification();

create function public.claim_partner_news_notifications(p_limit int default 3)
returns table(article_id bigint,lease uuid,title text,summary text,content text)
language plpgsql security definer set search_path='' as $$
begin
 update public.partner_news_notification_jobs j set state='skipped',lease=null,leased_until=null
 where j.state in ('pending','processing') and (j.expires_at<=now() or j.attempts>=3
  and coalesce(j.leased_until,'-infinity')<=now());
 return query with due as (
  select j.article_id from public.partner_news_notification_jobs j
  join public.partner_news a on a.id=j.article_id
  join public.partner_news_notification_policy p on p.source_id=j.source_id
  join public.partner_news_sources s on s.id=j.source_id
  where j.state in ('pending','processing') and coalesce(j.leased_until,'-infinity')<=now()
   and j.attempts<3 and j.expires_at>now() and p.enabled and s.enabled
   and p.activated_at=j.activated_at and a.status='published'
   and a.content_hash=j.content_hash and a.published_at=j.published_at
  order by j.created_at limit greatest(1,least(coalesce(p_limit,3),3)) for update of j skip locked
 ), claimed as (
  update public.partner_news_notification_jobs j set state='processing',attempts=j.attempts+1,
   lease=gen_random_uuid(),leased_until=now()+interval '3 minutes',last_error=null
  from due where j.article_id=due.article_id returning j.article_id,j.lease
 ) select c.article_id,c.lease,a.title,a.summary,a.content from claimed c join public.partner_news a on a.id=c.article_id;
end $$;

-- The model returns names/evidence, never authoritative FIDE IDs. Exact complete
-- name-token equality is required, with a unique directory row; aliases expanded
-- by the model still need a verbatim mention and evidence in source text.
create function public.partner_news_player_name_key(p_name text)
returns text[] language sql immutable set search_path='' as $$
 select array(select v from unnest(regexp_split_to_array(lower(btrim(regexp_replace(p_name,'[^[:alnum:]]+',' ','g'))),'\s+')) v order by v)
$$;
-- Expression index prevents a full player-directory scan for each AI candidate.
create index chess_players_partner_news_name on public.chess_players(public.partner_news_player_name_key(name));
create function public.resolve_partner_news_player(p_name text)
returns table(fide_id text,name text) language sql stable security definer set search_path='' as $$
 select cp.fideid::text,btrim(regexp_replace(cp.name,'^([^,]+),\s*(.+)$',E'\\2 \\1')) from public.chess_players cp
 where length(p_name) between 3 and 120 and cp.fideid>0
  and public.partner_news_player_name_key(cp.name)=public.partner_news_player_name_key(p_name)
 limit 2
$$;

create function public.complete_partner_news_notification(p_article_id bigint,p_lease uuid,p_subjects jsonb,p_model text,p_error text default null)
returns boolean language plpgsql security definer set search_path='' as $$
declare j public.partner_news_notification_jobs; a public.partner_news; s jsonb; ids text[]:='{}'; source_text text;
begin
 -- Policy first: same lock order as activation/admission, and held until commit.
 perform 1 from public.partner_news_notification_policy where source_id='rookreview' for share;
 select * into j from public.partner_news_notification_jobs where article_id=p_article_id for update;
 if not found or j.state<>'processing' or j.lease is distinct from p_lease or j.leased_until<=now() then return false; end if;
 if p_error is not null then
  update public.partner_news_notification_jobs set state=case when attempts<3 and expires_at>now() then 'pending' else 'skipped' end,
   lease=null,leased_until=null,last_error=left(p_error,160) where article_id=p_article_id;
  return false;
 end if;
 select * into a from public.partner_news where id=p_article_id for share;
 if a.status<>'published' or a.content_hash<>j.content_hash or a.published_at<>j.published_at or j.expires_at<=now()
  or not exists(select 1 from public.partner_news_notification_policy p join public.partner_news_sources src on src.id=p.source_id
   where p.source_id=j.source_id and p.enabled and src.enabled and p.activated_at=j.activated_at) then
  update public.partner_news_notification_jobs set state='skipped',lease=null,leased_until=null where article_id=p_article_id;
  return false;
 end if;
 if jsonb_typeof(p_subjects) is distinct from 'array' or jsonb_array_length(p_subjects)>5 or nullif(btrim(p_model),'') is null then
  raise exception 'Invalid partner subjects';
 end if;
 source_text:=a.title||E'\n'||a.summary||E'\n'||a.content;
 for s in select value from jsonb_array_elements(p_subjects) loop
  if s->>'role' is null or s->>'role' not in ('subject','quotation')
   or coalesce(s->>'fide_id','') !~ '^[1-9][0-9]{0,14}$' or s->>'fide_id'=any(ids)
   or length(coalesce(s->>'mention','')) not between 2 and 120
   or length(coalesce(s->>'evidence','')) not between 12 and 1000
   or position(s->>'mention' in s->>'evidence')=0 or position(s->>'evidence' in source_text)=0
   or (select count(*) from public.resolve_partner_news_player(s->>'name') cp where cp.fide_id=s->>'fide_id' and cp.name=s->>'name')<>1
   or (select count(*) from public.resolve_partner_news_player(s->>'name'))<>1 then
   raise exception 'Unverified partner player identity or evidence';
  end if;
  ids:=array_append(ids,s->>'fide_id');
 end loop;
 update public.partner_news_notification_jobs set state='done',subjects=p_subjects,model=p_model,lease=null,leased_until=null
  where article_id=p_article_id;
 if cardinality(ids)>0 then
  insert into public.partner_player_news_publications(article_id,source_id,fide_ids,subjects,content_hash,published_at,expires_at,activated_at)
   values(a.id,a.source_id,ids,p_subjects,a.content_hash,j.published_at,j.expires_at,j.activated_at) on conflict do nothing;
 end if;
 return true;
end $$;
revoke all on function public.partner_news_notification_boundary(),public.admit_partner_news_notification(),
 public.partner_news_player_name_key(text),public.claim_partner_news_notifications(int),public.resolve_partner_news_player(text),
 public.complete_partner_news_notification(bigint,uuid,jsonb,text,text) from public,anon,authenticated;
grant execute on function public.partner_news_player_name_key(text),public.claim_partner_news_notifications(int),public.resolve_partner_news_player(text),
 public.complete_partner_news_notification(bigint,uuid,jsonb,text,text) to service_role;
commit;
