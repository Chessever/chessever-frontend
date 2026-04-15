import urllib.request
import urllib.parse
import time
import json
import concurrent.futures

BASE_URL = "https://service.chessever.com"
API_KEY = "4e1b7d20-db18-41ae-8e48-5a35c127aeef"
headers = {"X-API-Key": API_KEY, "Content-Type": "application/json"}

payload = {"fen": "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1", "moves": ["e2e4"]}

def do_post(i):
    req = urllib.request.Request(f"{BASE_URL}/api/game-position/aggregates/query", headers=headers, method="POST", data=json.dumps(payload).encode("utf-8"))
    start = time.time()
    try:
        with urllib.request.urlopen(req) as response:
            body = response.read().decode('utf-8')
            end = time.time()
            data = json.loads(body)
            moves = data.get('data', {}).get('moves', [])
            return True, end - start, len(moves), response.status
    except Exception as e:
        end = time.time()
        error_msg = str(e)
        if hasattr(e, 'read'):
            try:
                error_msg = e.read().decode()
            except:
                pass
        return False, end - start, error_msg, getattr(e, 'code', 0)

print("Starting stress test for 1.e4 with 20 concurrent requests...")
with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
    futures = [executor.submit(do_post, i) for i in range(20)]
    results = [f.result() for f in concurrent.futures.as_completed(futures)]

successes = 0
failures = 0
times = []
for success, t, data, status in results:
    times.append(t)
    if success:
        successes += 1
    else:
        failures += 1
        print(f"Failure! Status: {status}, Error: {data}")

print(f"Total Success: {successes}")
print(f"Total Failures: {failures}")
print(f"Average Time: {sum(times)/len(times):.4f}s")
print(f"Max Time: {max(times):.4f}s")

