import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type OutboxItem = {
  id: string;
  event_type: string;
  game_id: string | null;
  round_id: string | null;
  tour_id: string | null;
  group_broadcast_id: string | null;
  payload: Record<string, unknown>;
  status: string;
  attempts: number;
  not_before: string;
};

type GameRow = {
  id: string;
  tour_id: string | null;
  player_white: string | null;
  player_black: string | null;
  player_fide_ids: number[] | null;
  fen: string | null;
  players: Record<string, unknown>[] | null;
  status: string | null;
  last_move: string | null;
  last_move_time: string | null;
  last_clock_white: number | null;
  last_clock_black: number | null;
};

type RoundGameRow = {
  player_white: string | null;
  player_black: string | null;
  player_fide_ids: number[] | null;
};

type RoundRow = {
  id: string;
  tour_id: string | null;
  name: string | null;
  starts_at: string | null;
};

type LiveSubscriptionRow = {
  user_id: string;
  platform: "ios" | "android";
  started_at: string | null;
};

type EvalSnapshot = {
  cp: number | null;
  mate: number | null;
  depth: number | null;
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
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
const fidePhotoCache = new Map<number, string | null>();

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  let limit = 25;
  try {
    const body = await req.json();
    if (typeof body?.limit === "number") limit = body.limit;
  } catch (_) {
    // Ignore body parsing errors; use default limit.
  }

  const items = await fetchPending(limit);
  const results: Array<Record<string, unknown>> = [];

  for (const item of items) {
    const result = await processItem(item);
    results.push(result);
  }

  return new Response(
    JSON.stringify({
      processed: results.length,
      results,
    }),
    { headers: jsonHeaders },
  );
});

async function fetchPending(limit: number): Promise<OutboxItem[]> {
  const { data, error } = await supabase
    .from("notification_outbox")
    .select("*")
    .eq("status", "pending")
    .lte("not_before", new Date().toISOString())
    .order("created_at", { ascending: true })
    .limit(limit);

  if (error) {
    throw error;
  }

  return (data ?? []) as OutboxItem[];
}

