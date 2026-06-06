import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { Chess } from "npm:chess.js@1.0.0";

type LiveSubscriptionRow = {
  user_id: string;
  game_id: string;
  platform: "ios" | "android";
  started_at: string | null;
  last_event_at: string | null;
};

type GameRow = {
  id: string;
  tour_id: string | null;
  round_id: string | null;
  player_white: string | null;
  player_black: string | null;
  player_fide_ids: Array<number | string> | null;
  fen: string | null;
  players: Record<string, unknown>[] | null;
  status: string | null;
  last_move: string | null;
  last_move_time: string | null;
  last_clock_white: number | null;
  last_clock_black: number | null;
};

type RoundRow = {
  id: string;
  tour_id: string | null;
  name: string | null;
};

type TourRow = {
  id: string;
  name: string | null;
  group_broadcast_id: string | null;
};

type GroupBroadcastRow = {
  id: string;
  name: string | null;
};

type UserBoardSettings = {
  board_theme_index: number | null;
  piece_style_index: number | null;
};

type PositionRow = {
  id: number | string;
  fen: string;
};

type EvalRow = {
  position_id: number | string;
  depth: number | null;
  pvs: unknown;
  multi_pv?: number | null;
  pvs_count?: number | null;
};

type EvalSnapshot = {
  cp: number | null;
  mate: number | null;
  depth: number | null;
};

type LiveUpdatePayload = {
  game_id: string;
  fen: string | null;
  last_move: string | null;
  last_move_uci: string | null;
  last_move_san: string | null;
  last_move_numbered: string | null;
  last_move_time: string | null;
  white_clock_seconds: number | null;
  black_clock_seconds: number | null;
  clock_anchor_time: string | null;
  active_clock_color: "white" | "black" | null;
  active_clock_deadline: string | null;
  eval_cp: number | null;
  eval_mate: number | null;
  board_theme_index: number | null;
  piece_style_index: number | null;
  player_white: string;
  player_black: string;
  event_name: string | null;
  round_name: string | null;
  white_fide_id: number | null;
  black_fide_id: number | null;
  white_photo: string | null;
  black_photo: string | null;
  white_title: string | null;
  black_title: string | null;
  white_fed: string | null;
  black_fed: string | null;
  white_flag: string | null;
  black_flag: string | null;
  is_check: boolean;
  is_checkmate: boolean;
  is_game_over: boolean;
  follow_live: boolean;
  status: string | null;
  refresh_ts: number;
};

type RefreshStatus =
  | "updated"
  | "throttled"
  | "ended"
  | "disabled_missing_game"
  | "disabled_not_live_status"
  | "disabled_stale"
  | "not_found"
  | "error";

type RefreshResult = {
  status: RefreshStatus;
  gameId: string;
  userId: string;
  error?: string;
  debug?: RefreshDebug;
};

type RefreshDebug = {
  payload: Record<string, unknown>;
  dryRun?: boolean;
  oneSignal?: {
    ok: boolean;
    notFound: boolean;
    status: number;
    body?: string;
  };
  delivery?: unknown;
};

type OneSignalResult = {
  ok: boolean;
  notFound: boolean;
  status: number;
  errorText?: string;
  responseText?: string;
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
  Deno.env.get("SERVICE_ROLE_KEY") ??
  "";
const ONESIGNAL_APP_ID = Deno.env.get("ONESIGNAL_APP_ID") ?? "";
const ONESIGNAL_REST_API_KEY = Deno.env.get("ONESIGNAL_REST_API_KEY") ?? "";

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error("Missing Supabase environment variables.");
}
if (!ONESIGNAL_APP_ID || !ONESIGNAL_REST_API_KEY) {
  throw new Error("Missing OneSignal environment variables.");
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const jsonHeaders = { "Content-Type": "application/json" };
const DEFAULT_LIMIT = readIntEnv("LIVE_ACTIVITY_REFRESH_LIMIT", 100, 1, 500);
const MAX_LIMIT = readIntEnv("LIVE_ACTIVITY_REFRESH_MAX_LIMIT", 500, 1, 1000);
const MIN_INTERVAL_MS = readIntEnv(
  "LIVE_ACTIVITY_REFRESH_MIN_INTERVAL_MS",
  250,
  0,
  60_000,
);
const FRESH_WINDOW_MS = readIntEnv(
  "LIVE_ACTIVITY_FRESH_WINDOW_MS",
  3 * 60 * 60 * 1000,
  60_000,
  24 * 60 * 60 * 1000,
);
const CONCURRENCY = readIntEnv("LIVE_ACTIVITY_REFRESH_CONCURRENCY", 5, 1, 20);
const UPDATE_PRIORITY = normalizeLiveActivityPriority(
  readIntEnv("LIVE_ACTIVITY_UPDATE_PRIORITY", 10, 5, 10),
);
// MOVE-ONLY delivery: we push a Live Activity update ONLY when a new move lands,
// always at priority 10 (immediate + guaranteed). There are NO between-move clock
// nudges — clocks were removed from the widget (they were unreliable, and the
// interim pushes just burned Apple's high-priority budget and delayed real moves).
// This keeps push volume to ~1 per move so every move is delivered.
// Android Live Notifications (silent, rendered by the app's NotificationService-
// Extension) are sent straight from this function via the OneSignal Create Message
// API — on a REAL MOVE only (Android's notification chronometer ticks the clock
// locally, so there are no between-move nudges). Defaults OFF so deploying this
// cannot touch a single Android user until it is explicitly enabled and verified
// on a device. LIVE_ACTIVITY_ANDROID_ENABLED="true" turns it on; it is the kill
// switch. These are NEVER the notification-outbox / sendLiveGameAlert path that
// flooded users on 2026-06-06.
const ANDROID_ENABLED =
  (Deno.env.get("LIVE_ACTIVITY_ANDROID_ENABLED") ?? "false").toLowerCase() ===
    "true";
const LIVE_ACTIVITY_REFRESH_ALLOWED_KEYS = parseAllowedKeys(
  Deno.env.get("LIVE_ACTIVITY_REFRESH_ALLOWED_KEYS") ?? "",
);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: jsonHeaders });
  }
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }
  if (!isAuthorized(req)) {
    return new Response("Unauthorized", { status: 401 });
  }

  try {
    const options = await resolveRequestOptions(req);
    const selected = await selectSubscriptions(options);
    const context = await buildRefreshContext(selected.candidates);

    const results = await mapWithConcurrency(
      selected.candidates,
      options.concurrency,
      (row) => refreshSubscription(row, context, options),
    );

    return jsonResponse({
      checked: selected.candidates.length,
      fetched: selected.fetched,
      skippedThrottle: selected.skippedThrottle,
      dryRun: options.dryRun,
      ...summarize(results),
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, 500);
  }
});

