/**
 * Tells owners of starred My Prep players, the same day and while they are
 * awake, that the player is playing online. pg_cron starts it hourly
 * (kick_prep_games_check). Each run reads every starred account's game
 * totals (counts.ts), records them (record_prep_watch_checks adds any growth
 * to the owner's day), then queue_prep_games_pushes sends at most one push
 * per owner: twice a day at most, four hours apart, never at night.
 *
 * Authenticates with the dispatcher's stream token, so it stays behind
 * `verify_jwt = false` like every function here.
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  chessComTotals,
  lichessReadings,
  planChecks,
  type Reading,
  type WatchRow,
} from "./counts.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  Deno.env.get("SERVICE_ROLE_KEY") ??
  "";
if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error("Missing Supabase environment variables.");
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const ACCOUNTS_PER_RUN = 2000;
/** Sites are read one request at a time; what is left waits an hour. */
const READ_BUDGET_MS = 90_000;
const LICHESS_BATCH = 300;
const USER_AGENT = "ChessEver/1.0 (+https://chessever.com; prep check)";
const jsonHeaders = { "Content-Type": "application/json" };

let tokenCache: { token: string; expiresAtMs: number } | null = null;

async function streamToken(): Promise<string | null> {
  const now = Date.now();
  if (tokenCache && tokenCache.expiresAtMs > now) return tokenCache.token;
  const { data, error } = await supabase.rpc("get_vault_secret", {
    secret_name: "live_dispatch_token",
  });
  if (error || typeof data !== "string" || data.length === 0) return null;
  tokenCache = { token: data, expiresAtMs: now + 60_000 };
  return data;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }
  const token = await streamToken();
  if (!token || req.headers.get("x-stream-token") !== token) {
    return new Response("Unauthorized", { status: 401 });
  }

  const { data, error } = await supabase.rpc("prep_watches_to_check", {
    p_limit: ACCOUNTS_PER_RUN,
  });
  if (error) {
    console.error(`[prep-games-check] watch lookup failed: ${error.message}`);
    return json({ error: "watch_lookup_failed" }, 500);
  }
  const rows = (data ?? []) as WatchRow[];
  if (rows.length === 0) return json({ accounts: 0 });

  const deadline = Date.now() + READ_BUDGET_MS;
  const names = (source: string) => [
    ...new Set(
      rows.filter((r) => r.source === source).map((r) =>
        r.username.toLowerCase()
      ),
    ),
  ];
  const lichess = await readLichess(names("lichess"), deadline);
  const chesscom = await readChessCom(names("chesscom"), deadline);
  const checks = planChecks(
    rows,
    (row) =>
      (row.source === "lichess" ? lichess : chesscom).get(
        row.username.toLowerCase(),
      ),
  );

  let recorded = 0;
  if (checks.length > 0) {
    const { data: count, error: recordError } = await supabase.rpc(
      "record_prep_watch_checks",
      { p_checks: checks },
    );
    if (recordError) {
      console.error(
        `[prep-games-check] record failed: ${recordError.message}`,
      );
      return json({ error: "record_failed" }, 500);
    }
    recorded = typeof count === "number" ? count : 0;
  }

  // Also sends what earlier runs found while the owner slept or waited out
  // the four hours, so it runs even when this hour found nothing new.
  const { data: queued, error: queueError } = await supabase.rpc(
    "queue_prep_games_pushes",
  );
  if (queueError) {
    console.error(`[prep-games-check] queue failed: ${queueError.message}`);
    return json({ error: "queue_failed", recorded }, 500);
  }

  return json({
    accounts: rows.length,
    read: lichess.size + chesscom.size,
    recorded,
    queued: typeof queued === "number" ? queued : 0,
  });
});

/**
 * Lichess, 300 players a request. Lichess asks that a 429 be followed by a
 * full minute's pause, so one ends the reading for this run.
 */
async function readLichess(
  ids: string[],
  deadline: number,
): Promise<Map<string, Reading>> {
  const readings = new Map<string, Reading>();
  for (let i = 0; i < ids.length; i += LICHESS_BATCH) {
    if (Date.now() > deadline) break;
    const batch = ids.slice(i, i + LICHESS_BATCH);
    try {
      const res = await fetch("https://lichess.org/api/users", {
        method: "POST",
        headers: { "Content-Type": "text/plain", "User-Agent": USER_AGENT },
        body: batch.join(","),
      });
      if (!res.ok) {
        await res.body?.cancel();
        console.warn(`[prep-games-check] lichess answered ${res.status}`);
        break;
      }
      for (const [id, reading] of lichessReadings(batch, await res.json())) {
        readings.set(id, reading);
      }
    } catch (error) {
      console.warn(`[prep-games-check] lichess unreachable: ${error}`);
      break;
    }
  }
  return readings;
}

/**
 * Chess.com, one player at a time: serial requests are never limited there,
 * parallel ones may be. 404 and 410 mean the account is gone; anything else
 * that fails is tried again next hour.
 */
async function readChessCom(
  names: string[],
  deadline: number,
): Promise<Map<string, Reading>> {
  const readings = new Map<string, Reading>();
  for (const name of names) {
    if (Date.now() > deadline) break;
    try {
      const res = await fetch(
        `https://api.chess.com/pub/player/${encodeURIComponent(name)}/stats`,
        { headers: { "User-Agent": USER_AGENT } },
      );
      if (res.status === 404 || res.status === 410) {
        await res.body?.cancel();
        readings.set(name, { kind: "missing" });
        continue;
      }
      if (!res.ok) {
        await res.body?.cancel();
        console.warn(`[prep-games-check] chess.com answered ${res.status}`);
        if (res.status === 429) break;
        continue;
      }
      readings.set(name, {
        kind: "totals",
        totals: chessComTotals(await res.json()),
      });
    } catch (error) {
      console.warn(`[prep-games-check] chess.com unreachable: ${error}`);
    }
  }
  return readings;
}
