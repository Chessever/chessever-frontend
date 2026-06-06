import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

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
  players: Record<string, unknown>[] | null;
};

type RoundRow = {
  id: string;
  tour_id: string | null;
  name: string | null;
  starts_at: string | null;
};

type TourRow = {
  id: string;
  name: string | null;
  slug: string | null;
  group_broadcast_id: string | null;
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY =
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
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
const DEFAULT_DISPATCH_LIMIT = 50;
const MAX_DISPATCH_LIMIT = 500;
const PUSH_USER_QUERY_CHUNK_SIZE = 1000;
const ONESIGNAL_EXTERNAL_ID_CHUNK_SIZE = 1000;
const ONESIGNAL_SUBSCRIPTION_ID_CHUNK_SIZE = 20000;
const dispatchTokenCache: { token: string | null; expiresAtMs: number } = {
  token: null,
  expiresAtMs: 0,
};

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }
  const requiredToken = await resolveDispatchToken();
  const providedToken = req.headers.get("x-stream-token");
  if (providedToken && requiredToken && providedToken !== requiredToken) {
    return new Response("Unauthorized", { status: 401 });
  }

  const limit = await resolveDispatchLimit(req);
  const items = await claimPending(limit);
  const results: Array<Record<string, unknown>> = [];

  for (const item of items) {
    const result = await processItem(item);
    results.push(result);
  }

  // SEND-AND-FORGET: purge clock-ping refresh rows that are already done so they
  // never accumulate. The ~1s clock ping makes this run every second, so a
  // clock_ping row lives only for the one invocation that dispatches it. Real
  // move/finish rows keep their 'sent' record for audit/dedupe.
  try {
    await supabase
      .from("notification_outbox")
      .delete()
      .like("dedupe_key", "clock_ping%")
      .in("status", ["sent", "skipped", "failed"]);
  } catch (_err) {
    // Non-fatal — the 6h cleanup cron is the backstop.
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
  const now = Date.now();
  if (dispatchTokenCache.expiresAtMs > now) return dispatchTokenCache.token;

  const { data, error } = await supabase.rpc("get_vault_secret", {
    secret_name: "live_dispatch_token",
  });

  if (error) {
    // Fail-open on vault lookup errors so pg_net trigger dispatch does not
    // break when DB-side token forwarding is not configured.
    dispatchTokenCache.token = null;
    dispatchTokenCache.expiresAtMs = now + 15_000;
    return null;
  }

  const vaultToken = typeof data === "string" && data.length > 0 ? data : null;
  dispatchTokenCache.token = vaultToken;
  dispatchTokenCache.expiresAtMs = now + 60_000;
  return vaultToken;
}

async function resolveDispatchLimit(req: Request): Promise<number> {
  let requestedLimit: unknown = null;
  try {
    const body = await req.json();
    requestedLimit = body?.limit;
  } catch (_error) {
    return DEFAULT_DISPATCH_LIMIT;
  }

  if (typeof requestedLimit !== "number" || !Number.isFinite(requestedLimit)) {
    return DEFAULT_DISPATCH_LIMIT;
  }

  const normalizedLimit = Math.trunc(requestedLimit);
  if (normalizedLimit < 1) return DEFAULT_DISPATCH_LIMIT;
  return Math.min(normalizedLimit, MAX_DISPATCH_LIMIT);
}

async function claimPending(limit: number): Promise<OutboxItem[]> {
  const { data, error } = await supabase.rpc(
    "claim_notification_outbox_batch",
    {
      p_limit: limit,
    },
  );

  if (error) {
    throw error;
  }

  return (data ?? []) as OutboxItem[];
}

const STALE_THRESHOLD_MS = 60 * 60 * 1000; // 1 hour