async function resolveRequestOptions(req: Request) {
  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch (_) {
    body = {};
  }

  const requestedLimit = parseFiniteInt(body.limit);
  const limit = clamp(
    requestedLimit ?? DEFAULT_LIMIT,
    1,
    Math.min(MAX_LIMIT, 1000),
  );
  const requestedConcurrency = parseFiniteInt(body.concurrency);
  const concurrency = clamp(requestedConcurrency ?? CONCURRENCY, 1, 20);
  const requestedMinInterval = parseFiniteInt(body.min_interval_ms);
  const minIntervalMs = clamp(
    requestedMinInterval ?? MIN_INTERVAL_MS,
    0,
    60_000,
  );
  const gameId = typeof body.game_id === "string" && body.game_id.trim()
    ? body.game_id.trim()
    : null;

  return {
    limit,
    concurrency,
    minIntervalMs,
    gameId,
    dryRun: body.dry_run === true,
    debug: body.debug === true,
    force: body.force === true,
    nowMs: Date.now(),
  };
}

async function selectSubscriptions(options: {
  limit: number;
  minIntervalMs: number;
  gameId: string | null;
  nowMs: number;
}) {
  const fetchLimit = Math.min(options.limit * 4, Math.max(options.limit, 1000));
  const platforms = ANDROID_ENABLED ? ["ios", "android"] : ["ios"];
  let query = supabase
    .from("user_live_game_subscriptions")
    .select("user_id,game_id,platform,started_at,last_event_at")
    .eq("enabled", true)
    .in("platform", platforms);

  if (options.gameId) {
    query = query.eq("game_id", options.gameId);
  }

  const { data, error } = await query
    .order("last_event_at", { ascending: true })
    .limit(fetchLimit);

  if (error) throw error;

  const rows = ((data ?? []) as LiveSubscriptionRow[])
    .filter((row) => row.user_id && row.game_id);
  const candidates: LiveSubscriptionRow[] = [];
  let skippedThrottle = 0;

  for (const row of rows) {
    const lastEventMs = parseDateMs(row.last_event_at);
    if (
      lastEventMs !== null &&
      options.nowMs - lastEventMs < options.minIntervalMs
    ) {
      skippedThrottle += 1;
      continue;
    }
    candidates.push(row);
    if (candidates.length >= options.limit) break;
  }

  return {
    candidates,
    fetched: rows.length,
    skippedThrottle,
  };
}

async function buildRefreshContext(rows: LiveSubscriptionRow[]) {
  const gameIds = unique(rows.map((row) => row.game_id));
  const games = await fetchGames(gameIds);
  const roundIds = unique(
    Array.from(games.values())
      .map((game) => game.round_id)
      .filter(isNonEmptyString),
  );
  const tourIds = unique(
    Array.from(games.values())
      .map((game) => game.tour_id)
      .filter(isNonEmptyString),
  );

  const rounds = await fetchRounds(roundIds);
  for (const round of rounds.values()) {
    if (round.tour_id) tourIds.push(round.tour_id);
  }

  const tours = await fetchTours(unique(tourIds));
  const groupBroadcastIds = unique(
    Array.from(tours.values())
      .map((tour) => tour.group_broadcast_id)
      .filter(isNonEmptyString),
  );
  const groupBroadcasts = await fetchGroupBroadcasts(groupBroadcastIds);
  const boardSettings = await fetchBoardSettings(
    unique(rows.map((row) => row.user_id)),
  );
  const evalSnapshots = await fetchEvalSnapshots(
    unique(
      Array.from(games.values())
        .map((game) => game.fen)
        .filter(isNonEmptyString),
    ),
  );

  return {
    games,
    rounds,
    tours,
    groupBroadcasts,
    boardSettings,
    evalSnapshots,
  };
}

