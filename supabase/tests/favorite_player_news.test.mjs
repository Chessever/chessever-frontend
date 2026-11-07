// Native publication migration. Preferred-service fanout/claims/provider and
// native two-connection races are tested by the actual admin source owner.
import assert from 'node:assert/strict';
import {before,after,test} from 'node:test';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
let db;
const content='Players involved: [Alpha Player](/player/101)\n\nAlpha speaks.';
const subjects=[{fide_id:'101',name:'Alpha Player',role:'quotation'}];
async function count(){return (await db.query('select count(*)::int n from favorite_player_news_publications')).rows[0].n;}
async function article(status='published',date='now',metadata=subjects){return (await db.query('insert into news(content,status,published_at,player_news_subjects) values($1,$2,$3,$4::jsonb) returning id',[content,status,date,JSON.stringify(metadata)])).rows[0].id;}
before(async()=>{
 db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create role service_role;create schema auth;
 create function auth.role() returns text language sql stable as $$select coalesce(current_setting('request.jwt.claim.role',true),'')$$;
 create table news(id bigint generated always as identity primary key,content text,status text,published_at timestamptz,created_at timestamptz default now());
 create table chess_players(fideid bigint,name text);insert into chess_players values(101,'Player,Alpha');
 insert into news(content,status,published_at)values('Old','published',now()),('Old draft','draft',null);
 select set_config('request.jwt.claim.role','service_role',false);`);
 await db.exec(await readFile(new URL('../migrations/20261031051924_favorite_player_news.sql',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../migrations/20261102120000_favorite_player_news_publish_skew.sql',import.meta.url),'utf8'));
 if (!process.env.FAVORITE_NEWS_BASELINE) {
  // Model a previously published eligible article, including a pending ledger
  // consumer, before replacing the function. The migration must not touch data.
  const legacyId=await article();
  const snapshot=async()=>({news:(await db.query('select * from news order by id')).rows,ledger:(await db.query('select * from favorite_player_news_publications order by news_id')).rows,guards:(await db.query("select oid::regprocedure::text signature,pg_get_functiondef(oid) definition,proacl::text acl from pg_proc where oid in ('queue_favorite_player_news()'::regprocedure,'activate_due_favorite_player_news(integer)'::regprocedure) order by oid")).rows});
  const original=await snapshot();
  await db.exec(await readFile(new URL('../migrations/20261107060000_favorite_player_news_structured_subjects.sql',import.meta.url),'utf8'));
  assert.deepEqual(await snapshot(),original,'migration preserves all news, ledgers and queue/activation definitions/ACLs');
  await db.query("update news set content='Alpha speaks.' where id=$1",[legacyId]);
  assert.deepEqual((await db.query('select fide_ids from favorite_player_news_publications where news_id=$1',[legacyId])).rows[0].fide_ids,await subjectIds(subjects,'Alpha speaks.'));
  assert.deepEqual((await db.query('select * from favorite_player_news_publications order by news_id')).rows,original.ledger);
 }
});
after(async()=>await db.close());
async function bodyArticle(body,metadata=subjects){return (await db.query("insert into news(content,status,published_at,player_news_subjects) values($1,'published',now(),$2::jsonb) returning id",[body,JSON.stringify(metadata)])).rows[0].id;}
async function subjectIds(metadata,body=null){return (await db.query('select favorite_player_news_subject_ids($1::jsonb,$2) ids',[JSON.stringify(metadata),body])).rows[0].ids;}
test('structured subjects alone qualify without a visible header or any body link; exact metadata and IDs are stored',async()=>{
 const n=await count();
 for(const body of ['Alpha speaks.','Inline [Alpha Player](/player/101) only.',null,'Players involved: malformed unrelated display']){
  const id=await bodyArticle(body);
  assert.deepEqual((await db.query('select player_news_subjects,content from news where id=$1',[id])).rows[0],{player_news_subjects:subjects,content:body});
  assert.deepEqual((await db.query('select fide_ids from favorite_player_news_publications where news_id=$1',[id])).rows[0]?.fide_ids,['101']);
 }
 assert.equal(await count(),n+4);
 assert.deepEqual(await subjectIds([{...subjects[0],role:'subject'}]),['101']);
});
test('missing/malformed/duplicate structured IDs, names and roles fail the whole article closed',async()=>{
 const bad=[null,{},[],[null],['101'],[{name:'Alpha Player',role:'subject'}],
  ...['','0','01','-1','101.0','1e2',' 101','101 ','1'.repeat(16),null,{},true].map(fide_id=>[{...subjects[0],fide_id}]),
  ...['',' ',' Alpha Player','Alpha Player ','[Alpha]','Alpha\nPlayer',null,'X'.repeat(121)].map(name=>[{...subjects[0],name}]),
  ...['participant','result','Subject','',null,{},101].map(role=>[{...subjects[0],role}]),
  [subjects[0],subjects[0]],Array.from({length:21},(_,i)=>({...subjects[0],fide_id:String(i+1)}))];
 const n=await count();
 for(const metadata of bad){assert.deepEqual(await subjectIds(metadata,content),[],JSON.stringify(metadata));await bodyArticle(content,metadata);}
 assert.equal(await count(),n);
});
test('canonical DB identity validation rejects missing, mismatched and ambiguous IDs without a header',async()=>{
 const n=await count();
 for(const metadata of [[{...subjects[0],fide_id:'999'}],[{...subjects[0],name:'Wrong Name'}],[{...subjects[0],name:{}}],[{...subjects[0],name:101}],[subjects[0],{fide_id:'999',name:'Other Player',role:'subject'}]])await bodyArticle('Interview',metadata);
 await db.exec("insert into chess_players values(103,'Player,Alpha'),(103,'Other,Person')");
 try{await bodyArticle('Interview',[{...subjects[0],fide_id:'103'}]);}finally{await db.exec('delete from chess_players where fideid=103');}
 assert.equal(await count(),n);
});
test('incidental inline links and even the old visible header do not infer structured eligibility',async()=>{
 const n=await count();await bodyArticle(content,[]);await bodyArticle('Results: [Alpha Player](/player/101)',[]);assert.equal(await count(),n);
});
test('removing the header of an already-published article preserves metadata, ledger and one-shot dedupe',async()=>{
 const id=await article(),n=await count();
 const ledger=(await db.query('select * from favorite_player_news_publications where news_id=$1',[id])).rows;
 await db.query("update news set content='Alpha speaks with [inline profile](/player/101).' where id=$1",[id]);
 await db.exec('select activate_due_favorite_player_news(100)');
 assert.equal(await count(),n);
 assert.deepEqual((await db.query('select * from favorite_player_news_publications where news_id=$1',[id])).rows,ledger);
 assert.deepEqual((await db.query('select player_news_subjects,player_news_publication_seen from news where id=$1',[id])).rows[0],{player_news_subjects:subjects,player_news_publication_seen:true});
});
test('scheduled no-header publication keeps due-time and pre-edit eligibility fences',async()=>{
 const n=await count(),date=new Date(Date.now()+100).toISOString();
 const insert=async metadata=>(await db.query("insert into news(content,status,published_at,player_news_subjects) values('Interview','published',$1,$2::jsonb) returning id",[date,JSON.stringify(metadata)])).rows[0].id;
 await insert(subjects);const incidental=await insert([]);assert.equal(await count(),n);
 await new Promise(r=>setTimeout(r,130));
 await db.query('update news set player_news_subjects=$2::jsonb where id=$1',[incidental,JSON.stringify(subjects)]);
 await db.exec('select activate_due_favorite_player_news(100)');assert.equal(await count(),n+1);
 await db.exec('select activate_due_favorite_player_news(100)');assert.equal(await count(),n+1);
});
test('first subject/quote publication persists atomically and only once; routine edits and republish do not repeat',async()=>{
 const n=await count(),id=await article();assert.equal(await count(),n+1);
 await db.query("update news set content=content||' edit' where id=$1",[id]);await db.query("update news set status='draft' where id=$1",[id]);await db.query("update news set status='published' where id=$1",[id]);assert.equal(await count(),n+1);
 await db.exec('begin');await article();await db.exec('rollback');assert.equal(await count(),n+1);
});
test('existing rows/drafts, historical imports, incidental and late-added eligibility cannot backfill',async()=>{
 const n=await count();for(const id of [1,2])await db.query("update news set content=$2,status='published',published_at=now(),player_news_subjects=$3::jsonb where id=$1",[id,content,JSON.stringify(subjects)]);
 await article('published','2000-01-01T00:00:00Z');const id=await article('published','now',[]);await db.query('update news set player_news_subjects=$2::jsonb where id=$1',[id,JSON.stringify(subjects)]);assert.equal(await count(),n);
});
test('scheduled first publication activates only when due; after-due eligibility cannot backfill',async()=>{
 const n=await count(),date=new Date(Date.now()+50).toISOString();await article('published',date);const incidental=await article('published',date,[]);
 assert.equal(await count(),n);await new Promise(r=>setTimeout(r,80));
 await db.query('update news set player_news_subjects=$2::jsonb where id=$1',[incidental,JSON.stringify(subjects)]);
 await db.exec('select activate_due_favorite_player_news(100)');assert.equal(await count(),n+1);
});
test('non-service cannot change eligible content/status or metadata; ledgers/RPC remain private',async()=>{
 const id=await article('draft',null);await db.exec("select set_config('request.jwt.claim.role','anon',false)");
 await assert.rejects(db.query("update news set status='published',published_at=now() where id=$1",[id]),/editorial service/);
 await assert.rejects(db.query("update news set content=content||' unauthorized' where id=$1",[id]),/editorial service/);
 await assert.rejects(db.query("update news set player_news_subjects='[]' where id=$1",[id]),/editorial service/);
 await db.exec("select set_config('request.jwt.claim.role','service_role',false)");
 for(const role of ['anon','authenticated'])assert.equal((await db.query("select has_table_privilege($1,'favorite_player_news_publications','select') or has_function_privilege($1,'activate_due_favorite_player_news(integer)','execute') or has_function_privilege($1,'favorite_player_news_subject_ids(jsonb,text)','execute') allowed",[role])).rows[0].allowed,false);
});
test('publisher clock a few seconds behind the insert still counts as a new publication; an hour behind is an import',async()=>{
 // Production 2026-11-01: Hermes stamped published_at 0.4-12 s before created_at's now().
 const n=await count();await article('published',new Date(Date.now()-12_000).toISOString());assert.equal(await count(),n+1);
 await article('published',new Date(Date.now()-3_600_000).toISOString());assert.equal(await count(),n+1);
});
