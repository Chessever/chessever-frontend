import urllib.request
import urllib.parse
import time
import json

BASE_URL = "https://service.chessever.com"
API_KEY = "4e1b7d20-db18-41ae-8e48-5a35c127aeef"
headers = {"X-API-Key": API_KEY}

# FEN after 1.e4, but with e3 and with -
fen_e3 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"

url = f"{BASE_URL}/api/game-position/aggregates?fen={urllib.parse.quote(fen_e3)}"
req = urllib.request.Request(url, headers=headers)
try:
    with urllib.request.urlopen(req) as response:
        body = response.read().decode('utf-8')
        data = json.loads(body)
        print(f"GET e3 Status: {response.status}")
        print(f"GET e3 Data: {data.get('data', {}).get('moves', [])}")
except Exception as e:
    print(f"GET Error: {e}")

fen_dash = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
url = f"{BASE_URL}/api/game-position/aggregates?fen={urllib.parse.quote(fen_dash)}"
req = urllib.request.Request(url, headers=headers)
try:
    with urllib.request.urlopen(req) as response:
        body = response.read().decode('utf-8')
        data = json.loads(body)
        print(f"GET dash Status: {response.status}")
        print(f"GET dash Data length: {len(data.get('data', {}).get('moves', []))}")
except Exception as e:
    print(f"GET Error: {e}")
