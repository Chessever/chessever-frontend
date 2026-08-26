import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const TABLE_NAME = "lichess_move_annotations_cache";
const USER_AGENT = "chessever.com";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, " +
    "x-lichess-annotations-refresh-token",
};

type AnnotationPayload = { name: string; comment: string };

/// Whether the caller may bypass the cache.
///
/// This endpoint is reachable without a session (gateway verification is off
/// project-wide), so an unauthenticated `force_refresh=true` would let anyone
/// make us call Lichess on every request, spending our LICHESS_API_TOKEN's
/// rate limit at will. Mirrors the fide-photo function's refresh gate.
///
/// Fails closed: with no secret configured, nobody may force a refresh.
///
/// Withholding this costs correctness nothing. A cached row is only returned
/// when its `moves_signature` matches the caller's, so a game whose moves have
/// changed is re-fetched regardless of this flag.
function hasRefreshPermission(req: Request): boolean {
  const expected = Deno.env.get("LICHESS_ANNOTATIONS_REFRESH_TOKEN") ?? "";
  if (!expected) return false;

  const headerToken =
    req.headers.get("x-lichess-annotations-refresh-token") ?? "";
  const authorization = req.headers.get("authorization") ?? "";
  const [scheme, bearer] = authorization.split(" ");

  return headerToken === expected ||
    (scheme?.toLowerCase() === "bearer" && bearer === expected);
}

function buildSignature(moves: string[]): string {
  return `${moves.length}:${moves.join("|")}`;
}

// Extract annotations from Lichess JSON analysis (for regular games)
function extractAnnotationsFromJson(analysis: unknown): Record<string, AnnotationPayload> {
  if (!Array.isArray(analysis)) return {};
  const annotations: Record<string, AnnotationPayload> = {};
  for (let i = 0; i < analysis.length; i++) {
    const entry = analysis[i];
    if (!entry || typeof entry !== "object") continue;
    const judgment = (entry as Record<string, unknown>).judgment;
    if (!judgment || typeof judgment !== "object") continue;
    const name = (judgment as Record<string, unknown>).name;
    const comment = (judgment as Record<string, unknown>).comment;
    if (typeof name !== "string") continue;
    annotations[String(i)] = {
      name,
      comment: typeof comment === "string" ? comment : "",
    };
  }
  return annotations;
}

// Extract annotations from PGN comments (for broadcast/study games)
// Format: move { [%eval X.XX] } { Inaccuracy. Bxh4 was best. } { [%clk ...] }
function extractAnnotationsFromPgn(pgn: string): { moves: string[], annotations: Record<string, AnnotationPayload> } {
  const annotations: Record<string, AnnotationPayload> = {};
  const moves: string[] = [];

  // Remove headers (lines starting with [)
  const lines = pgn.split('\n');
  const moveLines = lines.filter(line => !line.trim().startsWith('[') && line.trim().length > 0);
  const moveSection = moveLines.join(' ');

  // Split by move numbers to process each move with its comments
  // This handles: "1. e4 { comments } e5 { comments } 2. Nf3 { comments }"
  const tokens = moveSection.split(/(\d+\.+|\{[^}]*\})/g).filter(t => t.trim());

  let currentMoveIndex = 0;
  let lastWasMove = false;

  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i].trim();
    if (!token) continue;

    // Skip move numbers like "1." or "1..."
    if (/^\d+\.+$/.test(token)) {
      continue;
    }

    // Check if it's a comment
    if (token.startsWith('{') && token.endsWith('}')) {
      const comment = token.slice(1, -1).trim();

      // Check for annotation keywords
      const inaccuracyMatch = comment.match(/^Inaccuracy\.\s*(.+)$/i);
      const mistakeMatch = comment.match(/^Mistake\.\s*(.+)$/i);
      const blunderMatch = comment.match(/^Blunder\.\s*(.+)$/i);

      // Associate annotation with the previous move
      const annotationIndex = currentMoveIndex - 1;
      if (annotationIndex >= 0) {
        if (blunderMatch) {
          annotations[String(annotationIndex)] = {
            name: "Blunder",
            comment: `Blunder. ${blunderMatch[1].trim()}`,
          };
        } else if (mistakeMatch) {
          annotations[String(annotationIndex)] = {
            name: "Mistake",
            comment: `Mistake. ${mistakeMatch[1].trim()}`,
          };
        } else if (inaccuracyMatch) {
          annotations[String(annotationIndex)] = {
            name: "Inaccuracy",
            comment: `Inaccuracy. ${inaccuracyMatch[1].trim()}`,
          };
        }
      }
      lastWasMove = false;
    } else {
      // It should be a move - extract just the move part (remove ?! markers and results)
      const moveMatch = token.match(/^([KQRBN]?[a-h]?[1-8]?x?[a-h][1-8](?:=[QRBN])?|O-O-O|O-O)/);
      if (moveMatch) {
        moves.push(moveMatch[1]);
        currentMoveIndex++;
        lastWasMove = true;
      } else if (token === '1-0' || token === '0-1' || token === '1/2-1/2' || token === '*') {
        // Game result - ignore
        continue;
      }
    }
  }

  return { moves, annotations };
}

