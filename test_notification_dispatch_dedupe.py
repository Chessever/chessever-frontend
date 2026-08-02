from pathlib import Path


EDGE_FUNCTION = Path("supabase/functions/onesignal-dispatch/index.ts")
SUPABASE_CONFIG = Path("supabase/config.toml")
ROUND_START_DEDUPE_MIGRATION = Path(
    "supabase/migrations/20260527232342_grouped_round_start_exact_time_dedupe.sql"
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


def test_round_started_waits_for_moves_instead_of_terminally_skipping() -> None:
    source = _source()
    guard_start = source.index('if (item.event_type === "round_started")')
    guard_end = source.index("hasSentGroupedRoundStart", guard_start)
    guard = source[guard_start:guard_end]

    assert 'await reschedulePending(item.id, "round_not_live_yet")' in guard
    assert 'await markSkipped(item.id, "round_not_live_yet")' not in guard
    assert 'status: "pending"' in guard
    assert "function reschedulePending" in source


def test_successful_retry_clears_the_waiting_reason() -> None:
    source = _source()
    mark_sent_start = source.index("async function markSent")
    mark_sent_end = source.index("async function markSkipped", mark_sent_start)
    mark_sent = source[mark_sent_start:mark_sent_end]

    assert 'update({ status: "sent", last_error: null })' in mark_sent


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


def test_round_start_queue_requires_a_real_move_before_enqueue() -> None:
    migration = ROUND_START_DEDUPE_MIGRATION.read_text(encoding="utf-8")

    assert "EXISTS (" in migration
    assert "FROM public.games g" in migration
    assert "g.round_id = r.id" in migration
    assert "g.last_move_time IS NOT NULL" in migration
