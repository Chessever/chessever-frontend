import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
const require = createRequire(process.env.REWARDED_TEST_DEPS
  ? resolve(process.env.REWARDED_TEST_DEPS,'package.json') : import.meta.url);
const {PGlite} = require('@electric-sql/pglite');
const {pgcrypto} = require('@electric-sql/pglite/contrib/pgcrypto');
const user='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const other='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
const token='a'.repeat(43);
const hash=createHash('sha256').update(token).digest('hex');
const migration = await readFile(new URL('../migrations/20261001044952_rewarded_premium_sessions.sql',import.meta.url),'utf8');

async function database() {
  const db = new PGlite({extensions:{pgcrypto}});
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create schema extensions;
    create extension pgcrypto with schema extensions;
    create table auth.users(id uuid primary key);
    insert into auth.users values ('${user}'),('${other}');
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    grant usage on schema auth to authenticated, service_role;
    grant execute on function auth.uid() to authenticated, service_role;
    grant usage on schema extensions to authenticated, service_role;
    create function public._user_has_premium(uuid) returns boolean language sql stable as $$select false$$;
    create function public.claim_game_analysis_report(text) returns jsonb language sql as
      $$select '{"allowed":false,"reason":"daily_limit","is_premium":false}'::jsonb$$;
    create table public.user_folders(id uuid primary key,user_id uuid,is_liked_games boolean);
    create table public.user_saved_analyses(user_id uuid,folder_id uuid,source_game_id text,created_at timestamptz);
  `);
  await db.exec(migration);
  await db.exec(await readFile(new URL('../migrations/20261002170755_premium_only_game_reports.sql',import.meta.url),'utf8'));
  return db;
}
async function scalar(db, sql, params=[]) {return (await db.query(sql,params)).rows[0].value;}
async function attempt(db,sessionHash=hash) {
  return scalar(db,'select public.rewarded_prepare($1,$2,$3) as value',[user,sessionHash,'ad-unit']);
}
async function verify(db,id,transaction='tx1') {
  return scalar(db,'select public.rewarded_verify($1,$2,$3,$4) as value',[id,user,transaction,'ad-unit']);
}
async function activate(db,id,uid=user,sessionHash=hash) {
  return scalar(db,'select public.rewarded_activate($1,$2,$3) as value',[id,uid,sessionHash]);
}
async function caller(db,uid=user,role='authenticated') {
  await db.query("select set_config('request.jwt.claim.sub',$1,false)",[uid]);
  await db.exec(`set role ${role}`);
}

test('migration grants ten minutes only after verification; activation is idempotent',async()=>{
  const db=await database();try {
    const id=await attempt(db);
    assert.equal((await activate(db,id)).status,'pending');
    assert.equal(await verify(db,id),true);
    const first=await activate(db,id);const second=await activate(db,id);
    assert.equal(first.status,'active');assert.equal(first.expires_at,second.expires_at);
    assert.equal(new Date(first.expires_at)-new Date(first.server_now),600000);
    await caller(db);
    assert.equal(await scalar(db,'select public.rewarded_premium_access($1) as value',[token]),true);
    assert.equal(await scalar(db,'select public.rewarded_premium_access($1) as value',['b'.repeat(43)]),false);
    await db.exec('reset role');await caller(db,other);
    assert.equal(await scalar(db,'select public.rewarded_premium_access($1) as value',[token]),false);
  } finally {await db.close();}
});
test('forged, replayed, wrong-user and wrong-session attempts cannot activate',async()=>{
  const db=await database();try {
    const a=await attempt(db); const b=await attempt(db);
    await assert.rejects(activate(db,a,other),/rewarded_invalid_attempt/);
    await assert.rejects(activate(db,a,user,'b'.repeat(64)),/rewarded_invalid_attempt/);
    assert.equal(await verify(db,a),true);assert.equal(await verify(db,a),true);
    await assert.rejects(verify(db,b),/unique constraint/);
    assert.equal(await verify(db,a,'different-transaction'),false);
    await caller(db);
    await assert.rejects(db.query('select public.rewarded_activate($1,$2,$3)',[a,user,hash]),/permission denied/);
    await assert.rejects(db.query('insert into rewarded_private.attempts(user_id,session_hash,ad_unit) values($1,$2,$3)',[user,hash,'ad']),/permission denied/);
  } finally {await db.close();}
});
test('expiry and restart tokens restore report limits; new grants never stack',async()=>{
  const db=await database();try {
    const a=await attempt(db);await verify(db,a);const first=await activate(db,a);
    const b=await attempt(db);await verify(db,b,'tx2');const second=await activate(db,b);
    assert.equal(first.expires_at,second.expires_at);
    await caller(db);
    const granted=await scalar(db,'select public.claim_game_analysis_report($1,$2) as value',['game',token]);
    assert.equal(granted.allowed,true);assert.equal(granted.is_premium,false);
    const fresh=await scalar(db,'select public.claim_game_analysis_report($1,$2) as value',['game','c'.repeat(43)]);
    assert.equal(fresh.allowed,false);
    await db.exec("reset role; update rewarded_private.attempts set expires_at=now()-interval '1 second'");
    assert.equal((await activate(db,a)).status,'expired');
    await caller(db);
    assert.equal(await scalar(db,'select public.rewarded_premium_access($1) as value',[token]),false);
    assert.equal((await scalar(db,'select public.claim_game_analysis_report($1,$2) as value',['game',token])).allowed,false);
  } finally {await db.close();}
});
test('premium rankings accept a verified session and reject expired or unknown sessions',async()=>{
  const db=await database();try {
    const a=await attempt(db);await verify(db,a);await activate(db,a);
    await caller(db);
    const from='2026-01-01';const to='2026-02-01';
    assert.deepEqual((await db.query('select * from public.most_liked_games($1,$2,$3,$4)',[from,to,12,token])).rows,[]);
    await assert.rejects(db.query('select * from public.most_liked_games($1,$2,$3,$4)',[from,to,12,'b'.repeat(43)]),/premium_required/);
  } finally {await db.close();}
});


test('first report and repeated free report claims require premium', async()=>{
  const db=await database();try {
    await caller(db);
    for (let i=0;i<2;i++) {
      const result=await scalar(db,'select public.claim_game_analysis_report($1) as value',['first-game']);
      assert.equal(result.allowed,false);
      assert.equal(result.reason,'premium_required');
    }
    await db.exec('reset role');
    await db.exec('create or replace function public._user_has_premium(uuid) returns boolean language sql stable as $$select true$$');
    await caller(db);
    assert.equal((await scalar(db,'select public.claim_game_analysis_report($1) as value',['first-game'])).allowed,true);
  } finally {await db.close();}
});
