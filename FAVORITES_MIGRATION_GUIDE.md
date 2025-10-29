# Favorites Migration Guide

## Overview

This update migrates the favorites system from local-only SharedPreferences to Supabase with local caching, ensuring full backwards compatibility for existing users.

## 📊 Supabase Tables

### 1. `user_favorite_events`
Stores event/tournament favorites.

**Columns:**
- `id` (UUID) - Primary key
- `user_id` (UUID) - References auth.users, Foreign key
- `event_id` (TEXT) - Event identifier
- `event_name` (TEXT) - Event display name
- `metadata` (JSONB) - Stores timeControl, maxAvgElo, dates
- `created_at` (TIMESTAMPTZ) - Creation timestamp
- `updated_at` (TIMESTAMPTZ) - Last update timestamp

**Indexes:**
- `idx_user_favorite_events_user_id` on `user_id`
- `idx_user_favorite_events_event_id` on `event_id`

**Unique Constraint:** `(user_id, event_id)`

---

### 2. `user_favorite_players`
Stores player favorites.

**Columns:**
- `id` (UUID) - Primary key
- `user_id` (UUID) - References auth.users, Foreign key
- `fide_id` (TEXT) - FIDE ID (nullable)
- `player_name` (TEXT) - Player name
- `metadata` (JSONB) - Stores countryCode, rating, title
- `created_at` (TIMESTAMPTZ) - Creation timestamp
- `updated_at` (TIMESTAMPTZ) - Last update timestamp

**Indexes:**
- `idx_user_favorite_players_user_id` on `user_id`
- `idx_user_favorite_players_fide_id` on `fide_id`

**Unique Constraint:** `(user_id, player_name)`

---

## 🔄 Migration Process

### Automatic Migration on App Startup

When users update to this version, the app automatically migrates their existing favorites:

**File:** `lib/utils/favorites_migration.dart`

**Process:**
1. Checks if migration already completed (via `favorites_migration_complete_v1` flag)
2. If not, reads old SharedPreferences data:
   - **Events**: From keys `current`, `upcoming`, `past` (starred event IDs)
   - **Players**: From key `favorite_players` (JSON array)
3. Uploads to Supabase tables
4. Marks migration as complete
5. Never runs again

**Triggered in:** `lib/screens/splash/splash_screen_provider.dart:92`

```dart
await FavoritesMigration.migrateIfNeeded();
```

---

## 📁 New Architecture

### Providers (Business Logic)

**`lib/providers/favorite_events_provider.dart`**
- `favoriteEventsProvider` - AsyncNotifier managing event favorites
- `isEventFavoritedProvider` - Family provider to check favorite status

**`lib/providers/favorite_players_provider.dart`**
- `favoritePlayersProviderNew` - AsyncNotifier managing player favorites
- `isPlayerFavoritedProvider` - Family provider to check favorite status

### Data Models

**`lib/repository/favorites/models/favorite_event.dart`**
- Uses `dart_mappable` for serialization
- Methods: `fromSupabase()`, `toSupabase()`, `toSupabaseInsert()`

**`lib/repository/favorites/models/favorite_player.dart`**
- Uses `dart_mappable` for serialization
- Methods: `fromSupabase()`, `toSupabase()`, `toSupabaseInsert()`

---

## 🔑 Key Features

✅ **Backwards Compatible** - Old favorites automatically migrate
✅ **Supabase as Source of Truth** - Always syncs from cloud
✅ **Local Cache** - Works offline, falls back to SharedPreferences
✅ **One-time Migration** - Runs once per user, never again
✅ **Anonymous User Support** - Can favorite items, preserved on login
✅ **Error Handling** - Migration errors don't block app startup

---

## 🧪 Testing Migration

### Test New User (No Migration)
1. Fresh install
2. Sign in
3. Star events/players
4. Check Supabase tables - should see entries

### Test Existing User (With Migration)
1. Have app with old favorites in SharedPreferences
2. Update to new version
3. Launch app and sign in
4. Check logs for: `✅ Favorites migration and sync complete`
5. Check Supabase tables - should see old favorites
6. Star new items - should work normally

### Reset Migration (For Testing)
```dart
await FavoritesMigration.resetMigration();
```

---

## 📝 Important Notes

1. **Run Migration SQL First**: Apply `supabase/migrations/001_create_user_favorites_tables.sql` to your Supabase database before deploying

2. **Old Data Preserved**: Original SharedPreferences data is NOT deleted - keeps working as cache

3. **Anonymous Users**: They can favorite items! When they sign in with real account, favorites persist (same user_id)

4. **RLS Enabled**: Users can only access their own favorites via Row Level Security policies

5. **No Breaking Changes**: Old favoriting UI/UX works exactly the same

---

## 🚀 Deployment Checklist

- [ ] Apply Supabase migration (`001_create_user_favorites_tables.sql`)
- [ ] Verify tables created with proper RLS policies
- [ ] Test migration with staging data
- [ ] Monitor logs on first production deploy
- [ ] Verify old users see their favorites after update
- [ ] Confirm new favorites sync to Supabase
