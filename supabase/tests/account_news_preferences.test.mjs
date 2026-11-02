import assert from 'node:assert/strict';
import {before,after,test} from 'node:test';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
let db;
const owner='00000000-0000-4000-8000-000000000001';
const other='00000000-0000-4000-8000-000000000002';
const row=async()=> (await db.query('select * from user_notification_preferences where user_id=$1',[owner])).rows[0];
before(async()=>{
 db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create role service_role;
 create schema auth;create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;
 create table user_notification_preferences(user_id uuid primary key,push_enabled boolean default true,favorite_player_alerts boolean default true,favorite_event_alerts boolean default true);
 alter table user_notification_preferences enable row level security;
 grant usage on schema public,auth to authenticated;
 grant select,insert,update on user_notification_preferences to authenticated;
 create policy own_preferences on user_notification_preferences to authenticated using(auth.uid()=user_id) with check(auth.uid()=user_id);`);
 await db.exec(await readFile(new URL('../migrations/20261031051929_account_news_preferences.sql',import.meta.url),'utf8'));
 await db.query('insert into user_notification_preferences(user_id) values($1),($2)',[owner,other]);
});
after(async()=>db.close());
test('account News defaults independently and ordinary game saves preserve its activation boundary',async()=>{
 const before=await row();assert.equal(before.favorite_player_news_alerts,true);
 await db.query('update user_notification_preferences set favorite_player_alerts=false where user_id=$1',[owner]);
 const after=await row();assert.deepEqual(after.favorite_player_news_enabled_at,before.favorite_player_news_enabled_at);assert.equal(after.favorite_player_news_alerts,true);
});
test('optout/re-enable advances the boundary; client timestamps cannot replay historical publications',async()=>{
 const before=await row();await new Promise(r=>setTimeout(r,5));
 await db.query('update user_notification_preferences set favorite_player_news_alerts=false where user_id=$1',[owner]);
 await db.query("update user_notification_preferences set favorite_player_news_alerts=true,favorite_player_news_enabled_at='2000-01-01' where user_id=$1",[owner]);
 const after=await row();assert.ok(after.favorite_player_news_enabled_at.getTime()>before.favorite_player_news_enabled_at.getTime());
 await db.query("update user_notification_preferences set favorite_player_news_enabled_at='2000-01-01' where user_id=$1",[owner]);
 assert.deepEqual((await row()).favorite_player_news_enabled_at,after.favorite_player_news_enabled_at);
});
test('existing ownership RLS lets an account change its News preference but not another account',async()=>{
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[owner]);
 await db.exec('set role authenticated');
 try{
  await db.query('update user_notification_preferences set favorite_player_news_alerts=false where user_id=$1',[owner]);
  assert.equal((await row()).favorite_player_news_alerts,false);
  const result=await db.query('update user_notification_preferences set favorite_player_news_alerts=false where user_id=$1 returning user_id',[other]);assert.equal(result.rows.length,0);
  await assert.rejects(db.query('insert into user_notification_preferences(user_id) values($1)',['00000000-0000-4000-8000-000000000003']),/row-level security/);
 }finally{await db.exec('reset role');}
 assert.equal((await db.query('select favorite_player_news_alerts from user_notification_preferences where user_id=$1',[other])).rows[0].favorite_player_news_alerts,true);
});