async function refreshSubscription(
  row: LiveSubscriptionRow,
  context: Awaited<ReturnType<typeof buildRefreshContext>>,
  options: {
    dryRun: boolean;
    debug: boolean;
    force?: boolean;
    nowMs: number;
  },
): Promise<RefreshResult> {
  const game = context.games.get(row.game_id) ?? null;
  if (!game) {
    await disableLiveSubscription(row);
    return {
      status: "disabled_missing_game",
      gameId: row.game_id,
      userId: row.user_id,
    };
  }

  const activityId = buildLiveActivityId(row.game_id, row.user_id);
  const round = game.round_id
    ? context.rounds.get(game.round_id) ?? null
    : null;
  const tourId = game.tour_id ?? round?.tour_id ?? null;
  const tour = tourId ? context.tours.get(tourId) ?? null : null;
  const groupBroadcast = tour?.group_broadcast_id
    ? context.groupBroadcasts.get(tour.group_broadcast_id) ?? null
    : null;
  const settings = context.boardSettings.get(row.user_id) ?? null;
  const payload = buildLiveUpdatePayload({
    game,
    round,
    tour,
    groupBroadcast,
    settings,
    evalSnapshots: context.evalSnapshots,
    nowMs: options.nowMs,
  });

  // Android is served by a silent Create-Message live notification, not the
  // iOS ActivityKit endpoint. Same freshness/ghost-sub gates, different transport.
  if (row.platform === "android") {
    return await refreshAndroidSubscription(row, game, payload, options);
  }

  if (isGameOverStatus(game.status)) {
    if (!options.dryRun) {
      const updateResult = await sendLiveActivityUpdate(activityId, payload);
      if (updateResult.notFound) {
        await disableLiveSubscription(row);
        return {
          status: "not_found",
          gameId: row.game_id,
          userId: row.user_id,
        };
      }
      if (!updateResult.ok) {
        return errorResult(row, updateResult, "final update failed");
      }

      const endResult = await sendLiveActivityEnd(activityId, payload);
      if (endResult.notFound) {
        await disableLiveSubscription(row);
        return {
          status: "not_found",
          gameId: row.game_id,
          userId: row.user_id,
        };
      }
      if (!endResult.ok) {
        return errorResult(row, endResult, "end failed");
      }
      await disableLiveSubscription(row);
    }
    return { status: "ended", gameId: row.game_id, userId: row.user_id };
  }

  if (!isOngoingStatus(game.status)) {
    await disableLiveSubscription(row);
    return {
      status: "disabled_not_live_status",
      gameId: row.game_id,
      userId: row.user_id,
    };
  }

  const lastMoveMs = parseDateMs(game.last_move_time);
  if (lastMoveMs === null || options.nowMs - lastMoveMs > FRESH_WINDOW_MS) {
    if (!options.dryRun) {
      await sendLiveActivityEnd(activityId);
      await disableLiveSubscription(row);
    }
    return {
      status: "disabled_stale",
      gameId: row.game_id,
      userId: row.user_id,
    };
  }

  if (options.dryRun) {
    return {
      status: "updated",
      gameId: row.game_id,
      userId: row.user_id,
      ...(options.debug
        ? { debug: { payload: debugPayloadSnapshot(payload), dryRun: true } }
        : {}),
    };
  }

  // Move-only, full priority: push ONLY when a new move landed, ALWAYS at
  // priority 10 (immediate + guaranteed delivery). No between-move clock nudges —
  // interim updates were removed (clocks are gone from the widget; the nudges just
  // burned Apple's budget and delayed real moves).
  const lastEventMs = parseDateMs(row.last_event_at);
  const moved = lastEventMs === null || lastMoveMs > lastEventMs;
  if (!moved && !options.force) {
    return { status: "throttled", gameId: row.game_id, userId: row.user_id };
  }

  const updateResult = await sendLiveActivityUpdate(
    activityId,
    payload,
    10,
  );
  if (updateResult.notFound) {
    await disableLiveSubscription(row);
    return { status: "not_found", gameId: row.game_id, userId: row.user_id };
  }
  if (!updateResult.ok) {
    return errorResult(row, updateResult, "update failed");
  }

  await markLiveSubscriptionEvent(row);
  let delivery: unknown = undefined;
  if (options.debug) {
    const notifId = parseNotificationId(updateResult.responseText);
    if (notifId) {
      await sleep(2000);
      delivery = await fetchLiveActivityDelivery(notifId);
    }
  }
  return {
    status: "updated",
    gameId: row.game_id,
    userId: row.user_id,
    ...(options.debug
      ? {
        debug: {
          payload: debugPayloadSnapshot(payload),
          oneSignal: debugOneSignalResult(updateResult),
          delivery,
        },
      }
      : {}),
  };
}

// ---------------------------------------------------------------------------
// Android Live Notification path (silent, NSE-rendered). On-move only.
// ---------------------------------------------------------------------------
async function refreshAndroidSubscription(
  row: LiveSubscriptionRow,
  game: GameRow,
  payload: LiveUpdatePayload,
  options: { dryRun: boolean; debug: boolean; force?: boolean; nowMs: number },
): Promise<RefreshResult> {
  // Finished game → one final "end" notification (shows the result, dismissable),
  // then disable the sub.
  if (isGameOverStatus(game.status)) {
    if (!options.dryRun) {
      const endResult = await sendAndroidLiveNotification(row, payload, "end");
      if (!endResult.ok && !endResult.notFound) {
        return errorResult(row, endResult, "android end failed");
      }
      await disableLiveSubscription(row);
    }
    return { status: "ended", gameId: row.game_id, userId: row.user_id };
  }

  if (!isOngoingStatus(game.status)) {
    await disableLiveSubscription(row);
    return {
      status: "disabled_not_live_status",
      gameId: row.game_id,
      userId: row.user_id,
    };
  }

  // Ghost-sub guard: never push for a game whose last move is stale (this is the
  // gate that, together with isOngoing, prevents the 2026-06-06 flood class of bug).
  const lastMoveMs = parseDateMs(game.last_move_time);
  if (lastMoveMs === null || options.nowMs - lastMoveMs > FRESH_WINDOW_MS) {
    if (!options.dryRun) {
      await sendAndroidLiveNotification(row, payload, "end");
      await disableLiveSubscription(row);
    }
    return {
      status: "disabled_stale",
      gameId: row.game_id,
      userId: row.user_id,
    };
  }

  // Android's clock ticks LOCALLY via the notification chronometer, so — unlike
  // iOS — we never send between-move clock nudges. Push ONLY on a real move (it
  // redraws the board and re-anchors the clock). Keeps Android push volume to
  // roughly one per move.
  const lastEventMs = parseDateMs(row.last_event_at);
  const moved = lastEventMs === null || lastMoveMs > lastEventMs;
  if (!moved && !options.force) {
    return { status: "throttled", gameId: row.game_id, userId: row.user_id };
  }

  if (options.dryRun) {
    return {
      status: "updated",
      gameId: row.game_id,
      userId: row.user_id,
      ...(options.debug
        ? { debug: { payload: debugPayloadSnapshot(payload), dryRun: true } }
        : {}),
    };
  }

  const result = await sendAndroidLiveNotification(row, payload, "update");
  if (!result.ok) {
    return errorResult(row, result, "android update failed");
  }
  await markLiveSubscriptionEvent(row);
  return {
    status: "updated",
    gameId: row.game_id,
    userId: row.user_id,
    ...(options.debug
      ? {
        debug: {
          payload: debugPayloadSnapshot(payload),
          oneSignal: debugOneSignalResult(result),
        },
      }
      : {}),
  };
}

