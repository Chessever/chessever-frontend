import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
const require = createRequire(process.env.REWARDED_TEST_DEPS
  ? resolve(process.env.REWARDED_TEST_DEPS,'package.json') : import.meta.url);
const {PGlite} = require('@electric-sql/pglite');
const migration = await readFile(new URL('../migrations/20261026120000_partner_news.sql',import.meta.url),'utf8');

async function database({token='secret-token'}={}) {
  const db = new PGlite();
  await db.exec(`
    create role anon; create role authenticated; create role service_role bypassrls;
    create schema cron; create schema net;
    create table cron.jobs(name text, schedule text, command text);
    create function cron.schedule(text,text,text) returns bigint language sql as
      $$ insert into cron.jobs values ($1,$2,$3); select 1::bigint $$;
    create table net.calls(url text, body jsonb, headers jsonb, timeout_milliseconds int);
    create function net.http_post(url text, body jsonb, headers jsonb, timeout_milliseconds int) returns bigint
      language sql as $$ insert into net.calls values (url, body, headers, timeout_milliseconds); select 1::bigint $$;
    create function public.get_vault_secret(secret_name text) returns text language sql stable as
      $$ select case secret_name when 'live_dispatch_token' then ${token === null ? 'null' : `'${token}'`} end $$;
    grant usage on schema public to anon, authenticated, service_role;
  `);
  await db.exec(migration);
  return db;
}

const article = (n, extra={}) => ({
  guid: `https://rookreview.com/news/${n}`,
  url: `https://rookreview.com/news/${n}`,
  title: `Title ${n}`,
  summary: `Summary ${n}`,
  content: `Body ${n}`,
  image_url: `https://rookreview.b-cdn.net/${n}.jpg`,
  published_at: `2026-10-2${n}T10:00:00Z`,
  ...extra,
});

async function upsert(db, items, source='rookreview') {
  return (await db.query('select public.upsert_partner_news($1,$2::jsonb) as value',
    [source, JSON.stringify(items)])).rows[0].value;
}

async function asRole(db, role, sql) {
  await db.exec(`set role ${role}`);
  try { return (await db.query(sql)).rows; } finally { await db.exec('reset role'); }
}

test('seeds RookReview and schedules the sync every ten minutes', async () => {
  const db = await database();
  const {rows: sources} = await db.query('select id, name, site_url, feed_url, asset_hosts, enabled from public.partner_news_sources');
  assert.deepEqual(sources, [{
    id: 'rookreview', name: 'RookReview', site_url: 'https://rookreview.com',
    feed_url: 'https://rookreview.com/feed.xml', asset_hosts: ['rookreview.b-cdn.net'], enabled: true,
  }]);
  const {rows: jobs} = await db.query('select * from cron.jobs');
  assert.deepEqual(jobs, [{name: 'partner-news-sync', schedule: '4-59/10 * * * *',
    command: 'select public.kick_partner_news_sync()'}]);
});

test('inserts new articles, skips unchanged ones and replaces edited ones', async () => {
  const db = await database();
  assert.deepEqual(await upsert(db, [article(1), article(2), article(2, {title: 'dup'})]),
    {received: 3, inserted: 2, updated: 0});
  const before = (await db.query("select id, updated_at, title from public.partner_news order by id")).rows;
  assert.deepEqual(before.map((r) => r.title), ['Title 1', 'Title 2']);

  assert.deepEqual(await upsert(db, [article(1), article(2)]), {received: 2, inserted: 0, updated: 0});
  const same = (await db.query("select id, updated_at from public.partner_news order by id")).rows;
  assert.deepEqual(same, before.map(({id, updated_at}) => ({id, updated_at})));

  assert.deepEqual(await upsert(db, [article(1, {content: 'Edited'}), article(3)]),
    {received: 2, inserted: 1, updated: 1});
  const {rows} = await db.query("select id, content from public.partner_news order by id");
  assert.deepEqual(rows.map((r) => r.content), ['Edited', 'Body 2', 'Body 3']);
  assert.equal(rows[0].id, before[0].id);

  const {rows: [source]} = await db.query('select last_success_at, last_error, last_item_count, consecutive_failures from public.partner_news_sources');
  assert.ok(source.last_success_at);
  assert.equal(source.last_error, null);
  assert.equal(source.last_item_count, 2);
  assert.equal(source.consecutive_failures, 0);
});

