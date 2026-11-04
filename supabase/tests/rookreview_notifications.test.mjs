import assert from 'node:assert/strict';
import {before,after,beforeEach,test} from 'node:test';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const {PGlite}=require('@electric-sql/pglite');
let db;
const subject={fide_id:'101',name:'Alpha Player',role:'subject',mention:'Alpha Player',evidence:'Alpha Player wins the tournament.'};
const migrationRoot=process.env.ROOKREVIEW_MIGRATIONS_ROOT??new URL('../migrations/',import.meta.url);
const load=async name=>db.exec(await readFile(new URL(name,typeof migrationRoot==='string'?new URL('file://'+migrationRoot+'/'):migrationRoot),'utf8'));
before(async()=>{
 db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create role service_role;create schema cron;create schema net;
 create function cron.schedule(text,text,text) returns bigint language sql as $$select 1::bigint$$;
 create function net.http_post(url text,body jsonb,headers jsonb,timeout_milliseconds int) returns bigint language sql as $$select 1::bigint$$;
 create function public.get_vault_secret(text) returns text language sql as $$select null::text$$;
 create table chess_players(fideid bigint,name text);insert into chess_players values(101,'Player, Alpha'),(102,'Player, Beta');`);
 await db.exec(await readFile(new URL('../migrations/20261026120000_partner_news.sql',import.meta.url),'utf8'));
 await load('20261104005515_rookreview_player_notifications.sql');
});
after(async()=>db.close());
beforeEach(async()=>{
 await db.exec(`delete from partner_news;update partner_news_notification_policy set enabled=false;
 update partner_news_sources set enabled=true;delete from chess_players where fideid>102;`);
});
const enable=()=>db.exec('update partner_news_notification_policy set enabled=true');
async function add({guid=crypto.randomUUID(),date='clock_timestamp()',content=subject.evidence,url}={}){
 await db.query(`select upsert_partner_news('rookreview',jsonb_build_array(jsonb_build_object('guid',$1::text,'url',$2::text,'title','Alpha Player wins','summary','','content',$3::text,'published_at',date_trunc('milliseconds',${date}))))`,[guid,url??'https://rookreview.com/news/'+guid,content]);
 return (await db.query('select id from partner_news where guid=$1',[guid])).rows[0].id;
}
const claim=async()=> (await db.query('select * from claim_partner_news_notifications(3)')).rows;
const complete=async(job,subjects=[subject],error=null)=> (await db.query('select complete_partner_news_notification($1,$2,$3::jsonb,$4,$5) ok',[job.article_id,job.lease,JSON.stringify(subjects),'fixture-model',error])).rows[0].ok;
const count=async table=>(await db.query(`select count(*)::int n from ${table}`)).rows[0].n;

test('default off, pre-activation rows, old and future articles cannot alert; no edit/backfill',async()=>{
 const old=await add({url:'https://rookreview.com/news/existing'});assert.equal(await count('partner_news_notification_jobs'),0);
 await enable();
 await add({url:'https://rookreview.com/news/existing'});
 await db.query("update partner_news set published_at=clock_timestamp(),title='edited' where id=$1",[old]);
 await add({date:"clock_timestamp()-interval '31 minutes'"});await add({date:"clock_timestamp()+interval '1 minute'"});
 assert.equal(await count('partner_news_notification_jobs'),0);
 await add();assert.equal((await claim()).length,1);
});
test('repeated RSS upserts and changed GUIDs for the same URL create only one job/publication',async()=>{
 await enable();const id=await add({guid:'same'});
 const row=(await db.query('select * from partner_news where id=$1',[id])).rows[0];
 for(let i=0;i<3;i++)await db.query("select upsert_partner_news('rookreview',$1::jsonb)",[JSON.stringify([{...row,image_url:null,published_at:row.published_at.toISOString()}])]);
 await add({url:row.url});
 assert.equal(await count('partner_news_notification_jobs'),1);
 const [job]=await claim();assert.equal(await complete(job),true);assert.equal(await complete(job),false);
 assert.equal(await count('partner_player_news_publications'),1);assert.deepEqual(await claim(),[]);
});
test('claims lease each job once and reject wrong/expired leases',async()=>{
 await enable();await add();const [job]=await claim();assert.deepEqual(await claim(),[]);
 assert.equal(await complete({...job,lease:crypto.randomUUID()}),false);
 await db.exec("update partner_news_notification_jobs set leased_until=now()-interval '1 second'");
 assert.equal(await complete(job),false);const [retry]=await claim();assert.notEqual(retry.lease,job.lease);
 assert.equal(await complete(retry),true);
});
test('invalid FIDE IDs, duplicate identities, fabricated evidence and ambiguous names fail closed',async()=>{
 await enable();await add();const [job]=await claim();
 for(const subjects of [[{...subject,fide_id:'999'}],[subject,subject],[{...subject,evidence:'Alpha Player has invented news.'}],[{...subject,role:'participant'}]])await assert.rejects(complete(job,subjects));
 await db.exec("insert into chess_players values(999,'Alpha Player')");
 await assert.rejects(complete(job));assert.equal(await count('partner_player_news_publications'),0);
});
test('material edits, hiding, source disable and reactivation fence extraction without replay',async()=>{
 for(const mutation of ["update partner_news set content_hash='edited'","update partner_news set status='hidden'","update partner_news_sources set enabled=false","update partner_news_notification_policy set enabled=false;update partner_news_notification_policy set enabled=true"]){
  await db.exec('delete from partner_news;update partner_news_notification_policy set enabled=false;update partner_news_sources set enabled=true');await enable();await add();const [job]=await claim();
  await db.exec(mutation);assert.equal(await complete(job),false);assert.equal(await count('partner_player_news_publications'),0);
 }
});
test('bounded retries reuse the job; expiry never creates a publication',async()=>{
 await enable();await add();
 for(let i=0;i<3;i++){const [job]=await claim();assert.ok(job);assert.equal(await complete(job,[],'ai_http_503'),false);}
 assert.deepEqual(await claim(),[]);assert.equal(await count('partner_player_news_publications'),0);
 await add();const [job]=await claim();await db.exec("update partner_news_notification_jobs set expires_at=now()-interval '1 second'");
 assert.equal(await complete(job),false);assert.equal(await count('partner_player_news_publications'),0);
});
test('no-player outcome is consumed, protected tables and RPCs cannot be called publicly',async()=>{
 await enable();await add();const [job]=await claim();assert.equal(await complete(job,[]),true);assert.deepEqual(await claim(),[]);
 for(const role of ['anon','authenticated']){
  for(const table of ['partner_news_notification_jobs','partner_player_news_publications','partner_news_notification_policy'])assert.equal((await db.query('select has_table_privilege($1,$2,\'select\') allowed',[role,table])).rows[0].allowed,false);
  assert.equal((await db.query("select has_function_privilege($1,'claim_partner_news_notifications(int)','execute') allowed",[role])).rows[0].allowed,false);
 }
});
