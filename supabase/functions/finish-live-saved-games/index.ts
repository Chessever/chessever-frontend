/**
 * Finishes games that were liked or saved while they were being played
 * (Trello #1387). Such a row holds the moves up to the save and
 * `Result "*"`; once the broadcast is over this adds the rest of the game and
 * its result, keeping everything the reader added (finish.ts).
 *
 * pg_cron starts it every two minutes while there is a row to finish
 * (`kick_finish_live_saved_games`). Every app reads the row from the server,
 * so phone, desktop and chessever.com all show the finished game, old builds
 * included.
 *
 * A row it finished is finished again, from the copy saved before its write,
 * when the game changes afterwards (a result posted before the last moves)
 * and the reader has not touched the row (`live_saved_games_to_finish`).
 *
 * Authenticates with the dispatcher's stream token, so it stays behind
 * `verify_jwt = false` like every function here.
 *
 * Body (all optional): `{ "limit": 50, "dryRun": false, "reprocess": false }`.
 * A dry run reads and merges but writes nothing, and answers with what it
 * would have done. `reprocess` reads every row the job finished and nobody
 * has changed since, from the copy saved before the job's write, and finishes
 * it again: run it by hand once after the merge rules change.
 */
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import {
  type FinishOutcome,
  finishSavedGame,
  type SavedChessGame,
} from "./finish.ts";

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

// An edge worker has little CPU: 555 full games in one call ran out of it
// (WORKER_RESOURCE_LIMIT, 2026-11-14). The cron runs every two minutes, so
// 50 a run is still 1,500 an hour.
const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 100;
/** Rows not reached inside the budget wait for the next run. */
const WRITE_BUDGET_MS = 100_000;
const jsonHeaders = { "Content-Type": "application/json" };

interface CandidateRow {
  id: string;
  source_game_id: string | null;
  chess_game: SavedChessGame;
  variation_comments: Record<string, unknown> | null;
  move_nags: Record<string, unknown> | null;
  updated_at: string;
  game_id: string;
  pgn: string;
  status: string;
  /** games.live_ply_count (0: not known). */
  game_plies: number;
  /** Finished before; its game changed since. */
  refinish: boolean;
}

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

async function readBody(
  req: Request,
): Promise<{ limit: number; dryRun: boolean; reprocess: boolean }> {
  let body: Record<string, unknown> = {};
  try {
    const parsed = await req.json();
    if (parsed && typeof parsed === "object") {
      body = parsed as Record<string, unknown>;
    }
  } catch {
    // An empty body is the cron's call.
  }
  const asked = Number(body.limit);
  const limit = Number.isFinite(asked) && asked > 0
    ? Math.min(Math.floor(asked), MAX_LIMIT)
    : DEFAULT_LIMIT;
  return {
    limit,
    dryRun: body.dryRun === true,
    reprocess: body.reprocess === true,
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }
  const token = await streamToken();
  if (!token || req.headers.get("x-stream-token") !== token) {
    return new Response("Unauthorized", { status: 401 });
  }

  const { limit, dryRun, reprocess } = await readBody(req);
  const { data, error } = await supabase.rpc(
    reprocess ? "live_saved_games_to_reprocess" : "live_saved_games_to_finish",
    { p_limit: limit },
  );
  if (error) {
    console.error(`[finish-live-saved-games] read failed: ${error.message}`);
    return json({ error: "read_failed" }, 500);
  }
  const rows = (data ?? []) as CandidateRow[];

  const outcomes: Partial<Record<FinishOutcome | "skipped", number>> = {};
  let restored = 0;
  let written = 0;
  let changedMeanwhile = 0;
  let failed = 0;
  let addedMoves = 0;
  let refinished = 0;
  const deadline = Date.now() + WRITE_BUDGET_MS;

  for (const row of rows) {
    if (Date.now() > deadline) break;
    let finished: ReturnType<typeof finishSavedGame> = null;
    try {
      finished = finishSavedGame(
        row,
        row.pgn ?? "",
        row.status,
        row.game_plies ?? 0,
      );
    } catch (e) {
      console.error(
        `[finish-live-saved-games] merge failed for ${row.id}: ${e}`,
      );
    }
    const outcome = finished?.outcome ?? "skipped";
    outcomes[outcome] = (outcomes[outcome] ?? 0) + 1;
    // What is written. A row that cannot be shown as the game keeps its
    // saved moves: a fresh one is left alone, and one the job finished
    // before (`row.chess_game` is then the copy saved before that write) is
    // put back.
    let write: { outcome: string; chessGame: SavedChessGame | null };
    if (!finished) {
      write = { outcome: "skipped", chessGame: null };
    } else if (finished.outcome === "unjoinable") {
      write = row.refinish
        ? { outcome: "restored", chessGame: row.chess_game }
        : { outcome: "skipped", chessGame: null };
    } else {
      write = { outcome: finished.outcome, chessGame: finished.chessGame };
      addedMoves += finished.chessGame.m.length -
        (row.chess_game?.m?.length ?? 0);
    }
    if (dryRun) continue;

    const { data: wrote, error: writeError } = await supabase.rpc(
      "finish_live_saved_game",
      {
        p_id: row.id,
        p_expected_updated_at: row.updated_at,
        p_game_id: row.game_id,
        p_outcome: write.outcome,
        p_chess_game: write.chessGame,
        p_game_plies: row.game_plies ?? 0,
      },
    );
    if (writeError) {
      failed++;
      console.error(
        `[finish-live-saved-games] write failed for ${row.id}: ${writeError.message}`,
      );
    } else if (wrote === true) {
      written++;
      if (row.refinish) refinished++;
      if (write.outcome === "restored") restored++;
    } else {
      changedMeanwhile++;
    }
  }

  const summary = {
    dryRun,
    reprocess,
    rows: rows.length,
    outcomes,
    addedMoves,
    written,
    changedMeanwhile,
    refinished,
    restored,
    failed,
  };
  if (rows.length > 0) {
    console.log(`[finish-live-saved-games] ${JSON.stringify(summary)}`);
  }
  return json(summary, failed > 0 ? 500 : 200);
});