async function processItem(item: OutboxItem) {
  const claimOk = await markProcessing(item.id, item.attempts);
  if (!claimOk) {
    return { id: item.id, status: "skipped", reason: "already_claimed" };
  }

  try {
    const context = await buildContext(item);
    if (item.event_type === "live_game_update") {
      if (!item.game_id) {
        await markSkipped(item.id, "missing_game_id");
        return { id: item.id, status: "skipped", reason: "missing_game_id" };
      }

      const subscriptions = await fetchLiveSubscriptions(item.game_id);
      const iosUserIdsRaw = subscriptions.ios.map((row) => row.user_id);
      const androidUserIdsRaw = subscriptions.android.map((row) => row.user_id);

      const iosUserIds = await filterLiveUpdateEnabled(iosUserIdsRaw);
      const androidUserIds = await filterLiveUpdateEnabled(androidUserIdsRaw);

      const iosEligible = subscriptions.ios.filter((row) =>
        iosUserIds.has(row.user_id)
      );
      const androidEligible = subscriptions.android.filter((row) =>
        androidUserIds.has(row.user_id)
      );

      if (iosEligible.length === 0 && androidEligible.length === 0) {
        await markSkipped(item.id, "no_live_subscribers");
        return {
          id: item.id,
          status: "skipped",
          reason: "no_live_subscribers",
        };
      }

      const fen = (item.payload?.fen as string) ?? context.game?.fen ?? null;
      const evalSnapshots = await fetchEvalSnapshots(fen ? [fen] : []);
      const evalSnapshot = fen ? evalSnapshots.get(fen) ?? null : null;

      const livePayload = await buildLiveUpdatePayload({
        item,
        context,
        evalSnapshot,
      });

      for (const row of iosEligible) {
        const activityId = buildLiveActivityId(item.game_id, row.user_id);
        await sendLiveActivityUpdate(activityId, livePayload);
      }

      if (iosEligible.length > 0) {
        await markLiveSubscriptionEvent({
          gameId: item.game_id,
          userIds: iosEligible.map((row) => row.user_id),
          platform: "ios",
        });
      }

      const androidNewUsers = androidEligible
        .filter((row) => !row.started_at)
        .map((row) => row.user_id);
      const androidExistingUsers = androidEligible
        .filter((row) => row.started_at)
        .map((row) => row.user_id);

      const newSubscriptionIds = await fetchAndroidSubscriptionIds(
        androidNewUsers,
      );
      const existingSubscriptionIds = await fetchAndroidSubscriptionIds(
        androidExistingUsers,
      );

      if (newSubscriptionIds.length > 0) {
        await sendAndroidLiveNotification({
          subscriptionIds: newSubscriptionIds,
          livePayload,
          event: "start",
        });
        await markLiveSubscriptionEvent({
          gameId: item.game_id,
          userIds: androidNewUsers,
          platform: "android",
          markStarted: true,
        });
      }

      if (existingSubscriptionIds.length > 0) {
        await sendAndroidLiveNotification({
          subscriptionIds: existingSubscriptionIds,
          livePayload,
          event: "update",
        });
        await markLiveSubscriptionEvent({
          gameId: item.game_id,
          userIds: androidExistingUsers,
          platform: "android",
        });
      }

      await markSent(item.id);
      return {
        id: item.id,
        status: "sent",
        recipients: iosEligible.length + androidEligible.length,
      };
    }
    if (item.event_type === "round_started") {
      const { playerRecipients, eventRecipients } = await filterRoundRecipients(
        context.eventUserIds,
        context.playerUserIds,
      );

      if (playerRecipients.length === 0 && eventRecipients.length === 0) {
        await markSkipped(item.id, "no_recipients");
        return { id: item.id, status: "skipped", reason: "no_recipients" };
      }

      if (playerRecipients.length > 0) {
        const playerNotification = buildRoundNotification(context, "player");
        await sendOneSignal(playerRecipients, playerNotification);
      }

      if (eventRecipients.length > 0) {
        const eventNotification = buildRoundNotification(context, "event");
        await sendOneSignal(eventRecipients, eventNotification);
      }

      await markSent(item.id);
      return {
        id: item.id,
        status: "sent",
        recipients: playerRecipients.length + eventRecipients.length,
      };
    }

    if (item.event_type === "round_heads_up") {
      const { playerRecipients, eventRecipients } =
        await filterHeadsUpRecipients(
          context.eventUserIds,
          context.playerUserIds,
        );

      if (playerRecipients.length === 0 && eventRecipients.length === 0) {
        await markSkipped(item.id, "no_recipients");
        return { id: item.id, status: "skipped", reason: "no_recipients" };
      }

      if (playerRecipients.length > 0) {
        const playerNotification = buildHeadsUpNotification(context, "player");
        await sendOneSignal(playerRecipients, playerNotification);
      }

      if (eventRecipients.length > 0) {
        const eventNotification = buildHeadsUpNotification(context, "event");
        await sendOneSignal(eventRecipients, eventNotification);
      }

      await markSent(item.id);
      return {
        id: item.id,
        status: "sent",
        recipients: playerRecipients.length + eventRecipients.length,
      };
    }

    const allUserIds = new Set([
      ...context.eventUserIds,
      ...context.playerUserIds,
    ]);
    const filteredUserIds = await applyPreferences(
      item.event_type,
      allUserIds,
      context.eventUserIds,
      context.playerUserIds,
    );

    if (filteredUserIds.size === 0) {
      await markSkipped(item.id, "no_recipients");
      return { id: item.id, status: "skipped", reason: "no_recipients" };
    }

    const notification = buildNotification(context, item);
    await sendOneSignal(Array.from(filteredUserIds), notification);
    await markSent(item.id);

    return {
      id: item.id,
      status: "sent",
      recipients: filteredUserIds.size,
    };
  } catch (error) {
    await markFailed(item.id, item.attempts + 1, `${error}`);
    return { id: item.id, status: "failed", error: `${error}` };
  }
}

async function markProcessing(id: string, attempts: number) {
  const { data, error } = await supabase
    .from("notification_outbox")
    .update({ status: "processing", attempts: attempts + 1 })
    .eq("id", id)
    .eq("status", "pending")
    .select("id");

  if (error) return false;
  return (data ?? []).length > 0;
}

async function markSent(id: string) {
  await supabase
    .from("notification_outbox")
    .update({ status: "sent" })
    .eq("id", id);
}

async function markSkipped(id: string, reason: string) {
  await supabase
    .from("notification_outbox")
    .update({ status: "skipped", last_error: reason })
    .eq("id", id);
}

async function markFailed(id: string, attempts: number, error: string) {
  await supabase
    .from("notification_outbox")
    .update({ status: "failed", attempts, last_error: error })
    .eq("id", id);
}

