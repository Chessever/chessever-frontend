from pathlib import Path


EDGE_FUNCTION = Path("supabase/functions/onesignal-dispatch/index.ts")
RETRY_POLICY = Path("supabase/functions/onesignal-dispatch/retry_policy.ts")
ROUND_FAVORITE_CACHE = Path(
    "supabase/functions/onesignal-dispatch/round_favorite_cache.ts"
)
SUPABASE_CONFIG = Path("supabase/config.toml")
ROUND_START_DEDUPE_MIGRATION = Path(
    "supabase/migrations/20260527232342_grouped_round_start_exact_time_dedupe.sql"
)
PUNCTUALITY_MIGRATION = Path(
    "supabase/migrations/20260815155000_start_alert_punctuality.sql"
)


def _source() -> str:
    return EDGE_FUNCTION.read_text(encoding="utf-8")


def test_dispatch_requires_the_configured_stream_token() -> None:
    source = _source()

    assert "if (providedToken !== requiredToken)" in source
    assert "if (providedToken && requiredToken" not in source
    assert "if (requiredToken && providedToken" not in source


def test_dispatch_fails_closed_when_vault_token_is_unavailable() -> None:
    source = _source()

    assert 'throw new Error(`Dispatch token lookup failed: ${error.message}`)' in source
    assert 'throw new Error("Dispatch token is not configured")' in source
    assert "Fail-open on vault lookup errors" not in source


def test_dispatch_function_keeps_gateway_jwt_verification_disabled() -> None:
    config = SUPABASE_CONFIG.read_text(encoding="utf-8")

    assert "[functions.onesignal-dispatch]" in config
    assert "verify_jwt = false" in config


def test_onesignal_targets_every_enabled_device_by_external_id() -> None:
    source = _source()
    send_start = source.index("async function sendOneSignal(")
    send_end = source.index("function buildOneSignalPayload", send_start)
    send_block = source[send_start:send_end]

    assert "const uniqueUserIds = [...new Set(userIds.filter(Boolean))]" in send_block
    assert "include_aliases: { external_id: batch }" in send_block
    assert "const aliasRecipientCount = await sendOneSignalPayload" in send_block
    assert "if (aliasRecipientCount !== 0) continue" in send_block
    fallback_guard = send_block.index("if (aliasRecipientCount !== 0) continue")
    direct_fallback = send_block.index("include_subscription_ids")
    assert direct_fallback > fallback_guard
    assert "fetchLegacySubscriptionFallback" in send_block


def test_onesignal_create_response_recipient_count_is_observed() -> None:
    source = _source()
    payload_start = source.index("async function sendOneSignalPayload(")
    payload_end = source.index("async function sendOneSignal(", payload_start)
    payload_block = source[payload_start:payload_end]

    assert 'typeof response?.recipients === "number"' in payload_block
    assert "return response.recipients" in payload_block


def test_game_started_notifications_do_not_reinclude_event_only_recipients() -> None:
    source = _source()
    game_block_start = source.index(
        'if (eventType === "game_started" || eventType === "game_finished")'
    )
    game_block_end = source.index('if (eventType === "call_to_action")', game_block_start)
    game_block = source[game_block_start:game_block_end]

    assert "favorite_player_alerts" in game_block
    assert "filtered.add(userId)" in game_block
    assert "favorite_event_alerts" not in game_block
    assert "isEventFav && eventAllowed" not in game_block


def test_game_and_round_notifications_have_device_collapse_id() -> None:
    source = _source()

    assert "const collapseId = notificationCollapseId(notification)" in source
    assert "payload.collapse_id = collapseId" in source
    assert 'game:${type ?? "update"}:${gameId}' in source
    assert 'round:${type ?? "update"}:${roundId}' in source


def test_round_started_uses_grouped_exact_start_collapse_id() -> None:
    source = _source()

    assert "function groupedRoundStartCollapseKey" in source
    assert "round_started:${groupId}:${startsAt}" in source
    assert "grouped_round_start_key: groupedRoundStartCollapseKey(context)" in source
    assert "typeof groupedRoundStartKey" in source


