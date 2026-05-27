from pathlib import Path


EDGE_FUNCTION = Path("supabase/functions/onesignal-dispatch/index.ts")
ROUND_START_DEDUPE_MIGRATION = Path(
    "supabase/migrations/024_grouped_round_start_exact_time_dedupe.sql"
)


def _source() -> str:
    return EDGE_FUNCTION.read_text(encoding="utf-8")


def test_onesignal_recipients_are_deduped_before_send() -> None:
    source = _source()

    assert "const uniqueUserIds = Array.from(new Set(userIds.filter(Boolean)))" in source
    assert "const chunks = chunk(uniqueUserIds, 1000)" in source


def test_game_started_notifications_do_not_reinclude_event_only_recipients() -> None:
    source = _source()
    game_block_start = source.index('if (eventType === "game_started")')
    game_block_end = source.index('if (eventType === "game_finished")', game_block_start)
    game_block = source[game_block_start:game_block_end]

    assert "favorite_player_alerts" in game_block
    assert "filtered.add(userId)" in game_block
    assert "favorite_event_alerts" not in game_block
    assert "isEventFav && eventAllowed" not in game_block


def test_game_notifications_have_device_collapse_id() -> None:
    source = _source()

    assert "const collapseId = notificationCollapseId(notification)" in source
    assert "payload.collapse_id = collapseId" in source
    assert 'game:${type ?? "update"}:${gameId}' in source


def test_round_started_uses_grouped_exact_start_collapse_id() -> None:
    source = _source()

    assert "function groupedRoundStartCollapseKey" in source
    assert "round_started:${groupId}:${startsAt}" in source
    assert "grouped_round_start_key: groupedRoundStartCollapseKey(context)" in source
    assert "typeof groupedRoundStartKey" in source


def test_dispatcher_skips_duplicate_grouped_round_starts() -> None:
    source = _source()

    assert "hasEarlierGroupedRoundStart(item, context)" in source
    assert "duplicate_grouped_round_start" in source
    assert '.eq("event_type", "round_started")' in source
    assert '.eq("group_broadcast_id", groupId)' in source
    assert '.contains("payload", { starts_at: startsAt })' in source


def test_combined_tours_do_not_send_round_result_notifications() -> None:
    source = _source()

    assert 'item.event_type === "round_finished" && isCombinedTour(context.tour)' in source
    assert "combined_round_results_suppressed" in source
    assert "function isCombinedTour" in source


def test_round_start_queue_dedupe_is_exact_group_start_time_not_two_hour_bucket() -> None:
    migration = ROUND_START_DEDUPE_MIGRATION.read_text(encoding="utf-8")

    assert "CREATE OR REPLACE FUNCTION public.queue_round_start_notifications()" in migration
    assert "COALESCE(t.group_broadcast_id::text, r.tour_id::text, r.id::text)" in migration
    assert "EXTRACT(EPOCH FROM r.starts_at)::bigint::text" in migration
    assert "/ 7200" not in migration