async function buildContext(item: OutboxItem) {
  let game: GameRow | null = null;
  let round: RoundRow | null = null;
  let eventName: string | null = null;
  let groupBroadcastId = item.group_broadcast_id ?? null;

  if (item.game_id) {
    const { data } = await supabase
      .from("games")
      .select(
        "id,tour_id,player_white,player_black,player_fide_ids,fen,players,status,last_move,last_move_time,last_clock_white,last_clock_black",
      )
      .eq("id", item.game_id)
      .maybeSingle();
    game = (data ?? null) as GameRow | null;
  }

  if (item.round_id) {
    const { data } = await supabase
      .from("rounds")
      .select("id,tour_id,name,starts_at")
      .eq("id", item.round_id)
      .maybeSingle();
    round = (data ?? null) as RoundRow | null;
  }

  const tourId = item.tour_id ?? game?.tour_id ?? round?.tour_id ?? null;
  if (!groupBroadcastId && tourId) {
    const { data } = await supabase
      .from("tours")
      .select("group_broadcast_id")
      .eq("id", tourId)
      .maybeSingle();
    groupBroadcastId = data?.group_broadcast_id ?? null;
  }

  if (groupBroadcastId) {
    const { data } = await supabase
      .from("group_broadcasts")
      .select("name")
      .eq("id", groupBroadcastId)
      .maybeSingle();
    eventName = data?.name ?? null;
  }

  const playerNames = new Set<string>();
  const fideIdSet = new Set<string>();

  const seedPlayers = [
    item.payload?.player_white as string | undefined,
    item.payload?.player_black as string | undefined,
    game?.player_white ?? undefined,
    game?.player_black ?? undefined,
  ].filter(Boolean) as string[];

  for (const name of seedPlayers) {
    playerNames.add(name);
  }

  for (const id of game?.player_fide_ids ?? []) {
    fideIdSet.add(id.toString());
  }

  if (
    (item.event_type === "round_started" ||
      item.event_type === "round_heads_up") &&
    item.round_id
  ) {
    const roundPlayers = await fetchRoundPlayers(item.round_id);
    for (const name of roundPlayers.playerNames) {
      playerNames.add(name);
    }
    for (const id of roundPlayers.fideIds) {
      fideIdSet.add(id);
    }
  }

  const { eventUserIds, playerUserIds } = await resolveRecipients({
    groupBroadcastId,
    fideIds: Array.from(fideIdSet),
    players: Array.from(playerNames),
  });

  return {
    game,
    round,
    eventName,
    groupBroadcastId,
    eventUserIds,
    playerUserIds,
  };
}

async function fetchRoundPlayers(roundId: string) {
  const { data, error } = await supabase
    .from("games")
    .select("player_white,player_black,player_fide_ids")
    .eq("round_id", roundId);

  if (error) {
    throw error;
  }

  const playerNames = new Set<string>();
  const fideIds = new Set<string>();

  for (const row of (data ?? []) as RoundGameRow[]) {
    if (row.player_white) playerNames.add(row.player_white);
    if (row.player_black) playerNames.add(row.player_black);
    for (const id of row.player_fide_ids ?? []) {
      fideIds.add(id.toString());
    }
  }

  return {
    playerNames: Array.from(playerNames),
    fideIds: Array.from(fideIds),
  };
}

async function resolveRecipients(args: {
  groupBroadcastId: string | null;
  fideIds: string[];
  players: string[];
}) {
  const eventUserIds = new Set<string>();
  const playerUserIds = new Set<string>();

  if (args.groupBroadcastId) {
    const { data } = await supabase
      .from("user_favorite_events")
      .select("user_id")
      .eq("event_id", args.groupBroadcastId);
    for (const row of data ?? []) {
      eventUserIds.add(row.user_id as string);
    }
  }

  if (args.fideIds.length > 0) {
    const { data } = await supabase
      .from("user_favorite_players")
      .select("user_id")
      .in("fide_id", args.fideIds);
    for (const row of data ?? []) {
      playerUserIds.add(row.user_id as string);
    }
  }

  if (args.players.length > 0) {
    const { data } = await supabase
      .from("user_favorite_players")
      .select("user_id")
      .in("player_name", args.players);
    for (const row of data ?? []) {
      playerUserIds.add(row.user_id as string);
    }
  }

  return { eventUserIds, playerUserIds };
}