def test_dispatcher_skips_duplicate_grouped_round_starts() -> None:
    source = _source()

    assert "hasSentGroupedRoundStart(item, context)" in source
    assert "duplicate_grouped_round_start" in source
    assert '.eq("event_type", "round_started")' in source
    assert '.eq("group_broadcast_id", groupId)' in source
    assert '.eq("status", "sent")' in source
    assert "sameInstant(row.payload?.starts_at, startsAt)" in source


def test_round_started_requires_actual_move_before_dispatch() -> None:
    source = _source()

    assert "hasRoundWithMoves(item.round_id)" in source
    assert "round_not_live_yet" in source
    assert '.select("id")' in source
    assert '.not("last_move_time", "is", null)' in source
    # A failed lookup must not masquerade as "no moves yet" — that reschedules
    # silently until the 1h stale guard eats the row.
    moves_start = source.index("async function hasRoundWithMoves(")
    moves = source[moves_start:source.index("function sameInstant(", moves_start)]
    assert "throw new Error(`Round move lookup failed: ${error.message}`)" in moves
    assert "if (error) return false" not in moves


def test_round_started_waits_for_moves_instead_of_terminally_skipping() -> None:
    source = _source()
    guard_start = source.index('if (item.event_type === "round_started")')
    guard_end = source.index("hasSentGroupedRoundStart", guard_start)
    guard = source[guard_start:guard_end]

    assert 'await reschedulePending(item.id, "round_not_live_yet")' in guard
    assert 'await markSkipped(item.id, "round_not_live_yet")' not in guard
    assert 'status: "pending"' in guard
    assert "function reschedulePending" in source

    resched_start = source.index("async function reschedulePending(")
    resched = source[resched_start:source.index("async function markRetry", resched_start)]
    # Every claim bumps attempts; a long wait for the first move must not eat
    # the error-retry budget.
    assert "attempts: 0," in resched


def test_successful_retry_clears_the_waiting_reason() -> None:
    source = _source()
    mark_sent_start = source.index("async function markSent")
    mark_sent_end = source.index("async function markSkipped", mark_sent_start)
    mark_sent = source[mark_sent_start:mark_sent_end]

    assert 'update({ status: "sent", last_error: null })' in mark_sent


def test_favorite_recipient_queries_paginate_past_postgrest_row_cap() -> None:
    # PostgREST silently caps un-ranged selects at 1000 rows. A star-studded
    # round (Saint Louis 2026 R1: 1883 favoriter rows) lost ~half its
    # recipients to that cap until resolveRecipients paged every lookup.
    source = _source()
    resolve_start = source.index("async function resolveRecipients(")
    resolve_end = source.index("type TimeControlLookup", resolve_start)
    resolve_block = source[resolve_start:resolve_end]

    assert "function fetchAllPages" in source
    assert resolve_block.count("fetchAllPages") == 4
    assert '.in("user_id", batch)' in resolve_block  # muted lookup is chunked
    assert "POSTGREST_IN_QUERY_CHUNK_SIZE" in resolve_block


def test_favorite_map_user_list_is_chunked_not_one_giant_in_query() -> None:
    # An unchunked .in(user_id, <hundreds of uuids>) builds a URL the gateway
    # rejects; the swallowed error sent everyone the generic round template.
    source = _source()
    map_start = source.index("async function resolvePlayerFavoriteMap(")
    map_end = source.index("function buildEventHeader(", map_start)
    map_block = source[map_start:map_end]

    assert map_block.count("chunk(userIds, POSTGREST_IN_QUERY_CHUNK_SIZE)") == 2
    assert map_block.count("fetchAllPages") == 2
    assert "Round favorite game lookup failed" in map_block


def test_game_start_window_lookup_is_chunked_and_fails_loud() -> None:
    # If the window read fails silently, covered users look uncovered and the
    # per-game fallback double-sends after a round_started push.
    source = _source()
    win_start = source.index("async function fetchUsersWithActiveGameStartWindow(")
    win_end = source.index("async function resolveRecursiveBookSubscribers(", win_start)
    win_block = source[win_start:win_end]

    assert "chunk(userIds, POSTGREST_IN_QUERY_CHUNK_SIZE)" in win_block
    assert "Game-start window lookup failed" in win_block