async function processItem(item: OutboxItem) {
  // Skip stale items to prevent sending outdated notifications
  const createdAt = new Date(item.created_at);
  if (Date.now() - createdAt.getTime() > STALE_THRESHOLD_MS) {
    await markSkipped(item.id, "stale");
    return { id: item.id, status: "skipped", reason: "stale" };
  }

  try {
    const context = await buildContext(item);
    if (item.event_type === "round_started") {
      if (!item.round_id || !(await hasRoundWithMoves(item.round_id))) {
        await markSkipped(item.id, "round_not_live_yet");
        return {
          id: item.id,
          status: "skipped",
          reason: "round_not_live_yet",
        };
      }
      if (await hasSentGroupedRoundStart(item, context)) {
        await markSkipped(item.id, "duplicate_grouped_round_start");
        return {
          id: item.id,
          status: "skipped",
          reason: "duplicate_grouped_round_start",
        };
      }
    }
    if (item.event_type === "round_finished" && isCombinedTour(context.tour)) {
      await markSkipped(item.id, "combined_round_results_suppressed");
      return {
        id: item.id,
        status: "skipped",
        reason: "combined_round_results_suppressed",
      };
    }

    if (item.event_type === "live_game_update") {
      // Live Activity refresh has a dedicated, isolated Edge Function. The
      // regular push dispatcher must not process widget transport rows.
      await markSkipped(item.id, "live_activity_refresh_isolated");
      return {
        id: item.id,
        status: "skipped",
        reason: "live_activity_refresh_isolated",
      };
    }
    if (item.event_type === "round_started") {
      const rsTimeControl = await resolveGameTimeControl(
        item.tour_id ?? context.round?.tour_id ?? null,
      );
      const { playerRecipients, eventRecipients } = await filterRoundRecipients(
        context.eventUserIds,
        context.playerUserIds,
        rsTimeControl,
      );

      if (playerRecipients.length === 0 && eventRecipients.length === 0) {
        await markSkipped(item.id, "no_recipients");
        return { id: item.id, status: "skipped", reason: "no_recipients" };
      }

      const roundId = item.round_id ?? context.round?.id ?? "";
      const eventName = context.displayEventName ?? context.eventName ??
        "Live chess";
      const roundName = context.round?.name ?? "";
      const title = buildEventHeader(eventName, roundName) ?? eventName;

      // Exclude player-favorite users who already received a game_started
      // push for this round (recorded by the game_started handler).
      const suppressedByWindow = await fetchUsersWithActiveGameStartWindow(
        roundId,
        playerRecipients,
      );
      const dedupedPlayerRecipients = playerRecipients.filter(
        (uid) => !suppressedByWindow.has(uid),
      );

      // Per-user personalized notifications for player-favorite users.
      // Batch users with identical messages into a single sendOneSignal() call.
      if (dedupedPlayerRecipients.length > 0) {
        const messageBatches = new Map<string, string[]>();
        const unresolved: string[] = []; // favorites not resolved → event fallback

        for (const userId of dedupedPlayerRecipients) {
          const favNames = context.playerFavoriteMap.get(userId) ?? [];
          if (favNames.length === 0) {
            unresolved.push(userId);
            continue;
          }

          // Sort favorites by rating DESC
          const sorted = [...favNames].sort((a, b) => {
            const ra = context.playerRatingMap.get(a) ?? 0;
            const rb = context.playerRatingMap.get(b) ?? 0;
            return rb - ra;
          });

          let body: string;
          if (sorted.length === 1) {
            const fav = formatPlayerName(sorted[0]);
            const oppName = context.playerOpponentMap.get(sorted[0]) ?? "Opponent";
            const opp = formatPlayerName(oppName);
            body = `${fav} vs ${opp} is live.`;
          } else if (sorted.length === 2) {
            const p1 = formatPlayerName(sorted[0]);
            const p2 = formatPlayerName(sorted[1]);
            body = `${p1} and ${p2} are live.`;
          } else {
            const p1 = formatPlayerName(sorted[0]);
            const p2 = formatPlayerName(sorted[1]);
            body = `${p1}, ${p2}, and others are live.`;
          }

          const key = body;
          if (!messageBatches.has(key)) messageBatches.set(key, []);
          messageBatches.get(key)!.push(userId);
        }

        for (const [body, userIds] of messageBatches) {
          await sendOneSignal(userIds, {
            title,
            body,
            url: null,
            data: buildRoundStartedNotificationData(context, roundId),
            androidChannelId: channelForEvent("round_started"),
          });
        }

        // Fallback for player-favorite users whose specific favorites
        // couldn't be resolved to a name — send the event-level template.
        if (unresolved.length > 0) {
          const template = pickTemplate(ROUND_STARTED_EVENT, roundId);
          const filled = fillTemplate(template, { e: eventName, r: roundName });
          await sendOneSignal(unresolved, {
            title: filled.title,
            body: filled.body,
            url: null,
            data: buildRoundStartedNotificationData(context, roundId),
            androidChannelId: channelForEvent("round_started"),
          });
        }
      }

      // Record game_start windows for every player recipient who just
      // received this round_started notification.  This prevents
      // game_started (which fires later, when the first move is played)
      // from sending a duplicate push to the same users.
      // TTL = 15 min — comfortably covers the gap between round start
      // and first moves in any standard tournament format.
      if (dedupedPlayerRecipients.length > 0) {
        await supabase.rpc("record_game_start_window", {
          p_user_ids: dedupedPlayerRecipients,
          p_round_id: roundId,
          p_cooldown_seconds: 900,
        });
      }

      // Event-only recipients (starred event, no favorites playing)
      if (eventRecipients.length > 0) {
        const template = pickTemplate(ROUND_STARTED_EVENT, roundId);
        const filled = fillTemplate(template, { e: eventName, r: roundName });
        await sendOneSignal(eventRecipients, {
          title: filled.title,
          body: filled.body,
          url: null,
          data: buildRoundStartedNotificationData(context, roundId),
          androidChannelId: channelForEvent("round_started"),
        });
      }

      await markSent(item.id);
      return {
        id: item.id,
        status: "sent",
        recipients: dedupedPlayerRecipients.length + eventRecipients.length,
      };
    }

    if (item.event_type === "round_heads_up") {
      const roundId = item.round_id ?? context.round?.id ?? "";
      const eventName = context.eventName ?? "Live chess";
      const roundName = context.round?.name ?? "";
      const leadMinutes = (item.payload?.lead_minutes as number) ?? 30;
      const timeStr = `~${leadMinutes} min`;

      // Only send to users whose preferred lead time and time-control filter match.
      const huTimeControl = await resolveGameTimeControl(
        item.tour_id ?? context.round?.tour_id ?? null,
      );
      const { playerRecipients, eventRecipients } =
        await filterHeadsUpRecipients(
          context.eventUserIds,
          context.playerUserIds,
          leadMinutes,
          huTimeControl,
        );

      if (playerRecipients.length === 0 && eventRecipients.length === 0) {
        await markSkipped(item.id, "no_recipients");
        return { id: item.id, status: "skipped", reason: "no_recipients" };
      }

      const headsUpData = {
        type: "round_heads_up",
        round_id: roundId,
        tour_id: context.tourId ?? null,
        group_broadcast_id: context.groupBroadcastId ?? null,
      };

      // Per-user combined messages — Scenario A/B/C (same logic as round_started).
      // A (1 fav): "Carlsen at the board in ~30 min"
      // B (2 favs): "Carlsen & Caruana in ~30 min."
      // C (3+ favs): "Carlsen, Caruana & 1 more in ~30 min."
      if (playerRecipients.length > 0) {
        const msgGroups = new Map<
          string,
          { recipients: string[]; title: string; body: string }
        >();
        const ungrouped: string[] = [];

        for (const uid of playerRecipients) {
          const favs = context.playerFavoriteMap.get(uid) ?? [];
          if (favs.length === 0) { ungrouped.push(uid); continue; }

          let title: string;
          let body: string;

          if (favs.length === 1) {
            const template = pickTemplate(ROUND_HEADS_UP_PLAYER, roundId);
            const msg = fillTemplate(template, {
              p: extractLastName(favs[0]),
              e: eventName,
              r: roundName,
              t: timeStr,
            });
            title = msg.title;
            body = msg.body;
          } else if (favs.length === 2) {
            title = buildEventHeader(eventName, roundName) ?? eventName;
            body = `${extractLastName(favs[0])} & ${extractLastName(favs[1])} in ${timeStr}.`;
          } else {
            title = buildEventHeader(eventName, roundName) ?? eventName;
            const [a, b] = favs.slice(0, 2).map(extractLastName);
            body = `${a}, ${b} & ${favs.length - 2} more in ${timeStr}.`;
          }

          const key = `${title}|${body}`;
          if (!msgGroups.has(key)) msgGroups.set(key, { recipients: [], title, body });
          msgGroups.get(key)!.recipients.push(uid);
        }

        for (const { recipients, title, body } of msgGroups.values()) {
          await sendOneSignal(recipients, {
            title,
            body,
            url: null,
            data: headsUpData,
            androidChannelId: channelForEvent("round_heads_up"),
          });
        }

        // Fallback for users with no resolved favorite in this round.
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
            data: headsUpData,
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
          data: headsUpData,
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

    if (item.event_type.startsWith("book_")) {
      const folderId = item.payload?.folder_id as string;
      if (!folderId) {
        await markSkipped(item.id, "missing_folder_id");
        return { id: item.id, status: "skipped", reason: "missing_folder_id" };
      }

      const subscriberIds = await resolveRecursiveBookSubscribers(folderId);
      if (subscriberIds.length === 0) {
        await markSkipped(item.id, "no_subscribers");
        return { id: item.id, status: "skipped", reason: "no_subscribers" };
      }

      const eligible = await filterBookUpdateRecipients(subscriberIds);
      if (eligible.length === 0) {
        await markSkipped(item.id, "no_recipients");
        return { id: item.id, status: "skipped", reason: "no_recipients" };
      }

      const folderName = (item.payload?.folder_name as string) ?? "a book";
      const gameTitle = (item.payload?.game_title as string) ?? "a game";
      const ownerName =
        (item.payload?.owner_display_name as string) ?? "Someone";

      let body = "";
      switch (item.event_type) {
        case "book_game_added":
          body = `${ownerName} added "${gameTitle}"`;
          break;
        case "book_game_updated":
          body = `${ownerName} updated "${gameTitle}"`;
          break;
        case "book_game_removed":
          body = `${ownerName} removed "${gameTitle}"`;
          break;
        case "book_folder_added":
          body = `${ownerName} added sub-database "${gameTitle}"`;
          break;
        case "book_folder_updated":
          body = `${ownerName} updated sub-database "${gameTitle}"`;
          break;
        case "book_folder_removed":
          body = `${ownerName} removed sub-database "${gameTitle}"`;
          break;
      }

      if (!body) {
        await markSkipped(item.id, "unsupported_book_event");
        return {
          id: item.id,
          status: "skipped",
          reason: "unsupported_book_event",
        };
      }

      await sendOneSignal(eligible, {
        title: folderName,
        body,
        url: `https://chessever.com/databases/${folderId}`,
        data: {
          type: item.event_type,
          folder_id: folderId,
          analysis_id: item.payload?.analysis_id,
        },
        androidChannelId: ANDROID_CHANNELS.general,
      });

      await markSent(item.id);
      return { id: item.id, status: "sent", recipients: eligible.length };
    }

    // --- round_finished: one results digest per round, event-starred users only ---
    // Anti-spam guarantees:
    //   1. DB trigger uses ON CONFLICT (dedupe_key) DO NOTHING → max 1 outbox row per round.
    //   2. Only eventRecipients receive this — player-fav users already got
    //      individual game_finished pushes for each game they follow.
    //   3. Muted users are already stripped by resolveRecipients() above.
    //   4. Requires favorite_event_alerts opt-in (handled by filterRoundRecipients).
    if (item.event_type === "round_finished") {
      const rfTimeControl = await resolveGameTimeControl(
        item.tour_id ?? context.round?.tour_id ?? null,
      );
      const { eventRecipients } = await filterRoundRecipients(
        context.eventUserIds,
        context.playerUserIds,
        rfTimeControl,
      );

      if (eventRecipients.length === 0) {
        await markSkipped(item.id, "no_recipients");
        return { id: item.id, status: "skipped", reason: "no_recipients" };
      }

      const roundId = item.round_id ?? context.round?.id ?? "";
      const eventName = context.eventName ?? "Chess";
      const roundName = context.round?.name ?? "";

      // Title clearly signals results, not a new round starting.
      const title = roundName
        ? `${eventName} — ${roundName} Results`
        : `${eventName} Results`;

      // Results are embedded in the payload by the DB trigger.
      const rawResults =
        (item.payload?.results as Array<Record<string, unknown>>) ?? [];
      const results = rawResults.map((r) => ({
        white: (r.white as string) ?? "White",
        black: (r.black as string) ?? "Black",
        status: (r.status as string) ?? "*",
        boardNr: (r.board_nr as number | null) ?? null,
      }));

      const body = results.length > 0
        ? buildResultsBody(results)
        : "Round results are in.";

      await sendOneSignal(eventRecipients, {
        title,
        body,
        url: null,
        data: {
          type: "round_finished",
          round_id: roundId,
          tour_id: context.tourId ?? null,
          group_broadcast_id: context.groupBroadcastId ?? null,
        },
        androidChannelId: channelForEvent("round_finished"),
      });

      await markSent(item.id);
      return { id: item.id, status: "sent", recipients: eventRecipients.length };
    }

    if (item.event_type === "game_finished") {
      const payload = item.payload ?? {};
      const white = (payload.player_white as string) ?? context.game?.player_white ?? "White";
      const black = (payload.player_black as string) ?? context.game?.player_black ?? "Black";
      const status = (payload.status as string) ?? context.game?.status ?? "";
      const result = status || "Game over";

      const allUserIds = new Set([
        ...context.eventUserIds,
        ...context.playerUserIds,
      ]);
      const timeControl = await resolveGameTimeControl(
        context.game?.tour_id ?? item.tour_id,
      );
      const filteredUserIds = await applyPreferences(
        item.event_type,
        allUserIds,
        context.eventUserIds,
        context.playerUserIds,
        timeControl,
      );

      if (filteredUserIds.size === 0) {
        await markSkipped(item.id, "no_recipients");
        return { id: item.id, status: "skipped", reason: "no_recipients" };
      }

      const title = buildEventHeader(context.eventName, context.round?.name) ?? `${formatPlayerName(white)} vs ${formatPlayerName(black)}`;
      const body = `${formatPlayerName(white)} vs ${formatPlayerName(black)}: ${result}`;

      await sendOneSignal(Array.from(filteredUserIds), {
        title,
        body,
        url: null,
        data: { type: "game_finished", game_id: item.game_id },
        androidChannelId: channelForEvent("game_finished"),
      });

      await markSent(item.id);
      return {
        id: item.id,
        status: "sent",
        recipients: filteredUserIds.size,
      };
    }

    // Guard: skip game_started if the game already ended before the dispatcher
    // claimed this row. Happens when a game starts and finishes within the
    // 1-minute cron window — prevents "is live" pings for finished games.
    if (item.event_type === "game_started" && isGameOverStatus(context.game?.status ?? null)) {
      await markSkipped(item.id, "game_already_finished");
      return { id: item.id, status: "skipped", reason: "game_already_finished" };
    }

    const allUserIds = new Set([
      ...context.eventUserIds,
      ...context.playerUserIds,
    ]);
    const gsTimeControl = await resolveGameTimeControl(
      context.game?.tour_id ?? item.tour_id,
    );
    const filteredUserIds = await applyPreferences(
      item.event_type,
      allUserIds,
      context.eventUserIds,
      context.playerUserIds,
      gsTimeControl,
    );

    if (filteredUserIds.size === 0) {
      await markSkipped(item.id, "no_recipients");
      return { id: item.id, status: "skipped", reason: "no_recipients" };
    }

    // For game_started: exclude users with 2+ favorites playing in the round.

    // Per spec (Scenarios B/C), those users must receive ONE combined notification
    // from round_started — not individual per-game pushes.
    // Only single-favorite users (Scenario A) are handled here.
    if (item.event_type === "game_started" && item.round_id) {
      for (const uid of Array.from(filteredUserIds)) {
        const favCount = (context.playerFavoriteMap.get(uid) ?? []).length;
        if (favCount !== 1) filteredUserIds.delete(uid);
      }

      // Also skip users who already received a round_started notification
      // for this round (window recorded by the round_started handler when
      // cron fires before the first move arrives).  This prevents the
      // second push when the game_started trigger fires later.
      if (filteredUserIds.size > 0) {
        const alreadyCovered = await fetchUsersWithActiveGameStartWindow(
          item.round_id,
          Array.from(filteredUserIds),
        );
        for (const uid of alreadyCovered) {
          filteredUserIds.delete(uid);
        }
      }
    }

    if (filteredUserIds.size === 0) {
      await markSent(item.id);
      return { id: item.id, status: "sent", recipients: 0 };
    }

    const notification = buildNotification(context, item);
    await sendOneSignal(Array.from(filteredUserIds), notification);

    // Record a cooldown window so that round_started skips these users.
    // Only record for the users who actually received this push (1-favorite users).
    if (item.event_type === "game_started" && item.round_id) {
      const playerRecipients = Array.from(filteredUserIds).filter(
        (uid) => context.playerUserIds.has(uid),
      );
      if (playerRecipients.length > 0) {
        await supabase.rpc("record_game_start_window", {
          p_user_ids: playerRecipients,
          p_round_id: item.round_id,
          p_cooldown_seconds: 900, // 15 min covers delay until round_started cron runs
        });
      }
    }

    await markSent(item.id);

    return {
      id: item.id,
      status: "sent",
      recipients: filteredUserIds.size,
    };
  } catch (error) {
    await markFailed(item.id, item.attempts, `${error}`);
    return { id: item.id, status: "failed", error: `${error}` };
  }
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
  let tour: TourRow | null = null;
  let eventName: string | null = null;
  let groupBroadcastId = item.group_broadcast_id ?? null;
  let groupSectionCount = 0;

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
  if (tourId) {
    const { data } = await supabase
      .from("tours")
      .select("id,name,slug,group_broadcast_id")
      .eq("id", tourId)
      .maybeSingle();
    tour = (data ?? null) as TourRow | null;
    groupBroadcastId = groupBroadcastId ?? tour?.group_broadcast_id ?? null;
  }

  if (groupBroadcastId) {
    const { data } = await supabase
      .from("group_broadcasts")
      .select("name")
      .eq("id", groupBroadcastId)
      .maybeSingle();
    eventName = data?.name ?? null;

    const { data: groupedTours } = await supabase
      .from("tours")
      .select("id,name,slug")
      .eq("group_broadcast_id", groupBroadcastId);
    groupSectionCount = ((groupedTours ?? []) as TourRow[])
      .filter((row) => !isCombinedTour(row)).length;
  }

  const displayEventName = buildRoundEventDisplayName(
    eventName,
    tour?.name ?? null,
    groupSectionCount,
  );

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

  let playerRatingMap = new Map<string, number>();
  let playerOpponentMap = new Map<string, string>();

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
    playerRatingMap = roundPlayers.playerRatingMap;
    playerOpponentMap = roundPlayers.playerOpponentMap;
  }

  const { eventUserIds, playerUserIds } = await resolveRecipients({
    groupBroadcastId,
    fideIds: Array.from(fideIdSet),
    players: Array.from(playerNames),
  });

  // Resolve per-user player favorites for round/game notifications
  let playerFavoriteMap = new Map<string, string[]>();
  if (
    (item.event_type === "round_started" ||
      item.event_type === "round_heads_up" ||
      item.event_type === "game_started") &&
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
    tour,
    eventName,
    displayEventName,
    groupBroadcastId,
    tourId,
    eventUserIds,
    playerUserIds,
    playerFavoriteMap,
    playerRatingMap,
    playerOpponentMap,
  };
}

function isCombinedTour(tour: TourRow | null): boolean {
  const label = `${tour?.name ?? ""} ${tour?.slug ?? ""}`.toLowerCase();
  return /(^|[^a-z0-9])combined([^a-z0-9]|$)/.test(label);
}

function groupedRoundStartCollapseKey(
  context: { round: RoundRow | null; groupBroadcastId: string | null },
): string | null {
  const startsAt = context.round?.starts_at;
  const groupId = context.groupBroadcastId;
  if (!startsAt || !groupId) return null;
  return `round_started:${groupId}:${startsAt}`;
}

function buildRoundStartedNotificationData(
  context: { round: RoundRow | null; groupBroadcastId: string | null },
  roundId: string,
) {
  return {
    type: "round_started",
    round_id: roundId,
    group_broadcast_id: context.groupBroadcastId ?? null,
    grouped_round_start_key: groupedRoundStartCollapseKey(context),
  };
}

async function hasSentGroupedRoundStart(
  item: OutboxItem,
  context: { round: RoundRow | null; groupBroadcastId: string | null },
): Promise<boolean> {
  const startsAt = context.round?.starts_at;
  const groupId = context.groupBroadcastId;
  if (!startsAt || !groupId) return false;

  const itemCreatedAt = new Date(item.created_at).getTime();
  const minCreatedAt = new Date(itemCreatedAt - 60 * 60 * 1000).toISOString();

  const { data, error } = await supabase
    .from("notification_outbox")
    .select("id,payload")
    .eq("event_type", "round_started")
    .eq("group_broadcast_id", groupId)
    .eq("status", "sent")
    .neq("id", item.id)
    .gte("created_at", minCreatedAt)
    .limit(25);

  if (error) return false;

  return ((data ?? []) as Array<{ payload?: Record<string, unknown> | null }>)
    .some((row) => sameInstant(row.payload?.starts_at, startsAt));
}

async function hasRoundWithMoves(roundId: string): Promise<boolean> {
  const { data, error } = await supabase
    .from("games")
    .select("id")
    .eq("round_id", roundId)
    .not("last_move_time", "is", null)
    .limit(1);

  if (error) return false;
  return (data ?? []).length > 0;
}

function sameInstant(a: unknown, b: string): boolean {
  if (typeof a !== "string" || !a) return false;
  const aTime = Date.parse(a);
  const bTime = Date.parse(b);
  if (Number.isNaN(aTime) || Number.isNaN(bTime)) {
    return a === b;
  }
  return aTime === bTime;
}

async function fetchRoundPlayers(roundId: string) {
  const { data, error } = await supabase
    .from("games")
    .select("player_white,player_black,player_fide_ids,players")
    .eq("round_id", roundId);

  if (error) {
    throw error;
  }

  const playerNames = new Set<string>();
  const fideIds = new Set<string>();
  const playerRatingMap = new Map<string, number>();
  const playerOpponentMap = new Map<string, string>();

  for (const row of (data ?? []) as RoundGameRow[]) {
    if (row.player_white) playerNames.add(row.player_white);
    if (row.player_black) playerNames.add(row.player_black);
    for (const id of row.player_fide_ids ?? []) {
      fideIds.add(id.toString());
    }

    // Build opponent map
    if (row.player_white && row.player_black) {
      playerOpponentMap.set(row.player_white, row.player_black);
      playerOpponentMap.set(row.player_black, row.player_white);
    }

    // Extract ratings from players JSON
    if (Array.isArray(row.players)) {
      for (const p of row.players) {
        const name = (p?.name as string | undefined) ?? null;
        const rating = p?.rating as number | undefined;
        if (name && typeof rating === "number" && rating > 0) {
          playerRatingMap.set(name, rating);
        }
      }
    }
  }

  return {
    playerNames: Array.from(playerNames),
    fideIds: Array.from(fideIds),
    playerRatingMap,
    playerOpponentMap,
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

  // Remove muted users from BOTH channels in one query.
  // A user who has muted this event must receive no notification from it —
  // regardless of whether they arrive via eventUserIds (starred) or
  // playerUserIds (favorite player).
  if (args.groupBroadcastId) {
    const allCandidates = new Set([...eventUserIds, ...playerUserIds]);
    if (allCandidates.size > 0) {
      const { data: mutedData } = await supabase
        .from("user_muted_events")
        .select("user_id")
        .eq("group_broadcast_id", args.groupBroadcastId)
        .in("user_id", Array.from(allCandidates));
      for (const row of mutedData ?? []) {
        const uid = row.user_id as string;
        eventUserIds.delete(uid);
        playerUserIds.delete(uid);
      }
    }
  }

  return { eventUserIds, playerUserIds };
}

// Normalises a raw time-class string from the tours table into one of the
// three canonical values the preference columns use.
function normaliseTimeControl(
  raw: string | null | undefined,
): "classical" | "rapid" | "blitz" | null {
  if (!raw) return null;
  const s = raw.trim().toLowerCase();
  if (s === "classical" || s === "standard") return "classical";
  if (s === "rapid") return "rapid";
  if (s === "blitz" || s === "bullet") return "blitz";
  return null;
}

// Fetch the time-control class for a tour. Returns null when unknown so that
// the preference filter is skipped (fail-open — users always get the push).
async function resolveGameTimeControl(
  tourId: string | null | undefined,
): Promise<"classical" | "rapid" | "blitz" | null> {
  if (!tourId) return null;
  try {
    const { data } = await supabase
      .from("tours")
      .select("time_class")
      .eq("id", tourId)
      .maybeSingle();
    return normaliseTimeControl(data?.time_class as string | null);
  } catch (_) {
    // Column may not exist yet — fail-open.
    return null;
  }
}

async function applyPreferences(
  eventType: string,
  allUserIds: Set<string>,
  eventUserIds: Set<string>,
  playerUserIds: Set<string>,
  // Canonical time control for the game/round being notified about.
  // null means "unknown — skip time-control filtering".
  gameTimeControl: "classical" | "rapid" | "blitz" | null = null,
) {
  const ids = Array.from(allUserIds);
  if (ids.length === 0) return allUserIds;

  const { data } = await supabase
    .from("user_notification_preferences")
    .select(
      "user_id,push_enabled,favorite_event_alerts,favorite_player_alerts," +
      "live_game_updates,call_to_action_alerts," +
      "fp_classical,fp_rapid,fp_blitz," +
      "se_classical,se_rapid,se_blitz",
    )
    .in("user_id", ids);

  const prefsMap = new Map<string, Record<string, unknown>>();
  const preferenceRows =
    (data ?? []) as unknown as Array<Record<string, unknown> & { user_id: string }>;
  for (const row of preferenceRows) {
    prefsMap.set(row.user_id, row);
  }

  const filtered = new Set<string>();

  for (const userId of ids) {
    const prefs = prefsMap.get(userId);
    if (prefs && prefs.push_enabled === false) continue;

    const isEventFav = eventUserIds.has(userId);
    const isPlayerFav = playerUserIds.has(userId);

    // Time-control filter: apply category-specific columns.
    // fp_* governs player-favourite notifications; se_* governs event-starred.
    // When a user is both, the notification is allowed if either category
    // permits it (most-permissive wins).
    // No prefs row → all columns default to true (fail-open).
    if (gameTimeControl && prefs) {
      const tc = gameTimeControl;
      const fpBlocked = prefs[`fp_${tc}`] === false;
      const seBlocked = prefs[`se_${tc}`] === false;

      if (isPlayerFav && !isEventFav && fpBlocked) continue;
      if (isEventFav && !isPlayerFav && seBlocked) continue;
      if (isPlayerFav && isEventFav && fpBlocked && seBlocked) continue;
    }

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
      if (!prefs || prefs.live_game_updates !== true) continue;
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
  gameTimeControl: "classical" | "rapid" | "blitz" | null = null,
) {
  const allUserIds = new Set([...eventUserIds, ...playerUserIds]);
  const ids = Array.from(allUserIds);
  if (ids.length === 0) {
    return { playerRecipients: [], eventRecipients: [] };
  }

  const { data } = await supabase
    .from("user_notification_preferences")
    .select(
      "user_id,push_enabled,favorite_event_alerts,favorite_player_alerts," +
      "fp_classical,fp_rapid,fp_blitz," +
      "se_classical,se_rapid,se_blitz",
    )
    .in("user_id", ids);

  const prefsMap = new Map<string, Record<string, unknown>>();
  const preferenceRows =
    (data ?? []) as unknown as Array<Record<string, unknown> & { user_id: string }>;
  for (const row of preferenceRows) {
    prefsMap.set(row.user_id, row);
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

    // Category-specific time-control gate.
    if (gameTimeControl && prefs) {
      const tc = gameTimeControl;
      if (isPlayerFav && playerAllowed && prefs[`fp_${tc}`] === false) {
        // This player-fav user has blocked this time control — demote to event
        // recipient only if they also star the event, otherwise skip entirely.
        if (!isEventFav || !eventAllowed || prefs[`se_${tc}`] === false) continue;
        // Falls through to event-recipient branch below.
        eventRecipients.add(userId);
        continue;
      }
      if (isEventFav && !isPlayerFav && eventAllowed &&
          prefs[`se_${tc}`] === false) {
        continue;
      }
    }

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

async function fetchMutedUserIds(
  groupBroadcastId: string | null,
  candidateUserIds: string[],
): Promise<Set<string>> {
  const muted = new Set<string>();
  if (!groupBroadcastId || candidateUserIds.length === 0) return muted;
  const unique = Array.from(new Set(candidateUserIds));
  const { data, error } = await supabase
    .from("user_muted_events")
    .select("user_id")
    .eq("group_broadcast_id", groupBroadcastId)
    .in("user_id", unique);
  if (error) return muted;
  for (const row of data ?? []) {
    muted.add(row.user_id as string);
  }
  return muted;
}

async function fetchUsersWithActiveGameStartWindow(
  roundId: string,
  userIds: string[],
): Promise<Set<string>> {
  if (userIds.length === 0) return new Set();
  const { data } = await supabase
    .from("notification_user_windows")
    .select("user_id")
    .eq("round_id", roundId)
    .eq("family", "game_start")
    .gt("expires_at", new Date().toISOString())
    .in("user_id", userIds);
  const suppressed = new Set<string>();
  for (const row of data ?? []) {
    suppressed.add(row.user_id as string);
  }
  return suppressed;
}

async function resolveRecursiveBookSubscribers(
  folderId: string,
): Promise<string[]> {
  const allFolderIds = new Set<string>();
  let currentId: string | null = folderId;

  // Traverse up the folder hierarchy to collect all parent folder IDs
  while (currentId) {
    allFolderIds.add(currentId);
    const { data, error } = await supabase
      .from("user_folders")
      .select("parent_id")
      .eq("id", currentId)
      .maybeSingle();

    if (error || !data?.parent_id) {
      currentId = null;
    } else {
      currentId = data.parent_id as string;
    }
  }

  const { data: subs } = await supabase
    .from("book_subscriptions")
    .select("subscriber_id")
    .in("folder_id", Array.from(allFolderIds));

  return [...new Set((subs ?? []).map((s) => s.subscriber_id as string))];
}

async function filterBookUpdateRecipients(
  userIds: string[],
): Promise<string[]> {
  if (userIds.length === 0) return [];

  const { data } = await supabase
    .from("user_notification_preferences")
    .select("user_id,push_enabled,book_update_alerts")
    .in("user_id", userIds);

  const prefsMap = new Map<string, Record<string, unknown>>();
  const preferenceRows =
    (data ?? []) as unknown as Array<Record<string, unknown> & { user_id: string }>;
  for (const row of preferenceRows) {
    prefsMap.set(row.user_id, row);
  }

  const filtered: string[] = [];
  for (const userId of userIds) {
    const prefs = prefsMap.get(userId);
    if (prefs && prefs.push_enabled === false) continue;
    if (prefs && prefs.book_update_alerts === false) continue;
    filtered.push(userId);
  }
  return filtered;
}

async function filterHeadsUpRecipients(
  eventUserIds: Set<string>,
  playerUserIds: Set<string>,
  // The lead time of this specific outbox row (10 or 30 minutes).
  // Only users whose heads_up_lead_minutes preference matches will be included.
  leadMinutes: number = 30,
  gameTimeControl: "classical" | "rapid" | "blitz" | null = null,
) {
  const allUserIds = new Set([...eventUserIds, ...playerUserIds]);
  const ids = Array.from(allUserIds);
  if (ids.length === 0) {
    return { playerRecipients: [], eventRecipients: [] };
  }

  const { data } = await supabase
    .from("user_notification_preferences")
    .select(
      "user_id,push_enabled,favorite_event_alerts,favorite_player_alerts," +
      "heads_up_alerts,heads_up_lead_minutes," +
      "fp_classical,fp_rapid,fp_blitz," +
      "se_classical,se_rapid,se_blitz",
    )
    .in("user_id", ids);

  const prefsMap = new Map<string, Record<string, unknown>>();
  const preferenceRows =
    (data ?? []) as unknown as Array<Record<string, unknown> & { user_id: string }>;
  for (const row of preferenceRows) {
    prefsMap.set(row.user_id, row);
  }

  const playerRecipients = new Set<string>();
  const eventRecipients = new Set<string>();

  for (const userId of ids) {
    const prefs = prefsMap.get(userId);
    if (prefs && prefs.push_enabled === false) continue;
    if (!prefs || prefs.heads_up_alerts !== true) continue;

    // Lead-time gate: user's preference must match this outbox row's lead time.
    // No prefs row → default is 30 min (matches the DB column default).
    const userLeadMinutes = (prefs?.heads_up_lead_minutes as number) ?? 30;
    if (userLeadMinutes !== leadMinutes) continue;

    const isPlayerFav = playerUserIds.has(userId);
    const isEventFav = eventUserIds.has(userId);
    const playerAllowed = !prefs || prefs.favorite_player_alerts !== false;
    const eventAllowed = !prefs || prefs.favorite_event_alerts !== false;

    // Category-specific time-control gate for heads-up notifications.
    if (gameTimeControl && prefs) {
      const tc = gameTimeControl;
      const fpBlocked = prefs[`fp_${tc}`] === false;
      const seBlocked = prefs[`se_${tc}`] === false;

      if (isPlayerFav && playerAllowed && fpBlocked) {
        // Player-fav blocked by fp_* — promote to event recipient if eligible.
        if (isEventFav && eventAllowed && !seBlocked) {
          eventRecipients.add(userId);
        }
        continue;
      }
      if (isEventFav && !isPlayerFav && eventAllowed && seBlocked) continue;
    }

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

function formatPlayerName(name: string): string {
  const trimmed = name.trim();
  // Already "Last, First" format
  if (trimmed.includes(",")) return trimmed;
  const parts = trimmed.split(/\s+/);
  if (parts.length <= 1) return trimmed;
  // "Gukesh D" — single-char last token is ambiguous, keep as-is
  if (parts[parts.length - 1].length <= 2 && parts.length >= 2) {
    return trimmed;
  }
  const last = parts[parts.length - 1];
  const first = parts.slice(0, -1).join(" ");
  return `${last}, ${first}`;
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

// Normalise all result strings to the three standard chess symbols.
function formatResultSymbol(status: string): string {
  const s = (status ?? "").trim();
  if (s === "1-0" || s === "W") return "1-0";
  if (s === "0-1" || s === "B") return "0-1";
  if (s === "1/2-1/2" || s === "½-½" || s === "D" || s.toUpperCase() === "DRAW") return "½-½";
  return s || "*";
}

// Builds a compact results digest body for a round_finished notification.
// Shows up to 3 boards sorted by board number, then "+N more" for the rest.
// Example: "Carlsen 1-0 Nepo · Caruana ½-½ Giri · Nakamura 1-0 Duda +4 more"
function buildResultsBody(
  results: Array<{ white: string; black: string; status: string; boardNr: number | null }>,
): string {
  const sorted = [...results].sort((a, b) => {
    if (a.boardNr !== null && b.boardNr !== null) return a.boardNr - b.boardNr;
    if (a.boardNr !== null) return -1;
    if (b.boardNr !== null) return 1;
    return 0;
  });

  const MAX_SHOWN = 3;
  const shown = sorted.slice(0, MAX_SHOWN);
  const rest = sorted.length - MAX_SHOWN;

  const parts = shown.map((r) => {
    const w = extractLastName(r.white);
    const b = extractLastName(r.black);
    const sym = formatResultSymbol(r.status);
    return `${w} ${sym} ${b}`;
  });

  let body = parts.join(" · ");
  if (rest > 0) body += ` +${rest} more`;
  return body;
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
    .select("player_white,player_black,players")
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
    // Use players JSONB array for deterministic fideId→name mapping.
    // player_fide_ids uses array_agg(DISTINCT) which has non-deterministic
    // order, so positional indexing ([0]=white, [1]=black) is unreliable.
    for (const p of g.players ?? []) {
      const fideId = (p as Record<string, unknown>)["fideId"];
      const name = (p as Record<string, unknown>)["name"];
      if (fideId != null && name) {
        const fid = String(fideId);
        roundFideIds.add(fid);
        fideIdToName.set(fid, name as string);
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
      const fideId = String(row.fide_id);
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

function buildEventHeader(
  eventName: string | null,
  roundName: string | null | undefined,
): string | null {
  if (eventName && roundName) return `${eventName} — ${roundName}`;
  if (eventName) return eventName;
  return null;
}

function buildRoundEventDisplayName(
  eventName: string | null,
  tourName: string | null,
  groupSectionCount: number,
): string | null {
  if (!eventName) return tourName;
  if (!tourName || groupSectionCount <= 1) return eventName;

  if (normalizeEventLabel(tourName).startsWith(normalizeEventLabel(eventName))) {
    return tourName;
  }

  if (isRedundantOpenSection(eventName, tourName)) {
    return eventName;
  }

  const sectionName = extractTourSection(eventName, tourName);
  if (!sectionName || isRedundantOpenSection(eventName, sectionName)) {
    return eventName;
  }

  return `${eventName} — ${sectionName}`;
}

function extractTourSection(eventName: string, tourName: string): string | null {
  const pipeSection = tourName.split("|").pop()?.trim();
  if (pipeSection && pipeSection !== tourName.trim()) return pipeSection;

  const normalizedEvent = normalizeEventLabel(eventName);
  const normalizedTour = normalizeEventLabel(tourName);
  if (!normalizedTour.startsWith(normalizedEvent)) return null;

  return tourName.slice(eventName.length).replace(/^\s*[-–—:|]\s*/, "").trim() || null;
}

function isRedundantOpenSection(eventName: string, sectionName: string): boolean {
  return /\bopen\b/i.test(sectionName) && /\bopen\b/i.test(eventName);
}

function normalizeEventLabel(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

function channelForEvent(eventType: string) {
  switch (eventType) {
    case "round_heads_up":
      return ANDROID_CHANNELS.headsUp;
    case "live_game_update":
      return ANDROID_CHANNELS.live;
    case "round_started":
    case "round_finished":
    case "game_started":
    case "game_finished":
      return ANDROID_CHANNELS.favorites;
    case "call_to_action":
      return ANDROID_CHANNELS.callToAction;
    case "book_game_added":
    case "book_game_updated":
    case "book_game_removed":
      return ANDROID_CHANNELS.general;
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
    const eventHeader = buildEventHeader(context.eventName, context.round?.name);
    const playerLine = `${formatPlayerName(white)} vs ${formatPlayerName(black)} is live.`;
    return {
      title: eventHeader ?? `${formatPlayerName(white)} vs ${formatPlayerName(black)}`,
      body: playerLine,
      url: null,
      data: { type: "game_started", game_id: item.game_id },
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

function isGameOverStatus(status: string | null) {
  if (!status) return false;
  const trimmed = status.trim().toLowerCase();
  if (trimmed.length === 0) return false;
  return trimmed !== "*" && trimmed !== "ongoing";
}

async function sendOneSignalPayload(payload: Record<string, unknown>) {
  const res = await fetch("https://api.onesignal.com/notifications", {
    method: "POST",
    headers: {
      ...jsonHeaders,
      Authorization: `Key ${ONESIGNAL_REST_API_KEY}`,
    },
    body: JSON.stringify(payload),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`OneSignal API error: ${res.status} ${text}`);
  }
}

async function sendOneSignal(
  userIds: string[],
  notification: NotificationPayload,
) {
  if (userIds.length === 0) return;

  const targets = await fetchPushSubscriptionTargets(userIds);

  for (const batch of chunk(
    targets.subscriptionIds,
    ONESIGNAL_SUBSCRIPTION_ID_CHUNK_SIZE,
  )) {
    const payload: Record<string, unknown> = {
      ...buildOneSignalPayload(notification),
      app_id: ONESIGNAL_APP_ID,
      include_subscription_ids: batch,
      target_channel: "push",
    };

    await sendOneSignalPayload(payload);
  }

  // Some older installs may have a OneSignal external_id but no mirrored row in
  // user_push_tokens yet. Keep a fallback for those users only, so users with
  // synced devices do not receive duplicates.
  for (const batch of chunk(
    targets.externalIdFallbackUserIds,
    ONESIGNAL_EXTERNAL_ID_CHUNK_SIZE,
  )) {
    const payload: Record<string, unknown> = {
      ...buildOneSignalPayload(notification),
      app_id: ONESIGNAL_APP_ID,
      include_aliases: { external_id: batch },
      target_channel: "push",
    };

    await sendOneSignalPayload(payload);
  }
}

function buildOneSignalPayload(notification: NotificationPayload) {
  const payload: Record<string, unknown> = {
    headings: { en: notification.title },
    contents: { en: notification.body },
    data: notification.data,
  };

  const collapseId = notificationCollapseId(notification);
  if (collapseId) {
    payload.collapse_id = collapseId;
  }

  if (notification.url) {
    payload.url = notification.url;
  }

  // NOTE: android_channel_id omitted — channels are not registered in
  // OneSignal yet. Notifications use the default channel instead.

  if (notification.iosSound) {
    payload.ios_sound = notification.iosSound;
  }
  if (notification.androidSound) {
    payload.android_sound = notification.androidSound;
  }

  return payload;
}

function notificationCollapseId(notification: NotificationPayload): string | null {
  const type = typeof notification.data?.type === "string"
    ? notification.data.type
    : null;
  const gameId = typeof notification.data?.game_id === "string"
    ? notification.data.game_id
    : null;
  const roundId = typeof notification.data?.round_id === "string"
    ? notification.data.round_id
    : null;

  if (gameId) return compactCollapseId(`game:${type ?? "update"}:${gameId}`);

  if (type === "round_started") {
    const groupedRoundStartKey = notification.data?.grouped_round_start_key;
    if (typeof groupedRoundStartKey === "string" && groupedRoundStartKey) {
      return compactCollapseId(groupedRoundStartKey);
    }
  }

  if (roundId) return compactCollapseId(`round:${type ?? "update"}:${roundId}`);
  return null;
}

function compactCollapseId(value: string): string {
  if (value.length <= 64) return value;
  let hash = 0;
  for (let i = 0; i < value.length; i++) {
    hash = ((hash << 5) - hash + value.charCodeAt(i)) | 0;
  }
  return `${value.slice(0, 48)}:${Math.abs(hash).toString(36)}`;
}

async function fetchPushSubscriptionTargets(userIds: string[]) {
  const uniqueUserIds = [...new Set(userIds.filter(Boolean))];
  const subscriptionIds = new Set<string>();
  const usersWithSubscriptions = new Set<string>();
  if (uniqueUserIds.length === 0) {
    return {
      subscriptionIds: [],
      externalIdFallbackUserIds: [],
    };
  }

  try {
    for (const batch of chunk(uniqueUserIds, PUSH_USER_QUERY_CHUNK_SIZE)) {
      const { data, error } = await supabase
        .from("user_push_tokens")
        .select("user_id, subscription_id")
        .eq("provider", "onesignal")
        .eq("opted_in", true)
        .in("user_id", batch);

      if (error) throw error;

      for (const row of data ?? []) {
        const userId = row.user_id as string | null;
        const subscriptionId = row.subscription_id as string | null;
        if (!userId || !subscriptionId) continue;
        usersWithSubscriptions.add(userId);
        subscriptionIds.add(subscriptionId);
      }
    }
  } catch (error) {
    console.warn(
      `[onesignal-dispatch] Falling back to external_id targeting after token lookup failed: ${error}`,
    );
    return {
      subscriptionIds: [],
      externalIdFallbackUserIds: uniqueUserIds,
    };
  }

  return {
    subscriptionIds: Array.from(subscriptionIds),
    externalIdFallbackUserIds: uniqueUserIds.filter((userId) =>
      !usersWithSubscriptions.has(userId)
    ),
  };
}

function chunk<T>(list: T[], size: number) {
  const chunks: T[][] = [];
  for (let i = 0; i < list.length; i += size) {
    chunks.push(list.slice(i, i + size));
  }
  return chunks;
}
