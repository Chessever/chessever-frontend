import urllib.request
import urllib.parse
import time
import json

import os

BASE_URL = "https://service.chessever.com"
API_KEY = os.environ.get("GAMEBASE_API_KEY")
if not API_KEY:
    raise SystemExit("Set GAMEBASE_API_KEY before running this script.")
headers = {"X-API-Key": API_KEY, "Content-Type": "application/json"}

# Test POST request to /api/game-position/aggregates/query
fen = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
payload = {"fen": fen, "moves": ["e2e4"]}

req = urllib.request.Request(f"{BASE_URL}/api/game-position/aggregates/query", headers=headers, method="POST", data=json.dumps(payload).encode("utf-8"))

start = time.time()
try:
    with urllib.request.urlopen(req) as response:
        body = response.read().decode('utf-8')
        end = time.time()
        print(f"Status: {response.status}")
        print(f"Time: {end - start:.4f} seconds")
        data = json.loads(body)
        print(f"Moves count: {len(data.get('data', {}).get('moves', []))}")
except Exception as e:
    end = time.time()
    print(f"Error: {e}")
    if hasattr(e, 'read'):
        print(e.read().decode())
    print(f"Time: {end - start:.4f} seconds")