def test_round_event_display_name_omits_redundant_single_open_section() -> None:
    source = _source()

    assert "displayEventName" in source
    assert "buildRoundEventDisplayName" in source
    assert "normalizeEventLabel(tourName).startsWith(normalizeEventLabel(eventName))" in source
    assert "isRedundantOpenSection(eventName, tourName)" in source


def test_combined_tours_do_not_send_round_result_notifications() -> None:
    source = _source()

    assert 'item.event_type === "round_finished" && isCombinedTour(context.tour)' in source
    assert "combined_round_results_suppressed" in source
    assert "function isCombinedTour" in source


def test_round_start_queue_dedupe_is_exact_group_start_time_not_two_hour_bucket() -> None:
    migration = ROUND_START_DEDUPE_MIGRATION.read_text(encoding="utf-8")

    assert "CREATE OR REPLACE FUNCTION public.queue_round_start_notifications()" in migration
    assert "t.group_broadcast_id::text" in migration
    assert "EXTRACT(EPOCH FROM r.starts_at)::bigint::text" in migration
    assert "'round_started:' || r.id::text" in migration
    assert "/ 7200" not in migration


def test_round_start_queue_widens_its_window_without_dropping_the_move_gate() -> None:
    # The enqueue window is deliberately generous (a round whose scheduled start
    # drifted still gets a row); the *send* is what requires a real move, and
    # that gate lives in the dispatcher (hasRoundWithMoves).
    migration = PUNCTUALITY_MIGRATION.read_text(encoding="utf-8")
    source = _source()

    assert "r.starts_at >= now_ts - interval '60 minutes'" in migration
    assert "hasRoundWithMoves(item.round_id)" in source


def test_round_started_favorites_notify_per_board_not_per_favorite_set() -> None:
    # Favorite two players on two boards and the round-end pushes arrive twice,
    # so the round-start pushes must too. Grouping recipients by their whole
    # favorite set ("X and Y are live.") collapsed several boards into one push
    # AND split one board's audience across dozens of tiny sends: Saint Louis
    # R4 fanned 5 starting boards out into 40 separate notifications, the
    # biggest Aronian/Caruana batch reaching 6 users against 467 at game end.
    source = _source()
    start = source.index("const rsTimeControl = await resolveGameTimeControl(")
    end = source.index('if (item.event_type === "round_heads_up")', start)
    block = source[start:end]

    assert "const boardBatches = new Map<string, string[]>()" in block
    assert "context.playerGameIds.get(playerBoardKey(name))" in block
    assert "context.roundBoards.has(gameId)" in block
    assert "} is live.`" in block
    # The per-favorite-set wording is what fragmented the audience.
    assert "${p1} and ${p2} are live." not in block
    assert "${p1}, ${p2}, and others are live." not in block
    assert "playerRatingMap" not in source
    assert "playerOpponentMap" not in source


def test_round_started_board_pushes_carry_a_game_deep_link() -> None:
    # deep_link_service routes `game_started` by game_id, so a board-worded
    # start push opens that board and collapses per board — not once per round.
    source = _source()
    start = source.index("for (const [gameId, userIds] of boardBatches)")
    end = source.index("if (unresolved.length > 0)", start)
    block = source[start:end]

    assert "...buildRoundStartedNotificationData(context, roundId)" in block
    assert 'type: "game_started"' in block
    assert "game_id: gameId" in block


def test_round_board_index_accepts_both_player_name_spellings() -> None:
    # A favorite matched by fide_id carries the players-JSONB spelling; one
    # matched by name carries the games column spelling. Indexing only one of
    # them would drop that user into the generic event fallback.
    source = _source()
    start = source.index("async function fetchRoundPlayers(")
    end = source.index("function calendarEventFavoriteIdFromName(", start)
    block = source[start:end]

    assert "function playerBoardKey" in source
    assert "const boardNames = [row.player_white, row.player_black]" in block
    assert "if (name) boardNames.push(name)" in block
    assert "playerGameIds.set(key, new Set([row.id]))" in block
    # An unpaired board cannot be worded "White vs Black is live."
    assert "if (!row.id || !row.player_white || !row.player_black) continue" in block


