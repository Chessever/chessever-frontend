from pathlib import Path


ANDROID_NOTIFICATION = Path(
    "android/app/src/main/kotlin/com/chessEver/app/NotificationServiceExtension.kt"
)


def _source() -> str:
    return ANDROID_NOTIFICATION.read_text(encoding="utf-8")


def test_android_live_notifications_install_delete_intent() -> None:
    source = _source()

    assert "ACTION_DISMISS_LIVE_UPDATES" in source
    assert "val deleteIntent = Intent(context, NotificationActionReceiver::class.java)" in source
    assert "action = ACTION_DISMISS_LIVE_UPDATES" in source
    assert ".setDeleteIntent(deletePendingIntent)" in source


def test_android_live_notifications_suppress_recreated_pushes_after_dismiss() -> None:
    source = _source()

    assert "fun suppressLiveNotification(context: Context, gameId: String)" in source
    assert "fun isLiveNotificationSuppressed(context: Context, gameId: String): Boolean" in source
    assert "isLiveNotificationSuppressed(context, gameId)" in source
    assert "event.preventDefault()" in source
    assert "NotificationServiceExtension.suppressLiveNotification(context, gameId)" in source


def test_android_live_notifications_clear_suppression_on_explicit_restart() -> None:
    source = _source()

    assert "fun clearLiveNotificationSuppression(context: Context, gameId: String)" in source
    assert "gameId?.let { clearLiveNotificationSuppression(context, it) }" in source
