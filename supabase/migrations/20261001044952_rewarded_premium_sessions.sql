-- Production-only rewarded capability. Deploy separately after service integration.
-- No billing records or subscription predicates are modified.
create schema if not exists rewarded_private;
revoke all on schema rewarded_private from public, anon, authenticated;
grant usage on schema rewarded_private to authenticated, service_role;

create table rewarded_private.attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  session_hash text not null check (session_hash ~ '^[a-f0-9]{64}$'),
  ad_unit text not null,
  created_at timestamptz not null default now(),
  verified_at timestamptz,
  transaction_id text unique,
  expires_at timestamptz
);
create index rewarded_attempt_user_session on rewarded_private.attempts(user_id, session_hash, expires_at);
alter table rewarded_private.attempts enable row level security;
revoke all on rewarded_private.attempts from public, anon, authenticated;
grant select, insert, update, delete on rewarded_private.attempts to service_role;

-- This helper crosses RLS only to answer whether the caller owns an active
-- verified grant and possesses its process-local secret. No user-id argument.
create function rewarded_private.has_access(p_token text)
returns boolean language sql stable security definer
set search_path = '' as $$
  select auth.uid() is not null
    and p_token ~ '^[A-Za-z0-9_-]{43}$'
    and exists (
      select 1 from rewarded_private.attempts a
      where a.user_id = auth.uid()
        and a.session_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
        and a.verified_at is not null and a.expires_at > now()
    );
$$;
revoke all on function rewarded_private.has_access(text) from public, anon;
grant execute on function rewarded_private.has_access(text) to authenticated;

-- Backend services call with the USER bearer token, never a service-role JWT.
create function public.rewarded_premium_access(p_session_token text)
returns boolean language sql stable security invoker set search_path = '' as $$
  select coalesce(rewarded_private.has_access(p_session_token), false);
$$;
revoke all on function public.rewarded_premium_access(text) from public, anon;
grant execute on function public.rewarded_premium_access(text) to authenticated;

create function public.rewarded_prepare(p_user uuid, p_hash text, p_adunit text)
returns uuid language plpgsql security invoker set search_path = '' as $$
declare v_id uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_user::text, 0));
  if (select count(*) from rewarded_private.attempts
      where user_id = p_user and created_at > now() - interval '1 minute') >= 5 then
    raise exception 'rewarded_rate_limit';
  end if;
  insert into rewarded_private.attempts(user_id, session_hash, ad_unit)
    values(p_user, p_hash, p_adunit) returning id into v_id;
  return v_id;
end;
$$;

create function public.rewarded_verify(p_attempt uuid, p_user uuid,
    p_transaction text, p_adunit text)
returns boolean language plpgsql security invoker set search_path = '' as $$
declare a rewarded_private.attempts;
begin
  select * into a from rewarded_private.attempts where id = p_attempt for update;
  if not found or a.user_id <> p_user or a.ad_unit <> p_adunit
      or a.created_at < now() - interval '24 hours' then return false; end if;
  if a.transaction_id is not null then return a.transaction_id = p_transaction; end if;
  update rewarded_private.attempts set verified_at = now(),
    transaction_id = p_transaction where id = a.id;
  return true;
end;
$$;