def test_start_pushes_are_high_priority_and_expire_when_stale() -> None:
    # No explicit priority means OneSignal hands FCM a normal-priority message,
    # which Android is free to hold until the next Doze window. That is the
    # difference between "is live" and "was live two minutes ago".
    source = _source()

    assert "const ONESIGNAL_HIGH_PRIORITY = 10" in source
    assert "priority: ONESIGNAL_HIGH_PRIORITY" in source
    assert "payload.ttl = TIME_CRITICAL_TTL_SECONDS" in source
    assert 'TIME_CRITICAL_TYPES = new Set(["game_started", "round_started"])' in source


def test_a_claimed_batch_is_not_walked_one_item_at_a_time() -> None:
    # Rounds start on the hour together; a serial walk put the last board of the
    # last event minutes behind the first. Same-round items stay ordered because
    # they share dedupe state (grouped-round-start, game_start windows).
    source = _source()

    assert "function dispatchGroupKey" in source
    assert "return item.round_id ?? item.game_id ?? item.id" in source
    assert "const workers = Math.min(DISPATCH_CONCURRENCY, queue.length)" in source
    assert "for (const item of items) {\n    const result = await processItem(item)" not in source


def test_transient_dispatch_errors_retry_instead_of_burning_the_row() -> None:
    source = _source()
    policy = RETRY_POLICY.read_text(encoding="utf-8")

    assert "planDispatchFailure" in source
    assert 'plan.action === "retry"' in source
    assert 'plan.action === "skip"' in source
    assert "transient_retry_expired" in source
    assert "MAX_DISPATCH_ATTEMPTS" not in source
    assert "function markRetry" in source
    assert "RETRY_DELAYS_MS" in policy
    assert "Math.min(jitteredDelayMs, remainingMs)" in policy


def test_dispatch_bursts_share_round_favorite_results_and_open_a_transient_circuit() -> None:
    source = _source()
    cache = ROUND_FAVORITE_CACHE.read_text(encoding="utf-8")

    assert "new RoundFavoriteCache(resolvePlayerFavoriteMap)" in source
    assert "roundFavoriteCache.resolve(" in source
    assert "new TransientFailureCircuit()" in source
    assert "transientFailureCircuit.trip(" in source
    assert "transientFailureCircuit.blocked(" in source
    assert "loadedUserIds" in cache
    assert "missingUserIds" in cache


def test_game_started_is_not_parked_for_two_minutes() -> None:
    # Measured on prod: game_started rows carried not_before = created_at + 120s
    # unconditionally, so any board the round-level push did not cover was two
    # minutes late by construction. The hold now exists only while a
    # round_started row for the same round is still pending or processing —
    # those terminate in 1-2s, so 20s is ample.
    migration = PUNCTUALITY_MIGRATION.read_text(encoding="utf-8")

    body_start = migration.index(
        "CREATE OR REPLACE FUNCTION public.queue_game_notifications()"
    )
    body = migration[body_start:]

    assert "now() + interval '2 minutes'" not in body
    assert "v_game_delay := now();" in migration
    assert "v_game_delay := now() + interval '20 seconds';" in migration
    assert "IF v_round_status IN ('pending', 'processing') THEN" in migration


def test_first_move_pulls_a_waiting_round_start_forward() -> None:
    # The cron queues round_started at the scheduled start and the dispatcher
    # reschedules it until a move exists. Without this the row waited out its
    # retry delay plus the next heartbeat (~90s) after the move it was waiting
    # for had already landed.
    migration = PUNCTUALITY_MIGRATION.read_text(encoding="utf-8")

    assert "SET not_before = now()" in migration
    assert "AND n.not_before > now()" in migration
    assert "PERFORM public.dispatch_notification_now();" in migration
    # The poke sits on the live ingestion path and must never abort the write.
    assert "EXCEPTION WHEN OTHERS THEN" in migration


def test_rows_abandoned_in_processing_are_requeued() -> None:
    migration = PUNCTUALITY_MIGRATION.read_text(encoding="utf-8")

    assert "FUNCTION public.requeue_stuck_notification_outbox()" in migration
    assert "WHERE status = 'processing'" in migration
    assert "requeue-stuck-notification-outbox" in migration
    assert "dispatch-pending-heartbeat-15s" in migration
