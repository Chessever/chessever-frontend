-- ================================================================
-- SUPABASE INDEXES FOR "FOR YOU" TAB OPTIMIZED PERFORMANCE
-- ================================================================
-- Run these commands in your Supabase SQL Editor
-- These indexes will dramatically improve ListView scrolling performance

-- ================================================================
-- 1. COMPOSITE INDEX FOR LIVE GAMES (Status + Last Move Time)
-- ================================================================
-- This index speeds up fetching live games sorted by recency
CREATE INDEX IF NOT EXISTS idx_games_status_last_move
ON games(status, last_move_time DESC)
WHERE status = '*';

-- ================================================================
-- 2. INDEX FOR PLAYER LOOKUP (JSONB players field)
-- ================================================================
-- GIN index for fast lookup of games by player FIDE ID
CREATE INDEX IF NOT EXISTS idx_games_players_gin
ON games USING gin(players);

-- Additional specialized index for FIDE ID lookups
CREATE INDEX IF NOT EXISTS idx_games_players_fideid
ON games USING gin((players) jsonb_path_ops);

-- ================================================================
-- 3. INDEX FOR COUNTRY LOOKUP
-- ================================================================
-- Partial GIN index for country federation lookups
CREATE INDEX IF NOT EXISTS idx_games_players_fed
ON games USING gin(players)
WHERE players IS NOT NULL;

-- ================================================================
-- 4. INDEX FOR TOURNAMENT/EVENT GAMES
-- ================================================================
-- Composite index for fetching games by tournament
CREATE INDEX IF NOT EXISTS idx_games_tour_lastmove
ON games(tour_id, last_move_time DESC);

-- Index for live games in specific tournaments
CREATE INDEX IF NOT EXISTS idx_games_tour_status
ON games(tour_id, status)
WHERE status = '*';

-- ================================================================
-- 5. INDEX FOR HIGH-ELO GAMES (Fallback category)
-- ================================================================
-- Since we filter high ELO in Dart, optimize for last_move_time ordering
CREATE INDEX IF NOT EXISTS idx_games_lastmove_desc
ON games(last_move_time DESC)
WHERE last_move_time IS NOT NULL;

-- ================================================================
-- 6. INDEX FOR PAGINATION (offset/limit queries)
-- ================================================================
-- Covering index for common select columns to avoid table lookups
CREATE INDEX IF NOT EXISTS idx_games_pagination_cover
ON games(last_move_time DESC, id)
INCLUDE (
    round_id, round_slug, tour_id, tour_slug,
    fen, players, last_move, status,
    last_clock_white, last_clock_black
);

-- ================================================================
-- 7. INDEX FOR PLAYER NAME LOOKUP (for non-FIDE players)
-- ================================================================
-- Index for player_white and player_black columns
CREATE INDEX IF NOT EXISTS idx_games_player_white
ON games(player_white)
WHERE player_white IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_games_player_black
ON games(player_black)
WHERE player_black IS NOT NULL;

-- Composite for OR queries on player names
CREATE INDEX IF NOT EXISTS idx_games_player_names
ON games(player_white, player_black);

-- ================================================================
-- 8. PARTIAL INDEX FOR RECENT GAMES
-- ================================================================
-- Optimize for games from last 7 days (most commonly viewed)
CREATE INDEX IF NOT EXISTS idx_games_recent
ON games(last_move_time DESC)
WHERE last_move_time > (CURRENT_TIMESTAMP - INTERVAL '7 days');

-- ================================================================
-- ANALYZE TABLES TO UPDATE STATISTICS
-- ================================================================
-- Run this after creating indexes to update query planner statistics
ANALYZE games;

-- ================================================================
-- OPTIONAL: MATERIALIZED VIEW FOR LIVE GAMES
-- ================================================================
-- If live games query is still slow, consider this materialized view
-- Refresh it every minute with a cron job

/*
CREATE MATERIALIZED VIEW IF NOT EXISTS live_games_view AS
SELECT
    id, round_id, round_slug, tour_id, tour_slug,
    name, fen, players, last_move, think_time, status,
    board_nr, last_move_time, last_clock_white, last_clock_black
FROM games
WHERE status = '*'
ORDER BY last_move_time DESC;

CREATE INDEX ON live_games_view(last_move_time DESC);
CREATE INDEX ON live_games_view(tour_id);
CREATE INDEX ON live_games_view USING gin(players);

-- Refresh command (run via cron every minute):
-- REFRESH MATERIALIZED VIEW CONCURRENTLY live_games_view;
*/

-- ================================================================
-- MONITORING QUERIES
-- ================================================================
-- Use these to check index usage and performance

-- Check index sizes
/*
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    idx_scan AS index_scans,
    idx_tup_read AS tuples_read
FROM pg_stat_user_indexes
WHERE tablename = 'games'
ORDER BY pg_relation_size(indexrelid) DESC;
*/

-- Check slow queries
/*
SELECT
    query,
    calls,
    total_time,
    mean_time,
    max_time
FROM pg_stat_statements
WHERE query LIKE '%games%'
ORDER BY mean_time DESC
LIMIT 20;
*/

-- ================================================================
-- NOTES FOR IMPLEMENTATION
-- ================================================================
/*
1. Run indexes 1-8 first - they cover all main query patterns
2. ANALYZE command is crucial - run it after index creation
3. The materialized view is optional - only if live games are still slow
4. Monitor with the provided queries to see which indexes are being used
5. Consider dropping unused indexes after monitoring for a week

EXPECTED PERFORMANCE IMPROVEMENTS:
- Player FIDE ID lookups: 10-50x faster
- Live games queries: 20-100x faster
- Tournament games: 10-30x faster
- Pagination: 5-20x faster (due to covering index)
- Country filtering: 10-40x faster

These indexes optimize for:
- The heterogeneous distribution algorithm
- Fast scrolling with large datasets
- Quick filtering by category (favorite players, events, country, ELO)
- Efficient pagination with offset/limit
*/