async function applyPreferences(
  eventType: string,
  allUserIds: Set<string>,
  eventUserIds: Set<string>,
  playerUserIds: Set<string>,
) {
  const ids = Array.from(allUserIds);
  if (ids.length === 0) return allUserIds;

  const { data } = await supabase
    .from("user_notification_preferences")
    .select(
      "user_id,push_enabled,favorite_event_alerts,favorite_player_alerts,live_game_updates,daily_digest",
    )
    .in("user_id", ids);

  const prefsMap = new Map<string, Record<string, unknown>>();
  for (const row of data ?? []) {
    prefsMap.set(row.user_id as string, row);
  }

  const filtered = new Set<string>();

  for (const userId of ids) {
    const prefs = prefsMap.get(userId);
    if (prefs && prefs.push_enabled === false) continue;

    const isEventFav = eventUserIds.has(userId);
    const isPlayerFav = playerUserIds.has(userId);

    if (eventType === "game_started" || eventType === "game_finished") {
      const eventAllowed = !prefs || prefs.favorite_event_alerts !== false;
      const playerAllowed = !prefs || prefs.favorite_player_alerts !== false;
      if (isEventFav && eventAllowed) {
        filtered.add(userId);
        continue;
      }
      if (isPlayerFav && playerAllowed) {
        filtered.add(userId);
        continue;
      }
      continue;
    }

    if (eventType === "live_game_update") {
      if (prefs && prefs.live_game_updates === false) {
        continue;
      }
      if (isEventFav || isPlayerFav) {
        filtered.add(userId);
      }
      continue;
    }

    filtered.add(userId);
  }

  return filtered;
}

async function filterRoundRecipients(
  eventUserIds: Set<string>,
  playerUserIds: Set<string>,
) {
  const allUserIds = new Set([...eventUserIds, ...playerUserIds]);
  const ids = Array.from(allUserIds);
  if (ids.length === 0) {
    return { playerRecipients: [], eventRecipients: [] };
  }

  const { data } = await supabase
    .from("user_notification_preferences")
    .select("user_id,push_enabled,favorite_event_alerts,favorite_player_alerts")
    .in("user_id", ids);

  const prefsMap = new Map<string, Record<string, unknown>>();
  for (const row of data ?? []) {
    prefsMap.set(row.user_id as string, row);
  }

  const playerRecipients = new Set<string>();
  const eventRecipients = new Set<string>();

  for (const userId of ids) {
    const prefs = prefsMap.get(userId);
    if (prefs && prefs.push_enabled === false) continue;

    const isPlayerFav = playerUserIds.has(userId);
    const isEventFav = eventUserIds.has(userId);
    const playerAllowed = !prefs || prefs.favorite_player_alerts !== false;
    const eventAllowed = !prefs || prefs.favorite_event_alerts !== false;

    if (isPlayerFav && playerAllowed) {
      playerRecipients.add(userId);
      continue;
    }

    if (isEventFav && eventAllowed && !playerRecipients.has(userId)) {
      eventRecipients.add(userId);
    }
  }

  return {
    playerRecipients: Array.from(playerRecipients),
    eventRecipients: Array.from(eventRecipients),
  };
}

async function fetchLiveSubscriptions(gameId: string) {
  const { data, error } = await supabase
    .from("user_live_game_subscriptions")
    .select("user_id,platform,started_at")
    .eq("game_id", gameId)
    .eq("enabled", true);

  if (error) throw error;

  const ios: LiveSubscriptionRow[] = [];
  const android: LiveSubscriptionRow[] = [];

  for (const row of (data ?? []) as LiveSubscriptionRow[]) {
    if (row.platform === "ios") {
      ios.push(row);
    } else if (row.platform === "android") {
      android.push(row);
    }
  }

  return { ios, android };
}

async function filterLiveUpdateEnabled(userIds: string[]) {
  if (userIds.length === 0) return new Set<string>();

  const { data } = await supabase
    .from("user_notification_preferences")
    .select("user_id,push_enabled,live_game_updates")
    .in("user_id", userIds);

  const filtered = new Set<string>();
  const prefsMap = new Map<string, Record<string, unknown>>();
  for (const row of data ?? []) {
    prefsMap.set(row.user_id as string, row);
  }
  for (const id of userIds) {
    const prefs = prefsMap.get(id);
    if (prefs && prefs.push_enabled === false) continue;
    if (prefs && prefs.live_game_updates === false) continue;
    filtered.add(id);
  }
  return filtered;
}

