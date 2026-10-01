import { createClient } from 'npm:@supabase/supabase-js@2.57.4';
import { parseCallback, verifyCallback, rewardIdentity } from './verification.ts';

let keys: {keyId:number; pem:string}[] = [];
let fetched = 0;
async function publicKey(keyId: string) {
  if (!keys.length || Date.now()-fetched > 23*60*60*1000 ||
      (!keys.some(key=>String(key.keyId)===keyId) && Date.now()-fetched > 60000)) {
    const response = await fetch('https://www.gstatic.com/admob/reward/verifier-keys.json', {signal:AbortSignal.timeout(5000)});
    if (!response.ok) throw new Error('keys_unavailable');
    keys = (await response.json()).keys; fetched = Date.now();
  }
  const key = keys.find(key=>String(key.keyId)===keyId);
  if (!key) throw new Error('unknown_key');
  return key.pem;
}
Deno.serve(async request => {
  const project = Deno.env.get('SUPABASE_URL')!;
  const units = (Deno.env.get('REWARDED_AD_UNIT_IDS') ?? 'ca-app-pub-3681310687796023/8590975808,ca-app-pub-3681310687796023/8331032066').split(',').map(s=>s.trim()).filter(Boolean);
  if (new URL(project).host !== 'oelbsuggrzyqwzmvidju.supabase.co' || !units.length) return new Response('unconfigured',{status:503});
  if (request.method !== 'GET') return new Response('method_not_allowed',{status:405});
  try {
    const parsed = parseCallback(request.url);
    const params = await verifyCallback(request.url, await publicKey(parsed.params.get('key_id')!));
    const adUnit = units.find(unit => unit === params.get('ad_unit') ||
      unit.split('/')[1] === params.get('ad_unit'));
    if (!adUnit) return new Response('invalid_ad_unit',{status:403});
    const timestamp = Number(params.get('timestamp'));
    if (!Number.isFinite(timestamp) || Math.abs(Date.now()-timestamp) > 24*60*60*1000) return new Response('expired_callback',{status:403});
    const identity = rewardIdentity(params);
    if (!identity) return new Response('verified_no_reward', {headers:{'cache-control':'no-store'}});
    const admin = createClient(project,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{
      auth:{persistSession:false,autoRefreshToken:false},
    });
    const {data,error} = await admin.rpc('rewarded_verify', {
      p_attempt:identity.attempt, p_user:identity.user,
      p_transaction:params.get('transaction_id'), p_adunit:adUnit,
    });
    if (error) return new Response('verification_unavailable',{status:error.code === '23505' ? 403 : 503});
    if (data !== true) return new Response('verified_no_reward',{headers:{'cache-control':'no-store'}});
    return new Response('verified',{headers:{'cache-control':'no-store'}});
  } catch (error) {
    const reason = error instanceof Error ? error.message : 'unknown_error';
    // Never log callback URLs, identity fields or transaction data.
    console.warn('rewarded_ssv_rejected', {reason});
    return new Response('verification_failed',{status:/keys_unavailable|fetch|timeout/i.test(reason) ? 503 : 403});
  }
});