test('a hidden article stays hidden through later syncs and edits', async () => {
  const db = await database();
  await upsert(db, [article(1), article(2)]);
  await db.exec("update public.partner_news set status = 'hidden' where guid like '%/1'");
  await upsert(db, [article(1, {title: 'Edited'}), article(2)]);
  const {rows} = await db.query('select title, status from public.partner_news order by id');
  assert.deepEqual(rows, [{title: 'Edited', status: 'hidden'}, {title: 'Title 2', status: 'published'}]);
});

test('readers see published articles of enabled sources only, never the sources table', async () => {
  const db = await database();
  await upsert(db, [article(1), article(2)]);
  await db.exec("update public.partner_news set status = 'hidden' where guid like '%/2'");
  for (const role of ['anon', 'authenticated']) {
    assert.deepEqual((await asRole(db, role, 'select title from public.partner_news')).map((r) => r.title), ['Title 1']);
    await assert.rejects(asRole(db, role, 'select * from public.partner_news_sources'), /permission denied/);
    await assert.rejects(asRole(db, role, "select public.upsert_partner_news('rookreview', '[]')"), /permission denied/);
    await assert.rejects(asRole(db, role, "insert into public.partner_news(source_id, guid, url, title, content, published_at, content_hash) values ('rookreview','g','https://x','t','c',now(),'h')"), /permission denied/);
  }
  await db.exec("update public.partner_news_sources set enabled = false");
  assert.deepEqual(await asRole(db, 'anon', 'select title from public.partner_news'), []);
});

test('records failures without touching the last success', async () => {
  const db = await database();
  await upsert(db, [article(1)]);
  await db.query("select public.record_partner_news_failure('rookreview', $1)", ['feed answered HTTP 503 ' + 'x'.repeat(900)]);
  await db.query("select public.record_partner_news_failure('rookreview', 'again')");
  const {rows: [source]} = await db.query('select last_success_at, last_error, consecutive_failures from public.partner_news_sources');
  assert.ok(source.last_success_at);
  assert.equal(source.last_error, 'again');
  assert.equal(source.consecutive_failures, 2);
  await upsert(db, [article(1)]);
  const {rows: [healed]} = await db.query('select last_error, consecutive_failures from public.partner_news_sources');
  assert.deepEqual(healed, {last_error: null, consecutive_failures: 0});
});

test('rejects unknown sources and malformed payloads', async () => {
  const db = await database();
  await assert.rejects(upsert(db, [article(1)], 'nobody'), /unknown partner news source/);
  await assert.rejects(db.query("select public.upsert_partner_news('rookreview', '{}'::jsonb)"), /must be a JSON array/);
  assert.deepEqual(await upsert(db, [article(1, {guid: ' '}), article(2, {content: ''})]), {received: 2, inserted: 0, updated: 0});
});

test('the kick posts to the function with the stream token, and only while a source is enabled', async () => {
  const db = await database();
  await db.query('select public.kick_partner_news_sync()');
  const {rows} = await db.query('select * from net.calls');
  assert.equal(rows.length, 1);
  assert.equal(rows[0].url, 'https://oelbsuggrzyqwzmvidju.supabase.co/functions/v1/partner-news-sync');
  assert.equal(rows[0].headers['x-stream-token'], 'secret-token');
  assert.equal(rows[0].timeout_milliseconds, 60000);

  await db.exec('update public.partner_news_sources set enabled = false');
  await db.query('select public.kick_partner_news_sync()');
  assert.equal((await db.query('select * from net.calls')).rows.length, 1);
});
