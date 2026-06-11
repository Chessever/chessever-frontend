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

# Base FEN with different clocks
moves_uci = ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6", "b5a4", "g8f6", "e1g1", "f8e7", "f1e1", "b7b5", "a4b3", "d7d6", "c2c3", "e8g8", "h2h3", "c6b8", "d2d4", "b8d7", "b1d2", "c8b7"]

payload1 = {"fen": "r2q1rk1/1bpnbppp/p2p1n2/1p2p3/3PP3/1BP2N1P/PP1N1PP1/R1BQR1K1 w - - 3 12", "moves": moves_uci}
payload2 = {"fen": "r2q1rk1/1bpnbppp/p2p1n2/1p2p3/3PP3/1BP2N1P/PP1N1PP1/R1BQR1K1 w - - 0 1", "moves": moves_uci}

def do_post(payload, i):
    req = urllib.request.Request(f"{BASE_URL}/api/game-position/aggregates/query", headers=headers, method="POST", data=json.dumps(payload).encode("utf-8"))
    start = time.time()
    try:
        with urllib.request.urlopen(req) as response:
            body = response.read().decode('utf-8')
            end = time.time()
            data = json.loads(body)
            moves = data.get('data', {}).get('moves', [])
            print(f"Request {i} | Payload FEN: {payload['fen'][-10:]} | Status: {response.status} | Time: {end - start:.4f}s")
    except Exception as e:
        end = time.time()
        print(f"Request {i} | Payload FEN: {payload['fen'][-10:]} | Error: {e} | Time: {end - start:.4f}s")

print("Testing cache hit across different FEN clocks:")
do_post(payload1, 1) # Should be fast since we already computed it
do_post(payload2, 2) # If slow (9s), backend cache is broken!

