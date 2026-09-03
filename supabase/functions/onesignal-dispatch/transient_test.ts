/**
 * Transient-failure classification + in-process retry.
 * Run: deno test --allow-read supabase/functions/onesignal-dispatch/transient_test.ts
 */
import {
  assert,
  assertEquals,
  assertRejects,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  describeError,
  formatPostgrestError,
  isTransientError,
  runQuery,
  runQuerySettled,
  withTransientRetry,
} from "./transient.ts";

// The exact shape Deno's fetch produced on 2026-09-01 when the pooled HTTP/2
// connection to PostgREST was recycled mid-request.
const H2_STREAM_ERROR =
  "TypeError: error sending request for url (https://oelbsuggrzyqwzmvidju.supabase.co/rest/v1/user_favorite_players?select=user_id&player_name=in.%28%22Carlsen%2C%20Magnus%22%29&order=id.asc&offset=0&limit=1000): client error (SendRequest): http2 error: stream error received: unexpected internal error encountered";

const noSleep = () => Promise.resolve();
const quiet = () => {};

Deno.test("Deno HTTP/2 stream failures classify as transient", () => {
  assert(isTransientError(new Error(H2_STREAM_ERROR)));
  assert(
    isTransientError(
      new Error(
        "Favorite player name lookup failed: [status 0] " + H2_STREAM_ERROR,
      ),
    ),
  );
  assert(
    isTransientError(
      "client error (Connect): dns error: failed to lookup address information",
    ),
  );
  assert(
    isTransientError(
      "http2 error: connection error received: not a result of an error",
    ),
  );
});

Deno.test("gateway 5xx / 429 and PostgREST connection codes are transient", () => {
  assert(isTransientError(new Error("Lookup failed: [status 503] <html>")));
  assert(isTransientError(new Error("Lookup failed: [status 429] slow down")));
  assert(
    isTransientError(
      new Error(
        "Lookup failed: [status 500] [code PGRST001] Could not query the database for the schema cache",
      ),
    ),
  );
  assert(
    isTransientError(
      new Error(
        "Lookup failed: [status 500] [code 57014] canceling statement due to statement timeout",
      ),
    ),
  );
  assert(isTransientError(new Error("OneSignal API error: 502 Bad Gateway")));
  assert(isTransientError(new Error("OneSignal API error: 429 {}")));
});

Deno.test("deterministic failures never classify as transient", () => {
  assert(
    !isTransientError(
      new Error(
        "Lookup failed: [status 406] [code PGRST116] JSON object requested, multiple (or no) rows returned",
      ),
    ),
  );
  assert(
    !isTransientError(
      new Error(
        "Lookup failed: [status 400] [code 42703] column games.nope does not exist",
      ),
    ),
  );
  assert(
    !isTransientError(
      new Error('OneSignal API error: 400 {"errors":["Invalid app_id"]}'),
    ),
  );
  assert(!isTransientError(new Error("Dispatch token is not configured")));
  assert(!isTransientError(null));
  assert(!isTransientError(undefined));
  // Bare numbers that happen to match a status or SQLSTATE are not tags.
  assert(
    !isTransientError(
      new Error(
        'Lookup failed: [status 400] [code 22P02] invalid input syntax for type integer: "57014,503"',
      ),
    ),
  );
  // A player name or fide id inside an echoed URL must not trip the classifier.
  assert(
    !isTransientError(
      new Error(
        "Lookup failed: [status 400] [code PGRST100] bad filter fide_id=in.(57014,53300,502)",
      ),
    ),
  );
});

Deno.test("isTransientError walks the cause chain", () => {
  const wrapped = new Error("Favorite map name lookup failed", {
    cause: new TypeError(H2_STREAM_ERROR),
  });
  assert(isTransientError(wrapped));
});

Deno.test("plain PostgREST error objects are classified through their tags", () => {
  assert(isTransientError({ message: "boom", code: "PGRST002", status: 503 }));
  assert(!isTransientError({ message: "boom", code: "PGRST116", status: 406 }));
});

Deno.test("formatPostgrestError tags status and code ahead of the message", () => {
  assertEquals(
    formatPostgrestError({ message: "m", code: "PGRST001" }, 500),
    "[status 500] [code PGRST001] m",
  );
  assertEquals(formatPostgrestError({ message: "m", code: "" }), "m");
  assertEquals(formatPostgrestError({ message: "m" }, 0), "[status 0] m");
});

Deno.test("describeError drops query strings and caps length", () => {
  const described = describeError(new Error(H2_STREAM_ERROR));
  assertStringIncludes(
    described,
    "https://oelbsuggrzyqwzmvidju.supabase.co/rest/v1/user_favorite_players?…",
  );
  assert(!described.includes("player_name=in."));
  assertStringIncludes(described, "http2 error: stream error received");

  const long = describeError(new Error("x".repeat(5000)), 100);
  assertEquals(long.length, 100);
  assert(long.endsWith("…"));

  // Thrown PostgREST objects used to persist as "[object Object]".
  assertEquals(
    describeError({ message: "nope", code: "PGRST116", status: 406 }),
    "[status 406] [code PGRST116] nope",
  );
});