async function sendAndroidLiveNotification(
  row: LiveSubscriptionRow,
  payload: LiveUpdatePayload,
  event: "start" | "update" | "end",
): Promise<OneSignalResult> {
  // The app's NotificationServiceExtension intercepts any push carrying
  // `data.live_notification` (event.preventDefault()) and renders its OWN ongoing
  // notification on the low-importance "live_updates" channel (no sound/vibration/
  // badge). So this is a SILENT card update, never an alert. It is NOT the
  // notification-outbox / sendLiveGameAlert path that flooded users on 2026-06-06.
  const liveNotification = {
    key: "live_game",
    event,
    event_attributes: {
      game_id: payload.game_id,
      player_white: payload.player_white,
      player_black: payload.player_black,
      white_title: payload.white_title ?? "",
      black_title: payload.black_title ?? "",
      white_fed: payload.white_fed ?? "",
      black_fed: payload.black_fed ?? "",
      white_photo: payload.white_photo ?? "",
      black_photo: payload.black_photo ?? "",
      white_flag: payload.white_flag ?? "",
      black_flag: payload.black_flag ?? "",
      event_name: payload.event_name ?? "",
      round_name: payload.round_name ?? "",
      board_theme_index: payload.board_theme_index ?? 0,
      piece_style_index: payload.piece_style_index ?? 0,
    },
    event_updates: {
      fen: payload.fen ?? "",
      last_move: payload.last_move ?? "",
      last_move_uci: payload.last_move_uci ?? payload.last_move ?? "",
      white_clock_seconds: payload.white_clock_seconds,
      black_clock_seconds: payload.black_clock_seconds,
      last_move_time: payload.last_move_time,
      eval_cp: payload.eval_cp,
      eval_mate: payload.eval_mate,
      status: payload.status,
      is_game_over: payload.is_game_over ? 1 : 0,
      follow_live: 1,
      white_flag: payload.white_flag ?? "",
      black_flag: payload.black_flag ?? "",
    },
  };

  const fallback = payload.last_move_numbered ?? payload.last_move ?? "";
  const body: Record<string, unknown> = {
    app_id: ONESIGNAL_APP_ID,
    target_channel: "push",
    isAndroid: true,
    include_aliases: { external_id: [row.user_id] },
    collapse_id: `live_${payload.game_id}`,
    priority: 10,
    // Benign fallback shown ONLY by a hypothetical build with no NSE (our shipping
    // builds suppress it). Never a stale "game over" alert.
    headings: { en: `${payload.player_white} vs ${payload.player_black}` },
    contents: { en: fallback.length > 0 ? fallback : "Live game" },
    data: {
      type: "live_game_update_v2",
      game_id: payload.game_id,
      live_notification: liveNotification,
    },
  };

  return sendOneSignalCreateMessage(body);
}

