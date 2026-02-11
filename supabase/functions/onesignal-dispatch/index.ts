import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { Chess } from "npm:chess.js@1.0.0";

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
  created_at: string;
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

type CheckState = {
  isCheck: boolean;
  isCheckmate: boolean;
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    Deno.env.get("SERVICE_ROLE_KEY") ??
    "";
const ONESIGNAL_APP_ID = Deno.env.get("ONESIGNAL_APP_ID") ?? "";
const ONESIGNAL_REST_API_KEY = Deno.env.get("ONESIGNAL_REST_API_KEY") ?? "";
const LICHESS_CLOUD_EVAL_KEY = Deno.env.get("LICHESS_CLOUD_EVAL_KEY") ?? "";
const CHESS_API_URL = Deno.env.get("CHESS_API_URL") ?? "https://chess-api.com/v1";
const STREAM_DISPATCH_TOKEN = Deno.env.get("STREAM_DISPATCH_TOKEN") ?? "";

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
const CLOUD_EVAL_MAX_REQUESTS = 5;
const CHESS_API_MAX_REQUESTS = 10;
const cloudEvalCache = new Map<string, EvalSnapshot | null>();
const chessApiEvalCache = new Map<string, EvalSnapshot | null>();
const dispatchTokenCache: { token: string | null; expiresAtMs: number } = {
  token: null,
  expiresAtMs: 0,
};

type CloudEvalState = {
  remaining: number;
  chessApiRemaining: number;
};

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }
  const requiredToken = await resolveDispatchToken();
  if (requiredToken) {
    const provided = req.headers.get("x-stream-token") ?? "";
    if (provided !== requiredToken) {
      return new Response("Unauthorized", { status: 401 });
    }
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
  const cloudEvalState: CloudEvalState = {
    remaining: CLOUD_EVAL_MAX_REQUESTS,
    chessApiRemaining: CHESS_API_MAX_REQUESTS,
  };

  for (const item of items) {
    const result = await processItem(item, cloudEvalState);
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

async function resolveDispatchToken(): Promise<string | null> {
  if (STREAM_DISPATCH_TOKEN) return STREAM_DISPATCH_TOKEN;

  const now = Date.now();
  if (dispatchTokenCache.expiresAtMs > now) return dispatchTokenCache.token;

  const { data, error } = await supabase.rpc("get_vault_secret", {
    secret_name: "live_dispatch_token",
  });

  if (error) {
    // Cache the miss briefly to avoid hammering the DB on transient failures.
    dispatchTokenCache.token = null;
    dispatchTokenCache.expiresAtMs = now + 15_000;
    return null;
  }

  const token = typeof data === "string" && data.length > 0 ? data : null;
  dispatchTokenCache.token = token;
  dispatchTokenCache.expiresAtMs = now + 60_000;
  return token;
}

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

const STALE_THRESHOLD_MS = 60 * 60 * 1000; // 1 hour

async function processItem(item: OutboxItem, cloudEvalState: CloudEvalState) {
  // Skip stale items to prevent sending outdated notifications
  const createdAt = new Date(item.created_at);
  if (Date.now() - createdAt.getTime() > STALE_THRESHOLD_MS) {
    await markSkipped(item.id, "stale");
    return { id: item.id, status: "skipped", reason: "stale" };
  }

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
      const evalSnapshots = await fetchEvalSnapshots(fen ? [fen] : [], {
        allowCloudEval: true,
        cloudEvalState,
      });
      const evalSnapshot = fen ? evalSnapshots.get(fen) ?? null : null;

      const livePayload = await buildLiveUpdatePayload({
        item,
        context,
        evalSnapshot,
      });

      const boardSettingsByUser = await fetchBoardSettings([
        ...new Set([
          ...iosEligible.map((row) => row.user_id),
          ...androidEligible.map((row) => row.user_id),
        ]),
      ]);

      const payloadForUser = (userId: string) => {
        const settings = boardSettingsByUser.get(userId);
        return {
          ...livePayload,
          board_theme_index: settings?.board_theme_index ?? 0,
          piece_style_index: settings?.piece_style_index ?? 0,
        };
      };

      const iosNotFound: string[] = [];
      for (const row of iosEligible) {
        const activityId = buildLiveActivityId(item.game_id, row.user_id);
        const updateResult = await sendLiveActivityUpdate(
          activityId,
          payloadForUser(row.user_id),
        );
        if (!updateResult.ok && updateResult.notFound) {
          iosNotFound.push(row.user_id);
        }
        if (livePayload.is_game_over) {
          await sendLiveActivityEnd(activityId);
        }
      }

      if (iosEligible.length > 0) {
        await markLiveSubscriptionEvent({
          gameId: item.game_id,
          userIds: iosEligible.map((row) => row.user_id),
          platform: "ios",
        });
      }

      if (iosNotFound.length > 0) {
        await disableLiveSubscriptions({
          gameId: item.game_id,
          userIds: iosNotFound,
          platform: "ios",
        });
      }

      const androidGroups = new Map<
        string,
        {
          rows: LiveSubscriptionRow[];
          boardThemeIndex: number;
          pieceStyleIndex: number;
        }
      >();

      for (const row of androidEligible) {
        const settings = boardSettingsByUser.get(row.user_id);
        const boardThemeIndex = settings?.board_theme_index ?? 0;
        const pieceStyleIndex = settings?.piece_style_index ?? 0;
        const key = `${boardThemeIndex}:${pieceStyleIndex}`;
        if (!androidGroups.has(key)) {
          androidGroups.set(key, {
            rows: [],
            boardThemeIndex,
            pieceStyleIndex,
          });
        }
        androidGroups.get(key)!.rows.push(row);
      }

      for (const group of androidGroups.values()) {
        const androidNewUsers = group.rows
          .filter((row) => !row.started_at)
          .map((row) => row.user_id);
        const androidExistingUsers = group.rows
          .filter((row) => row.started_at)
          .map((row) => row.user_id);

        const newSubscriptionIds = await fetchAndroidSubscriptionIds(
          androidNewUsers,
        );
        const existingSubscriptionIds = await fetchAndroidSubscriptionIds(
          androidExistingUsers,
        );

        const groupPayload = {
          ...livePayload,
          board_theme_index: group.boardThemeIndex,
          piece_style_index: group.pieceStyleIndex,
        };

        if (!livePayload.is_game_over) {
          if (newSubscriptionIds.length > 0) {
            await sendAndroidLiveNotification({
              subscriptionIds: newSubscriptionIds,
              livePayload: groupPayload,
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
              livePayload: groupPayload,
              event: "update",
            });
            await markLiveSubscriptionEvent({
              gameId: item.game_id,
              userIds: androidExistingUsers,
              platform: "android",
            });
          }
        } else if (existingSubscriptionIds.length > 0) {
          await sendAndroidLiveNotification({
            subscriptionIds: existingSubscriptionIds,
            livePayload: groupPayload,
            event: "end",
          });
        }

        if (livePayload.is_game_over) {
          const allUsers = [...androidNewUsers, ...androidExistingUsers];
          if (allUsers.length > 0) {
            await disableLiveSubscriptions({
              gameId: item.game_id,
              userIds: allUsers,
              platform: "android",
            });
          }
        }
      }

      const alertReason = resolveLiveAlertReason(livePayload);
      if (alertReason) {
        const alertUsers = Array.from(
          new Set([
            ...iosEligible.map((row) => row.user_id),
            ...androidEligible.map((row) => row.user_id),
          ]),
        );
        if (alertUsers.length > 0) {
          await sendLiveGameAlert(alertUsers, livePayload, alertReason);
        }
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

      const roundId = item.round_id ?? context.round?.id ?? "";
      const eventName = context.eventName ?? "Live chess";
      const roundName = context.round?.name ?? "";

      // Send personalized player notifications grouped by player combo
      if (playerRecipients.length > 0) {
        const groups = groupUsersByPlayerCombo(context.playerFavoriteMap);
        for (const [, groupUserIds] of groups) {
          const eligible = groupUserIds.filter((id) =>
            playerRecipients.includes(id),
          );
          if (eligible.length === 0) continue;
          // Use the first user's player list (all in this group share the same set)
          const playerNames =
            context.playerFavoriteMap.get(eligible[0]) ?? [];
          const playersStr = formatPlayersList(playerNames);
          const template = pickTemplate(ROUND_STARTED_PLAYER, roundId);
          const { title, body } = fillTemplate(template, {
            p: playersStr,
            e: eventName,
            r: roundName,
          });
          await sendOneSignal(eligible, {
            title,
            body,
            url: null,
            data: { type: "round_started", round_id: roundId, group_broadcast_id: context.groupBroadcastId ?? null },
            androidChannelId: channelForEvent("round_started"),
          });
        }
        // Also send to player recipients not in any group (no resolved favorite map entry)
        const groupedUsers = new Set(
          Array.from(context.playerFavoriteMap.keys()),
        );
        const ungrouped = playerRecipients.filter(
          (id) => !groupedUsers.has(id),
        );
        if (ungrouped.length > 0) {
          const template = pickTemplate(ROUND_STARTED_EVENT, roundId);
          const { title, body } = fillTemplate(template, { e: eventName, r: roundName });
          await sendOneSignal(ungrouped, {
            title,
            body,
            url: null,
            data: { type: "round_started", round_id: roundId, group_broadcast_id: context.groupBroadcastId ?? null },
            androidChannelId: channelForEvent("round_started"),
          });
        }
      }

      if (eventRecipients.length > 0) {
        const template = pickTemplate(ROUND_STARTED_EVENT, roundId);
        const { title, body } = fillTemplate(template, { e: eventName, r: roundName });
        await sendOneSignal(eventRecipients, {
          title,
          body,
          url: null,
          data: { type: "round_started", round_id: roundId, group_broadcast_id: context.groupBroadcastId ?? null },
          androidChannelId: channelForEvent("round_started"),
        });
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

      const roundId = item.round_id ?? context.round?.id ?? "";
      const eventName = context.eventName ?? "Live chess";
      const roundName = context.round?.name ?? "";
      const leadMinutes = (item.payload?.lead_minutes as number) ?? 30;
      const timeStr = `~${leadMinutes} min`;

      // Send personalized player notifications grouped by player combo
      if (playerRecipients.length > 0) {
        const groups = groupUsersByPlayerCombo(context.playerFavoriteMap);
        for (const [, groupUserIds] of groups) {
          const eligible = groupUserIds.filter((id) =>
            playerRecipients.includes(id),
          );
          if (eligible.length === 0) continue;
          const playerNames =
            context.playerFavoriteMap.get(eligible[0]) ?? [];
          const playersStr = formatPlayersList(playerNames);
          const template = pickTemplate(ROUND_HEADS_UP_PLAYER, roundId);
          const { title, body } = fillTemplate(template, {
            p: playersStr,
            e: eventName,
            r: roundName,
            t: timeStr,
          });
          await sendOneSignal(eligible, {
            title,
            body,
            url: null,
            data: { type: "round_heads_up", round_id: roundId, group_broadcast_id: context.groupBroadcastId ?? null },
            androidChannelId: channelForEvent("round_heads_up"),
          });
        }
        // Ungrouped player recipients
        const groupedUsers = new Set(
          Array.from(context.playerFavoriteMap.keys()),
        );
        const ungrouped = playerRecipients.filter(
          (id) => !groupedUsers.has(id),
        );
        if (ungrouped.length > 0) {
          const template = pickTemplate(ROUND_HEADS_UP_EVENT, roundId);
          const { title, body } = fillTemplate(template, {
            e: eventName,
            r: roundName,
            t: timeStr,
          });
          await sendOneSignal(ungrouped, {
            title,
            body,
            url: null,
            data: { type: "round_heads_up", round_id: roundId, group_broadcast_id: context.groupBroadcastId ?? null },
            androidChannelId: channelForEvent("round_heads_up"),
          });
        }
      }

      if (eventRecipients.length > 0) {
        const template = pickTemplate(ROUND_HEADS_UP_EVENT, roundId);
        const { title, body } = fillTemplate(template, {
          e: eventName,
          r: roundName,
          t: timeStr,
        });
        await sendOneSignal(eventRecipients, {
          title,
          body,
          url: null,
          data: { type: "round_heads_up", round_id: roundId, group_broadcast_id: context.groupBroadcastId ?? null },
          androidChannelId: channelForEvent("round_heads_up"),
        });
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

  // Resolve per-user player favorites for round notifications
  let playerFavoriteMap = new Map<string, string[]>();
  if (
    (item.event_type === "round_started" ||
      item.event_type === "round_heads_up") &&
    item.round_id
  ) {
    playerFavoriteMap = await resolvePlayerFavoriteMap(
      item.round_id,
      playerUserIds,
    );
  }

  return {
    game,
    round,
    eventName,
    groupBroadcastId,
    eventUserIds,
    playerUserIds,
    playerFavoriteMap,
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
      "user_id,push_enabled,favorite_event_alerts,favorite_player_alerts,live_game_updates,daily_digest,call_to_action_alerts",
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
      // Only player-favorite users get individual game notifications.
      // Event-favorite users only receive round-level notifications.
      const playerAllowed = !prefs || prefs.favorite_player_alerts !== false;
      if (isPlayerFav && playerAllowed) {
        filtered.add(userId);
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

    if (eventType === "call_to_action") {
      // Off by default — only send to users who explicitly opted in
      if (!prefs || prefs.call_to_action_alerts !== true) {
        continue;
      }
      filtered.add(userId);
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

async function fetchBoardSettings(userIds: string[]) {
  if (userIds.length === 0) return new Map<string, UserBoardSettings>();

  const { data } = await supabase
    .from("user_engine_settings")
    .select("user_id,board_theme_index,piece_style_index")
    .in("user_id", userIds);

  const map = new Map<string, UserBoardSettings>();
  for (const row of data ?? []) {
    map.set(row.user_id as string, {
      board_theme_index: (row.board_theme_index as number | null) ?? 0,
      piece_style_index: (row.piece_style_index as number | null) ?? 0,
    });
  }
  return map;
}

async function disableLiveSubscriptions(args: {
  gameId: string;
  userIds: string[];
  platform: "ios" | "android";
}) {
  if (args.userIds.length === 0) return;
  await supabase
    .from("user_live_game_subscriptions")
    .update({ enabled: false })
    .eq("game_id", args.gameId)
    .eq("platform", args.platform)
    .in("user_id", args.userIds);
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
  iosSound?: string;
  androidSound?: string;
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
  is_check: boolean;
  is_checkmate: boolean;
  is_game_over: boolean;
  status: string | null;
};

type UserBoardSettings = {
  board_theme_index: number | null;
  piece_style_index: number | null;
};

const ANDROID_CHANNELS = {
  favorites: "fav_updates",
  headsUp: "heads_up",
  live: "live_updates",
  liveAlerts: "live_alerts",
  callToAction: "call_to_action",
  general: "general",
} as const;

// --- Smart notification templates ---

type Template = { title: string; body: string };

const ROUND_STARTED_PLAYER: Template[] = [
  { title: "{e} — {r}", body: "{p} at the board. Games are live." },
  { title: "{e} is live", body: "{r}: {p} just started" },
  { title: "{e} — {r}", body: "{p} playing right now" },
  { title: "{e}", body: "{r} started. {p} at the board." },
  { title: "It's on", body: "{p} live in {e} — {r}" },
  { title: "{e} — {r}", body: "{p} at the board right now" },
  { title: "{e}", body: "{r}: {p} just sat down. Games are live." },
  { title: "Your move", body: "{p} live in {e} — {r}. Are you watching?" },
  { title: "{e} — {r}", body: "{p} on the board. Watch live." },
  { title: "{e} is live", body: "{r}: {p} already making moves" },
  { title: "{e} — {r}", body: "The wait is over. {p} live now." },
  { title: "{e}", body: "{r}: {p} just kicked off" },
  { title: "{e} — {r}", body: "{p} at the board. Don't miss it." },
  { title: "{e}", body: "{r}: {p} live now. Get in here." },
  { title: "{e} — {r}", body: "{p} playing. Follow along." },
];

const ROUND_STARTED_EVENT: Template[] = [
  { title: "{e} — {r}", body: "Games are live" },
  { title: "{e} is live", body: "{r}: First moves have been played" },
  { title: "{e} — {r}", body: "Games just started" },
  { title: "{e}", body: "{r} started. Watch live." },
  { title: "{e} — {r}", body: "The wait is over. Games are live." },
  { title: "{e} is live", body: "{r}. Don't miss it." },
  { title: "{e} — {r}", body: "It's live. Get in here." },
  { title: "{e}", body: "{r} is underway. Follow the games live." },
  { title: "{e} — {r}", body: "The round just started" },
  { title: "{e}", body: "{r} started. Games are live now." },
];

const ROUND_HEADS_UP_PLAYER: Template[] = [
  { title: "{e} — {r}", body: "{p} at the board in {t}" },
  { title: "Heads up", body: "{p} in {e} {r}. {t} to go." },
  { title: "{e} in {t}", body: "{r}: {p} on the schedule" },
  { title: "{e} — {r}", body: "{p} in about {t}. Don't forget." },
  { title: "Heads up", body: "{p} in {t}. {e} — {r}." },
  { title: "{e} — {r}", body: "{p} in about {t}" },
  { title: "{e}", body: "{r}: {p} at the board in {t}. Got time?" },
  { title: "Heads up", body: "{r} in {t}. {p} at the board." },
  { title: "{e} — {r}", body: "{t} to go. {p} on the schedule." },
  { title: "Almost time", body: "{p} in {e} {r}. About {t}." },
  { title: "{e} — {r}", body: "{p} coming up in {t}" },
  { title: "Heads up", body: "{p} in {t}. {e} — {r}." },
  { title: "{e}", body: "{r}: {p} in {t}. Clear your schedule." },
  { title: "{e} — {r}", body: "{t} until {p} at the board" },
  { title: "Heads up", body: "{p} in {e} {r}. About {t} out." },
];

const ROUND_HEADS_UP_EVENT: Template[] = [
  { title: "Heads up", body: "{e} {r} starts in {t}" },
  { title: "{e} — {r}", body: "Starting in {t}" },
  { title: "{e} in {t}", body: "{r} starting soon" },
  { title: "Heads up", body: "{e} {r} in {t}. Set a reminder." },
  { title: "{e} — {r}", body: "About {t} to go" },
  { title: "{e}", body: "{r} starts in {t}. Don't miss it." },
  { title: "Heads up", body: "{e} {r} in about {t}" },
  { title: "{e} — {r}", body: "{t} to go" },
  { title: "Almost time", body: "{e} {r} in {t}" },
  { title: "{e}", body: "{r}: {t} until games begin" },
];

function pickTemplate(templates: Template[], roundId: string): Template {
  let hash = 0;
  for (let i = 0; i < roundId.length; i++) {
    hash = ((hash << 5) - hash + roundId.charCodeAt(i)) | 0;
  }
  return templates[Math.abs(hash) % templates.length];
}

function fillTemplate(
  template: Template,
  vars: { p?: string; e: string; r?: string; t?: string },
): { title: string; body: string } {
  const replace = (s: string) => {
    let result = s
      .replace(/\{p\}/g, vars.p ?? "")
      .replace(/\{e\}/g, vars.e)
      .replace(/\{r\}/g, vars.r ?? "")
      .replace(/\{t\}/g, vars.t ?? "");
    // Clean up dangling separators when round name is empty
    result = result
      .replace(/ — (?=\.|,|$)/g, "")  // "Event — ." → "Event."
      .replace(/ — \s*$/g, "")          // "Event — " → "Event"
      .replace(/:\s*\./g, ".")           // ": ." → "."
      .replace(/:\s*$/g, "")             // trailing ":"
      .replace(/\s{2,}/g, " ")          // collapse double spaces
      .trim();
    return result;
  };
  return { title: replace(template.title), body: replace(template.body) };
}

function extractLastName(name: string): string {
  const trimmed = name.trim();
  // "Carlsen, Magnus" or "GM Carlsen, Magnus" → "Carlsen"
  if (trimmed.includes(",")) {
    const before = trimmed.split(",")[0].trim();
    // Strip title prefix: "GM Carlsen" → "Carlsen"
    const parts = before.split(/\s+/);
    return parts.length > 1 ? parts[parts.length - 1] : parts[0];
  }
  // "Gukesh D" → "Gukesh" (last word is single letter)
  const parts = trimmed.split(/\s+/);
  if (parts.length >= 2 && parts[parts.length - 1].length <= 2) {
    return parts[parts.length - 2];
  }
  // Fallback: last word
  return parts[parts.length - 1];
}

function formatPlayersList(names: string[]): string {
  // Deduplicate by last name
  const seen = new Set<string>();
  const unique: string[] = [];
  for (const name of names) {
    const last = extractLastName(name).toLowerCase();
    if (!seen.has(last)) {
      seen.add(last);
      unique.push(extractLastName(name));
    }
  }

  if (unique.length === 0) return "";
  if (unique.length === 1) return unique[0];
  if (unique.length === 2) return `${unique[0]} & ${unique[1]}`;
  if (unique.length === 3) {
    return `${unique[0]}, ${unique[1]} & 1 more`;
  }
  return `${unique[0]}, ${unique[1]} & ${unique.length - 2} more of your favorites`;
}

async function resolvePlayerFavoriteMap(
  roundId: string,
  playerUserIds: Set<string>,
): Promise<Map<string, string[]>> {
  // Returns Map<userId, playerName[]> — which specific round players each user favorited.
  const result = new Map<string, string[]>();
  if (playerUserIds.size === 0) return result;

  // Get all games in this round to know which players are participating
  const { data: games } = await supabase
    .from("games")
    .select("player_white,player_black,player_fide_ids")
    .eq("round_id", roundId);

  if (!games || games.length === 0) return result;

  const roundFideIds = new Set<string>();
  const roundPlayerNames = new Set<string>();
  const fideIdToName = new Map<string, string>();

  for (const g of games as RoundGameRow[]) {
    if (g.player_white) {
      roundPlayerNames.add(g.player_white);
    }
    if (g.player_black) {
      roundPlayerNames.add(g.player_black);
    }
    if (g.player_fide_ids) {
      for (let i = 0; i < g.player_fide_ids.length; i++) {
        const fid = g.player_fide_ids[i].toString();
        roundFideIds.add(fid);
        // Map fide_id to player name for display
        const name = i === 0 ? g.player_white : g.player_black;
        if (name) fideIdToName.set(fid, name);
      }
    }
  }

  const userIds = Array.from(playerUserIds);

  // Fetch by fide_id
  if (roundFideIds.size > 0) {
    const { data: faveByFide } = await supabase
      .from("user_favorite_players")
      .select("user_id,fide_id")
      .in("user_id", userIds)
      .in("fide_id", Array.from(roundFideIds));

    for (const row of faveByFide ?? []) {
      const userId = row.user_id as string;
      const fideId = (row.fide_id as number).toString();
      const name = fideIdToName.get(fideId);
      if (name) {
        if (!result.has(userId)) result.set(userId, []);
        result.get(userId)!.push(name);
      }
    }
  }

  // Fetch by player_name (fallback for players without fide_id matches)
  if (roundPlayerNames.size > 0) {
    const { data: faveByName } = await supabase
      .from("user_favorite_players")
      .select("user_id,player_name")
      .in("user_id", userIds)
      .in("player_name", Array.from(roundPlayerNames));

    for (const row of faveByName ?? []) {
      const userId = row.user_id as string;
      const name = row.player_name as string;
      if (!result.has(userId)) result.set(userId, []);
      const existing = result.get(userId)!;
      // Deduplicate: don't add if last name already present from fide_id match
      const lastNameLower = extractLastName(name).toLowerCase();
      const alreadyHas = existing.some(
        (n) => extractLastName(n).toLowerCase() === lastNameLower,
      );
      if (!alreadyHas) {
        existing.push(name);
      }
    }
  }

  return result;
}

function groupUsersByPlayerCombo(
  playerFavoriteMap: Map<string, string[]>,
): Map<string, string[]> {
  // Groups users who share the same set of favorite players for this round.
  // Key: sorted player names joined by "|", Value: user IDs
  const groups = new Map<string, string[]>();
  for (const [userId, names] of playerFavoriteMap) {
    const key = names
      .map((n) => extractLastName(n).toLowerCase())
      .sort()
      .join("|");
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key)!.push(userId);
  }
  return groups;
}

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
    case "call_to_action":
      return ANDROID_CHANNELS.callToAction;
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
      url: null,
      data: { type: "game_started", game_id: item.game_id },
      androidChannelId,
    };
  }

  if (item.event_type === "game_finished") {
    return {
      title: `Final: ${white} vs ${black}`,
      body: status ? `Result: ${status}` : "A favorite game just finished.",
      url: null,
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
      url: null,
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

// buildRoundNotification and buildHeadsUpNotification replaced by
// personalized template system in processItem() handlers above.

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
  const status = (payload.status as string) ?? args.context.game?.status ?? null;
  const whiteClockSeconds =
    (payload.last_clock_white as number | null) ??
    args.context.game?.last_clock_white ?? null;
  const blackClockSeconds =
    (payload.last_clock_black as number | null) ??
    args.context.game?.last_clock_black ?? null;
  const players = (payload.players as Record<string, unknown>[] | null) ??
    args.context.game?.players ?? null;

  const checkState = analyzePosition(fen);
  const rawSan = uciToSan(lastMoveUci, fen);
  const san = appendCheckSuffix(rawSan, checkState);
  const numbered = formatMoveWithNumber(san, fen);
  const { whiteFide, blackFide } = extractFideIdsFromPlayers(
    players,
    white,
    black,
  );
  const { whiteTitle, blackTitle, whiteFed, blackFed } = extractPlayerMeta(
    players,
    white,
    black,
    whiteFide,
    blackFide,
  );
  const [whitePhoto, blackPhoto] = await Promise.all([
    fetchFidePhotoUrl(whiteFide),
    fetchFidePhotoUrl(blackFide),
  ]);
  const isGameOver = isGameOverStatus(status);

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
    board_theme_index: null,
    piece_style_index: null,
    player_white: white,
    player_black: black,
    event_name: args.context.eventName ?? null,
    round_name: args.context.round?.name ?? null,
    white_fide_id: whiteFide,
    black_fide_id: blackFide,
    white_photo: whitePhoto,
    black_photo: blackPhoto,
    white_title: whiteTitle,
    black_title: blackTitle,
    white_fed: whiteFed,
    black_fed: blackFed,
    is_check: checkState.isCheck,
    is_checkmate: checkState.isCheckmate,
    is_game_over: isGameOver,
    status,
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

function analyzePosition(fen: string | null): CheckState {
  if (!fen) return { isCheck: false, isCheckmate: false };
  try {
    const chess = new Chess(fen);
    return { isCheck: chess.isCheck(), isCheckmate: chess.isCheckmate() };
  } catch (_) {
    return { isCheck: false, isCheckmate: false };
  }
}

function appendCheckSuffix(move: string | null, checkState: CheckState) {
  if (!move) return move;
  if (move.includes("#") || move.includes("+")) return move;
  if (checkState.isCheckmate) return `${move}#`;
  if (checkState.isCheck) return `${move}+`;
  return move;
}

function isGameOverStatus(status: string | null) {
  if (!status) return false;
  const trimmed = status.trim().toLowerCase();
  if (trimmed.length === 0) return false;
  return trimmed !== "*" && trimmed !== "ongoing";
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
      const fideId = raw?.fideId as number | undefined;
      const title = (raw?.title as string | undefined) ?? null;
      const fed = (raw?.fed as string | undefined) ?? null;

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

  return { whiteTitle, blackTitle, whiteFed, blackFed };
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

function parseSideToMove(fen: string): "w" | "b" | null {
  const parts = fen.split(" ");
  if (parts.length < 2) return null;
  const side = parts[1];
  return side === "w" || side === "b" ? side : null;
}

function estimateMaterialCpFromFen(fen: string): number | null {
  const grid = parseFenBoard(fen);
  if (!grid) return null;

  // Centipawn-style values (positive = white advantage).
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
      const val = values[piece.toLowerCase()] ?? 0;
      cp += piece === piece.toUpperCase() ? val : -val;
    }
  }

  // Clamp to avoid absurd spikes in the UI. Widgets clamp anyway, but keeping
  // this bounded makes payloads predictable.
  return Math.max(-2500, Math.min(2500, cp));
}

function estimateEvalSnapshotFromFen(fen: string): EvalSnapshot | null {
  // Best-effort fallback: material balance (white perspective). This is only
  // used when we have no engine/cloud evaluation available.
  const side = parseSideToMove(fen);
  const check = analyzePosition(fen);
  if (check.isCheckmate && side) {
    // Side to move is checkmated, so the other side has won.
    const mate = side === "w" ? -1 : 1;
    return { cp: null, mate, depth: 0 };
  }

  const cp = estimateMaterialCpFromFen(fen);
  if (cp == null) return { cp: 0, mate: null, depth: 0 };
  return { cp, mate: null, depth: 0 };
}

async function fetchEvalSnapshots(
  fens: string[],
  options?: {
    allowCloudEval?: boolean;
    cloudEvalState?: CloudEvalState;
  },
) {
  const result = new Map<string, EvalSnapshot>();
  if (fens.length === 0) return result;

  const uniqueFens = Array.from(new Set(fens));

  const { data: positions } = await supabase
    .from("positions")
    .select("id,fen")
    .in("fen", uniqueFens);

  const existingPositions = positions ?? [];
  const existingByFen = new Map<string, number>();
  for (const row of existingPositions) {
    existingByFen.set(row.fen as string, row.id as number);
  }

  const missingFens = uniqueFens.filter((fen) => !existingByFen.has(fen));
  if (missingFens.length > 0 && options?.allowCloudEval) {
    await supabase
      .from("positions")
      .upsert(
        missingFens.map((fen) => ({ fen })),
        { onConflict: "fen", ignoreDuplicates: true },
      );
  }

  const { data: refreshedPositions } = await supabase
    .from("positions")
    .select("id,fen")
    .in("fen", uniqueFens);

  if (!refreshedPositions || refreshedPositions.length === 0) return result;

  const posIds = refreshedPositions.map((row) => row.id as number);
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

  const evalByFen = new Map<string, EvalSnapshot>();
  for (const pos of refreshedPositions) {
    const posId = pos.id as number;
    const fen = pos.fen as string;
    const best = bestByPosition.get(posId);
    if (!best) continue;
    const snapshot = extractEvalFromPvs(best.pvs);
    if (snapshot) {
      snapshot.depth = best.depth ?? null;
      result.set(fen, snapshot);
      evalByFen.set(fen, snapshot);
    }
  }

  if (!options?.allowCloudEval || !options.cloudEvalState) {
    return result;
  }

  const missingEvalFens = uniqueFens.filter((fen) => {
    const snapshot = evalByFen.get(fen);
    if (!snapshot) return true;
    if (snapshot.cp == null && snapshot.mate == null) return true;
    return false;
  });
  if (missingEvalFens.length === 0) {
    return result;
  }

  for (const fen of missingEvalFens) {
    let snapshot = await fetchCloudEvalSnapshot(fen, options.cloudEvalState);
    if (!snapshot) {
      snapshot = await fetchChessApiEvalSnapshot(
        fen,
        options.cloudEvalState,
      );
    }
    if (!snapshot) {
      snapshot = estimateEvalSnapshotFromFen(fen);
    }
    if (!snapshot) continue;

    const positionId = refreshedPositions.find((row) => row.fen === fen)?.id;
    if (positionId) {
      await storeEvalSnapshot(positionId as number, snapshot);
      result.set(fen, snapshot);
    }
  }

  return result;
}

async function fetchCloudEvalSnapshot(
  fen: string,
  cloudEvalState: CloudEvalState,
): Promise<EvalSnapshot | null> {
  if (cloudEvalCache.has(fen)) {
    return cloudEvalCache.get(fen) ?? null;
  }

  if (cloudEvalState.remaining <= 0) {
    return null;
  }

  cloudEvalState.remaining -= 1;

  try {
    const url = new URL("https://lichess.org/api/cloud-eval");
    url.searchParams.set("fen", fen);
    url.searchParams.set("multiPv", "1");

    const headers: Record<string, string> = {
      Accept: "application/json",
    };
    if (LICHESS_CLOUD_EVAL_KEY) {
      headers.Authorization = `Bearer ${LICHESS_CLOUD_EVAL_KEY}`;
    }

    const res = await fetch(url.toString(), {
      headers,
    });

    if (res.status === 404) {
      cloudEvalCache.set(fen, null);
      return null;
    }

    if (!res.ok) {
      cloudEvalCache.set(fen, null);
      return null;
    }

    const json = await res.json();
    const pvs = Array.isArray(json?.pvs) ? json.pvs : [];
    const depth = typeof json?.depth === "number" ? json.depth : null;

    if (pvs.length === 0) {
      cloudEvalCache.set(fen, null);
      return null;
    }

    const snapshot = extractEvalFromPvs(pvs);
    if (!snapshot) {
      cloudEvalCache.set(fen, null);
      return null;
    }

    snapshot.depth = depth ?? null;
    cloudEvalCache.set(fen, snapshot);
    return snapshot;
  } catch (_) {
    cloudEvalCache.set(fen, null);
    return null;
  }
}

async function fetchChessApiEvalSnapshot(
  fen: string,
  cloudEvalState: CloudEvalState,
): Promise<EvalSnapshot | null> {
  if (chessApiEvalCache.has(fen)) {
    return chessApiEvalCache.get(fen) ?? null;
  }

  if (cloudEvalState.chessApiRemaining <= 0) {
    return null;
  }

  cloudEvalState.chessApiRemaining -= 1;

  try {
    const res = await fetch(CHESS_API_URL, {
      method: "POST",
      headers: jsonHeaders,
      body: JSON.stringify({ fen, depth: 12, variants: 1 }),
    });

    if (!res.ok) {
      chessApiEvalCache.set(fen, null);
      return null;
    }

    const json = await res.json();
    const depth = typeof json?.depth === "number" ? json.depth : 12;
    const mate = json?.mate != null ? Number(json.mate) : null;
    let cp: number | null = null;

    if (mate == null) {
      const centipawnsRaw = json?.centipawns;
      if (centipawnsRaw != null) {
        const parsed = Number(centipawnsRaw);
        if (!Number.isNaN(parsed)) cp = parsed;
      } else if (json?.eval != null) {
        const parsed = Number(json.eval);
        if (!Number.isNaN(parsed)) cp = Math.round(parsed * 100);
      }
    }

    if (cp == null && mate == null) {
      chessApiEvalCache.set(fen, null);
      return null;
    }

    const snapshot: EvalSnapshot = { cp, mate, depth };
    chessApiEvalCache.set(fen, snapshot);
    return snapshot;
  } catch (_) {
    chessApiEvalCache.set(fen, null);
    return null;
  }
}

async function storeEvalSnapshot(positionId: number, snapshot: EvalSnapshot) {
  const pvs = [
    {
      cp: snapshot.cp,
      mate: snapshot.mate,
    },
  ];

  const { data: existing } = await supabase
    .from("evals")
    .select("id")
    .eq("position_id", positionId)
    .eq("multi_pv", 1)
    .order("depth", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (existing?.id) {
    await supabase
      .from("evals")
      .update({
        depth: snapshot.depth ?? 0,
        knodes: 0,
        pvs,
        multi_pv: 1,
        pvs_count: 1,
      })
      .eq("id", existing.id);
    return;
  }

  await supabase
    .from("evals")
    .insert({
      position_id: positionId,
      depth: snapshot.depth ?? 0,
      knodes: 0,
      pvs,
      multi_pv: 1,
      pvs_count: 1,
    });
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
    const lower = text.toLowerCase();
    const notFound = res.status === 404 || res.status === 410 ||
      lower.includes("not found");
    return { ok: false, notFound };
  }

  return { ok: true, notFound: false };
}

async function sendLiveActivityEnd(activityId: string) {
  const payload = {
    event: "end",
    name: `live_game_update:${activityId}`,
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
    throw new Error(`OneSignal Live Activity end error: ${res.status} ${text}`);
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
      white_title: args.livePayload.white_title,
      black_title: args.livePayload.black_title,
      white_fed: args.livePayload.white_fed,
      black_fed: args.livePayload.black_fed,
      board_theme_index: args.livePayload.board_theme_index,
      piece_style_index: args.livePayload.piece_style_index,
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
      board_theme_index: args.livePayload.board_theme_index,
      piece_style_index: args.livePayload.piece_style_index,
      is_check: args.livePayload.is_check,
      is_checkmate: args.livePayload.is_checkmate,
      is_game_over: args.livePayload.is_game_over,
      status: args.livePayload.status,
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
  };

  await sendOneSignalPayload(payload);
}

function resolveLiveAlertReason(livePayload: LiveUpdatePayload) {
  if (livePayload.is_checkmate || livePayload.is_game_over) {
    return "game_end" as const;
  }
  if (livePayload.is_check) {
    return "check" as const;
  }
  return null;
}

async function sendLiveGameAlert(
  userIds: string[],
  payload: LiveUpdatePayload,
  reason: "check" | "game_end",
) {
  const title = reason === "check" ? "Check!" : "Game Finished";
  const move = payload.last_move_numbered ??
    payload.last_move_san ??
    payload.last_move ?? "";
  const body = reason === "check"
    ? `${payload.player_white} vs ${payload.player_black} — ${move}`
    : `${payload.player_white} vs ${payload.player_black} — ${
        payload.status ?? "Result"
      }`;

  const notification: NotificationPayload = {
    title,
    body,
    url: null,
    data: {
      type: "live_game_alert",
      game_id: payload.game_id,
      reason,
    },
    androidChannelId: ANDROID_CHANNELS.liveAlerts,
    iosSound: "default",
    androidSound: "default",
  };

  await sendOneSignal(userIds, notification);
}


async function sendOneSignal(
  userIds: string[],
  notification: NotificationPayload,
) {
  if (userIds.length === 0) return;

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

    // NOTE: android_channel_id omitted — channels are not registered in
    // OneSignal yet.  Notifications use the default channel instead.

    if (notification.iosSound) {
      payload.ios_sound = notification.iosSound;
    }
    if (notification.androidSound) {
      payload.android_sound = notification.androidSound;
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
