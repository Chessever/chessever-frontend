#!/usr/bin/env python3
"""Upload a PGN file as a Discovery › Collection.

    SUPABASE_URL=https://<ref>.supabase.co \
    SUPABASE_SERVICE_ROLE_KEY=... \
    python3 scripts/collections/upload_collection.py games.pgn \
        --slug us-championship-2025 --kind event \
        --title "US Championship 2025" \
        --subtitle "Saint Louis · October 2025" \
        --author "GM Name" --about-file about.txt [--cover-url https://...] \
        [--sort-order 10] [--publish] [--replace]

Every game keeps its whole PGN (comments, NAGs, variations); the header
fields the app lists by are copied beside it. A collection is created
unpublished unless --publish is given, so it can be checked before anyone
sees it. --replace drops the collection's existing games first (only that
collection's). Standard library only; see docs/collections.md.
"""

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request

HEADER = re.compile(r'^\[(\w+)\s+"((?:[^"\\]|\\.)*)"\]\s*$')


def split_games(text):
    """Games in a PGN file: each starts at a header block after movetext."""
    games, current, in_moves = [], [], False
    for line in text.replace('\r\n', '\n').split('\n'):
        is_header = bool(HEADER.match(line.strip()))
        if is_header and in_moves and current:
            games.append('\n'.join(current).strip())
            current, in_moves = [], False
        if line.strip() and not is_header:
            in_moves = True
        current.append(line)
    if current and '\n'.join(current).strip():
        games.append('\n'.join(current).strip())
    return [g for g in games if g]


def headers(pgn):
    out = {}
    for line in pgn.split('\n'):
        m = HEADER.match(line.strip())
        if m:
            out[m.group(1)] = m.group(2).replace('\\"', '"').replace('\\\\', '\\')
    return out


def as_int(value):
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return None


def text(value):
    value = (value or '').strip()
    return value or None


def game_row(collection_id, index, pgn):
    h = headers(pgn)
    return {
        'collection_id': collection_id,
        'sort_order': index,
        'pgn': pgn + '\n',
        'white': text(h.get('White')),
        'black': text(h.get('Black')),
        'white_elo': as_int(h.get('WhiteElo')),
        'black_elo': as_int(h.get('BlackElo')),
        'white_title': text(h.get('WhiteTitle')),
        'black_title': text(h.get('BlackTitle')),
        'white_fed': text(h.get('WhiteFed') or h.get('WhiteCountry')),
        'black_fed': text(h.get('BlackFed') or h.get('BlackCountry')),
        'white_fide_id': as_int(h.get('WhiteFideId')),
        'black_fide_id': as_int(h.get('BlackFideId')),
        'result': text(h.get('Result')),
        'event': text(h.get('Event')),
        'round': text(h.get('Round')),
        'played_on': text(h.get('Date')),
        'eco': text(h.get('ECO')),
        'opening': text(h.get('Opening')),
        'annotator': text(h.get('Annotator')),
    }


def request(method, url, key, body=None, prefer=None):
    headers_ = {
        'apikey': key,
        'Authorization': f'Bearer {key}',
        'Content-Type': 'application/json',
    }
    if prefer:
        headers_['Prefer'] = prefer
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method, headers=headers_)
    try:
        with urllib.request.urlopen(req) as res:
            raw = res.read().decode() or 'null'
            return json.loads(raw)
    except urllib.error.HTTPError as err:
        sys.exit(f'{method} {url.split("?")[0]} failed: {err.code} {err.read().decode()}')


def main():
    p = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    p.add_argument('pgn_file')
    p.add_argument('--slug', required=True)
    p.add_argument('--kind', choices=['event', 'book'], default='event')
    p.add_argument('--title', required=True)
    p.add_argument('--subtitle')
    p.add_argument('--author')
    p.add_argument('--about')
    p.add_argument('--about-file')
    p.add_argument('--cover-url')
    p.add_argument('--sort-order', type=int, default=0)
    p.add_argument('--publish', action='store_true')
    p.add_argument('--replace', action='store_true')
    args = p.parse_args()

    base = os.environ.get('SUPABASE_URL', '').rstrip('/')
    key = os.environ.get('SUPABASE_SERVICE_ROLE_KEY', '')
    if not base or not key:
        sys.exit('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY.')
    rest = f'{base}/rest/v1'

    with open(args.pgn_file, encoding='utf-8-sig') as f:
        games = split_games(f.read())
    if not games:
        sys.exit('No games found in the PGN file.')

    about = args.about
    if args.about_file:
        with open(args.about_file, encoding='utf-8') as f:
            about = f.read().strip()

    collection = {
        'slug': args.slug,
        'kind': args.kind,
        'title': args.title,
        'subtitle': args.subtitle,
        'author': args.author,
        'about': about,
        'cover_url': args.cover_url,
        'sort_order': args.sort_order,
        'published': args.publish,
    }
    saved = request(
        'POST',
        f'{rest}/discovery_collections?on_conflict=slug',
        key,
        collection,
        prefer='resolution=merge-duplicates,return=representation',
    )
    collection_id = saved[0]['id']

    if args.replace:
        request(
            'DELETE',
            f'{rest}/discovery_collection_games?collection_id=eq.{collection_id}',
            key,
        )

    rows = [game_row(collection_id, i, g) for i, g in enumerate(games)]
    for start in range(0, len(rows), 200):
        request(
            'POST',
            f'{rest}/discovery_collection_games',
            key,
            rows[start:start + 200],
            prefer='return=minimal',
        )

    state = 'published' if args.publish else 'saved unpublished'
    print(f'{args.title}: {len(rows)} games {state} (id {collection_id}).')


if __name__ == '__main__':
    main()