async function fetchAndroidSubscriptionIds(userIds: string[]) {
  if (userIds.length === 0) return [];

  const { data } = await supabase
    .from("user_push_tokens")
    .select("subscription_id")
    .eq("provider", "onesignal")
    .eq("platform", "android")
    .eq("opted_in", true)
    .in("user_id", userIds);

  const ids = new Set<string>();
  for (const row of data ?? []) {
    if (row.subscription_id) ids.add(row.subscription_id as string);
  }
  return Array.from(ids);
}

async function markLiveSubscriptionEvent(args: {
  gameId: string;
  userIds: string[];
  platform: "ios" | "android";
  markStarted?: boolean;
}) {
  if (args.userIds.length === 0) return;

  const nowIso = new Date().toISOString();
  const update: Record<string, unknown> = { last_event_at: nowIso };
  if (args.markStarted) update.started_at = nowIso;

  await supabase
    .from("user_live_game_subscriptions")
    .update(update)
    .eq("game_id", args.gameId)
    .eq("platform", args.platform)
    .in("user_id", args.userIds);
}

async function filterHeadsUpRecipients(
  eventUserIds: Set<string>,
  playerUserIds: Set<string>,
) {
  const allUserIds = new Set([...eventUserIds, ...playerUserIds]);
  const ids = Array.from(allUserIds);
  if (ids.length === 0) {
    return { playerRecipients: [], eventRecipients: [] };
  }

  const { data } = await supabase
    .from("user_notification_preferences")
    .select(
      "user_id,push_enabled,favorite_event_alerts,favorite_player_alerts,heads_up_alerts",
    )
    .in("user_id", ids);

  const prefsMap = new Map<string, Record<string, unknown>>();
  for (const row of data ?? []) {
    prefsMap.set(row.user_id as string, row);
  }

  const playerRecipients = new Set<string>();
  const eventRecipients = new Set<string>();

  for (const userId of ids) {
    const prefs = prefsMap.get(userId);
    if (prefs && prefs.push_enabled === false) continue;
    if (prefs && prefs.heads_up_alerts === false) continue;

    const isPlayerFav = playerUserIds.has(userId);
    const isEventFav = eventUserIds.has(userId);
    const playerAllowed = !prefs || prefs.favorite_player_alerts !== false;
    const eventAllowed = !prefs || prefs.favorite_event_alerts !== false;

    if (isPlayerFav && playerAllowed) {
      playerRecipients.add(userId);
      continue;
    }

    if (isEventFav && eventAllowed && !playerRecipients.has(userId)) {
      eventRecipients.add(userId);
    }
  }

  return {
    playerRecipients: Array.from(playerRecipients),
    eventRecipients: Array.from(eventRecipients),
  };
}

type NotificationPayload = {
  title: string;
  body: string;
  url: string | null;
  data: Record<string, unknown>;
  androidChannelId?: string;
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
  eval_cp: number | null;
  eval_mate: number | null;
  player_white: string;
  player_black: string;
  event_name: string | null;
  round_name: string | null;
  white_fide_id: number | null;
  black_fide_id: number | null;
  white_photo: string | null;
  black_photo: string | null;
};

const ANDROID_CHANNELS = {
  favorites: "fav_updates",
  headsUp: "heads_up",
  live: "live_updates",
  general: "general",
} as const;

function channelForEvent(eventType: string) {
  switch (eventType) {
    case "round_heads_up":
      return ANDROID_CHANNELS.headsUp;
    case "live_game_update":
      return ANDROID_CHANNELS.live;
    case "round_started":
    case "game_started":
    case "game_finished":
      return ANDROID_CHANNELS.favorites;
    default:
      return ANDROID_CHANNELS.general;
  }
}

function buildNotification(
  context: {
    game: GameRow | null;
    round: RoundRow | null;
    eventName: string | null;
    groupBroadcastId: string | null;
  },
  item: OutboxItem,
): NotificationPayload {
  const payload = item.payload ?? {};
  const white = (payload.player_white as string) ?? context.game?.player_white ??
    "White";
  const black = (payload.player_black as string) ?? context.game?.player_black ??
    "Black";
  const status = (payload.status as string) ?? context.game?.status ?? "";
  const androidChannelId = channelForEvent(item.event_type);

  if (item.event_type === "game_started") {
    return {
      title: `Live: ${white} vs ${black}`,
      body: context.eventName
        ? `${context.eventName} is live now.`
        : "A favorite game just went live.",
      url: item.game_id ? `https://chessever.com/games/${item.game_id}` : null,
      data: { type: "game_started", game_id: item.game_id },
      androidChannelId,
    };
  }

  if (item.event_type === "game_finished") {
    return {
      title: `Final: ${white} vs ${black}`,
      body: status ? `Result: ${status}` : "A favorite game just finished.",
      url: item.game_id ? `https://chessever.com/games/${item.game_id}` : null,
      data: { type: "game_finished", game_id: item.game_id },
      androidChannelId,
    };
  }

  if (item.event_type === "live_game_update") {
    const lastMove = (payload.last_move as string) ?? "";
    return {
      title: `${white} vs ${black}`,
      body: lastMove
        ? `Latest move: ${lastMove}`
        : "Live game update.",
      url: item.game_id ? `https://chessever.com/games/${item.game_id}` : null,
      data: { type: "live_game_update", game_id: item.game_id },
      androidChannelId,
    };
  }

  return {
    title: "ChessEver update",
    body: "You have a new update.",
    url: null,
    data: { type: item.event_type },
    androidChannelId,
  };
}

