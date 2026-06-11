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

# Test standard 1.e4 position
fen = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
payload = {"fen": fen, "moves": ["e2e4"]}

def do_post(i):
    req = urllib.request.Request(f"{BASE_URL}/api/game-position/aggregates/query", headers=headers, method="POST", data=json.dumps(payload).encode("utf-8"))
    start = time.time()
    try:
        with urllib.request.urlopen(req) as response:
            body = response.read().decode('utf-8')
            end = time.time()
            data = json.loads(body)
            moves = data.get('data', {}).get('moves', [])
            print(f"Request {i} | Status: {response.status} | Time: {end - start:.4f}s | Moves count: {len(moves)}")
    except Exception as e:
        end = time.time()
        print(f"Request {i} | Error: {e} | Time: {end - start:.4f}s")
        if hasattr(e, 'read'):
            print(e.read().decode())

print("Testing repeated POST requests (to check Redis cache behavior):")
for i in range(1, 6):
    do_post(i)
    time.sleep(0.5)

