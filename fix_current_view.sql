-- Fix group_broadcasts_current view
-- Problem: date_closest_round filter only shows 2 events instead of 84
-- Run this in Supabase Dashboard -> SQL Editor

DROP VIEW IF EXISTS group_broadcasts_current;

CREATE VIEW group_broadcasts_current AS
SELECT
    t.id,
    t.created_at,
    t.name,
    t.search,
    t.max_avg_elo,
    t.date_start,
    t.date_end,
    t.time_control,
    t.date_closest_round
FROM group_broadcasts t
WHERE
    (t.date_end IS NULL OR t.date_end > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC' - INTERVAL '1 day'))
    AND (t.date_start IS NULL OR t.date_start <= (CURRENT_TIMESTAMP AT TIME ZONE 'UTC' + INTERVAL '7 day'));
