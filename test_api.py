import urllib.request
import urllib.parse
import json
import sys

BASE_URL = "https://service.chessever.com"
API_KEY = "4e1b7d20-db18-41ae-8e48-5a35c127aeef"

headers = {
    "X-API-Key": API_KEY,
    "Content-Type": "application/json",
    "User-Agent": "TestScript/1.0"
}

def make_request(url, method="GET", data=None, params=None):
    try:
        url_with_params = url
        if params:
            url_with_params += "?" + urllib.parse.urlencode(params)
        
        # print(f"DEBUG call: {method} {url_with_params}")
        req = urllib.request.Request(url_with_params, headers=headers, method=method)
        if data:
            json_data = json.dumps(data).encode('utf-8')
            req.data = json_data
            
        with urllib.request.urlopen(req) as response:
            status = response.status
            body = response.read().decode('utf-8')
            try:
                json_body = json.loads(body)
                return status, json_body, None
            except:
                return status, body, None
    except urllib.error.HTTPError as e:
        body = e.read().decode('utf-8')
        try:
             json_body = json.loads(body)
             return e.code, json_body, str(e)
        except:
             return e.code, body, str(e)
    except Exception as e:
        return 0, None, str(e)

def print_result(name, status, body, error):
    print(f"--- {name} ---")
    print(f"Status: {status}")
    if error:
        print(f"Error: {error}")
    if body:
        print(f"Response: {json.dumps(body, indent=2)}")
    else:
        print("Response: <Empty>")

def test_api():
    # 1. /api/search/metadata
    print("\nTesting /api/search/metadata...")
    status, body, error = make_request(f"{BASE_URL}/api/search/metadata")
    print_result("Search Metadata", status, body, error)

    # 2. /api/game-position/aggregates
    print("\nTesting /api/game-position/aggregates...")
    fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    status, body, error = make_request(f"{BASE_URL}/api/game-position/aggregates", params={"fen": fen})
    print_result("Position Aggregates", status, body, error)

    # 3. /api/player (Search)
    print("\nTesting /api/player (search 'Carlsen')...")
    status, body, error = make_request(f"{BASE_URL}/api/player", params={"name": "Carlsen"})
    print_result("Player Search", status, body, error)
    
    player_id = None
    if body and isinstance(body, dict) and body.get('data') and len(body['data']) > 0:
        player_id = body['data'][0]['id']
        print(f"Found Player ID: {player_id}")

    # 4. /api/player/{id}
    if player_id:
        print(f"\nTesting /api/player/{player_id}...")
        status, body, error = make_request(f"{BASE_URL}/api/player/{player_id}")
        print_result("Get Player by ID", status, body, error)
    else:
        print("\nSkipping /api/player/{id} (No player ID found)")

    # 5. /api/search (Global)
    print("\nTesting /api/search (global 'Carlsen')...")
    status, body, error = make_request(f"{BASE_URL}/api/search", params={"q": "Carlsen"})
    print_result("Global Search", status, body, error)

    # 6. /api/search/query (POST)
    print("\nTesting /api/search/query (POST)...")
    payload = {
        "resource": "player",
        "q": "carlsen",
        "pageNumber": 1,
        "pageSize": 5
    }
    status, body, error = make_request(f"{BASE_URL}/api/search/query", method="POST", data=payload)
    print_result("Structured Query", status, body, error)

    # 7. Use search/query to find a game
    print("\nTesting /api/search/query (Finding a game)...")
    game_payload = {
        "resource": "game",
        "pageNumber": 1,
        "pageSize": 1
    }
    status, body, error = make_request(f"{BASE_URL}/api/search/query", method="POST", data=game_payload)
    print_result("Game Query", status, body, error)
    
    game_id = None
    if body and isinstance(body, dict) and body.get('data') and isinstance(body['data'], list) and len(body['data']) > 0:
        results = body['data']
        if len(results) > 0:
            game_id = results[0]['id']
            print(f"Found Game ID: {game_id}")
            
    if game_id:
        print(f"\nTesting /api/game/{game_id}...")
        status, body, error = make_request(f"{BASE_URL}/api/game/{game_id}")
        print_result("Get Game by ID", status, body, error)
    else:
        print("\nSkipping /api/game/{id} (No game ID found)")

if __name__ == "__main__":
    test_api()
