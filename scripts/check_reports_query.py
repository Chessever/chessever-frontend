#!/usr/bin/env python3
"""Read-only Reports latency check against this app's verified TEST backend.

Run explicitly with python3 scripts/check_reports_query.py. Loads .env.test
internally and never prints credentials or game/PGN contents. A successful empty
list is valid: this test branch may have no Cloudflare report writebacks.
"""

import json
from pathlib import Path
import re
import statistics
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
TEST_PROJECT = 'odmekzlfunfocvedqusl'


def main():
    env = {}
    for line in (ROOT / '.env.test').read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            key, value = line.split('=', 1)
            env[key.strip()] = value.strip().strip('\"\'')
    base = env['SUPABASE_URL'].rstrip('/')
    if urllib.parse.urlsplit(base).hostname != TEST_PROJECT + '.supabase.co':
        raise ValueError('Refusing a backend other than the verified test project')

    source = (ROOT / 'lib/screens/for_you/discovery/data/discovery_repository.dart').read_text()
    columns = re.search(r"const String _analyzedGameColumns = '''(.*?)''';", source, re.S).group(1)
    params = [
        ('select', re.sub(r'\s+', '', columns)),
        ('status', 'in.(1-0,0-1,1/2-1/2)'),
        ('pgn', r'like.%[\%eval %'),
        ('or', r'(pgn.like.%$24%,pgn.ilike.%chessever_annotation%)'),
        ('order', 'last_move_time.desc.nullslast,id.asc.nullslast'),
        ('limit', '30'),
    ]
    # Repetition crosses PostgreSQL's prepared-plan threshold. Check both
    # cursor shapes too, without assuming the test branch has any reports.
    cases = [('first', [])] * 6 + [
        ('dated', [('or', '(last_move_time.lt."2026-09-01T00:00:00Z",'
         'and(last_move_time.eq."2026-09-01T00:00:00Z",id.gt."probe"),'
         'last_move_time.is.null)')]),
        ('undated', [('last_move_time', 'is.null'), ('id', 'gt.probe')]),
    ]
    times = []
    for name, cursor in cases:
        request = urllib.request.Request(
            base + '/rest/v1/games?' + urllib.parse.urlencode(params + cursor),
            headers={
                'apikey': env['SUPABASE_ANON_KEY'],
                'Authorization': 'Bearer ' + env['SUPABASE_ANON_KEY'],
            },
        )
        started = time.monotonic()
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                body = response.read()
                rows = json.loads(body)
                seconds = time.monotonic() - started
                assert isinstance(rows, list) and len(rows) <= 30
                times.append(seconds)
                print(json.dumps({'case': name, 'status': response.status,
                                  'seconds': round(seconds, 3), 'rows': len(rows),
                                  'bytes': len(body)}), flush=True)
        except urllib.error.HTTPError as error:
            payload = json.loads(error.read())
            print(json.dumps({'case': name, 'status': error.code,
                              'error_code': payload.get('code')}))
            return 1
    median = statistics.median(times)
    print(json.dumps({'target': TEST_PROJECT, 'requests': len(times),
                      'median_seconds': round(median, 3),
                      'maximum_seconds': round(max(times), 3)}))
    return 0 if median < 1.5 and max(times) < 3 else 1


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        # Exception strings may include a request URL; print only the type.
        print(json.dumps({'error_type': type(error).__name__}))
        sys.exit(1)
