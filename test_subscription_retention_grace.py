from pathlib import Path

ROOT = Path(__file__).resolve().parent
WEBHOOK = ROOT / "supabase/functions/revenuecat-webhook/index.ts"
MIGRATION = ROOT / "supabase/migrations/20260606160000_subscription_retention_grace.sql"
RETENTION_STATE = ROOT / "lib/revenue_cat_service/subscription_retention_state.dart"
LIBRARY = ROOT / "lib/screens/library/library_screen.dart"
FAVORITES = ROOT / "lib/screens/favorites/favorites_tab_screen.dart"


def test_revenuecat_expiration_schedules_grace_instead_of_immediate_trim():
    text = WEBHOOK.read_text()
    expiration_block = text.split('if (eventType === "EXPIRATION")', 1)[1].split('if (!isPurchase', 1)[0]

    assert "scheduleRetentionGrace" in expiration_block
    assert "expirationGraceStartDate(event)" in expiration_block
    assert "trimToFreeTier" not in expiration_block
    assert 'Retention grace scheduled' in expiration_block


def test_retention_migration_defines_separate_favorite_and_database_deadlines():
    text = MIGRATION.read_text()

    assert "user_subscription_retention_grace" in text
    assert "favorite_cleanup_after" in text
    assert "database_cleanup_after" in text
    assert "interval '7 days'" in text
    assert "interval '14 days'" in text
    assert "public.enforce_subscription_retention_grace" in text
    assert "cron.schedule" in text
    assert "trim_favorite_players_to_top_n" in text
    assert "trim_saved_analyses_to_recent_n" in text


def test_app_surfaces_retention_warning_in_library_and_favorites():
    state = RETENTION_STATE.read_text()
    library = LIBRARY.read_text()
    favorites = FAVORITES.read_text()

    assert "subscriptionRetentionGraceProvider" in state
    assert "retentionWarningText" in state
    assert "tomorrow" in state.lower()
    assert "subscriptionRetentionGraceProvider" in library
    assert "SubscriptionRetentionWarningBanner" in library
    assert "subscriptionRetentionGraceProvider" in favorites
    assert "SubscriptionRetentionWarningBanner" in favorites
