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
});
after(async()=>await db.close());
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
 for(const role of ['anon','authenticated'])assert.equal((await db.query("select has_table_privilege($1,'favorite_player_news_publications','select') or has_function_privilege($1,'activate_due_favorite_player_news(integer)','execute') allowed",[role])).rows[0].allowed,false);
});
