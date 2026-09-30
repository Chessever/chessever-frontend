#!/usr/bin/env python3
"""Read-only production Smart Event API timing, without running the app.

Loads credentials privately from .env, verifies the production app's exact
project, and prints only durations, counts and cursor dates. No PGN or player
content is printed. Use after the additive smart-event migration.
"""

import datetime
import json
from pathlib import Path
import re
import statistics
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
PROJECT = 'oelbsuggrzyqwzmvidju'


def main():
    env = {}
    for line in (ROOT / '.env').read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            key, value = line.split('=', 1)
            env[key.strip()] = value.strip().strip('"\'')
    base = env['SUPABASE_URL'].rstrip('/')
    if urllib.parse.urlsplit(base).hostname != PROJECT + '.supabase.co':
        raise ValueError('Refusing a backend other than the production app project')
    headers = {'apikey': env['SUPABASE_ANON_KEY'],
               'Authorization': 'Bearer ' + env['SUPABASE_ANON_KEY']}

    def request(path, params=None, payload=None):
        url = base + '/rest/v1/' + path
        if params:
            url += '?' + urllib.parse.urlencode(params)
        body = None if payload is None else json.dumps(payload).encode()
        req = urllib.request.Request(
            url, data=body,
            headers={**headers, 'Content-Type': 'application/json'})
        with urllib.request.urlopen(req, timeout=10) as response:
            return json.load(response)

    source = (ROOT / 'lib/repository/supabase/game/game_repository.dart').read_text()
    columns = re.search(
        r"const String _smartEventDaySelectColumns = '''(.*?)''';", source, re.S
    ).group(1)
    columns = re.sub(r'\s+', '', columns) + ',rounds!games_round_id_fkey!inner(starts_at)'
    candidate_columns = (
        'tour_id,tours!games_tour_id_fkey('
        'group_broadcasts!tours_group_broadcast_id_fkey(time_control)),'
        'rounds!games_round_id_fkey!inner(starts_at)')
    cases = [
        ('C44 GM classical completed', ['C44'], 2500, ['standard', 'classical'], True),
        ('GM rapid', None, 2500, ['rapid'], False),
        ('Najdorf GM', ['B' + str(n) for n in range(90, 100)], 2500, None, False),
        ('All Games', None, None, None, False),
        ('empty opening', ['ZZZ'], 2500, None, True),
    ]
    records = []
    for name, ecos, floor, controls, completed in cases:
        for attempt in range(2):
            started = time.monotonic()
            day = request('rpc/get_current_smart_event_day', payload={
                'p_eco_codes': ecos, 'p_min_rating': floor,
                'p_time_controls': controls, 'p_completed_only': completed,
            })
            day_seconds = time.monotonic() - started
            requests = 1
            game_count = 0
            if day is not None:
                now = datetime.datetime.now(datetime.timezone.utc).isoformat()
                predicates = [
                    ('game_day', 'eq.' + day),
                    ('rounds.or', '(starts_at.is.null,starts_at.lte.' + now + ')'),
                ]
                if floor:
                    predicates.append(('player_max_rating', 'gte.' + str(floor)))
                if completed:
                    predicates.append(('status', 'not.in.(*,ongoing,live)'))
                if ecos:
                    predicates.append(('eco', 'in.(' + ','.join(ecos) + ')'))

                def pages(select, extra=None):
                    nonlocal requests
                    offset = 0
                    rows = []
                    while True:
                        page = request('games', params=[
                            ('select', select), *predicates, *(extra or []),
                            ('order', 'id.asc'), ('offset', str(offset)),
                            ('limit', '1000'),
                        ])
                        requests += 1
                        rows.extend(page)
                        if len(page) < 1000:
                            return rows
                        offset += len(page)

                if controls:
                    tours = set()
                    for row in pages(candidate_columns):
                        tour = row.get('tours') or {}
                        event = tour.get('group_broadcasts') or {}
                        tc = (event.get('time_control') or '').strip().lower()
                        if tc in controls:
                            tours.add(row['tour_id'])
                    assert tours, 'Day cursor must identify a qualifying format'
                    chunks = [sorted(tours)[i:i + 40] for i in range(0, len(tours), 40)]
                    games = []
                    for chunk in chunks:
                        games.extend(pages(columns, [
                            ('tour_id', 'in.(' + ','.join(chunk) + ')'),
                        ]))
                else:
                    games = pages(columns)
                assert len({g['id'] for g in games}) == len(games)
                for game in games:
                    assert 'pgn' not in game
                    assert game['game_day'] == day
                    ratings = [p.get('rating', 0) for p in (game.get('players') or [])[:2]]
                    average = (sum(map(int, ratings)) // 2
                               if len(ratings) == 2 and all(r > 0 for r in ratings) else 0)
                    if floor and average < floor:
                        continue
                    game_count += 1
                assert game_count, 'Resolved day must contain qualifying games'
            record = {'case': name, 'attempt': attempt + 1, 'day': day,
                      'games': game_count, 'requests_to_first_day': requests,
                      'day_lookup_seconds': round(day_seconds, 3),
                      'first_day_seconds': round(time.monotonic() - started, 3)}
            records.append(record)
            print(json.dumps(record), flush=True)
    print(json.dumps({'target': PROJECT,
                      'median_first_day_seconds': statistics.median(
                          r['first_day_seconds'] for r in records)}))
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except urllib.error.HTTPError as error:
        payload = json.loads(error.read())
        print(json.dumps({'status': error.code, 'error_code': payload.get('code')}))
        raise SystemExit(1)
    except Exception as error:
        # Exception strings can contain request URLs or credentials.
        print(json.dumps({'error_type': type(error).__name__}))
        raise SystemExit(1)
