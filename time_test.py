import urllib.request
import urllib.parse
import time
import json

BASE_URL = "https://service.chessever.com"
API_KEY = "4e1b7d20-db18-41ae-8e48-5a35c127aeef"
headers = {"X-API-Key": API_KEY}

# FEN after 1.e4, but with e3 and with -
fen_e3 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
fen_dash = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"

for fen in [fen_e3, fen_dash]:
    url = f"{BASE_URL}/api/game-position/aggregates?fen={urllib.parse.quote(fen)}"
    req = urllib.request.Request(url, headers=headers)
    
    start = time.time()
    try:
        with urllib.request.urlopen(req) as response:
            body = response.read().decode('utf-8')
            end = time.time()
            data = json.loads(body)
            moves = data.get('data', {}).get('moves', [])
            print(f"FEN: {fen}")
            print(f"Status: {response.status}")
            print(f"Time: {end - start:.4f} seconds")
            print(f"Moves count: {len(moves)}")
    except Exception as e:
        end = time.time()
        print(f"FEN: {fen} -> Error: {e}")
        print(f"Time: {end - start:.4f} seconds")