function buildRoundNotification(
  context: {
    round: RoundRow | null;
    eventName: string | null;
    groupBroadcastId: string | null;
  },
  variant: "player" | "event",
): NotificationPayload {
  const roundName = context.round?.name ?? "New round";
  const eventName = context.eventName;
  const title = eventName ?? roundName;
  const label = [eventName, roundName].filter(Boolean).join(" ");

  const body = variant === "player"
    ? `${label || roundName} started — your favorite player(s) are playing`
    : eventName
    ? `Your favorite event ${label || roundName} has started`
    : `Your favorite event ${roundName} has started`;

  return {
    title,
    body,
    url: context.groupBroadcastId ? `https://chessever.com` : null,
    data: { type: "round_started", round_id: context.round?.id },
    androidChannelId: channelForEvent("round_started"),
  };
}

function buildHeadsUpNotification(
  context: {
    round: RoundRow | null;
    eventName: string | null;
    groupBroadcastId: string | null;
  },
  variant: "player" | "event",
): NotificationPayload {
  const roundName = context.round?.name ?? "Upcoming round";
  const eventName = context.eventName;
  const title = `Heads-up`;
  const label = [eventName, roundName].filter(Boolean).join(" ");

  const body = variant === "player"
    ? `${label || roundName} starts soon — your favorite player(s) are playing`
    : eventName
    ? `Your favorite event ${label || roundName} starts soon`
    : `Your favorite event ${roundName} starts soon`;

  return {
    title,
    body,
    url: context.groupBroadcastId ? `https://chessever.com` : null,
    data: { type: "round_heads_up", round_id: context.round?.id },
    androidChannelId: channelForEvent("round_heads_up"),
  };
}

async function buildLiveUpdatePayload(args: {
  item: OutboxItem;
  context: {
    game: GameRow | null;
    round: RoundRow | null;
    eventName: string | null;
  };
  evalSnapshot: EvalSnapshot | null;
}): LiveUpdatePayload {
  const payload = args.item.payload ?? {};
  const white = (payload.player_white as string) ??
    args.context.game?.player_white ?? "White";
  const black = (payload.player_black as string) ??
    args.context.game?.player_black ?? "Black";
  const fen = (payload.fen as string) ?? args.context.game?.fen ?? null;
  const lastMove = (payload.last_move as string) ??
    args.context.game?.last_move ?? null;
  const lastMoveUci = (payload.last_move_uci as string) ?? lastMove;
  const lastMoveTime = (payload.last_move_time as string) ??
    args.context.game?.last_move_time ?? null;
  const whiteClockSeconds =
    (payload.last_clock_white as number | null) ??
    args.context.game?.last_clock_white ?? null;
  const blackClockSeconds =
    (payload.last_clock_black as number | null) ??
    args.context.game?.last_clock_black ?? null;
  const players = (payload.players as Record<string, unknown>[] | null) ??
    args.context.game?.players ?? null;

  const san = uciToSan(lastMoveUci, fen);
  const numbered = formatMoveWithNumber(san, fen);
  const { whiteFide, blackFide } = extractFideIdsFromPlayers(
    players,
    white,
    black,
  );
  const [whitePhoto, blackPhoto] = await Promise.all([
    fetchFidePhotoUrl(whiteFide),
    fetchFidePhotoUrl(blackFide),
  ]);

  return {
    game_id: args.item.game_id ?? "",
    fen,
    last_move: lastMove,
    last_move_uci: lastMoveUci,
    last_move_san: san,
    last_move_numbered: numbered,
    last_move_time: lastMoveTime,
    white_clock_seconds: whiteClockSeconds,
    black_clock_seconds: blackClockSeconds,
    eval_cp: args.evalSnapshot?.cp ?? null,
    eval_mate: args.evalSnapshot?.mate ?? null,
    player_white: white,
    player_black: black,
    event_name: args.context.eventName ?? null,
    round_name: args.context.round?.name ?? null,
    white_fide_id: whiteFide,
    black_fide_id: blackFide,
    white_photo: whitePhoto,
    black_photo: blackPhoto,
  };
}

