import { createClient } from 'npm:@supabase/supabase-js@2.57.4';

const project = Deno.env.get('SUPABASE_URL')!;
const expectedHost = 'oelbsuggrzyqwzmvidju.supabase.co';
const units = (Deno.env.get('REWARDED_AD_UNIT_IDS') ?? 'ca-app-pub-3681310687796023/8590975808,ca-app-pub-3681310687796023/8331032066').split(',').map(s => s.trim()).filter(Boolean);
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
});

Deno.serve(async request => {
  // This feature is explicitly production-only; never deploy into the test app.
  if (new URL(project).host !== expectedHost || !units.length) return json({error:'unconfigured'}, 503);
  if (request.method !== 'POST') return json({error:'method_not_allowed'}, 405);
  try {
    const bearer = request.headers.get('authorization')?.match(/^Bearer (.+)$/i)?.[1];
    if (!bearer) return json({error:'unauthorized'}, 401);
    const admin = createClient(project, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
      auth: {persistSession:false, autoRefreshToken:false},
    });
    const {data:{user}, error:authError} = await admin.auth.getUser(bearer);
    if (authError || !user) return json({error:'unauthorized'}, 401);
    if (Number(request.headers.get('content-length') ?? 0) > 2048) return json({error:'invalid_request'},400);
    const text = await request.text();
    if (text.length > 2048) return json({error:'invalid_request'},400);
    const body = JSON.parse(text);
    if (typeof body.session_token !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(body.session_token)) return json({error:'invalid_request'},400);
    const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',
      new TextEncoder().encode(body.session_token)))).map(b=>b.toString(16).padStart(2,'0')).join('');
    if (body.action === 'prepare') {
      if (!units.includes(body.ad_unit)) return json({error:'invalid_ad_unit'},400);
      const {data, error} = await admin.rpc('rewarded_prepare', {
        p_user:user.id, p_hash:hash, p_adunit:body.ad_unit,
      });
      if (error) return json({error:'attempt_unavailable'},429);
      return json({attempt_id:data});
    }
    if (body.action === 'activate' && typeof body.attempt_id === 'string' &&
        /^[\da-f-]{36}$/i.test(body.attempt_id)) {
      const {data,error} = await admin.rpc('rewarded_activate', {
        p_attempt:body.attempt_id, p_user:user.id, p_hash:hash,
      });
      if (error) return json({error:'invalid_attempt'},403);
      return json(data);
    }
    return json({error:'invalid_request'},400);
  } catch (_) { return json({error:'request_failed'},400); }
});