create function public.rewarded_activate(p_attempt uuid, p_user uuid, p_hash text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare a rewarded_private.attempts; v_expiry timestamptz;
begin
  -- Serializes activation across attempts in this app session; no stacking.
  perform pg_advisory_xact_lock(hashtextextended(p_user::text || p_hash, 0));
  select * into a from rewarded_private.attempts where id = p_attempt for update;
  if not found or a.user_id <> p_user or a.session_hash <> p_hash then
    raise exception 'rewarded_invalid_attempt';
  end if;
  if a.expires_at is not null then
    return jsonb_build_object('status', case when a.expires_at > now()
      then 'active' else 'expired' end, 'expires_at', a.expires_at, 'server_now', now());
  end if;
  if a.created_at < now() - interval '24 hours' then
    return jsonb_build_object('status', 'expired');
  end if;
  if a.verified_at is null then return jsonb_build_object('status', 'pending'); end if;
  select max(expires_at) into v_expiry from rewarded_private.attempts
    where user_id = p_user and session_hash = p_hash and expires_at > now();
  v_expiry := coalesce(v_expiry, now() + interval '10 minutes');
  update rewarded_private.attempts set expires_at = v_expiry where id = a.id;
  return jsonb_build_object('status', 'active', 'expires_at', v_expiry, 'server_now', now());
end;
$$;
revoke all on function public.rewarded_prepare(uuid,text,text) from public, anon, authenticated;
revoke all on function public.rewarded_verify(uuid,uuid,text,text) from public, anon, authenticated;
revoke all on function public.rewarded_activate(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.rewarded_prepare(uuid,text,text) to service_role;
grant execute on function public.rewarded_verify(uuid,uuid,text,text) to service_role;
grant execute on function public.rewarded_activate(uuid,uuid,text) to service_role;

-- Legacy overload stays intact. The new overload requires the ephemeral token.
create function public.claim_game_analysis_report(p_fingerprint text, p_rewarded_session text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
begin
  if coalesce(rewarded_private.has_access(p_rewarded_session), false) then
    if nullif(btrim(p_fingerprint), '') is null then
      return jsonb_build_object('allowed',false,'reason','invalid_fingerprint','is_premium',false);
    end if;
    return jsonb_build_object('allowed',true,'reason','rewarded_access','is_premium',false);
  end if;
  return public.claim_game_analysis_report(p_fingerprint);
end;
$$;
revoke all on function public.claim_game_analysis_report(text,text) from public, anon;
grant execute on function public.claim_game_analysis_report(text,text) to authenticated;

-- Keep the privileged aggregate in a non-exposed schema.
create or replace function rewarded_private.most_liked_games(
  p_from timestamptz,
  p_to timestamptz,
  p_limit integer,
  p_rewarded_session text
)
returns table (
  source_game_id text,
  like_count bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
begin
  if p_from is null or p_to is null or p_to <= p_from then
    return;
  end if;

  if (p_to - p_from > interval '26 hours'
      or p_from < now() - interval '26 hours')
    and not (coalesce(public._user_has_premium(auth.uid()), false)
      or coalesce(rewarded_private.has_access(p_rewarded_session), false)) then
    raise exception 'premium_required'
      using errcode = 'P0001',
            hint = 'Most Liked beyond the current day is a Premium ranking.';
  end if;

  return query
    select ranked.game_id, ranked.likes
    from (
      select
        a.source_game_id as game_id,
        count(distinct a.user_id)::bigint as likes
      from public.user_saved_analyses a
      join public.user_folders f
        on f.id = a.folder_id
       and f.user_id = a.user_id
       and f.is_liked_games
      where a.source_game_id is not null
        and btrim(a.source_game_id) <> ''
        and a.created_at >= p_from
        and a.created_at < p_to
      group by a.source_game_id
    ) ranked
    order by ranked.likes desc, ranked.game_id asc
    limit v_limit;
end;
$$;

revoke all on function rewarded_private.most_liked_games(timestamptz,timestamptz,integer,text) from public, anon;
grant execute on function rewarded_private.most_liked_games(timestamptz,timestamptz,integer,text) to authenticated;
create function public.most_liked_games(p_from timestamptz, p_to timestamptz,
    p_limit integer, p_rewarded_session text)
returns table(source_game_id text, like_count bigint)
language sql stable security invoker set search_path = '' as $$
  select * from rewarded_private.most_liked_games(p_from,p_to,p_limit,p_rewarded_session);
$$;
revoke all on function public.most_liked_games(timestamptz,timestamptz,integer,text) from public, anon;
grant execute on function public.most_liked_games(timestamptz,timestamptz,integer,text) to authenticated;