function buildLiveActivityId(gameId: string, userId: string) {
  return `live:${gameId}:${userId}`;
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
  if (role === "p" && from[0] !== to[0]) {
    move += `${from[0]}x`;
  }
  move += to;
  if (promotion) move += `=${promotion.toUpperCase()}`;
  return move;
}

function formatMoveWithNumber(move: string | null, fen: string | null) {
  if (!move || !fen) return move;
  const parts = fen.split(" ");
  if (parts.length < 6) return move;
  const sideToMove = parts[1];
  const fullMove = Number(parts[5]);
  if (!fullMove || Number.isNaN(fullMove)) return move;
  if (sideToMove === "b") {
    return `${fullMove}.${move}`;
  }
  const moveNumber = fullMove - 1;
  if (moveNumber <= 0) return move;
  return `${moveNumber}...${move}`;
}

function extractFideIdsFromPlayers(
  players: Record<string, unknown>[] | null,
  whiteName: string | null,
  blackName: string | null,
) {
  let whiteFide: number | null = null;
  let blackFide: number | null = null;

  if (Array.isArray(players)) {
    for (const raw of players) {
      const name = (raw?.name as string | undefined) ?? null;
      const fideId = raw?.fideId as number | undefined;
      if (!name || fideId == null) continue;
      if (whiteName && name === whiteName) whiteFide = fideId;
      if (blackName && name === blackName) blackFide = fideId;
    }
  }

  return { whiteFide, blackFide };
}

async function fetchFidePhotoUrl(fideId: number | null) {
  if (!fideId || fideId <= 0) return null;
  if (fidePhotoCache.has(fideId)) {
    return fidePhotoCache.get(fideId) ?? null;
  }

  try {
    const res = await fetch(
      `${SUPABASE_URL}/functions/v1/fetch-fide-photo?fide_id=${fideId}`,
      {
        headers: {
          Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
          apikey: SUPABASE_SERVICE_ROLE_KEY,
        },
      },
    );
    if (!res.ok) {
      fidePhotoCache.set(fideId, null);
      return null;
    }
    const json = await res.json();
    const url = typeof json?.url === "string" ? json.url : null;
    fidePhotoCache.set(fideId, url);
    return url;
  } catch (_) {
    fidePhotoCache.set(fideId, null);
    return null;
  }
}

function extractEvalFromPvs(pvs: unknown): EvalSnapshot | null {
  if (!Array.isArray(pvs) || pvs.length === 0) return null;
  const first = pvs[0] as Record<string, unknown>;
  let mate: number | null = null;
  let cp: number | null = null;

  if (first.mate !== undefined && first.mate !== null) {
    const parsed = Number(first.mate);
    if (!Number.isNaN(parsed)) mate = parsed;
  }

  if (mate === null && first.cp !== undefined && first.cp !== null) {
    const parsed = Number(first.cp);
    if (!Number.isNaN(parsed)) cp = parsed;
  }

  return { cp, mate, depth: null };
}

async function fetchEvalSnapshots(fens: string[]) {
  const result = new Map<string, EvalSnapshot>();
  if (fens.length === 0) return result;

  const { data: positions } = await supabase
    .from("positions")
    .select("id,fen")
    .in("fen", fens);

  if (!positions || positions.length === 0) return result;

  const posIds = positions.map((row) => row.id as number);
  const { data: evalRows } = await supabase
    .from("evals")
    .select("position_id,depth,pvs,multi_pv")
    .in("position_id", posIds);

  const bestByPosition = new Map<number, {
    depth: number | null;
    multiPv: number | null;
    pvs: unknown;
  }>();

  for (const row of evalRows ?? []) {
    const posId = row.position_id as number;
    const depth = row.depth as number | null;
    const multiPv = row.multi_pv as number | null;
    const pvs = row.pvs as unknown;

    if (!bestByPosition.has(posId)) {
      bestByPosition.set(posId, { depth, multiPv, pvs });
      continue;
    }

    const existing = bestByPosition.get(posId)!;
    const existingMulti = existing.multiPv ?? (Array.isArray(existing.pvs) ? existing.pvs.length : 0);
    const candidateMulti = multiPv ?? (Array.isArray(pvs) ? pvs.length : 0);

    if (
      candidateMulti > existingMulti ||
      (candidateMulti === existingMulti &&
        (depth ?? 0) > (existing.depth ?? 0))
    ) {
      bestByPosition.set(posId, { depth, multiPv, pvs });
    }
  }

  for (const pos of positions) {
    const posId = pos.id as number;
    const fen = pos.fen as string;
    const best = bestByPosition.get(posId);
    if (!best) continue;
    const snapshot = extractEvalFromPvs(best.pvs);
    if (snapshot) {
      snapshot.depth = best.depth ?? null;
      result.set(fen, snapshot);
    }
  }

  return result;
}

