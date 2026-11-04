"""Actual PostgreSQL locking tests in an explicitly named disposable container.

Start postgres:17-alpine with --network none and name codex-rookreview-<suffix>.
Then: python3 supabase/tests/rookreview_notification_concurrency.py --container NAME
No host database, credentials, model endpoint or push provider is used.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import subprocess
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('--container', required=True)
args = parser.parse_args()
if not args.container.startswith('codex-rookreview-'):
    raise SystemExit('Only a disposable codex-rookreview-* container is allowed')
database = 'rookreview_' + uuid.uuid4().hex
base = ['docker', 'exec', '-i', args.container, 'psql', '-U', 'postgres', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1']


def sql(statement, db=database):
    result = subprocess.run(base + ['-d', db], input=statement, text=True, capture_output=True, timeout=20)
    if result.returncode:
        raise RuntimeError(result.stderr)
    return result.stdout.strip()


def held(statement):
    """Return only once a separate transaction has acquired its row lock."""
    process = subprocess.Popen(base + ['-d', database], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True)
    process.stdin.write("begin;\n" + statement + "\n\\echo LOCKED\nselect pg_sleep(1);\ncommit;\n")
    process.stdin.close()
    output = []
    for line in process.stdout:
        if line.strip() == 'LOCKED':
            return process, output
        output.append(line.strip())
    raise RuntimeError(process.stderr.read())


def finish(process):
    process.wait(timeout=10)
    if process.returncode:
        raise RuntimeError(process.stderr.read())


root = Path(__file__).resolve().parents[1]
insert = """insert into partner_news(source_id,guid,url,title,content,published_at,content_hash)
 values('rookreview','%s','https://rookreview.com/news/%s','Alpha Player wins',
 'Alpha Player wins the tournament.',clock_timestamp(),'fixture-hash') returning id;"""
try:
    sql("do $$begin if not exists(select 1 from pg_roles where rolname='anon') then create role anon;end if;"
        "if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated;end if;"
        "if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role;end if;end$$;", 'postgres')
    sql('create database ' + database, 'postgres')
    sql("""create schema cron;create schema net;
 create function cron.schedule(text,text,text) returns bigint language sql as $$select 1::bigint$$;
 create function net.http_post(url text,body jsonb,headers jsonb,timeout_milliseconds int) returns bigint language sql as $$select 1::bigint$$;
 create function public.get_vault_secret(text) returns text language sql as $$select null::text$$;
 create table chess_players(fideid bigint,name text);insert into chess_players values(101,'Player, Alpha');""")
    for name in ['20261026120000_partner_news.sql', '20261104005515_rookreview_player_notifications.sql']:
        sql((root / 'migrations' / name).read_text())

    # An import begun while disabled holds the boundary until it commits. The
    # later activation cannot retrospectively admit this article.
    importer, _ = held(insert % ('before', 'before'))
    sql('update partner_news_notification_policy set enabled=true;')
    finish(importer)
    assert sql('select count(*) from partner_news_notification_jobs') == '0'
    print('PASS activation waits for in-flight import; no historical admission')

    article_id = sql(insert % ('current', 'current'))
    worker, claimed = held('select article_id from claim_partner_news_notifications(3);')
    assert claimed == [article_id], claimed
    assert sql('select article_id from claim_partner_news_notifications(3);') == ''
    finish(worker)
    print('PASS concurrent claim skips the locked job')

    lease = sql('select lease from partner_news_notification_jobs where article_id=' + article_id)
    subjects = json.dumps([{'fide_id': '101', 'name': 'Alpha Player', 'role': 'subject',
                           'mention': 'Alpha Player', 'evidence': 'Alpha Player wins the tournament.'}])
    command = "select complete_partner_news_notification(%s,'%s','%s'::jsonb,'fixture-model');" % (article_id, lease, subjects)
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(sql, [command, command]))
    assert sorted(results) == ['f', 't'], results
    assert sql('select count(*) from partner_player_news_publications') == '1'
    print('PASS competing completion commits exactly one publication')

    try:
        sql('begin isolation level repeatable read;update partner_news_notification_policy set enabled=false;commit;')
        raise AssertionError('repeatable-read activation unexpectedly accepted')
    except RuntimeError as error:
        assert 'requires READ COMMITTED' in str(error), error
    assert sql('select enabled from partner_news_notification_policy') == 't'
    print('PASS unsupported activation isolation is rejected atomically')

    # A second activation also invalidates pending work from the earlier epoch.
    second = sql(insert % ('second', 'second'))
    old_lease = sql('select lease from claim_partner_news_notifications(3) where article_id=' + second)
    sql('update partner_news_notification_policy set enabled=false;update partner_news_notification_policy set enabled=true;')
    command = "select complete_partner_news_notification(%s,'%s','%s'::jsonb,'fixture-model');" % (second, old_lease, subjects)
    assert sql(command) == 'f'
    assert sql('select count(*) from partner_player_news_publications') == '1'
    print('PASS reactivation cannot replay a previous activation job')
finally:
    sql('drop database if exists ' + database + ' with (force)', 'postgres')