Deno.test("withTransientRetry retries a transient failure and then succeeds", async () => {
  let calls = 0;
  const retries: number[] = [];
  const value = await withTransientRetry("t", () => {
    calls++;
    if (calls < 3) return Promise.reject(new Error(H2_STREAM_ERROR));
    return Promise.resolve("ok");
  }, {
    sleep: noSleep,
    onRetry: (_label, attempt) => retries.push(attempt),
  });
  assertEquals(value, "ok");
  assertEquals(calls, 3);
  assertEquals(retries, [1, 2]);
});

Deno.test("withTransientRetry gives up after the attempt budget with the last error", async () => {
  let calls = 0;
  await assertRejects(
    () =>
      withTransientRetry("t", () => {
        calls++;
        return Promise.reject(new Error(`${H2_STREAM_ERROR} #${calls}`));
      }, { attempts: 3, sleep: noSleep, onRetry: quiet }),
    Error,
    "#3",
  );
  assertEquals(calls, 3);
});

Deno.test("withTransientRetry does not retry deterministic failures", async () => {
  let calls = 0;
  await assertRejects(
    () =>
      withTransientRetry("t", () => {
        calls++;
        return Promise.reject(
          new Error("[status 400] [code 42703] bad column"),
        );
      }, { sleep: noSleep, onRetry: quiet }),
    Error,
    "bad column",
  );
  assertEquals(calls, 1);
});

Deno.test("withTransientRetry backs off exponentially with jitter", async () => {
  const delays: number[] = [];
  let calls = 0;
  await withTransientRetry("t", () => {
    calls++;
    if (calls < 4) return Promise.reject(new Error(H2_STREAM_ERROR));
    return Promise.resolve(1);
  }, {
    attempts: 4,
    baseDelayMs: 100,
    sleep: (ms) => {
      delays.push(ms);
      return Promise.resolve();
    },
    onRetry: quiet,
  });
  assertEquals(delays.length, 3);
  // 100 × 2^(n-1) × [0.5, 1.5)
  assert(delays[0] >= 50 && delays[0] < 150, `first delay ${delays[0]}`);
  assert(delays[1] >= 100 && delays[1] < 300, `second delay ${delays[1]}`);
  assert(delays[2] >= 200 && delays[2] < 600, `third delay ${delays[2]}`);
});

Deno.test("runQuery rebuilds the query per attempt and labels the failure", async () => {
  let builds = 0;
  const data = await runQuery<{ id: string }[]>(
    "Favorite map name lookup",
    () => {
      builds++;
      if (builds === 1) {
        return Promise.resolve({
          data: null,
          error: { message: H2_STREAM_ERROR, code: "" },
          status: 0,
        });
      }
      return Promise.resolve({ data: [{ id: "a" }], error: null, status: 200 });
    },
    { sleep: noSleep, onRetry: quiet },
  );
  assertEquals(data, [{ id: "a" }]);
  assertEquals(builds, 2);

  await assertRejects(
    () =>
      runQuery("Round move lookup", () =>
        Promise.resolve({
          data: null,
          error: { message: "multiple rows", code: "PGRST116" },
          status: 406,
        }), { sleep: noSleep, onRetry: quiet }),
    Error,
    "Round move lookup failed: [status 406] [code PGRST116] multiple rows",
  );
});

Deno.test("runQuerySettled returns deterministic errors and retries transient ones", async () => {
  let builds = 0;
  const settled = await runQuerySettled<{ tc: string }>(
    "Tour tc lookup",
    () => {
      builds++;
      if (builds === 1) {
        return Promise.resolve({
          data: null,
          error: { message: "gateway", code: "" },
          status: 503,
        });
      }
      return Promise.resolve({
        data: { tc: "blitz" },
        error: null,
        status: 200,
      });
    },
    { sleep: noSleep, onRetry: quiet },
  );
  assertEquals(settled.data, { tc: "blitz" });
  assertEquals(builds, 2);

  const deterministic = await runQuerySettled(
    "Tour tc lookup",
    () =>
      Promise.resolve({
        data: null,
        error: { message: "no such column", code: "42703" },
        status: 400,
      }),
    { sleep: noSleep, onRetry: quiet },
  );
  assertEquals(deterministic.error?.message, "no such column");

  const exhausted = await runQuerySettled(
    "Tour tc lookup",
    () =>
      Promise.resolve({
        data: null,
        error: { message: H2_STREAM_ERROR, code: "" },
        status: 0,
      }),
    { attempts: 2, sleep: noSleep, onRetry: quiet },
  );
  assert(exhausted.error);
  assertStringIncludes(exhausted.error.message, "Tour tc lookup failed");
});