async function sendOneSignalCreateMessage(
  body: Record<string, unknown>,
): Promise<OneSignalResult> {
  try {
    const res = await fetch("https://api.onesignal.com/notifications", {
      method: "POST",
      headers: {
        ...jsonHeaders,
        Authorization: `Key ${ONESIGNAL_REST_API_KEY}`,
      },
      body: JSON.stringify(body),
    });
    const text = await res.text();
    if (res.ok) {
      return {
        ok: true,
        notFound: false,
        status: res.status,
        responseText: truncateForDebug(text),
      };
    }
    const lower = text.toLowerCase();
    return {
      ok: false,
      notFound: res.status === 404 || lower.includes("not found") ||
        lower.includes("no subscribers") ||
        lower.includes("included players"),
      status: res.status,
      errorText: text,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return { ok: false, notFound: false, status: 0, errorText: message };
  }
}

function parseNotificationId(text: string | undefined): string | null {
  if (!text) return null;
  try {
    const parsed = JSON.parse(text);
    return typeof parsed?.id === "string" ? parsed.id : null;
  } catch (_) {
    return null;
  }
}

function sleep(ms: number) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function fetchLiveActivityDelivery(notificationId: string) {
  try {
    const res = await fetch(
      `https://api.onesignal.com/notifications/${notificationId}?app_id=${ONESIGNAL_APP_ID}`,
      { headers: { Authorization: `Key ${ONESIGNAL_REST_API_KEY}` } },
    );
    const text = await res.text();
    try {
      const j = JSON.parse(text);
      return {
        http: res.status,
        successful: j.successful,
        failed: j.failed,
        errored: j.errored,
        converted: j.converted,
        remaining: j.remaining,
        completed_at: j.completed_at,
        platform_delivery_stats: j.platform_delivery_stats,
        errors: j.errors,
        throttle_rate_per_minute: j.throttle_rate_per_minute,
      };
    } catch (_) {
      return { http: res.status, raw: text.slice(0, 500) };
    }
  } catch (error) {
    return { error: error instanceof Error ? error.message : String(error) };
  }
}

function buildLiveUpdatePayload(args: {
  game: GameRow;
  round: RoundRow | null;
  tour: TourRow | null;
  groupBroadcast: GroupBroadcastRow | null;
  settings: UserBoardSettings | null;
  evalSnapshots: Map<string, EvalSnapshot>;
  nowMs: number;
}): LiveUpdatePayload {
  const white = args.game.player_white ?? "White";
  const black = args.game.player_black ?? "Black";
  const fen = args.game.fen ?? null;
  const lastMove = args.game.last_move ?? null;
  const lastMoveUci = lastMove;
  const checkState = analyzePosition(fen);
  const rawSan = uciToSan(lastMoveUci, fen);
  const san = appendCheckSuffix(rawSan, checkState);
  const numbered = formatMoveWithNumber(san, fen);
  const { whiteFide, blackFide } = extractFideIds(args.game, white, black);
  const { whiteTitle, blackTitle, whiteFed, blackFed } = extractPlayerMeta(
    args.game.players,
    white,
    black,
    whiteFide,
    blackFide,
  );
  const evalSnapshot = fen
    ? args.evalSnapshots.get(fen) ?? estimateEvalSnapshotFromFen(fen)
    : null;
  const clockTiming = buildClockTiming(args.game, fen);

  return {
    game_id: args.game.id,
    fen,
    last_move: lastMove,
    last_move_uci: lastMoveUci,
    last_move_san: san,
    last_move_numbered: numbered,
    last_move_time: args.game.last_move_time ?? null,
    white_clock_seconds: args.game.last_clock_white ?? null,
    black_clock_seconds: args.game.last_clock_black ?? null,
    clock_anchor_time: clockTiming.anchorTime,
    active_clock_color: clockTiming.activeColor,
    active_clock_deadline: clockTiming.deadline,
    eval_cp: evalSnapshot?.cp ?? null,
    eval_mate: evalSnapshot?.mate ?? null,
    board_theme_index: args.settings?.board_theme_index ?? 0,
    piece_style_index: args.settings?.piece_style_index ?? 0,
    player_white: white,
    player_black: black,
    event_name: args.groupBroadcast?.name ?? args.tour?.name ?? null,
    round_name: args.round?.name ?? null,
    white_fide_id: whiteFide,
    black_fide_id: blackFide,
    white_photo: publicFidePhotoUrl(whiteFide),
    black_photo: publicFidePhotoUrl(blackFide),
    white_title: whiteTitle,
    black_title: blackTitle,
    white_fed: whiteFed,
    black_fed: blackFed,
    white_flag: fedToFlagEmoji(whiteFed),
    black_flag: fedToFlagEmoji(blackFed),
    is_check: checkState.isCheck,
    is_checkmate: checkState.isCheckmate,
    is_game_over: isGameOverStatus(args.game.status),
    follow_live: true,
    status: args.game.status ?? null,
    refresh_ts: args.nowMs,
  };
}

async function sendLiveActivityUpdate(
  activityId: string,
  updateData: Record<string, unknown>,
  priority: number = UPDATE_PRIORITY,
): Promise<OneSignalResult> {
  const payload = {
    event: "update",
    name: `live_activity_refresh:${activityId}`,
    event_updates: { data: updateData },
    // Always priority 10 — we only ever push on a real move now.
    priority,
    // Move-only cards sit between moves; keep them "fresh" for an hour so iOS
    // doesn't dim the card as stale during a normal think.
    stale_date: Math.floor(Date.now() / 1000) + 3600,
    ios_relevance_score: 1,
  };

  return sendLiveActivityEvent(activityId, payload);
}

async function sendLiveActivityEnd(
  activityId: string,
  finalData?: Record<string, unknown>,
): Promise<OneSignalResult> {
  const payload = {
    event: "end",
    name: `live_activity_refresh:${activityId}`,
    ...(finalData ? { event_updates: { data: finalData } } : {}),
    priority: 10,
    dismissal_date: Math.floor(Date.now() / 1000),
  };

  return sendLiveActivityEvent(activityId, payload);
}

async function sendLiveActivityEvent(
  activityId: string,
  payload: Record<string, unknown>,
): Promise<OneSignalResult> {
  try {
    // This is the ActivityKit Live Activity API. Do not replace this with
    // https://api.onesignal.com/notifications; that is the normal push path.
    const res = await fetch(
      `https://api.onesignal.com/apps/${ONESIGNAL_APP_ID}/live_activities/${activityId}/notifications`,
      {
        method: "POST",
        headers: {
          ...jsonHeaders,
          Authorization: `Key ${ONESIGNAL_REST_API_KEY}`,
        },
        body: JSON.stringify(payload),
      },
    );

    const text = await res.text();
    if (res.ok) {
      return {
        ok: true,
        notFound: false,
        status: res.status,
        responseText: truncateForDebug(text),
      };
    }

    const lower = text.toLowerCase();
    return {
      ok: false,
      notFound: res.status === 404 || res.status === 410 ||
        lower.includes("not found"),
      status: res.status,
      errorText: text,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return { ok: false, notFound: false, status: 0, errorText: message };
  }
}

async function fetchGames(gameIds: string[]) {
  const map = new Map<string, GameRow>();
  if (gameIds.length === 0) return map;

  const { data, error } = await supabase
    .from("games")
    .select(
      "id,tour_id,round_id,player_white,player_black,player_fide_ids,fen,players,status,last_move,last_move_time,last_clock_white,last_clock_black",
    )
    .in("id", gameIds);

  if (error) throw error;
  for (const row of (data ?? []) as GameRow[]) {
    map.set(row.id, row);
  }
  return map;
}

async function fetchRounds(roundIds: string[]) {
  const map = new Map<string, RoundRow>();
  if (roundIds.length === 0) return map;

  const { data, error } = await supabase
    .from("rounds")
    .select("id,tour_id,name")
    .in("id", roundIds);

  if (error) throw error;
  for (const row of (data ?? []) as RoundRow[]) {
    map.set(row.id, row);
  }
  return map;
}

async function fetchTours(tourIds: string[]) {
  const map = new Map<string, TourRow>();
  if (tourIds.length === 0) return map;

  const { data, error } = await supabase
    .from("tours")
    .select("id,name,group_broadcast_id")
    .in("id", tourIds);

  if (error) throw error;
  for (const row of (data ?? []) as TourRow[]) {
    map.set(row.id, row);
  }
  return map;
}

async function fetchGroupBroadcasts(groupBroadcastIds: string[]) {
  const map = new Map<string, GroupBroadcastRow>();
  if (groupBroadcastIds.length === 0) return map;

  const { data, error } = await supabase
    .from("group_broadcasts")
    .select("id,name")
    .in("id", groupBroadcastIds);

  if (error) throw error;
  for (const row of (data ?? []) as GroupBroadcastRow[]) {
    map.set(row.id, row);
  }
  return map;
}

async function fetchBoardSettings(userIds: string[]) {
  const map = new Map<string, UserBoardSettings>();
  if (userIds.length === 0) return map;

  const { data, error } = await supabase
    .from("user_engine_settings")
    .select("user_id,board_theme_index,piece_style_index")
    .in("user_id", userIds);

  if (error) throw error;
  for (const row of data ?? []) {
    map.set(row.user_id as string, {
      board_theme_index: (row.board_theme_index as number | null) ?? 0,
      piece_style_index: (row.piece_style_index as number | null) ?? 0,
    });
  }
  return map;
}

async function fetchEvalSnapshots(fens: string[]) {
  const map = new Map<string, EvalSnapshot>();
  if (fens.length === 0) return map;

  const { data: positions, error: positionsError } = await supabase
    .from("positions")
    .select("id,fen")
    .in("fen", fens);

  if (positionsError) throw positionsError;

  const fenByPositionId = new Map<string, string>();
  for (const row of (positions ?? []) as PositionRow[]) {
    if (row.id != null && row.fen) {
      fenByPositionId.set(String(row.id), row.fen);
    }
  }

  const positionIds = Array.from(fenByPositionId.keys());
  if (positionIds.length === 0) return map;

  const { data: evals, error: evalsError } = await supabase
    .from("evals")
    .select("position_id,depth,pvs,multi_pv,pvs_count")
    .in("position_id", positionIds);

  if (evalsError) throw evalsError;

  const bestByPositionId = new Map<
    string,
    { snapshot: EvalSnapshot; depth: number; multiPv: number }
  >();

  for (const row of (evals ?? []) as EvalRow[]) {
    const positionId = String(row.position_id);
    if (!fenByPositionId.has(positionId)) continue;

    const snapshot = parseEvalSnapshot(row);
    if (!snapshot) continue;

    const depth = parseFiniteInt(row.depth) ?? 0;
    const multiPv = parseFiniteInt(row.multi_pv) ??
      parseFiniteInt(row.pvs_count) ??
      countPvLines(row.pvs);
    const existing = bestByPositionId.get(positionId);
    if (
      !existing ||
      depth > existing.depth ||
      (depth === existing.depth && multiPv > existing.multiPv)
    ) {
      bestByPositionId.set(positionId, {
        snapshot: { ...snapshot, depth },
        depth,
        multiPv,
      });
    }
  }

  for (const [positionId, best] of bestByPositionId) {
    const fen = fenByPositionId.get(positionId);
    if (fen) map.set(fen, best.snapshot);
  }

  return map;
}

async function markLiveSubscriptionEvent(row: LiveSubscriptionRow) {
  await supabase
    .from("user_live_game_subscriptions")
    .update({ last_event_at: new Date().toISOString() })
    .eq("game_id", row.game_id)
    .eq("platform", row.platform)
    .eq("user_id", row.user_id);
}

async function disableLiveSubscription(row: LiveSubscriptionRow) {
  await supabase
    .from("user_live_game_subscriptions")
    .update({
      enabled: false,
      last_event_at: new Date().toISOString(),
    })
    .eq("game_id", row.game_id)
    .eq("platform", row.platform)
    .eq("user_id", row.user_id);
}

function errorResult(
  row: LiveSubscriptionRow,
  result: OneSignalResult,
  fallback: string,
): RefreshResult {
  const detail = result.errorText
    ? `${result.status}: ${result.errorText.slice(0, 240)}`
    : `${result.status}: ${fallback}`;
  return {
    status: "error",
    gameId: row.game_id,
    userId: row.user_id,
    error: detail,
  };
}

function summarize(results: RefreshResult[]) {
  const counts: Record<RefreshStatus, number> = {
    updated: 0,
    throttled: 0,
    ended: 0,
    disabled_missing_game: 0,
    disabled_not_live_status: 0,
    disabled_stale: 0,
    not_found: 0,
    error: 0,
  };
  const errors: string[] = [];
  const debugSamples: RefreshDebug[] = [];

  for (const result of results) {
    counts[result.status] += 1;
    if (result.status === "error" && result.error && errors.length < 10) {
      errors.push(`${result.gameId}:${result.error}`);
    }
    if (result.debug && debugSamples.length < 5) {
      debugSamples.push(result.debug);
    }
  }

  return {
    counts,
    errors,
    ...(debugSamples.length > 0 ? { debugSamples } : {}),
  };
}

function buildLiveActivityId(gameId: string, userId: string) {
  return `live:${gameId}:${userId}`;
}

function debugPayloadSnapshot(payload: LiveUpdatePayload) {
  const fenParts = typeof payload.fen === "string"
    ? payload.fen.trim().split(/\s+/)
    : [];

  return {
    game_id: payload.game_id,
    status: payload.status,
    side_to_move: fenParts.length > 1 ? fenParts[1] : null,
    fullmove: fenParts.length > 5 ? fenParts[5] : null,
    last_move: payload.last_move,
    last_move_san: payload.last_move_san,
    last_move_numbered: payload.last_move_numbered,
    last_move_time: payload.last_move_time,
    white_clock_seconds: payload.white_clock_seconds,
    black_clock_seconds: payload.black_clock_seconds,
    clock_anchor_time: payload.clock_anchor_time,
    active_clock_color: payload.active_clock_color,
    active_clock_deadline: payload.active_clock_deadline,
    eval_cp: payload.eval_cp,
    eval_mate: payload.eval_mate,
    is_check: payload.is_check,
    is_checkmate: payload.is_checkmate,
    is_game_over: payload.is_game_over,
    follow_live: payload.follow_live,
    refresh_ts: payload.refresh_ts,
    update_priority: UPDATE_PRIORITY,
  };
}

function debugOneSignalResult(result: OneSignalResult) {
  return {
    ok: result.ok,
    notFound: result.notFound,
    status: result.status,
    ...(result.responseText ? { body: result.responseText } : {}),
  };
}

function isAuthorized(req: Request) {
  const bearer = bearerToken(req);
  const refreshToken = Deno.env.get("LIVE_ACTIVITY_REFRESH_TOKEN") ?? "";
  const providedRefreshToken =
    req.headers.get("x-live-activity-refresh-token") ?? "";

  if (refreshToken) {
    return bearer === refreshToken || providedRefreshToken === refreshToken ||
      bearer === SUPABASE_SERVICE_ROLE_KEY ||
      LIVE_ACTIVITY_REFRESH_ALLOWED_KEYS.has(bearer);
  }
  return bearer === SUPABASE_SERVICE_ROLE_KEY ||
    LIVE_ACTIVITY_REFRESH_ALLOWED_KEYS.has(bearer);
}

function bearerToken(req: Request) {
  const header = req.headers.get("authorization") ?? "";
  const [scheme, token] = header.split(" ");
  if (scheme?.toLowerCase() !== "bearer" || !token) return "";
  return token.trim();
}

function parseAllowedKeys(raw: string) {
  return new Set(
    raw
      .split(",")
      .map((value) => value.trim())
      .filter((value) => value.length > 0),
  );
}

function isOngoingStatus(status: string | null) {
  const normalized = (status ?? "").trim().toLowerCase();
  return normalized === "*" || normalized === "ongoing";
}

function isGameOverStatus(status: string | null) {
  if (!status) return false;
  const trimmed = status.trim().toLowerCase();
  if (trimmed.length === 0) return false;
  return trimmed !== "*" && trimmed !== "ongoing";
}

function parseFenBoard(fen: string) {
  const boardPart = fen.split(" ")[0] ?? "";
  const ranks = boardPart.split("/");
  if (ranks.length !== 8) return null;
  const grid: Array<Array<string | null>> = [];
  for (const rank of ranks) {
    const row: Array<string | null> = [];
    for (const ch of rank) {
      if (/\d/.test(ch)) {
        const count = Number(ch);
        for (let i = 0; i < count; i++) row.push(null);
      } else {
        row.push(ch);
      }
    }
    if (row.length !== 8) return null;
    grid.push(row);
  }
  return grid;
}

function pieceAt(fen: string, square: string): string | null {
  if (square.length < 2) return null;
  const file = square.charCodeAt(0) - 97;
  const rank = Number(square[1]) - 1;
  if (file < 0 || file > 7 || rank < 0 || rank > 7) return null;
  const grid = parseFenBoard(fen);
  if (!grid) return null;
  const rowIndex = 7 - rank;
  return grid[rowIndex]?.[file] ?? null;
}

function uciToSan(uci: string | null, fen: string | null) {
  if (!uci || uci.length < 4) return null;
  const from = uci.slice(0, 2);
  const to = uci.slice(2, 4);
  const promotion = uci.length === 5 ? uci[4] : null;

  if (!fen) return to;
  if (
    (from === "e1" && (to === "g1" || to === "c1")) ||
    (from === "e8" && (to === "g8" || to === "c8"))
  ) {
    return to === "g1" || to === "g8" ? "O-O" : "O-O-O";
  }

  const piece = pieceAt(fen, to);
  if (!piece) return to;

  const role = piece.toLowerCase();
  const symbolMap: Record<string, string> = {
    k: "K",
    q: "Q",
    r: "R",
    b: "B",
    n: "N",
    p: "",
  };

  let move = "";
  if (role !== "p") move += symbolMap[role] ?? "";
  if (role === "p" && from[0] !== to[0]) move += `${from[0]}x`;
  move += to;
  if (promotion) move += `=${promotion.toUpperCase()}`;
  return move;
}

function analyzePosition(fen: string | null) {
  if (!fen) return { isCheck: false, isCheckmate: false };
  try {
    const chess = new Chess(fen);
    return { isCheck: chess.isCheck(), isCheckmate: chess.isCheckmate() };
  } catch (_) {
    return { isCheck: false, isCheckmate: false };
  }
}

function appendCheckSuffix(
  move: string | null,
  checkState: { isCheck: boolean; isCheckmate: boolean },
) {
  if (!move) return move;
  if (move.includes("#") || move.includes("+")) return move;
  if (checkState.isCheckmate) return `${move}#`;
  if (checkState.isCheck) return `${move}+`;
  return move;
}

function formatMoveWithNumber(move: string | null, fen: string | null) {
  if (!move || !fen) return move;
  const parts = fen.split(" ");
  if (parts.length < 6) return move;
  const sideToMove = parts[1];
  const fullMove = Number(parts[5]);
  if (!fullMove || Number.isNaN(fullMove)) return move;
  if (sideToMove === "b") return `${fullMove}.${move}`;
  const moveNumber = fullMove - 1;
  if (moveNumber <= 0) return move;
  return `${moveNumber}...${move}`;
}

function extractFideIds(
  game: GameRow,
  whiteName: string | null,
  blackName: string | null,
) {
  let whiteFide: number | null = null;
  let blackFide: number | null = null;

  if (Array.isArray(game.players)) {
    for (const raw of game.players) {
      const name = (raw?.name as string | undefined) ?? null;
      const fideId = parseFiniteInt(raw?.fideId);
      if (!name || fideId == null) continue;
      if (whiteName && name === whiteName) whiteFide = fideId;
      if (blackName && name === blackName) blackFide = fideId;
    }
  }

  const fallbackIds = game.player_fide_ids ?? [];
  whiteFide = whiteFide ?? parseFiniteInt(fallbackIds[0]);
  blackFide = blackFide ?? parseFiniteInt(fallbackIds[1]);
  return { whiteFide, blackFide };
}

function extractPlayerMeta(
  players: Record<string, unknown>[] | null,
  whiteName: string | null,
  blackName: string | null,
  whiteFide: number | null,
  blackFide: number | null,
) {
  let whiteTitle: string | null = null;
  let blackTitle: string | null = null;
  let whiteFed: string | null = null;
  let blackFed: string | null = null;

  if (Array.isArray(players)) {
    for (const raw of players) {
      const name = (raw?.name as string | undefined) ?? null;
      const fideId = parseFiniteInt(raw?.fideId);
      const title = toNonEmptyString(raw?.title);
      const fed = toNonEmptyString(raw?.fed) ??
        toNonEmptyString(raw?.federation);

      if (whiteFide && fideId === whiteFide) {
        whiteTitle = title;
        whiteFed = fed;
      } else if (blackFide && fideId === blackFide) {
        blackTitle = title;
        blackFed = fed;
      }

      if (name && whiteName && name === whiteName && whiteTitle == null) {
        whiteTitle = title;
        whiteFed = fed;
      }
      if (name && blackName && name === blackName && blackTitle == null) {
        blackTitle = title;
        blackFed = fed;
      }
    }
  }

  return {
    whiteTitle,
    blackTitle,
    whiteFed: normalizeFed(whiteFed),
    blackFed: normalizeFed(blackFed),
  };
}

function estimateEvalSnapshotFromFen(fen: string) {
  const side = parseSideToMove(fen);
  const check = analyzePosition(fen);
  if (check.isCheckmate && side) {
    return { cp: null, mate: side === "w" ? -1 : 1 };
  }

  const grid = parseFenBoard(fen);
  if (!grid) return { cp: null, mate: null };
  const values: Record<string, number> = {
    p: 100,
    n: 320,
    b: 330,
    r: 500,
    q: 900,
    k: 0,
  };
  let cp = 0;
  for (const row of grid) {
    for (const piece of row) {
      if (!piece) continue;
      const value = values[piece.toLowerCase()] ?? 0;
      cp += piece === piece.toUpperCase() ? value : -value;
    }
  }
  return { cp: Math.max(-2500, Math.min(2500, cp)), mate: null };
}

function buildClockTiming(game: GameRow, fen: string | null) {
  const activeColor = activeClockColorFromFen(fen);
  const anchorTime = game.last_move_time ?? null;
  const anchorMs = parseDateMs(anchorTime);
  const activeSeconds = activeColor === "white"
    ? parseFiniteInt(game.last_clock_white)
    : activeColor === "black"
    ? parseFiniteInt(game.last_clock_black)
    : null;

  if (
    !activeColor ||
    anchorMs === null ||
    activeSeconds === null ||
    isGameOverStatus(game.status)
  ) {
    return { anchorTime, activeColor, deadline: null };
  }

  const deadlineMs = anchorMs + Math.max(0, activeSeconds) * 1000;
  return {
    anchorTime,
    activeColor,
    deadline: new Date(deadlineMs).toISOString(),
  };
}

function activeClockColorFromFen(fen: string | null): "white" | "black" | null {
  if (!fen) return null;
  const side = parseSideToMove(fen);
  if (side === "w") return "white";
  if (side === "b") return "black";
  return null;
}

function parseEvalSnapshot(row: EvalRow): EvalSnapshot | null {
  const pv = firstPvLine(row.pvs);
  if (!pv) return null;

  const mate = parseFiniteInt(pv.mate);
  if (mate !== null) {
    return { cp: null, mate, depth: parseFiniteInt(row.depth) };
  }

  const score = isRecord(pv.score) ? pv.score : null;
  const scoreMate = score ? parseFiniteInt(score.mate) : null;
  if (scoreMate !== null) {
    return { cp: null, mate: scoreMate, depth: parseFiniteInt(row.depth) };
  }

  const cp = parseFiniteInt(pv.cp);
  if (cp !== null) {
    return { cp, mate: null, depth: parseFiniteInt(row.depth) };
  }

  const scoreCp = score ? parseFiniteInt(score.cp) : null;
  if (scoreCp !== null) {
    return { cp: scoreCp, mate: null, depth: parseFiniteInt(row.depth) };
  }

  return null;
}

function firstPvLine(pvs: unknown): Record<string, unknown> | null {
  if (!Array.isArray(pvs)) return null;
  const first = pvs[0];
  return isRecord(first) ? first : null;
}

function countPvLines(pvs: unknown) {
  return Array.isArray(pvs) ? pvs.length : 0;
}

function parseSideToMove(fen: string) {
  const side = fen.split(" ")[1];
  return side === "w" || side === "b" ? side : null;
}

function publicFidePhotoUrl(fideId: number | null) {
  if (!fideId || fideId <= 0) return null;
  return `${SUPABASE_URL}/storage/v1/object/public/player-photos/fide/${
    encodeURIComponent(String(fideId))
  }.jpg`;
}

function fedToFlagEmoji(fed: string | null) {
  if (!fed) return null;
  let iso2 = fed.trim().toUpperCase();
  const aliases: Record<string, string> = {
    FIDE: "",
    ENG: "GB",
    SCO: "GB",
    WLS: "GB",
  };
  iso2 = aliases[iso2] ?? iso2;
  if (iso2.length !== 2 || iso2 === "XX") return null;
  const base = 0x1f1e6;
  const a = iso2.charCodeAt(0) - 65 + base;
  const b = iso2.charCodeAt(1) - 65 + base;
  if (a < base || a > base + 25 || b < base || b > base + 25) return null;
  return String.fromCodePoint(a, b);
}

async function mapWithConcurrency<T, R>(
  items: T[],
  concurrency: number,
  worker: (item: T) => Promise<R>,
): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let nextIndex = 0;

  async function run() {
    while (nextIndex < items.length) {
      const current = nextIndex;
      nextIndex += 1;
      results[current] = await worker(items[current]);
    }
  }

  await Promise.all(
    Array.from(
      { length: Math.min(concurrency, items.length) },
      () => run(),
    ),
  );
  return results;
}

function jsonResponse(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders,
  });
}

function parseDateMs(value: string | null) {
  if (!value) return null;
  const ms = Date.parse(value);
  return Number.isFinite(ms) ? ms : null;
}

function readIntEnv(
  name: string,
  fallback: number,
  min: number,
  max: number,
) {
  return clamp(parseFiniteInt(Deno.env.get(name)) ?? fallback, min, max);
}

function normalizeLiveActivityPriority(value: number) {
  return value >= 10 ? 10 : 5;
}

function truncateForDebug(value: string) {
  return value.length > 500 ? `${value.slice(0, 500)}…` : value;
}

function parseFiniteInt(value: unknown) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value !== "string") return null;
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : null;
}

function clamp(value: number, min: number, max: number) {
  return Math.max(min, Math.min(max, Math.trunc(value)));
}

function unique(values: string[]) {
  return Array.from(new Set(values));
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.length > 0;
}

function toNonEmptyString(value: unknown) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function normalizeFed(value: string | null) {
  return value ? value.trim().toUpperCase() : null;
}
