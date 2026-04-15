import urllib.request
import urllib.parse
import json

BASE_URL = "https://service.chessever.com"
API_KEY = "4e1b7d20-db18-41ae-8e48-5a35c127aeef"
headers = {"X-API-Key": API_KEY, "Content-Type": "application/json"}

def test(fen, desc):
    print(f"\n--- {desc} ---")
    print(f"FEN: {fen}")
    
    url_get = f"{BASE_URL}/api/game-position/aggregates?fen={urllib.parse.quote(fen)}"
    try:
        req = urllib.request.Request(url_get, headers=headers)
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            moves = data.get('data', {}).get('moves', [])
            print(f"GET: Status {response.status}, Moves: {len(moves)}")
    except Exception as e:
        print(f"GET: Error {e}")

    try:
        payload = {"fen": fen, "moves": ["e2e4"]}
        req = urllib.request.Request(f"{BASE_URL}/api/game-position/aggregates/query", headers=headers, method="POST", data=json.dumps(payload).encode())
        with urllib.request.urlopen(req) as response:
            data = json.loads(response.read().decode())
            moves = data.get('data', {}).get('moves', [])
            print(f"POST: Status {response.status}, Moves: {len(moves)}")
    except Exception as e:
        print(f"POST: Error {e}")

test("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1", "With pseudo-legal EP")
test("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1", "Without pseudo-legal EP")

