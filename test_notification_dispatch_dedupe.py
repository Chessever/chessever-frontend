from pathlib import Path


EDGE_FUNCTION = Path("supabase/functions/onesignal-dispatch/index.ts")


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
