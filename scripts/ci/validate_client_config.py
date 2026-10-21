#!/usr/bin/env python3
"""Reject privileged or cross-project credentials before compiling a client."""
import argparse
import base64
import json
import os

PROJECT = 'oelbsuggrzyqwzmvidju'


def validate(values, mobile=False):
    if values.get('SUPABASE_URL', '').rstrip('/') != f'https://{PROJECT}.supabase.co':
        raise ValueError('SUPABASE_URL must target the production ChessEver project.')
    key = values.get('SUPABASE_ANON_KEY', '').strip()
    if not key.startswith('sb_publishable_'):
        try:
            payload = key.split('.')[1]
            claims = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))
        except (IndexError, ValueError, UnicodeError):
            raise ValueError('SUPABASE_ANON_KEY must be a public client key.') from None
        if claims.get('role') != 'anon' or claims.get('ref') != PROJECT:
            raise ValueError('SUPABASE_ANON_KEY must be a production anon key, never a service-role key.')
    if mobile and not values.get('REVENUECAT_API_KEY', '').startswith(('appl_', 'goog_')):
        raise ValueError('REVENUECAT_API_KEY must be a public Apple/Google SDK key, never an admin key.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--mobile', action='store_true')
    args = parser.parse_args()
    try:
        validate(os.environ, mobile=args.mobile)
    except ValueError as error:
        raise SystemExit(str(error)) from None
    print('Public production client configuration validated; values omitted.')