// Parse broadcast URL to extract roundId and gameId
// Format: https://lichess.org/broadcast/{slug}/{roundSlug}/{roundId}/{gameId}
function parseBroadcastUrl(siteUrl: string): { roundId: string | null; gameId: string | null } {
  const match = siteUrl.match(/lichess\.org\/broadcast\/[^/]+\/[^/]+\/([a-zA-Z0-9]{8})\/([a-zA-Z0-9]{8})/);
  if (match) {
    return { roundId: match[1], gameId: match[2] };
  }
  return { roundId: null, gameId: null };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const url = new URL(req.url);
    let gameId = url.searchParams.get("game_id");
    let roundId = url.searchParams.get("round_id");
    let siteUrl = url.searchParams.get("site_url");
    let forceRefresh = url.searchParams.get("force_refresh") === "true";
    let movesSignature = url.searchParams.get("moves_signature") ?? null;
    let moves: string[] | null = null;

    if (req.method === "POST") {
      const body = await req.json().catch(() => ({}));
      if (body && typeof body === "object") {
        const payload = body as Record<string, unknown>;
        gameId = gameId || (typeof payload.game_id === "string" ? payload.game_id : null);
        roundId = roundId || (typeof payload.round_id === "string" ? payload.round_id : null);
        siteUrl = siteUrl || (typeof payload.site_url === "string" ? payload.site_url : null);
        forceRefresh = forceRefresh || payload.force_refresh === true;
        movesSignature = movesSignature ||
          (typeof payload.moves_signature === "string" ? payload.moves_signature : null);
        if (Array.isArray(payload.moves)) {
          moves = payload.moves.map((move) => String(move));
        }
      }
    }

    // Downgrade rather than reject: the app never asks for a refresh, so a 403
    // here could only ever break a caller without protecting anything extra.
    // Ignoring the flag already removes the abuse — no Lichess call is made.
    if (forceRefresh && !hasRefreshPermission(req)) {
      console.warn(
        `Ignoring unauthorized force_refresh for game_id=${gameId ?? "unknown"}`,
      );
      forceRefresh = false;
    }

    // Try to extract roundId and gameId from site_url if not provided
    if (siteUrl && (!roundId || !gameId)) {
      const parsed = parseBroadcastUrl(siteUrl);
      roundId = roundId || parsed.roundId;
      gameId = gameId || parsed.gameId;
    }

    if (!gameId) {
      return new Response(
        JSON.stringify({ error: "Missing game_id parameter" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    if (!movesSignature && moves && moves.length > 0) {
      movesSignature = buildSignature(moves);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !supabaseServiceKey) {
      return new Response(
        JSON.stringify({ error: "Missing Supabase environment variables" }),
        {
          status: 500,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Check cache first
    if (!forceRefresh) {
      const { data: cached, error: cacheError } = await supabase
        .from(TABLE_NAME)
        .select("game_id,moves,moves_signature,move_count,annotations,fetched_at")
        .eq("game_id", gameId)
        .maybeSingle();

      if (cacheError) {
        console.error("Cache read error:", cacheError);
      } else if (cached) {
        if (!movesSignature || cached.moves_signature === movesSignature) {
          return new Response(
            JSON.stringify({
              game_id: cached.game_id,
              moves: cached.moves,
              move_count: cached.move_count,
              moves_signature: cached.moves_signature,
              annotations: cached.annotations ?? {},
              cached: true,
              fetched_at: cached.fetched_at,
            }),
            {
              headers: { ...corsHeaders, "Content-Type": "application/json" },
            }
          );
        }
      }
    }

    const lichessToken = Deno.env.get("LICHESS_API_TOKEN");
    const headers: HeadersInit = {
      "User-Agent": USER_AGENT,
    };
    if (lichessToken) {
      headers.Authorization = `Bearer ${lichessToken}`;
    }

    let movesText = "";
    let moveList: string[] = [];
    let annotations: Record<string, AnnotationPayload> = {};

    // Try broadcast/study endpoint first if we have roundId
    if (roundId) {
      const studyUrl = `https://lichess.org/api/study/${roundId}/${gameId}.pgn`;
      headers.Accept = "application/x-chess-pgn";
      const studyResp = await fetch(studyUrl, { headers });

      if (studyResp.ok) {
        const pgnText = await studyResp.text();
        const parsed = extractAnnotationsFromPgn(pgnText);
        moveList = parsed.moves;
        annotations = parsed.annotations;
        movesText = moveList.join(" ");
      }
    }

    // Fall back to regular game export if study failed or no roundId
    if (moveList.length === 0) {
      headers.Accept = "application/json";
      const lichessUrl = `https://lichess.org/game/export/${gameId}?evals=true`;
      const lichessResp = await fetch(lichessUrl, { headers });

      if (!lichessResp.ok) {
        return new Response(
          JSON.stringify({
            error: "Failed to fetch Lichess analysis",
            status: lichessResp.status,
            hint: roundId ? "Both study and game export failed" : "No round_id provided for broadcast game",
          }),
          {
            status: 502,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      const payload = await lichessResp.json();
      movesText = payload && typeof payload.moves === "string" ? payload.moves : "";
      moveList = movesText.trim().length > 0 ? movesText.trim().split(" ") : [];
      const analysis = payload?.analysis ?? [];
      annotations = extractAnnotationsFromJson(analysis);
    }

    const computedSignature = buildSignature(moveList);

    if (movesSignature && movesSignature !== computedSignature) {
      return new Response(
        JSON.stringify({
          game_id: gameId,
          moves: movesText,
          move_count: moveList.length,
          moves_signature: computedSignature,
          annotations,
          cached: false,
          mismatch: true,
        }),
        {
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // Cache the result
    const now = new Date().toISOString();
    const { error: upsertError } = await supabase
      .from(TABLE_NAME)
      .upsert({
        game_id: gameId,
        moves: movesText,
        moves_signature: computedSignature,
        move_count: moveList.length,
        annotations,
        fetched_at: now,
        updated_at: now,
      });

    if (upsertError) {
      console.error("Cache upsert error:", upsertError);
    }

    return new Response(
      JSON.stringify({
        game_id: gameId,
        moves: movesText,
        move_count: moveList.length,
        moves_signature: computedSignature,
        annotations,
        cached: false,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