async function sendOneSignalPayload(payload: Record<string, unknown>) {
  const res = await fetch("https://onesignal.com/api/v1/notifications", {
    method: "POST",
    headers: {
      ...jsonHeaders,
      Authorization: `Basic ${ONESIGNAL_REST_API_KEY}`,
    },
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`OneSignal API error: ${res.status} ${text}`);
  }
}

async function sendLiveActivityUpdate(
  activityId: string,
  updateData: Record<string, unknown>,
) {
  const payload = {
    event: "update",
    name: `live_game_update:${activityId}`,
    event_updates: {
      data: updateData,
    },
  };

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

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`OneSignal Live Activity error: ${res.status} ${text}`);
  }
}

async function sendAndroidLiveNotification(args: {
  subscriptionIds: string[];
  livePayload: LiveUpdatePayload;
  event: "start" | "update" | "end";
}) {
  if (args.subscriptionIds.length === 0) return;

  const liveNotification = {
    key: "live_game",
    event: args.event,
    event_attributes: {
      game_id: args.livePayload.game_id,
      player_white: args.livePayload.player_white,
      player_black: args.livePayload.player_black,
      event_name: args.livePayload.event_name,
      round_name: args.livePayload.round_name,
      white_fide_id: args.livePayload.white_fide_id,
      black_fide_id: args.livePayload.black_fide_id,
      white_photo: args.livePayload.white_photo,
      black_photo: args.livePayload.black_photo,
    },
    event_updates: {
      fen: args.livePayload.fen,
      last_move: args.livePayload.last_move_numbered ??
        args.livePayload.last_move_san ?? args.livePayload.last_move,
      last_move_uci: args.livePayload.last_move_uci,
      last_move_time: args.livePayload.last_move_time,
      white_clock_seconds: args.livePayload.white_clock_seconds,
      black_clock_seconds: args.livePayload.black_clock_seconds,
      eval_cp: args.livePayload.eval_cp,
      eval_mate: args.livePayload.eval_mate,
    },
  };

  const payload: Record<string, unknown> = {
    app_id: ONESIGNAL_APP_ID,
    include_player_ids: args.subscriptionIds,
    headings: { en: `${args.livePayload.player_white} vs ${args.livePayload.player_black}` },
    contents: {
      en: args.livePayload.last_move_numbered ??
        args.livePayload.last_move_san ??
        "Live game update.",
    },
    data: {
      type: "live_game_update",
      game_id: args.livePayload.game_id,
      live_notification: liveNotification,
    },
    collapse_id: `live_game:${args.livePayload.game_id}`,
    isAndroid: true,
    target_channel: "push",
    android_channel_id: ANDROID_CHANNELS.live,
  };

  await sendOneSignalPayload(payload);
}

async function sendOneSignal(
  userIds: string[],
  notification: NotificationPayload,
) {
  const chunks = chunk(userIds, 1000);

  for (const batch of chunks) {
    const payload: Record<string, unknown> = {
      app_id: ONESIGNAL_APP_ID,
      include_external_user_ids: batch,
      headings: { en: notification.title },
      contents: { en: notification.body },
      data: notification.data,
    };

    if (notification.url) {
      payload.url = notification.url;
    }

    if (notification.androidChannelId) {
      payload.android_channel_id = notification.androidChannelId;
    }

    await sendOneSignalPayload(payload);
  }
}

function chunk<T>(list: T[], size: number) {
  const chunks: T[][] = [];
  for (let i = 0; i < list.length; i += size) {
    chunks.push(list.slice(i, i + size));
  }
  return chunks;
}
